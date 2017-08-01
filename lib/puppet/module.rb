require 'puppet/util/logging'
require 'json'
require 'semantic_puppet/gem_version'

# Support for modules
class Puppet::Module
  class Error < Puppet::Error; end
  class MissingModule < Error; end
  class IncompatibleModule < Error; end
  class UnsupportedPlatform < Error; end
  class IncompatiblePlatform < Error; end
  class MissingMetadata < Error; end
  class FaultyMetadata < Error; end
  class InvalidName < Error; end
  class InvalidFilePattern < Error; end

  include Puppet::Util::Logging

  FILETYPES = {
    "manifests" => "manifests",
    "files" => "files",
    "templates" => "templates",
    "plugins" => "lib",
    "pluginfacts" => "facts.d",
  }

  # Find and return the +module+ that +path+ belongs to. If +path+ is
  # absolute, or if there is no module whose name is the first component
  # of +path+, return +nil+
  def self.find(modname, environment = nil)
    return nil unless modname
    # Unless a specific environment is given, use the current environment
    env = environment ? Puppet.lookup(:environments).get!(environment) : Puppet.lookup(:current_environment)
    env.module(modname)
  end

  def self.is_module_directory?(name, path)
    # it must be a directory
    fullpath = File.join(path, name)
    return false unless Puppet::FileSystem.directory?(fullpath)
    return is_module_directory_name?(name)
  end

  def self.is_module_directory_name?(name)
    # it must match an installed module name according to forge validator
    return true if name =~ /^[a-z][a-z0-9_]*$/
    return false
  end

  def self.is_module_namespaced_name?(name)
    # it must match the full module name according to forge validator
    return true if name =~ /^[a-zA-Z0-9]+[-][a-z][a-z0-9_]*$/
    return false
  end

  # @api private
  def self.parse_range(range, strict)
    @parse_range_method ||= SemanticPuppet::VersionRange.method(:parse)
    if @parse_range_method.arity == 1
      @semver_gem_version ||= SemanticPuppet::Version.parse(SemanticPuppet::VERSION)

      # Give user a heads-up if the desired strict setting cannot be honored
      if strict
        if @semver_gem_version.major < 1
          Puppet.warn_once('strict_version_ranges', 'version_range_cannot_be_strict',
            _('VersionRanges will never be strict when using non-vendored SemanticPuppet gem, version %{version}') % { version: @semver_gem_version},
            :default, :default, :notice)
        end
      else
        if @semver_gem_version.major >= 1
          Puppet.warn_once('strict_version_ranges', 'version_range_always_strict',
            _('VersionRanges will always be strict when using non-vendored SemanticPuppet gem, version %{version}') % { version: @semver_gem_version},
            :default, :default, :notice)
        end
      end
      @parse_range_method.call(range)
    else
      @parse_range_method.call(range, strict)
    end
  end

  attr_reader :name, :environment, :path, :metadata
  attr_writer :environment

  attr_accessor :dependencies, :forge_name
  attr_accessor :source, :author, :version, :license, :summary, :description, :project_page

  def initialize(name, path, environment, strict_semver = true)
    @name = name
    @path = path
    @strict_semver = strict_semver
    @environment = environment

    assert_validity
    load_metadata

    @absolute_path_to_manifests = Puppet::FileSystem::PathPattern.absolute(manifests)
  end

  # @deprecated The puppetversion module metadata field is no longer used.
  def puppetversion
    nil
  end

  # @deprecated The puppetversion module metadata field is no longer used.
  def puppetversion=(something)
  end

  # @deprecated The puppetversion module metadata field is no longer used.
  def validate_puppet_version
    return
  end

  def has_metadata?
    begin
      load_metadata
      @metadata.is_a?(Hash) && !@metadata.empty?
    rescue Puppet::Module::MissingMetadata
      false
    end
  end

  FILETYPES.each do |type, location|
    # A boolean method to let external callers determine if
    # we have files of a given type.
    define_method(type + '?') do
      type_subpath = subpath(location)
      unless Puppet::FileSystem.exist?(type_subpath)
        Puppet.debug("No #{type} found in subpath '#{type_subpath}' " +
                         "(file / directory does not exist)")
        return false
      end

      return true
    end

    # A method for returning a given file of a given type.
    # e.g., file = mod.manifest("my/manifest.pp")
    #
    # If the file name is nil, then the base directory for the
    # file type is passed; this is used for fileserving.
    define_method(type.sub(/s$/, '')) do |file|
      # If 'file' is nil then they're asking for the base path.
      # This is used for things like fileserving.
      if file
        full_path = File.join(subpath(location), file)
      else
        full_path = subpath(location)
      end

      return nil unless Puppet::FileSystem.exist?(full_path)
      return full_path
    end

    # Return the base directory for the given type
    define_method(type) do
      subpath(location)
    end
  end

  def license_file
    return @license_file if defined?(@license_file)

    return @license_file = nil unless path
    @license_file = File.join(path, "License")
  end

  def read_metadata
    md_file = metadata_file
    md_file.nil? ? {} : JSON.parse(File.read(md_file, :encoding => 'utf-8'))
  rescue Errno::ENOENT
    {}
  rescue JSON::JSONError => e
    msg = "#{name} has an invalid and unparsable metadata.json file. The parse error: #{e.message}"
    case Puppet[:strict]
    when :off
      Puppet.debug(msg)
    when :warning
      Puppet.warning(msg)
    when :error
      raise FaultyMetadata, msg
    end
    {}
  end

  def load_metadata
    return if instance_variable_defined?(:@metadata)

    @metadata = data = read_metadata
    return if data.empty?

    @forge_name = data['name'].gsub('-', '/') if data['name']

    [:source, :author, :version, :license, :dependencies].each do |attr|
      value = data[attr.to_s]
      raise MissingMetadata, "No #{attr} module metadata provided for #{self.name}" if value.nil?

      if attr == :dependencies
        unless value.is_a?(Array)
          raise MissingMetadata, "The value for the key dependencies in the file metadata.json of the module #{self.name} must be an array, not: '#{value}'"
        end
        value.each do |dep|
          name = dep['name']
          dep['name'] = name.tr('-', '/') unless name.nil?
          dep['version_requirement'] ||= '>= 0.0.0'
        end
      end

      send(attr.to_s + "=", value)
    end
  end

  # Return the list of manifests matching the given glob pattern,
  # defaulting to 'init.pp' for empty modules.
  def match_manifests(rest)
    if rest
      wanted_manifests = wanted_manifests_from(rest)
      searched_manifests = wanted_manifests.glob.reject { |f| FileTest.directory?(f) }
    else
      searched_manifests = []
    end

    # (#4220) Always ensure init.pp in case class is defined there.
    init_manifest = manifest("init.pp")
    if !init_manifest.nil? && !searched_manifests.include?(init_manifest)
      searched_manifests.unshift(init_manifest)
    end
    searched_manifests
  end

  def all_manifests
    return [] unless Puppet::FileSystem.exist?(manifests)

    Dir.glob(File.join(manifests, '**', '*.pp'))
  end

  def metadata_file
    return @metadata_file if defined?(@metadata_file)

    return @metadata_file = nil unless path
    @metadata_file = File.join(path, "metadata.json")
  end

  def hiera_conf_file
    unless defined?(@hiera_conf_file)
       @hiera_conf_file = path.nil? ? nil : File.join(path, Puppet::Pops::Lookup::HieraConfig::CONFIG_FILE_NAME)
    end
    @hiera_conf_file
  end

  def has_hiera_conf?
    hiera_conf_file.nil? ? false : Puppet::FileSystem.exist?(hiera_conf_file)
  end

  def modulepath
    File.dirname(path) if path
  end

  # Find all plugin directories.  This is used by the Plugins fileserving mount.
  def plugin_directory
    subpath("lib")
  end

  def plugin_fact_directory
    subpath("facts.d")
  end

  def has_external_facts?
    File.directory?(plugin_fact_directory)
  end

  def supports(name, version = nil)
    @supports ||= []
    @supports << [name, version]
  end

  def to_s
    result = "Module #{name}"
    result += "(#{path})" if path
    result
  end

  def dependencies_as_modules
    dependent_modules = []
    dependencies and dependencies.each do |dep|
      author, dep_name = dep["name"].split('/')
      found_module = environment.module(dep_name)
      dependent_modules << found_module if found_module
    end

    dependent_modules
  end

  def required_by
    environment.module_requirements[self.forge_name] || {}
  end

  # Identify and mark unmet dependencies.  A dependency will be marked unmet
  # for the following reasons:
  #
  #   * not installed and is thus considered missing
  #   * installed and does not meet the version requirements for this module
  #   * installed and doesn't use semantic versioning
  #
  # Returns a list of hashes representing the details of an unmet dependency.
  #
  # Example:
  #
  #   [
  #     {
  #       :reason => :missing,
  #       :name   => 'puppetlabs-mysql',
  #       :version_constraint => 'v0.0.1',
  #       :mod_details => {
  #         :installed_version => '0.0.1'
  #       }
  #       :parent => {
  #         :name    => 'puppetlabs-bacula',
  #         :version => 'v1.0.0'
  #       }
  #     }
  #   ]
  #
  def unmet_dependencies
    unmet_dependencies = []
    return unmet_dependencies unless dependencies

    dependencies.each do |dependency|
      name = dependency['name']
      version_string = dependency['version_requirement'] || '>= 0.0.0'

      dep_mod = begin
        environment.module_by_forge_name(name)
      rescue
        nil
      end

      error_details = {
        :name => name,
        :version_constraint => version_string.gsub(/^(?=\d)/, "v"),
        :parent => {
          :name => self.forge_name,
          :version => self.version.gsub(/^(?=\d)/, "v")
        },
        :mod_details => {
          :installed_version => dep_mod.nil? ? nil : dep_mod.version
        }
      }

      unless dep_mod
        error_details[:reason] = :missing
        unmet_dependencies << error_details
        next
      end

      if version_string
        begin
          required_version_semver_range = self.class.parse_range(version_string, @strict_semver)
          actual_version_semver = SemanticPuppet::Version.parse(dep_mod.version)
        rescue ArgumentError
          error_details[:reason] = :non_semantic_version
          unmet_dependencies << error_details
          next
        end

        unless required_version_semver_range.include? actual_version_semver
          error_details[:reason] = :version_mismatch
          unmet_dependencies << error_details
          next
        end
      end
    end

    unmet_dependencies
  end

  def ==(other)
    self.name == other.name &&
    self.version == other.version &&
    self.path == other.path &&
    self.environment == other.environment
  end

  def strict_semver?
    @strict_semver
  end

  private

  def wanted_manifests_from(pattern)
    begin
      extended = File.extname(pattern).empty? ? "#{pattern}.pp" : pattern
      relative_pattern = Puppet::FileSystem::PathPattern.relative(extended)
    rescue Puppet::FileSystem::PathPattern::InvalidPattern => error
      raise Puppet::Module::InvalidFilePattern.new(
        "The pattern \"#{pattern}\" to find manifests in the module \"#{name}\" " +
        "is invalid and potentially unsafe.", error)
    end

    relative_pattern.prefix_with(@absolute_path_to_manifests)
  end

  def subpath(type)
    File.join(path, type)
  end

  def assert_validity
    if !Puppet::Module.is_module_directory_name?(@name) && !Puppet::Module.is_module_namespaced_name?(@name)
      raise InvalidName, "Invalid module name #{@name}; module names must be alphanumeric (plus '-'), not '#{@name}'"
    end
  end
end
