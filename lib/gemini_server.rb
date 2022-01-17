# frozen_string_literal: true

require "addressable/uri"
require "async/io"
require "async/io/stream"
require "erb"
require "mime/types"
require "mustermann"
require "openssl"
require_relative "gemini_server/mime_types"
require_relative "gemini_server/responses"

class GeminiServer
  def initialize options = {}
    @routes = []
    @public_folder = File.expand_path(options[:public_folder]) rescue nil
    @views_folder = File.expand_path(options[:views_folder] || ".")
    @charset = options[:charset]
    @lang = options[:lang]
    @ssl_cert, @ssl_key, @ssl_chain = self.load_cert_and_key(options)
  end

  def route r, &blk
    raise "Missing required block for route #{r}" if blk.nil?
    @routes << [Mustermann.new(r), blk]
  end

  def listen host, port
    Async do
      endpoint = Async::IO::Endpoint.tcp(host, port)
      endpoint = Async::IO::SSLEndpoint.new(endpoint, ssl_context: self.ssl_context(@ssl_cert, @ssl_key, @ssl_chain))

      ["INT", "TERM"].each do |signal|
        old_handler = Signal.trap(signal) do
          @server.stop if @server
          old_handler.call if old_handler.respond_to?(:call)
        end
      end

      @server = Async do |task|
        endpoint.accept do |client|
          start_time = clock_time
          remote_ip = client.connect.io.remote_address.ip_address
          io = Async::IO::Stream.new(client.connect)
          status, size, uri, captured_error = handle_request(io, client)
          puts log(ip: remote_ip, uri: uri, start_time: start_time, status: status, body_size: size)
          raise captured_error if captured_error.is_a?(Exception)
        end
      end
    end
  end

  private

  MAX_URL_SIZE = 1024

  def read_request_url io
    buf = String.new
    offset = 0
    while buf.length <= MAX_URL_SIZE + 2 do
      buf << io.read_partial
      line_end = buf.index("\r\n", offset)
      offset = buf.length
      return buf[0...line_end] if line_end && line_end <= MAX_URL_SIZE
    end
  end

  def handle_request io, client
    data = read_request_url(io)
    if data.nil?
      ctx = ResponseContext.new({}, nil)
      ctx.bad_request "URI too long"
      return send_response(client, ctx.response)
    end
    status, size, captured_error = nil
    uri = begin
      Addressable::URI.parse(data)
    rescue Addressable::URI::InvalidURIError
      ctx = ResponseContext.new({}, nil)
      ctx.bad_request "Invalid URI"
      return send_response(client, ctx.response)
    end
    uri.scheme = "gemini" if uri.scheme.nil?
    params, handler = self.find_route(uri.path)
    if params
      ctx = ResponseContext.new(params, uri, views_folder: @views_folder, charset: @charset, lang: @lang)
      begin
        ctx.instance_exec(&handler)
      rescue StandardError => e
        ctx.temporary_failure
        captured_error = e
      ensure
        status, size = send_response(client, ctx.response)
      end
    elsif static_response = serve_static(uri.path)
      status, size = send_response(client, static_response)
    else
      ctx = ResponseContext.new(params, uri)
      ctx.not_found
      status, size = send_response(client, ctx.response)
    end
    [status, size, uri, captured_error]
  end

  def serve_static path
    return if @public_folder.nil?
    path = File.expand_path "#{@public_folder}#{path}"
    return unless path.start_with?(@public_folder)
    File.open(path) do |f|
      mime_type = MIME::Types.type_for(File.basename(path)).first || "text/plain"
      { code: 20, meta: mime_type, body: f.read }
    end
  rescue Errno::ENOENT, Errno::ENAMETOOLONG, Errno::EISDIR # TODO: index.gmi?
  rescue SystemCallError
    { code: 40, meta: "Temporary failure" }
  end

  def find_route path
    @routes.each do |(route, handler)|
      params = route.params(path)
      return [params, handler] if params
    end
    nil
  end

  def send_response client, response
    body_size = nil
    if (20...30).include?(response[:code])
      mime_type = MIME::Types[response[:mime_type] || response[:meta]].first || GEMINI_MIME_TYPE
      client.write "#{response[:code]} #{mime_type}"
      if mime_type.media_type == "text"
        client.write "; charset=#{response[:charset]}" if response[:charset]
        client.write "; lang=#{response[:lang]}" if response[:lang] && mime_type.sub_type == "gemini"
      end
      client.write "\r\n"
      body_size = client.write response[:body]
    else
      client.write "#{response[:code]} #{response[:meta]}\r\n"
    end
    client.close
    [response[:code], body_size]
  end

  LOG_FORMAT = "%s - %s [%s] \"%s\" %s %s %0.4f"

  def log ip:, uri:, start_time:, username:nil, status:, body_size:nil
    # Imitates Apache common log format to the extent that it applies to Gemini
    # http://httpd.apache.org/docs/1.3/logs.html#common
    path = uri ? uri.omit(:scheme, :host).to_s : '<uri too long>'
    path = path.length > 0 ? path : "/"
    LOG_FORMAT % [ip, username || '-', Time.now.strftime("%d/%b/%Y:%H:%M:%S %z"), path, status.to_s, body_size.to_s || '-', clock_time - start_time]
  end

  def parse_cert_and_chain input_text
    # Only works in Ruby 3+
    if OpenSSL::X509::Certificate.respond_to?(:load)
      certs = OpenSSL::X509::Certificate.load(input_text)
      return [certs.shift, certs]
    end

    # Fallback behavior for .pem certificates
    certificate_pattern = /-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m
    certs = input_text.scan(certificate_pattern).collect do |text|
      OpenSSL::X509::Certificate.new(text)
    end

    # Fallback behavior if above regex yields 0 certs. E.g. with .der certs
    # This won't parse any chain certs that might be present
    certs = [OpenSSL::X509::Certificate.new(input_text)] if certs.empty?

    [certs.shift, certs]
  end

  def load_cert_and_key options
    found_cert = options[:cert] || if options[:cert_path]
      File.open(options[:cert_path]) rescue nil
    elsif ENV["GEMINI_CERT_PATH"]
      File.open(ENV["GEMINI_CERT_PATH"]) rescue nil
    end

    found_key = options[:key] || if options[:key_path]
      File.open(options[:key_path]) rescue nil
    elsif ENV["GEMINI_KEY_PATH"]
      File.open(ENV["GEMINI_KEY_PATH"]) rescue nil
    end

    raise "SSL certificate not found" unless found_cert
    raise "SSL key not found" unless found_key

    if found_cert.is_a?(OpenSSL::X509::Certificate)
      main_cert = found_cert
      chain_list = []
    else
      main_cert, chain_list = parse_cert_and_chain found_cert.read
    end

    [
      main_cert,
      found_key.is_a?(OpenSSL::PKey::PKey) ? found_key : OpenSSL::PKey.read(found_key),
      chain_list
    ]
  end

  def ssl_context cert, key, chain
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.add_certificate(cert, key)
      context.extra_chain_cert = chain
      context.session_id_context = "gemini_server"
      context.min_version = OpenSSL::SSL::TLS1_2_VERSION
      context.max_version = OpenSSL::SSL::TLS1_3_VERSION
      context.setup
    end
  end

  if defined?(Process::CLOCK_MONOTONIC)
    def clock_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  else
    def clock_time
      Time.now.to_f
    end
  end
