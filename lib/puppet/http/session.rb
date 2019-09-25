class Puppet::HTTP::Session
  Route = Struct.new(:service, :api, :server_setting, :port_setting)

  ROUTES = {
    ca: Route.new(Puppet::HTTP::Service::Ca, '/puppet-ca/v1', :ca_server, :ca_port),
  }.freeze

  def initialize(client, resolvers)
    @client = client
    @resolvers = resolvers
    @resolved_services = {}
  end

  def route_to(name)
    route = ROUTES[name]
    raise ArgumentError, "Unknown service #{name}" unless route

    cached = @resolved_services[name]
    return cached if cached

    @resolvers.each do |resolver|
      Puppet.info("Resolving service '#{name}' using #{resolver.class}")
      resolver.resolve(self, name) do |service|
        begin
          service.connect
          @resolved_services[name] = service
          Puppet.info("Resolved service '#{name}' to #{service.url}")
          return service
        rescue Puppet::HTTP::ConnectionError => e
          Puppet.err("Connection to #{service.url} failed #{e.message}, trying next route")
        end
      end
    end

    raise Puppet::HTTP::RouteError, "No more routes to #{name}"
  end

  def create_service(name, server = nil, port = nil)
    route = ROUTES[name]
    raise ArgumentError, "Unknown service #{name}" unless route

    server ||= Puppet[route.server_setting]
    port   ||= Puppet[route.port_setting]
    url = URI::HTTPS.build(host: server,
                           port: port,
                           path: route.api
                          ).freeze
    route.service.new(@client, url)
  end
end
