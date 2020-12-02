require "test_helper"
require "localhost/authority"

AUTHORITY = Localhost::Authority.fetch

def make_request server, url
  input = Async::IO::Stream.new(StringIO.new("gemini://#{url}\r\n"))
  output = StringIO.new
  def output.close; end
  server.send(:handle_request, input, output)
  output.rewind
  output.read
end

class DefaultServer < MiniTest::Test
  def setup
    @server = GeminiServer.new(cert: AUTHORITY.certificate, key: AUTHORITY.key)
    @server.route("/hithere/:friend") do
      success "hi there, #{params["friend"]}!"
    end
    @server.route("/hello-erb-1/:friend") do
      erb "hello.gmi.erb"
    end
    @server.route("/hello-erb-2/:friend") do
      erb "hello.gmi"
    end
    @server.route("/byebye") do
      charset "utf-8"
      lang "pig-latin"
      success "arewellfay!"
    end
    @server.route("/text") do
      success "this is plain text"
      mime_type "text/plain"
    end
    @server.route("/error") do
      success "#{nil + 3}"
    end
  end

  def test_request_params
    response = make_request(@server, "localhost/hithere/Barry")
    assert_equal "20 text/gemini\r\nhi there, Barry!", response
  end

  def test_charset_lang
    response = make_request(@server, "localhost/byebye")
    assert_equal "20 text/gemini; charset=utf-8; lang=pig-latin\r\narewellfay!", response
  end

  def test_custom_mime_type
    response = make_request(@server, "localhost/text")
    assert_equal "20 text/plain\r\nthis is plain text", response
  end

  def test_runtime_error
    response = make_request(@server, "localhost/error")
    assert_equal "40 Temporary failure\r\n", response
  end

  def test_not_found
    response = make_request(@server, "localhost/nonexistant")
    assert_equal "51 Not found\r\n", response
  end

  def test_render_template_in_current_dir
    response = make_request(@server, "localhost/hello-erb-1/Barry")
    assert_equal "20 text/gemini\r\nRendered in ERB just for you, Barry", response.strip
  end

  def test_erb_extension_is_not_needed
    response = make_request(@server, "localhost/hello-erb-2/Barry")
    assert_equal "20 text/gemini\r\nRendered in ERB just for you, Barry", response.strip
  end

  def test_drops_long_request_urls
    response = make_request(@server, "localhost/#{"a" * 1024}")
    assert_equal "54 URI too long\r\n", response
  end
end

class StaticServer < MiniTest::Test
  def setup
    @server = GeminiServer.new(
      cert: AUTHORITY.certificate,
      key: AUTHORITY.key,
      public_folder: "public",
    )
    @server.route("/cool.gmi") do
      success "This cool page is served dynamically."
    end
  end

  def test_dynamic_routes_match_first
    response = make_request(@server, "localhost/cool.gmi")
    assert_equal "20 text/gemini\r\nThis cool page is served dynamically.", response
  end

  def test_static_file
    response = make_request(@server, "localhost/rad.gmi")
    assert_equal "20 text/gemini\r\nThis rad file is hosted statically.", response.strip
  end

  def test_infer_mime_type
    response = make_request(@server, "localhost/neat.txt")
    assert_equal "20 text/plain\r\nThis neat file is hosted statically.", response.strip
  end

  def test_cant_serve_outside_public_folder
    response = make_request(@server, "localhost/../test_helper.rb")
    assert_equal "51 Not found\r\n", response
  end
end

class CharsetLangServer < MiniTest::Test
  def setup
    @server = GeminiServer.new(
      cert: AUTHORITY.certificate,
      key: AUTHORITY.key,
      lang: "en",
      charset: "ISO-8859-1",
    )
    @server.route("/hithere/:friend") do
      success "hi there, #{params["friend"]}!"
    end
    @server.route("/byebye") do
      charset "utf-8"
      lang "pig-latin"
      success "arewellfay!"
    end
  end

  def test_default_charset_and_lang
    response = make_request(@server, "localhost/hithere/Barry")
    assert_equal "20 text/gemini; charset=ISO-8859-1; lang=en\r\nhi there, Barry!", response
  end

  def test_override_default_charset_and_lang
    response = make_request(@server, "localhost/byebye")
    assert_equal "20 text/gemini; charset=utf-8; lang=pig-latin\r\narewellfay!", response
  end
end

class ErbRendering < MiniTest::Test
  def setup
    @server = GeminiServer.new(
      cert: AUTHORITY.certificate,
      key: AUTHORITY.key,
      views_folder: "views",
    )
    @server.route("/hello-gmi/:friend") do
      erb "hello.gmi", locals: { friend: params["friend"] }
    end
    @server.route("/hello-txt/:friend") do
      erb "hello.txt", locals: { friend: params["friend"] }
    end
    @server.route("/hello-gmi-really/:friend") do
      erb "hello.txt", locals: { friend: params["friend"] }
      mime_type "text/gemini"
    end
  end

  def test_render_template
    response = make_request(@server, "localhost/hello-gmi/Barry")
    assert_equal "20 text/gemini\r\nComing to you in text/gemini, Barry", response.strip
  end

  def test_infer_mime_type
    response = make_request(@server, "localhost/hello-txt/Barry")
    assert_equal "20 text/plain\r\nComing to you in text/plain, Barry", response.strip
  end

  def test_override_inferred_mime_type
    response = make_request(@server, "localhost/hello-gmi-really/Barry")
    assert_equal "20 text/gemini\r\nComing to you in text/plain, Barry", response.strip
  end
end
