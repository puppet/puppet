module Puppet
  module Acceptance
    module RpmUtils
      # Utilities for creating a basic rpm package and using it in tests
      @@defaults = {:repo => '/tmp/rpmrepo', :pkg => 'mypkg', :publisher => 'tstpub.lan', :version => '1.0'}

      def rpm_provider(agent)
        has_dnf = on(agent, 'which dnf', :acceptable_exit_codes => [0,1]).exit_code
        if has_dnf == 0
          'dnf'
        else
          'yum'
        end
      end

      def setup(agent)
        cmd = rpm_provider(agent)
        required_packages = ['createrepo', 'rpm-build']
        required_packages.each do |pkg|
          unless ((on agent, "#{cmd} list installed #{pkg}", :acceptable_exit_codes => (0..255)).exit_code == 0) then
            on agent, "#{cmd} install -y #{pkg}"
          end
        end
      end

      def clean_rpm(agent, o={})
        cmd = rpm_provider(agent)
        o = @@defaults.merge(o)
        on agent, "rm -rf #{o[:repo]}", :acceptable_exit_codes => (0..255)
        on agent, "#{cmd} remove -y #{o[:pkg]}", :acceptable_exit_codes => (0..255)
        on agent, "rm -f /etc/yum.repos.d/#{o[:publisher]}.repo", :acceptable_exit_codes => (0..255)
      end

      def setup_rpm(agent, o={})
        setup(agent)
        o = @@defaults.merge(o)
        on agent, "mkdir -p #{o[:repo]}/{RPMS,SRPMS,BUILD,SOURCES,SPECS}"
        on agent, "echo '%_topdir #{o[:repo]}' > ~/.rpmmacros"
        on agent, "createrepo #{o[:repo]}"
        on agent, "cat <<EOF > /etc/yum.repos.d/#{o[:publisher]}.repo
[#{o[:publisher]}]
name=#{o[:publisher]}
baseurl=file://#{o[:repo]}/
enabled=1
gpgcheck=0
EOF
"
      end

      def send_rpm(agent, o={})
        setup(agent)
        o = @@defaults.merge(o)
        on agent, "mkdir -p #{o[:repo]}/#{o[:pkg]}-#{o[:version]}/usr/bin"
        on agent, "cat <<EOF > #{o[:repo]}/#{o[:pkg]}
#!/bin/bash
echo Hello World
EOF
"
        pkg_name = "#{o[:pkg]}-#{o[:version]}"
        on agent, "install -m 755 #{o[:repo]}/#{o[:pkg]} #{o[:repo]}/#{pkg_name}/usr/bin"
        on agent, "tar -zcvf #{o[:repo]}/SOURCES/#{pkg_name}.tar.gz -C #{o[:repo]} #{pkg_name}"
        on agent, "cat <<EOF > #{o[:repo]}/SPECS/#{o[:pkg]}.spec
# Don't try fancy stuff like debuginfo, which is useless on binary-only packages. Don't strip binary too
# Be sure buildpolicy set to do nothing
%define        __spec_install_post %{nil}
%define          debug_package %{nil}
%define        __os_install_post %{_dbpath}/brp-compress

Summary: A very simple toy bin rpm package
Name: #{o[:pkg]}
Version: #{o[:version]}
Release: 1
License: GPL+
Group: Development/Tools
SOURCE0 : %{name}-%{version}.tar.gz
URL: https://www.puppetlabs.com/

BuildRoot: %{_topdir}/BUILD/%{name}-%{version}-%{release}-root

%description
%{summary}

%prep
%setup -q

%build
# Empty section.

%install
rm -rf %{buildroot}
mkdir -p  %{buildroot}

# in builddir
cp -a * %{buildroot}


%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%{_bindir}/*

%changelog
* Mon Dec 01 2014  Michael Smith <michael.smith@puppetlabs.com> #{o[:version]}-1
- First Build

EOF
"
        on agent, "rpmbuild -ba #{o[:repo]}/SPECS/#{o[:pkg]}.spec"
        on agent, "createrepo --update #{o[:repo]}"

        cmd = rpm_provider(agent)
        # DNF requires a cache reset to make local repositories accessible.
        if cmd == 'dnf'
          on agent, "dnf clean metadata"
        end
      end
    end
  end
end

