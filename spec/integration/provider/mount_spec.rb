require 'spec_helper'
require 'puppet_spec/compiler'

require 'puppet/file_bucket/dipper'

describe "mount provider (integration)", :unless => Puppet.features.microsoft_windows? do
  include PuppetSpec::Files
  include PuppetSpec::Compiler

  family = Facter.value(:osfamily)

  def create_fake_fstab(initially_contains_entry)
    File.open(@fake_fstab, 'w') do |f|
      if initially_contains_entry
        f.puts("/dev/disk1s1\t/Volumes/foo_disk\tmsdos\tlocal\t0\t0")
      end
    end
  end

  before :each do
    @fake_fstab = tmpfile('fstab')
    @current_options = "local"
    @current_device = "/dev/disk1s1"
    Puppet::Type.type(:mount).defaultprovider.stubs(:default_target).returns(@fake_fstab)
    Facter.stubs(:value).with(:hostname).returns('some_host')
    Facter.stubs(:value).with(:domain).returns('some_domain')
    Facter.stubs(:value).with(:kernel).returns('Linux')
    Facter.stubs(:value).with(:operatingsystem).returns('RedHat')
    Facter.stubs(:value).with(:osfamily).returns('RedHat')
    Puppet::Util::ExecutionStub.set do |command, options|
      case command[0]
      when %r{/s?bin/mount}
        if command.length == 1
          if @mounted
            "#{@current_device} on /Volumes/foo_disk (msdos, #{@current_options})\n"
          else
            ''
          end
        else
          expect(command.last).to eq('/Volumes/foo_disk')
          @current_device = check_fstab(true)
          @mounted = true
          ''
        end
      when %r{/s?bin/umount}
        expect(command.length).to eq(2)
        expect(command[1]).to eq('/Volumes/foo_disk')
        expect(@mounted).to eq(true) # "umount" doesn't work when device not mounted (see #6632)
        @mounted = false
        ''
      else
        fail "Unexpected command #{command.inspect} executed"
      end
    end
  end

  after :each do
    Puppet::Type::Mount::ProviderParsed.clear # Work around bug #6628
  end

  def check_fstab(expected_to_be_present)
    # Verify that the fake fstab has the expected data in it
    fstab_contents = File.read(@fake_fstab).split("\n").reject { |x| x =~ /^#|^$/ }
    if expected_to_be_present
      expect(fstab_contents.length()).to eq(1)
      device, rest_of_line = fstab_contents[0].split(/\t/,2)
      expect(rest_of_line).to eq("/Volumes/foo_disk\tmsdos\t#{@desired_options}\t0\t0")
      device
    else
      expect(fstab_contents.length()).to eq(0)
      nil
    end
  end

  def run_in_catalog(settings)
    resource = Puppet::Type.type(:mount).new(settings.merge(:name => "/Volumes/foo_disk",
                                             :device => "/dev/disk1s1", :fstype => "msdos"))
    Puppet::FileBucket::Dipper.any_instance.stubs(:backup) # Don't backup to the filebucket
    resource.expects(:err).never
    catalog = Puppet::Resource::Catalog.new
    catalog.host_config = false # Stop Puppet from doing a bunch of magic
    catalog.add_resource resource
    catalog.apply
  end

  [false, true].each do |initial_state|
    describe "When initially #{initial_state ? 'mounted' : 'unmounted'}" do
      before :each do
        @mounted = initial_state
      end

      [false, true].each do |initial_fstab_entry|
        describe "When there is #{initial_fstab_entry ? 'an' : 'no'} initial fstab entry" do
          before :each do
            create_fake_fstab(initial_fstab_entry)
          end

          [:defined, :present, :mounted, :unmounted, :absent].each do |ensure_setting|
            expected_final_state = case ensure_setting
              when :mounted
                true
              when :unmounted, :absent
                false
              when :defined, :present
                initial_state
              else
                fail "Unknown ensure_setting #{ensure_setting}"
            end
            expected_fstab_data = (ensure_setting != :absent)
            describe "When setting ensure => #{ensure_setting}" do
              ["local", "journaled", "", nil].each do |options_setting|
                describe "When setting options => '#{options_setting}'" do
                  it "should leave the system in the #{expected_final_state ? 'mounted' : 'unmounted'} state, #{expected_fstab_data ? 'with' : 'without'} data in /etc/fstab" do
                    if family == "Solaris"
                      skip("Solaris: The mock :operatingsystem value does not get changed in lib/puppet/provider/mount/parsed.rb")
                    else
                      if options_setting && options_setting.empty?
                        expect { run_in_catalog(:ensure=>ensure_setting, :options => options_setting) }.to raise_error Puppet::ResourceError
                      else
                        if options_setting
                          @desired_options = options_setting
                          run_in_catalog(:ensure=>ensure_setting, :options => options_setting)
                        else
                          if initial_fstab_entry
                            @desired_options = @current_options
                          else
                            @desired_options = 'defaults'
                          end
                          run_in_catalog(:ensure=>ensure_setting)
                        end
                        expect(@mounted).to eq(expected_final_state)
                        if expected_fstab_data
                          expect(check_fstab(expected_fstab_data)).to eq("/dev/disk1s1")
                        else
                          expect(check_fstab(expected_fstab_data)).to eq(nil)
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  describe "When the wrong device is mounted" do
    it "should remount the correct device" do
      pending "Due to bug 6309"
      @mounted = true
      @current_device = "/dev/disk2s2"
      create_fake_fstab(true)
      @desired_options = "local"
      run_in_catalog(:ensure=>:mounted, :options=>'local')
      expect(@current_device).to eq("/dev/disk1s1")
      expect(@mounted).to eq(true)
      expect(@current_options).to eq('local')
      expect(check_fstab(true)).to eq("/dev/disk1s1")
    end
  end

  describe "when updating existing fstabs" do
    let(:tmp_fstab) { tmpfile('fstab_fixture') }
    let(:resources_manifest) { "resources { 'mount': sort_output => true }" }

    def compare(fixture)
      wanted = File.read(my_fixture(fixture))
      current = File.read(tmp_fstab).gsub(/# HEADER[^\n]*\n/, '')
      expect(current).to eq(wanted)
    end

    before :each do
      FileUtils.cp(my_fixture('ordering'), tmp_fstab)
    end

    { 'with unrelated entries' => {
        :example => 'should append new entries',
        :title => '/opt/data/log-archive',
        :device => '/dev/vg0/log_archive',
        :result => 'ordering-unrelated',
        :result_unsorted => 'ordering-unrelated',
      },
      'with an inner mount point' => {
        :example => 'should move the inner mount point',
        :title => '/opt/data',
        :device => '/dev/vg0/data',
        :result => 'ordering-inner',
        :result_unsorted => 'unordered-inner',
      },
      'with a newly contained bind mount' => {
        :example => 'should move the bind mount',
        :title => '/opt/temp',
        :device => '/dev/vg0/temp',
        :result => 'ordering-bind',
        :result_unsorted => 'unordered-bind',
      },
      'with a previously unsorted fstab' => {
        :example => 'should fix existing issues',
        :original => 'unordered',
        :title => '/opt/data/log-archive',
        :device => '/dev/vg0/log_archive',
        :result => 'unordered-fixed',
        :result_unsorted => 'unordered-unfixed',
      },
    }.each do |context_descr, data|
      context context_descr do
        [ true, false ].each do |set_order|

          if set_order
            example_description = "and output ordering #{data[:example]}"
          else
            example_description = 'and no ordering should just append new entries'
          end

          it example_description do
            if data[:original]
              FileUtils.cp(my_fixture(data[:original]), tmp_fstab)
            end

            manifest = <<-MANIFEST
              mount {
                  '#{data[:title]}':
                      ensure => 'present',
                      device => '#{data[:device]}',
                      fstype => 'ext4',
                      options => 'defaults',
                      target  => '#{tmp_fstab}',
              }
            MANIFEST

            if set_order
              manifest += resources_manifest
              apply_with_error_check(manifest)
              compare(data[:result])
            else
              apply_with_error_check(manifest)
              compare(data[:result_unsorted])
            end
          end
        end
      end
    end
  end
end
