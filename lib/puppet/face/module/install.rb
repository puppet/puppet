Puppet::Face.define(:module, '1.0.0') do
  action(:install) do
    summary "Install a module from a repository or release archive."
    description <<-EOT
      Installs a module from the Puppet Forge, from a release archive file
      on-disk, or from a private Forge-like repository.

      The specified module will be installed into the directory
      specified with the --dir option, which defaults to
      #{Puppet.settings[:modulepath].split(File::PATH_SEPARATOR).first}.
    EOT

    returns "Pathname object representing the path to the installed module."

    examples <<-EOT
      Install a module from the default repository:

      $ puppet module install puppetlabs/vcsrepo
      notice: Installing puppetlabs-vcsrepo-0.0.4.tar.gz to /etc/puppet/modules/vcsrepo

      Install a specific module version from a repository:

      $ puppet module install puppetlabs/vcsrepo -v 0.0.4
      notice: Installing puppetlabs-vcsrepo-0.0.4.tar.gz to /etc/puppet/modules/vcsrepo

      Install a module into a specific directory:

      $ puppet module install puppetlabs/vcsrepo --dir=/usr/share/puppet/modules
      notice: Installing puppetlabs-vcsrepo-0.0.4.tar.gz to /usr/share/puppet/modules/vcsrepo

      Install a module into a specific directory and check for dependencies in other directories:

      $ puppet module install puppetlabs/vcsrepo --dir=/usr/share/puppet/modules --modulepath /etc/puppet/modules
      notice: Installing puppetlabs-vcsrepo-0.0.4.tar.gz to /usr/share/puppet/modules/vcsrepo
      Install a module from a release archive:

      $ puppet module install puppetlabs-vcsrepo-0.0.4.tar.gz
      notice: Installing puppetlabs-vcsrepo-0.0.4.tar.gz to /etc/puppet/modules/vcsrepo
    EOT

    arguments "<name>"

    option "--force", "-f" do
      summary "Force overwrite of existing module, if any."
      description <<-EOT
        Force overwrite of existing module, if any.
      EOT
    end

    option "--dir DIR", "-i DIR" do
      summary "The directory into which modules are installed."
      description <<-EOT
        The directory into which modules are installed, defaults to the first
        directory in the modulepath.  Setting just the dir option sets the
        modulepath as well.  If you want install to check for dependencies in
        other paths, also give the modulepath option.
      EOT
    end

    option "--module-repository REPO", "-r REPO" do
      default_to { Puppet.settings[:module_repository] }
      summary "Module repository to use."
      description <<-EOT
        The module repository to use, as a URL. Defaults to http://forge.puppetlabs.com.
      EOT
    end

    option "--ignore-dependencies" do
      summary "Do not attempt to install dependencies"
      description <<-EOT
        Do not attempt to install dependencies
      EOT
    end

    option "--modulepath MODULEPATH" do
      summary "Which directories to look for modules in"
      description <<-EOT
        The directory into which modules are installed; defaults to the first
        directory in the modulepath.  If the dir option is also given, it is
        prepended to the modulepath.
      EOT
    end

    option "--version VER", "-v VER" do
      summary "Module version to install."
      description <<-EOT
        Module version to install; can be an exact version or a requirement string,
        eg '>= 1.0.3'. Defaults to latest version.
      EOT
    end

    when_invoked do |name, options|
      sep = File::PATH_SEPARATOR
      if options[:dir]
        if options[:modulepath]
          options[:modulepath] = "#{options[:dir]}#{sep}#{options[:modulepath]}"
          Puppet.settings[:modulepath] = options[:modulepath]
        else
          Puppet.settings[:modulepath] = options[:dir]
        end
      elsif options[:modulepath]
        Puppet.settings[:modulepath] = options[:modulepath]
      end
      options[:dir] = Puppet.settings[:modulepath].split(sep).first

      Puppet.settings[:module_repository] = options[:module_repository] if options[:module_repository]

      Puppet.notice "Preparing to install into #{options[:dir]} ..."
      Puppet::Module::Tool::Applications::Installer.run(name, options)
    end

    when_rendering :console do |return_value, name, options|
      if return_value[:result] == :failure
        Puppet.err(return_value[:error][:multiline])
        exit 1
      else
        tree = format_tree(return_value[:installed_modules], return_value[:install_dir])
        return_value[:install_dir] + "\n" +
        Puppet::Module::Tool.build_tree(tree)
      end
    end
  end
end

def format_tree(mods, dir)
  mods.each do |mod|
    version_string = mod[:version][:vstring].sub(/^(?!v)/, 'v')

    if mod[:action] == :upgrade
      previous_version = mod[:previous_version].sub(/^(?!v)/, 'v')
      version_string = "#{previous_version} -> #{version_string}"
    end

    mod[:text] = "#{mod[:module]} (#{version_string})"
    mod[:text] += " [#{mod[:path]}]" unless mod[:path] == dir
    format_tree(mod[:dependencies], dir)
  end
end