end

class ResponseContext
  include Responses

  def initialize params, uri, options={}
    @__params = params
    @__uri = uri
    @__mime_type = options[:mime_type]
    @__charset = options[:charset]
    @__lang = options[:lang]
    @__views_folder = options[:views_folder]
    temporary_failure
  end

  def mime_type t
    type = MIME::Types[t].first
    if type
      @__mime_type = type
    else
      STDERR.puts("WARN: Unknown MIME type #{t.inspect}")
    end
  end

  def params; @__params; end
  def uri; @__uri; end
  def charset c; @__charset = c; end
  def lang l; @__lang = l; end

  def erb template, locals: {}
    b = TOPLEVEL_BINDING.dup
    b.local_variable_set(:params, params)
    locals.each { |key, val| b.local_variable_set(key, val) }
    template = File.basename(template.to_s, ".erb")
    mime_type = MIME::Types.type_for(template).first || GEMINI_MIME_TYPE
    t = ERB.new(File.read(File.join(@__views_folder, "#{template}.erb")))
    body = t.result(b)
    success(body, mime_type)
  end

  def respond code, meta, body=nil
    @__response = { code: code, meta: meta, body: body }
  end

  def response
    @__response.to_h.merge({ mime_type: @__mime_type, lang: @__lang, charset: @__charset })
  end
end
