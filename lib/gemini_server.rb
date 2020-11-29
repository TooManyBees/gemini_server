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
    @public_folder = File.exapnd_path(options[:public_folder]) rescue nil
    @views_folder = File.expand_path(options[:views_folder] || ".")
    @charset = options[:charset]
    @lang = options[:lang]
    @ssl_cert, @ssl_key = self.load_cert_and_key(options)
  end

  def route r, &blk
    raise "Missing required block for route #{r}" if blk.nil?
    @routes << [Mustermann.new(r), blk]
  end

  def listen host, port
    endpoint = Async::IO::Endpoint.tcp(host, port)
    endpoint = Async::IO::SSLEndpoint.new(endpoint, ssl_context: self.ssl_context(@ssl_cert, @ssl_key))

    Async do |task|
      endpoint.accept do |client|
        remote_ip = client.connect.io.remote_address.ip_address
        data = Async::IO::Stream.new(client.connect).read_until("\r\n")
        status, size, captured_error = nil
        start_time = clock_time
        uri = begin
          Addressable::URI.parse(data)
        rescue Addressable::URI::InvalidURIError
          ctx = ResponseContext.new(params, uri)
          ctx.bad_request "Invalid URI"
          status, size = send_response(client, ctx.response)
          puts log(ip: remote_ip, uri: uri, status: status, body_size: size)
          next
        end
        uri.scheme = "gemini" if uri.scheme.nil?
        params, handler = self.find_route(uri.path)
        if params
          ctx = ResponseContext.new(params, uri, views_folder: @views_folder, mime_type: @mime_type, charset: @charset, lang: @lang)
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
        puts log(ip: remote_ip, uri: uri, start_time: start_time, status: status, body_size: size)
        raise captured_error if captured_error.is_a?(Exception)
      end
    end
  end

  private

  def serve_static path
    return if @public_folder.nil?
    path = File.expand_path "#{@public_folder}#{path}"
    return unless path.start_with?(@public_folder)
    File.open(path) do |f|
      mime_type = MIME::Types.type_for(File.basename(path)).first || "application/octet-stream"
      { code: 200, meta: mime_type, body: f.read }
    end
  rescue Errno::ENOENT
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

  def log ip:, uri:, start_time:, username:nil, status:nil, body_size:nil
    # Imitates Apache common log format to the extent that it applies to Gemini
    # http://httpd.apache.org/docs/1.3/logs.html#common
    path = uri.omit(:scheme, :host).to_s
    path = path.length > 0 ? path : "/"
    LOG_FORMAT % [ip, username || '-', Time.now.strftime("%d/%b/%Y:%H:%M:%S %z"), path, status.to_s || '-', body_size.to_s || '-', clock_time - start_time]
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

    [
      found_cert.is_a?(OpenSSL::X509::Certificate) ? found_cert : OpenSSL::X509::Certificate.new(found_cert),
      found_key.is_a?(OpenSSL::PKey) ? found_key : OpenSSL::PKey.read(found_key),
    ]
  end

  def ssl_context cert, key
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.add_certificate(cert, key)
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

  def mime_type t=nil
    return @__mime_type if t.nil?
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
