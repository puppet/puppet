class Puppet::HTTP::Client
  def initialize(pool: Puppet::Network::HTTP::Pool.new, ssl_context: nil, redirect_limit: 10, retry_limit: 100)
    @pool = pool
    @default_headers = {
      'X-Puppet-Version' => Puppet.version,
      'User-Agent' => Puppet[:http_user_agent],
    }.freeze
    @default_ssl_context = ssl_context
    @redirector = Puppet::HTTP::Redirector.new(redirect_limit)
    @retry_after_handler = Puppet::HTTP::RetryAfterHandler.new(retry_limit, Puppet[:runinterval])
    @resolvers = build_resolvers
  end

  def create_session
    Puppet::HTTP::Session.new(self, @resolvers)
  end

  def connect(uri, ssl_context: nil, &block)
    ctx = ssl_context ? ssl_context : default_ssl_context
    site = Puppet::Network::HTTP::Site.from_uri(uri)
    verifier = Puppet::SSL::Verifier.new(site.host, ctx)

    $stderr.puts "Connecting to #{site}"
    @pool.with_connection(site, verifier) do |http|
      $stderr.puts "Connected to #{site}"
      if block_given?
        handle_post_connect(uri, http, &block)
      end
    end
  rescue Puppet::HTTP::HTTPError
    raise
  rescue => e
    $stderr.puts "Never connected #{e.class} #{e.message}"
    raise Puppet::HTTP::ConnectionError.new(_("Failed to connect to %{uri}: %{message}") % {uri: uri, message: e.message}, e)
  end

  def get(url, headers: {}, params: {}, ssl_context: nil, user: nil, password: nil, &block)
    query = encode_params(params)
    unless query.empty?
      url = url.dup
      url.query = query
    end

    request = Net::HTTP::Get.new(url, @default_headers.merge(headers))

    execute_streaming(request, ssl_context: ssl_context, user: user, password: password) do |response|
      if block_given?
        yield response
      else
        response.read_body
      end
    end
  end

  def put(url, headers: {}, params: {}, content_type:, body:, ssl_context: nil, user: nil, password: nil)
    query = encode_params(params)
    unless query.empty?
      url = url.dup
      url.query = query
    end

    request = Net::HTTP::Put.new(url, @default_headers.merge(headers))
    request.body = body
    request['Content-Length'] = body.bytesize
    request['Content-Type'] = content_type

    execute_streaming(request, ssl_context: ssl_context, user: user, password: password) do |response|
      response.read_body
    end
  end

  def close
    @pool.close
  end

  private

  def execute_streaming(request, ssl_context:, user: nil, password: nil, &block)
    redirects = 0
    retries = 0

    loop do
      connect(request.uri, ssl_context: ssl_context) do |http|
        apply_auth(request, user, password)

        http.request(request) do |nethttp|
          response = Puppet::HTTP::Response.new(nethttp)
          begin
            Puppet.debug("HTTP #{request.method.upcase} #{request.uri} returned #{response.code} #{response.reason}")

            if @redirector.redirect?(request, response)
              request = @redirector.redirect_to(request, response, redirects)
              redirects += 1
              next
            elsif @retry_after_handler.retry_after?(request, response)
              interval = @retry_after_handler.retry_after_interval(request, response, retries)
              retries += 1
              if interval
                Puppet.warning(_("Sleeping for %{interval} seconds before retrying the request") % { interval: interval })
                ::Kernel.sleep(interval)
                next
              end
            end

            yield response
          ensure
            response.drain
          end

          return response
        end
      end
    end
  end

  def encode_params(params)
    params.map do |key, value|
      "#{key}=#{Puppet::Util.uri_query_encode(value.to_s)}"
    end.join('&')
  end

  def handle_post_connect(uri, http, &block)
    $stderr.puts "IN POST CONNECT"
    start = Time.now
    yield http
  rescue Puppet::HTTP::HTTPError
    raise
  rescue EOFError => e
    raise Puppet::HTTP::HTTPError.new(_("Request to %{uri} interrupted after %{elapsed} seconds") % {uri: uri, elapsed: elapsed(start)}, e)
  rescue Timeout::Error => e
    raise Puppet::HTTP::HTTPError.new(_("Request to %{uri} timed out after %{elapsed} seconds") % {uri: uri, elapsed: elapsed(start)}, e)
  rescue => e
    $stderr.puts "EXCEPTION #{e.class} #{e.message}"
    raise Puppet::HTTP::HTTPError.new(_("Request to %{uri} failed after %{elapsed} seconds: %{message}") % {uri: uri, elapsed: elapsed(start), message: e.message}, e)
  end

  def elapsed(start)
    (Time.now - start).to_f.round(3)
  end

  def default_ssl_context
    @default_ssl_context || Puppet.lookup(:ssl_context)
  end

  def apply_auth(request, user, password)
    if user && password
      request.basic_auth(user, password)
    end
  end

  def build_resolvers
    resolvers = []

    if Puppet[:use_srv_records]
      resolvers << Puppet::HTTP::Resolver::SRV.new(domain: Puppet[:srv_domain])
    end

    resolvers << Puppet::HTTP::Resolver::Settings.new
    resolvers.freeze
  end
end
