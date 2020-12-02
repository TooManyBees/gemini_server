# frozen_string_literal: true

module Responses
  def input prompt
    respond 10, prompt
  end

  def sensitive_input prompt
    respond 11, prompt
  end

  def success body, mime_type=nil
    respond 20, mime_type, body
  end

  def redirect_temporary url
    respond 30, url
  end

  def redirect_permanent url
    respond 31, url
  end

  def temporary_failure explanation = "Temporary failure"
    respond 40, explanation
  end

  def server_unavailable explanation = "Server unavailable"
    respond 41, explanation
  end

  def cgi_error explanation = "CGI error"
    respond 42, explanation
  end

  def proxy_error explanation = "Proxy error"
    respond 43, explanation
  end

  def slow_down delay
    respond 44, delay
  end

  def permanent_failure explanation = "Permanent failure"
    respond 50, explanation
  end

  def not_found explanation = "Not found"
    respond 51, explanation
  end

  def gone explanation = "Gone"
    respond 52, explanation
  end

  def proxy_request_refused explanation = "Proxy request refused"
    respond 53, explanation
  end

  def bad_request explanation = "Bad request"
    respond 59, explanation
  end

  def client_certificate_required explanation = "Client certificate required"
    respond 60, explanation
  end
  alias certificate_required client_certificate_required

  def certificate_not_authorized explanation = "Certificate not authorized"
    respond 61, explanation
  end

  def certificate_not_valid explanation = "Certificate not valid"
    respond 62, explanation
  end
end
