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
    @public_folder = options[:public_folder]
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
        data = Async::IO::Stream.new(client.connect).read_until("\r\n")
        uri = begin
          Addressable::URI.parse(data)
        rescue Addressable::URI::InvalidURIError
          request = Request.new(client, params, uri)
          request.bad_request "Invalid URI"
          client.close_write
          next
        end
        uri.scheme = "gemini" if uri.scheme.nil?
        params, handler = self.find_route(uri.path)
        request = Request.new(client, params, uri)
        if params
          request.fulfill(&handler)
        else
          request.not_found
        end
      end
    end
  end

  def static_file_exists? path

  end

  def serve_static path
    path = File.expand_path "#{@public_path}#{path}"
    if File.exist?(path)

    end
  end

  private

  def find_route(path)
    @routes.each do |(route, handler)|
      params = route.params(path)
      return [params, handler] if params
    end
    nil
  end

  def load_cert_and_key options
    found_cert = options[:cert] || if options[:cert_path]
      File.open(options[:cert_path])
    elsif ENV["GEMINI_CERT_PATH"]
      File.open(ENV["GEMINI_CERT_PATH"])
    end

    found_key = options[:key] || if options[:key_path]
      File.open(options[:key_path])
    elsif ENV["GEMINI_KEY_PATH"]
      File.open(ENV["GEMINI_KEY_PATH"])
    end

    raise "SSL certificate not found" unless found_cert
    raise "SSL key not found" unless found_key

    [
      found_cert.is_a?(OpenSSL::X509::Certificate) ? found_cert : OpenSSL::X509::Certificate.new(found_cert),
      found_key.is_a?(OpenSSL::PKey::RSA) ? found_key : OpenSSL::PKey::RSA.new(found_key),
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

class Request
  include Responses

  attr_reader :params, :uri

  def initialize client, params, uri
    @client = client
    @params = params
    @mime_type = GEMINI_MIME_TYPE
    @charset = "utf-8"
    @uri = uri
  end

  def mime_type t
    type = MIME::Types[t].first
    if type
      @mime_type = type
    else
      STDERR.puts("WARN: Unknown MIME type #{t.inspect}")
    end
  end

  # TODO: move this code so it can't be re-invoked in a handler
  def fulfill &blk
    begin
      self.instance_exec(@params, @uri, &blk)
    rescue StandardError => e
      temporary_failure
    ensure
      @client.close
    end
  end

  def respond code, meta, body = nil
    @client.write "#{code} #{meta}\r\n"
    if (20...30).include?(code)
      @client.write body
    end
  end
end
