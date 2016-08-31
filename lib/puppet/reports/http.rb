require 'puppet'
require 'net/http'
require 'uri'

Puppet::Reports.register_report(:http) do

  desc <<-DESC
  Send report information via HTTP to the `reporturl`. Each host sends
  its report as a YAML dump and this sends this YAML to a client via HTTP POST.
  The YAML is the body of the request.
  DESC

  def process
    url = URI.parse(Puppet[:reporturl])
    timeout = Puppet[:reporturl_timeout]
    req = Net::HTTP::Post.new(url.path)
    req.body = self.to_yaml
    req.content_type = "application/x-yaml"
    Net::HTTP.new(url.host, url.port).start {|http|
      http.read_timeout = timeout
      http.open_timeout = timeout
      response = http.request(req)
      unless response.kind_of?(Net::HTTPSuccess)
        Puppet.err "Unable to submit report to #{Puppet[:reporturl].to_s} [#{response.code}] #{response.msg}"
      end
    }
  rescue Timeout::Error
      Puppet.err "Timeout when submitting report to #{Puppet[:reporturl].to_s}"
  end
end
