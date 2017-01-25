tag 'risk:medium'
test_name 'ensure ruby compiler optimization is >= 2'

tag 'risk:medium'

step 'Validate ruby compiler optimization is >= 2' do
  hosts.each do |host|
    if host['platform'] =~ /osx/
      skip_test "OSX is known to have incorrect optimization - see RE-3281"
    end

    on(host, "env PATH=\"#{host['privatebindir']}:${PATH}\" ruby -r rbconfig -e 'puts RbConfig::CONFIG[\"CFLAGS\"]'") do |res|
      o_level = -99
      m = res.stdout.match(/-O(\d)/)
      m = res.stdout.match(/-xO(\d)/) unless m
      o_level = m[1].to_i if m

      fail_test('ruby compiler optimization is not >=2') unless o_level >= 2
    end
  end
end
