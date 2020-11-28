require "addressable/uri"
require "async/io"
require "async/io/stream"
require "mime/types"
require "mustermann"
require "openssl"
require_relative "gemini_server/mime_types"
require_relative "gemini_server/responses"

class GeminiServer
  def initialize options = {}
    @routes = []
    @public_folder = File.exapnd_path(options[:public_folder]) rescue nil
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
        status, size = nil
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
          ctx = ResponseContext.new(params, uri, mime_type: @mime_type, charset: @charset, lang: @lang)
          begin
            ctx.instance_exec(&handler)
          rescue StandardError => e
            ctx.temporary_failure
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
        puts log(ip: remote_ip, uri: uri, status: status, body_size: size)
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
        client.write "; lang=#{response[:lang]}" if response[:lang]
      end
      client.write "\r\n"
      body_size = client.write response[:body]
    else
      client.write "#{response[:code]} #{response[:meta]}\r\n"
    end
    client.close
    [response[:code], body_size]
  end

  def log ip:, uri:, username:nil, status:nil, body_size:nil
    # Imitates Apache common log format to the extent that it applies to Gemini
    # http://httpd.apache.org/docs/1.3/logs.html#common
    path = uri.omit(:scheme, :host).to_s
    path = path.length > 0 ? path : "/"
    "#{ip} - #{username || '-'} [#{Time.now.strftime("%d/%b/%Y:%H:%M:%S %z")}] \"#{path}\" #{status || '-'} #{body_size || '-'}"
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
end

class ResponseContext
  include Responses

  def initialize params, uri, options={}
    @__params = params
    @__uri = uri
    @__mime_type = options[:mime_type]
    @__charset = options[:charset]
    @__lang = options[:lang]
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

  def respond code, meta, body=nil
    @__response = { code: code, meta: meta, body: body }
  end

  def response
    @__response.to_h.merge({ mime_type: @__mime_type, lang: @__lang, charset: @__charset })
  end
end
