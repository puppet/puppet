require 'puppet/node'
require 'puppet/indirector/rest'

class Puppet::Node::Rest < Puppet::Indirector::REST
  desc "Get a node via REST. Puppet agent uses this to allow the puppet master
    to override its environment."

  def find(request)
    return super unless use_http_client?

    session = Puppet.lookup(:http_session)
    api = session.route_to(:puppet)
    api.get_node(
      request.key,
      environment: request.environment.to_s,
      configured_environment: request.options[:configured_environment],
      transaction_uuid: request.options[:transaction_uuid]
    )
  rescue Puppet::HTTP::ResponseError => e
    if e.response.code == 404
      return nil unless request.options[:fail_on_404]

      _, body = parse_response(e.response.nethttp)
      msg = _("Find %{uri} resulted in 404 with the message: %{body}") % { uri: elide(e.response.url.path, 100), body: body }
      raise Puppet::Error, msg
    else
      raise convert_to_http_error(e.response.nethttp)
    end
  end
end
