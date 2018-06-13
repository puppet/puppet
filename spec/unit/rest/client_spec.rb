require 'spec_helper'

require 'puppet/rest/client'

describe Puppet::Rest::Client do
  context 'when creating a new client' do
    let(:ssl_config) { stub_everything('ssl config') }
    let(:http) { stub_everything('http', :ssl_config => ssl_config) }

    it 'initializes itself with basic defaults' do
      HTTPClient.expects(:new).returns(http)
      # Configure connection with HTTP settings
      Puppet[:http_read_timeout] = 120
      Puppet[:http_connect_timeout] = 10
      Puppet[:http_debug] = true

      http.expects(:connect_timeout=).with(10)
      http.expects(:receive_timeout=).with(120)
      http.expects(:debug_dev=).with($stderr)

      # Configure verify mode with SSL settings
      Puppet[:ssl_client_ca_auth] = '/fake/path'
      Puppet[:hostcert] = '/fake/cert/path'

      Puppet::Rest::Client.new
    end

    it 'configures a receive timeout when provided' do
      http.expects(:receive_timeout=).with(10)
      Puppet::Rest::Client.new(client: http, receive_timeout: 10)
    end
  end

  context 'when making requests' do
    let(:ssl_config) { stub_everything('ssl config') }
    let(:http) { stub_everything('http', :ssl_config => ssl_config) }
    let(:client) { Puppet::Rest::Client.new(client: http) }
    let(:url) { 'https://myserver.com:555/data' }

    describe "#get" do
      it 'makes a GET request given a URL, query hash, header hash, and streaming block' do
        query = { 'environment' => 'production' }
        header = { 'Accept' => 'text/plain' }
        response_string = ''
        chunk_processing = lambda { |chunk| response_string = chunk }
        http.expects(:get_content).with(url, { query: query, header: header }).yields('response')
        client.get(url, query: query, header: header, &chunk_processing)
        expect(response_string).to eq('response')
      end

      it 'throws an exception when the response to the GET is not OK' do
        fake_response = mock('resp', :status => HTTP::Status::BAD_REQUEST)
        http.expects(:get_content).with(url, query: nil, header: nil)
            .raises(HTTPClient::BadResponseError.new('failed request', fake_response))
        expect { client.get(url) }.to raise_error do |error|
          expect(error.message).to eq('failed request')
          expect(error.response).to be_a(Puppet::Rest::Response)
          expect(error.response.status_code).to eq(400)
        end
      end

      it 'resets all connections after making an insecure request' do
        client.expects(:insecure?).returns(true)
        http.expects(:reset_all)
        client.get(url) { |chunk| chunk }
      end
    end

    describe "#put" do
      it 'makes a PUT request given a URL, string body, query hash, and header hash' do
        body = 'send to server'
        query = { 'environment' => 'production' }
        header = { 'Accept' => 'text/plain' }
        http.expects(:put).with(url, { body: body, query: query, header: header })
        client.put(url, body: body, query: query, header: header)
      end
    end
  end
end
