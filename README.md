# GeminiServer

A simple server for the Gemini protocol, with an API inspired by Sinatra.

## Usage

Use the built-in executable to serve the current directory.

```
$ gem install gemini_server
Successfully installed gemini_server-0.1.0
1 gem installed
$ gemini_server -h
Usage: gemini_server [options]
    -p, --port PORT                  Port to listen on
        --cert-path PATH             Path to cert file
        --key-path PATH              Path to key file
        --charset CHARSET            Charset of text/* files
        --lang LANG                  Language of text/* files
```

Or require the library to declare custom routes in Ruby.

```ruby
require "gemini_server"

server = GeminiServer.new

server.route("/hithere/:friend") do
  if params["friend"] == "Gary"
    gone "Gary and I aren't on speaking terms, sorry."
  else
    success "Hi there, #{params["friend"]}!"
  end
end

server.route("/byebye") do
  lang "pig-latin"
  success "arewellfay!"
end

server.listen("0.0.0.0", 1965)
```

### Initialization options

<dl>
  <dt><code>cert</code>*</dt>
  <dd>A SSL certificate. Either a <code>OpenSSL::X509::Certificate</code> object, or a string.</dd>
  <dt><code>cert_path</code>*</dt>
  <dd>Path to a SSL certificate file. Defaults to the value of the env variable <code>GEMINI_CERT_PATH</code>. Ignored if <code>cert</code> option is supplied.</dd>
  <dt><code>key</code>*</dt>
  <dd>A SSL key. Either a <code>OpenSSL::PKey</code> object, or a string.</dd>
  <dt><code>key_path</code>*</dt>
  <dd>Path to a private key file. Defaults to the value of the env variable <code>GEMINI_KEY_PATH</code>. Ignored if <code>key</code> option is supplied.</dd>
  <dt><code>mime_type</code></dt>
  <dd>Sets the default MIME type for successful responses. Defaults to <code>text/gemini</code>, or inferred by the name of the file being served.</dd>
  <dt><code>charset</code></dt>
  <dd>If set, includes the charset in the response's MIME type.</dd>
  <dt><code>lang</code></dt>
  <dd>If set, includes the language in the response's MIME type, if the MIME type is <code>text/gemini</code>. Per the Gemini spec, <em>"Valid values for the "lang" parameter are comma-separated lists of one or more language tags as defined in RFC4646."</em></dd>
  <dt><code>public_folder</code></dt>
  <dd>Path to a location from which the server will serve static files. If not set, the server will not serve any static files.</dd>
  <dt><code>views_folder</code></dt>
  <dd>Path to the location of ERB templates. If not set, defaults to current directory.</dd>
</dl>

*\* The option pairs `cert` and `cert_path`, and likewise `key` and `key_path`, are mutually exclusive, so they are technically optional. But per the Gemini spec, connections must use TLS, so it is a runtime error if neither option, nor either of the fallback env variables, are used.*

### Route handlers

To define a route handler, use `GeminiServer#route`:

```ruby
server = GeminiServer.new
server.route("/path/to/route/:variable") do
  # route logic
end
```

The route method takes a [Mustermann](https://github.com/sinatra/mustermann) matcher string and a block.

Within the block, code has access to these methods:

<dl>
  <dt><code>params</code></dt>
  <dd>Returns a hash of params parsed from the request path.</dd>
  <dt><code>uri</code></dt>
  <dd>Returns the full URI of the request.</dd>
  <dt><code>mime_type(type)</code></dt>
  <dd>Sets the MIME type of the response.</dd>
  <dt><code>charset(ch)</code></dt>
  <dd>Sets the charset of the response, overriding the server's default charset.</dd>
  <dt><code>lang(l)</code></dt>
  <dd>Sets the lang of the response, overriding the server's default lang.</dd>
  <dt><code>erb(filename, locals: {})</code></dt>
  <dd>Renders an ERB template located at <code>filename</code>, then sets status to success. MIME type is inferred by the template extension. The template will have access to any instance variables defined in the handler block, as well as any local variables passed in via the <code>locals</code> keyword param.</dd>
  <dt><code>respond(code, meta, body=nil)</code></dt>
  <dd>Sets the response code, meta, and optional body. It's probably easier to use <code>erb</code> method, or any of the convenience status methods in the next section.</dd>
</dl>

### ERB templates

Using an ERB template automatically sets the status to `20` (success) because a success is the only type of response that can contain a body. It also tries to infer the MIME type from the template extension (excluding any `.erb`).

ERB rendering can define local variables, like in Sinatra:

```ruby
server.route("/hithere/:friend") do
  erb "hithere.gmi", locals: { friend: params["friend"] }
end
```

```markdown
<!-- hithere.gmi.erb -->
# Hi there!

Hi there, <%= friend %>.
```

ERB templates have the `params` hash available as a local var:

```ruby
server.route("/hithere/:friend") do
  erb "hithere.gmi"
end
```

```markdown
<!-- hithere.gmi.erb -->
# Hi there!

Hi there, <%= params["friend"] %>.
```

### Status methods

Each of these methods are available within a route handler block. Forgetting to use a status method defaults to a temporary failure. See [Gemini Specification](https://gemini.circumlunar.space/docs/specification.html) for an explanation of each response status.

* `input(prompt)`
* `sensitive_input(prompt)`
* `success(body, mime_type=nil)`
* `redirect_temporary(url)`
* `redirect_permanent(url)`
* `temporary_failure(explanation = "Temporary failure")`
* `server_unavailable(explanation = "Server unavailable")`
* `cgi_error(explanation = "CGI error")`
* `proxy_error(explanation = "Proxy error")`
* `slow_down(delay)`
* `permanent_failure(explanation = "Permanent failure")`
* `not_found(explanation = "Not found")`
* `gone(explanation = "Gone")`
* `proxy_request_refused(explanation = "Proxy request refused")`
* `bad_request(explanation = "Bad request")`
* `client_certificate_required(explanation = "Client certificate )`
* `certificate_not_authorized(explanation = "Certificate not )`
* `certificate_not_valid(explanation = "Certificate not valid")`

### Static file serving

To serve static files, set the initialization option `public_folder` to the location of your static files. If no route handlers match a request, the server will look for a static file to serve in that location instead. If the `public_folder` option is unset, no static files will be served.
