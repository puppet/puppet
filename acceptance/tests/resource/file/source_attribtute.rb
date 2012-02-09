test_name "The source attribute"

agents.each do |agent|
  target = agent.tmpfile('source_file_test')

  step "Ensure the test environment is clean"
  on agent, "rm -f #{target}"

# TODO: Add tests for puppet:// URIs with master/agent setups.
# step "when using a puppet:/// URI with a master/agent setup"
# step "when using a puppet://$server/ URI with a master/agent setup"

  step "Using a local file path"
  source = agent.tmpfile('local_source_file_test')
  on agent, "echo 'Yay, this is the local file.' > #{source}"

  manifest = "file { '#{target}': source => '#{source}', ensure => present }"
  apply_manifest_on agent, manifest
  on agent, "cat #{target}" do
    assert_match(/Yay, this is the local file./, stdout, "FIRST: File contents not matched on #{agent}")
  end

  step "Ensure the test environment is clean"
  on agent, "rm -f #{target}"

  step "Using a puppet:/// URI with puppet apply"
  on agent, puppet_agent("--configprint modulepath") do
    modulepath = agent.path_split(stdout)[0]
    modulepath = modulepath.chomp
    on agent, "mkdir -p '#{modulepath}/test_module/files'"
    #on agent, "echo 'Yay, this is the puppet:/// file.' > #{modulepath}/test_module/files/test_file.txt"
    on agent, "echo 'Yay, this is the puppetfile.' > '#{modulepath}/test_module/files/test_file.txt'"
  end

  manifest = "file { '#{target}': source => 'puppet:///modules/test_module/test_file.txt', ensure => present }"
  apply_manifest_on agent, manifest

  on agent, "cat #{target}" do
    assert_match(/Yay, this is the puppetfile./, stdout, "SECOND: File contents not matched on #{agent}")
  end

  step "Cleanup"
  on agent, "rm -f #{target}; rm -rf #{source}"
end

# Oops. We (Jesse & Jacob) ended up writing this before realizing that you
# can't actually specify "source => 'http://...'".  However, we're leaving it
# here, since there have been feature requests to support doing this.
# -- Mon, 07 Mar 2011 16:12:56 -0800
#
#step "Ensure the test environment is clean"
#on agents, 'rm -f /tmp/source_file_test.txt'
#
#step "when using an http:// file path"
#
#File.open '/tmp/puppet-acceptance-webrick-script.rb', 'w' do |file|
#  file.puts %q{#!/usr/bin/env ruby
#
#require 'webrick'
#
#class Simple < WEBrick::HTTPServlet::AbstractServlet
#  def do_GET(request, response)
#    status, content_type, body = do_stuff_with(request)
#
#    response.status = status
#    response['Content-Type'] = content_type
#    response.body = body
#  end
#
#  def do_stuff_with(request)
#    return 200, "text/plain", "you got a page"
#  end
#end
#
#class SimpleTwo < WEBrick::HTTPServlet::AbstractServlet
#  def do_GET(request, response)
#    status, content_type, body = do_stuff_with(request)
#
#    response.status = status
#    response['Content-Type'] = content_type
#    response.body = body
#  end
#
#  def do_stuff_with(request)
#    return 200, "text/plain", "you got a different page"
#  end
#end
#
#server = WEBrick::HTTPServer.new :Port => 8081
#trap "INT"  do server.shutdown end
#trap "TERM" do server.shutdown end
#trap "QUIT" do server.shutdown end
#
#server.mount "/", SimpleTwo
#server.mount "/foo.txt", Simple
#server.start
#}
#end
#
#scp_to master, '/tmp/puppet-acceptance-webrick-script.rb', '/tmp'
#on master, "chmod +x /tmp/puppet-acceptance-webrick-script.rb && /tmp/puppet-acceptance-webrick-script.rb &"
#
#manifest = "file { '/tmp/source_file_test.txt': source => 'http://#{master}:8081/foo.txt', ensure => present }"
#
#apply_manifest_on agents, manifest
#
#on agents, 'test "$(cat /tmp/source_file_test.txt)" = "you got a page"'
#
#on master, "killall puppet-acceptance-webrick-script.rb"
