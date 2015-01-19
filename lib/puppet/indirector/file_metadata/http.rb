require 'puppet/file_serving/http_metadata'
require 'puppet/file_serving/terminus_helper'
require 'puppet/indirector/plain'
require 'puppet/indirector/file_metadata'
require 'net/http'
require 'puppet/network/http_pool'

class Puppet::Indirector::FileMetadata::Http < Puppet::Indirector::Plain
  desc "Retrieve file metadata from a remote HTTP server."

  include Puppet::FileServing::TerminusHelper

  def find(request)
    uri = URI( unescape_url(request.key) )

    use_ssl = uri.scheme == 'https'
    connection = Puppet::Network::HttpPool.http_instance(uri.host, uri.port, use_ssl)

    response = connection.head(uri.path)

    Puppet.debug("HTTP HEAD request to #{uri} returned #{response.code} #{response.message}")

    if response.is_a?(Net::HTTPSuccess)
      Puppet::FileServing::HttpMetadata.new(response)
    end
  end

  def search(request)
    raise Puppet::Error, "cannot lookup multiple files"
  end
end
