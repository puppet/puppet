Puppet::Type.type(:package).provide :zypper, :parent => :rpm do
  desc "Support for SuSE `zypper` package manager. Found in SLES10sp2+ and SLES11.

    This provider supports the `install_options` attribute, which allows command-line flags to be passed to zypper.
    These options should be specified as a string (e.g. '--flag'), a hash (e.g. {'--flag' => 'value'}),
    or an array where each element is either a string or a hash."

  has_feature :versionable, :install_options, :virtual_packages

  commands :zypper => "/usr/bin/zypper"

  confine    :operatingsystem => [:suse, :sles, :sled, :opensuse]

  #on zypper versions <1.0, the version option returns 1
  #some versions of zypper output on stderr
  def zypper_version
    cmd = [self.class.command(:zypper),"--version"]
    execute(cmd, { :failonfail => false, :combine => true})
  end

  # Install a package using 'zypper'.
  def install
    should = @resource[:ensure]
    self.debug "Ensuring => #{should}"
    wanted = @resource[:name]

    # XXX: We don't actually deal with epochs here.
    package_version = @resource[:ensure].is_a?(String) ? @resource[:ensure] : @resource[:version]
    if package_version
      # Add the package version
      wanted = "#{wanted}-#{package_version}"
    end

    #This has been tested with following zypper versions
    #SLE 10.2: 0.6.104
    #SLE 11.0: 1.0.8
    #OpenSuse 10.2: 0.6.13
    #OpenSuse 11.2: 1.2.8
    #Assume that this will work on newer zypper versions

    #extract version numbers and convert to integers
    major, minor, patch = zypper_version.scan(/\d+/).map{ |x| x.to_i }
    self.debug "Detected zypper version #{major}.#{minor}.#{patch}"

    #zypper version < 1.0 does not support --quiet flag
    if major < 1
      quiet = '--terse'
    else
      quiet = '--quiet'
    end

    options = [quiet, :install]

    #zypper 0.6.13 (OpenSuSE 10.2) does not support auto agree with licenses
    options << '--auto-agree-with-licenses' unless major < 1 and minor <= 6 and patch <= 13
    options << '--no-confirm'
    options << '--name' unless @resource.allow_virtual? || package_version
    options += install_options if resource[:install_options]
    options << wanted

    zypper *options

    unless self.query
      raise Puppet::ExecutionFailure.new(
        "Could not find package #{self.name}"
      )
    end
  end

  def version=
    self.install
  end

  # What's the latest package version available?
  def latest
    #zypper can only get a list of *all* available packages?
    output = zypper "list-updates"

    if output =~ /#{Regexp.escape @resource[:name]}\s*\|.*?\|\s*([^\s\|]+)/
      return $1
    else
      # zypper didn't find updates, pretend the current
      # version is the latest
      return @property_hash[:ensure]
    end
  end

  def update
    # zypper install can be used for update, too
    self.install
  end
end
