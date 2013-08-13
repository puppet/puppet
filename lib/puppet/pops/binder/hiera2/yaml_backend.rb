module Puppet::Pops::Binder::Hiera2
  # A Backend implementation capable of reading YAML syntax
  class Yaml_backend < Puppet::Pops::Binder::Hiera2::Backend
    def read_data(module_dir, source)
      begin
        source_file = File.join(module_dir, "#{source}.yaml")
        YAML.load_file(source_file)
      rescue Errno::ENOENT
        # This is OK, the file doesn't need to be present. Return an empty hash
        {}
      end
    end
  end
end
