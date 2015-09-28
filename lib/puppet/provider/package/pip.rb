# Puppet package provider for Python's `pip` package management frontend.
# <http://pip.openplans.org/>

require 'puppet/provider/package'
require 'xmlrpc/client'

Puppet::Type.type(:package).provide :pip,
  :parent => ::Puppet::Provider::Package do

  desc "Python packages via `pip`.

  This provider supports the `install_options` attribute, which allows command-line flags to be passed to pip.
  These options should be specified as a string (e.g. '--flag'), a hash (e.g. {'--flag' => 'value'}),
  or an array where each element is either a string or a hash."

  has_feature :installable, :uninstallable, :upgradeable, :versionable, :install_options

  # Parse lines of output from `pip freeze`, which are structured as
  # _package_==_version_.
  def self.parse(line)
    if line.chomp =~ /^([^=]+)==([^=]+)$/
      {:ensure => $2, :name => $1, :provider => name}
    else
      nil
    end
  end

  # Return an array of structured information about every installed package
  # that's managed by `pip` or an empty array if `pip` is not available.
  def self.instances
    packages = []
    pip_cmd = which(cmd) or return []
    execpipe "#{pip_cmd} freeze" do |process|
      process.collect do |line|
        next unless options = parse(line)
        packages << new(options)
      end
    end
    packages
  end

  def self.cmd
    if Facter.value(:osfamily) == "RedHat" and Facter.value(:operatingsystemmajrelease).to_i < 7
      "pip-python"
    else
      "pip"
    end
  end

  # Return structured information about a particular package or `nil` if
  # it is not installed or `pip` itself is not available.
  def query
    self.class.instances.each do |provider_pip|
      return provider_pip.properties if @resource[:name].downcase == provider_pip.name.downcase
    end
    return nil
  end

  # Return latest version from PyPI repo as seen by pip
  def latest
    pip_cmd = which(self.class.cmd) or return nil
    # This is the least hackish way to have pip look up versions. Output we're interested in is:
    # Could not find a version that satisfies the requirement Django==versionplease (from versions: 1.1.3, 1.8rc1)
    execpipe "#{pip_cmd} install #{@resource[:name]}==versionplease" do |process|
      process.collect do |line|
        if line =~ /from versions: /
          textAfterLastMatch = $'
          versionList = textAfterLastMatch.chomp(")\n").split(', ')
          return versionList.last
        end
      end
      return nil
    end
  end

  # Install a package.  The ensure parameter may specify installed,
  # latest, a version number, or, in conjunction with the source
  # parameter, an SCM revision.  In that case, the source parameter
  # gives the fully-qualified URL to the repository.
  def install
    args = %w{install -q}
    args +=  install_options if @resource[:install_options]
    if @resource[:source]
      if String === @resource[:ensure]
        args << "#{@resource[:source]}@#{@resource[:ensure]}#egg=#{
          @resource[:name]}"
      else
        args << "#{@resource[:source]}#egg=#{@resource[:name]}"
      end
    else
      case @resource[:ensure]
      when String
        args << "#{@resource[:name]}==#{@resource[:ensure]}"
      when :latest
        args << "--upgrade" << @resource[:name]
      else
        args << @resource[:name]
      end
    end
    lazy_pip *args
  end

  # Uninstall a package.  Uninstall won't work reliably on Debian/Ubuntu
  # unless this issue gets fixed.
  # <http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=562544>
  def uninstall
    lazy_pip "uninstall", "-y", "-q", @resource[:name]
  end

  def update
    install
  end

  # Execute a `pip` command.  If Puppet doesn't yet know how to do so,
  # try to teach it and if even that fails, raise the error.
  private
  def lazy_pip(*args)
    pip *args
  rescue NoMethodError => e
    if pathname = which(self.class.cmd)
      self.class.commands :pip => pathname
      pip *args
    else
      raise e, "Could not locate the #{self.class.cmd} command.", e.backtrace
    end
  end

  def install_options
    join_options(@resource[:install_options])
  end
end
