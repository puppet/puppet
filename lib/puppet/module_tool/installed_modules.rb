require 'pathname'

require 'puppet/forge'
require 'puppet/module_tool'

module Puppet::ModuleTool
  class InstalledModules < Semantic::Dependency::Source
    attr_reader :modules, :by_name

    def priority
      10
    end

    def initialize(env)
      @env = env
      modules = env.modules_by_path

      @fetched = []
      @modules = {}
      @by_name = {}
      env.modulepath.each do |path|
        modules[path].each do |mod|
          @by_name[mod.name] = mod
          next unless mod.has_metadata?
          release = ModuleRelease.new(self, mod)
          @modules[release.name] ||= release
        end
      end

      @modules.freeze
    end

    def fetch(name)
      name = name.tr('/', '-')

      if @modules.key? name
        @fetched << name
        [ @modules[name] ]
      else
        [ ]
      end
    end

    def fetched
      @fetched
    end

    class ModuleRelease < Semantic::Dependency::ModuleRelease
      attr_reader :mod, :metadata

      def initialize(source, mod)
        @mod = mod
        @metadata = mod.metadata
        name = mod.forge_name.tr('/', '-')
        version = Semantic::Version.parse(mod.version)

        super(source, name, version, {})

        if mod.dependencies
          mod.dependencies.each do |dep|
            range = dep['version_requirement'] || dep['versionRequirement'] || '>=0'
            range = Semantic::VersionRange.parse(range) rescue Semantic::VersionRange::EMPTY_RANGE

            dep.tap do |dep|
              add_constraint('initialize', dep['name'].tr('/', '-'), range.to_s) do |node|
                range === node.version
              end
            end
          end
        end
      end

      def forge_data(key)
        nil
      end

      def install_dir
        Pathname.new(@mod.path).dirname
      end

      def install(dir)
        # If we're already installed, there's no need for us to faff about.
      end

      def prepare
        # We're already installed; what preparation remains?
      end
    end
  end
end
