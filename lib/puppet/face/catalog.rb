require 'puppet/indirector/face'

Puppet::Indirector::Face.define(:catalog, '0.0.1') do
  require 'puppet/configurer'
  require 'puppet/configurer/fact_handler'
  extend Puppet::Configurer::FactHandler

  copyright "Puppet Inc.", 2011
  license   "Apache 2 license; see COPYING"

  summary _("Compile, save, view, and convert catalogs.")
  description <<-'EOT'
    This subcommand deals with catalogs, which are compiled per-node artifacts
    generated from a set of Puppet manifests. By default, it interacts with the
    compiling subsystem and compiles a catalog using the default manifest and
    `certname`, but you can change the source of the catalog with the
    `--terminus` option. You can also choose to print any catalog in 'dot'
    format (for easy graph viewing with OmniGraffle or Graphviz) with
    '--render-as dot'.
  EOT
  short_description <<-'EOT'
    This subcommand deals with catalogs, which are compiled per-node artifacts
    generated from a set of Puppet manifests. By default, it interacts with the
    compiling subsystem and compiles a catalog using the default manifest and
    `certname`; use the `--terminus` option to change the source of the catalog.
  EOT

  deactivate_action(:destroy)
  deactivate_action(:search)
  find = get_action(:find)
  find.summary "Retrieve the catalog for a node."
  find.arguments "<certname>"
  find.returns <<-'EOT'
    A serialized catalog. When used from the Ruby API, returns a
    Puppet::Resource::Catalog object.
  EOT

  action(:compile) do
    summary "Compile a catalog."
    arguments("[--facts <path>]")
    description "Stuff"
    returns "Stuff"

    option("--facts " + _("<path>")) do
      default_to { nil }
      summary _("Facts to include in the compilation.")
    end

    when_invoked do |options|
      env = Puppet.lookup(:current_environment)

      if options[:facts]
        yaml = Puppet::FileSystem.read(options[:facts], :encoding => 'bom|utf-8')
        formatter = Puppet::Network::FormatHandler.format(:yaml)
        facts = formatter.intern(Puppet::Node::Facts, yaml)
      else
        # gather current facts, need to set instance variable for FactHandler
        @environment = env.name.to_s
        facts = find_facts
      end

      # now that we've loaded facts, don't attempt to save them back out
      Puppet::Node::Facts.indirection.terminus_class = :memory

      # set the same options that configurer does
      request_options = encode_facts(facts)
      request_options[:transaction_uuid] = SecureRandom.uuid
      request_options[:environment] = env.name.to_s
      request_options[:configured_environment] = Puppet[:environment] if Puppet.settings.set_by_config?(:environment)
      request_options[:checksum_type] = Puppet[:supported_checksum_types]
      request_options[:static_catalog] = true

      # don't lookup or save to catalog cache
      request_options[:ignore_cache] = true
      request_options[:ignore_cache_save] = true
      begin
        unless catalog = Puppet::Resource::Catalog.indirection.find(Puppet[:certname], request_options)
          raise _("Could not compile catalog for %{node}") % { node: Puppet[:certname] }
        end

        puts JSON::pretty_generate(catalog.to_resource, :allow_nan => true, :max_nesting => false)
      rescue => detail
        Puppet.log_exception(detail, _("Failed to compile catalog for node %{node}: %{detail}") % { node: Puppet[:certname], detail: detail })
        exit(30)
      end
      exit(0)
    end
  end

  action(:apply) do
    summary "Find and apply a catalog."
    description <<-'EOT'
      Finds and applies a catalog. This action takes no arguments, but
      the source of the catalog can be managed with the `--terminus` option.
    EOT
    returns <<-'EOT'
      Nothing. When used from the Ruby API, returns a
      Puppet::Transaction::Report object.
    EOT
    examples <<-'EOT'
      Apply the locally cached catalog:

      $ puppet catalog apply --terminus yaml

      Retrieve a catalog from the master and apply it, in one step:

      $ puppet catalog apply --terminus rest

      API example:

          # ...
          Puppet::Face[:catalog, '0.0.1'].download
          # (Termini are singletons; catalog.download has a side effect of
          # setting the catalog terminus to yaml)
          report  = Puppet::Face[:catalog, '0.0.1'].apply
          # ...
    EOT

    when_invoked do |options|
      catalog = Puppet::Face[:catalog, "0.0.1"].find(Puppet[:certname]) or raise "Could not find catalog for #{Puppet[:certname]}"
      catalog = catalog.to_ral

      report = Puppet::Transaction::Report.new
      report.configuration_version = catalog.version
      report.environment = Puppet[:environment]

      Puppet::Util::Log.newdestination(report)

      begin
        benchmark(:notice, "Finished catalog run in %{seconds} seconds") do
          catalog.apply(:report => report)
        end
      rescue => detail
        Puppet.log_exception(detail, "Failed to apply catalog: #{detail}")
      end

      report.finalize_report
      report
    end
  end

  action(:download) do
    summary "Download this node's catalog from the puppet master server."
    description <<-'EOT'
      Retrieves a catalog from the puppet master and saves it to the local yaml
      cache. This action always contacts the puppet master and will ignore
      alternate termini.

      The saved catalog can be used in any subsequent catalog action by specifying
      '--terminus yaml' for that action.
    EOT
    returns "Nothing."
    notes <<-'EOT'
      When used from the Ruby API, this action has a side effect of leaving
      Puppet::Resource::Catalog.indirection.terminus_class set to yaml. The
      terminus must be explicitly re-set for subsequent catalog actions.
    EOT
    examples <<-'EOT'
      Retrieve and store a catalog:

      $ puppet catalog download

      API example:

          Puppet::Face[:plugin, '0.0.1'].download
          Puppet::Face[:facts, '0.0.1'].upload
          Puppet::Face[:catalog, '0.0.1'].download
          # ...
    EOT
    when_invoked do |options|
      Puppet::Resource::Catalog.indirection.terminus_class = :rest
      Puppet::Resource::Catalog.indirection.cache_class = nil
      catalog = nil
      retrieval_duration = thinmark do
        catalog = Puppet::Face[:catalog, '0.0.1'].find(Puppet[:certname])
      end
      catalog.retrieval_duration = retrieval_duration
      catalog.write_class_file

      Puppet::Resource::Catalog.indirection.terminus_class = :yaml
      Puppet::Face[:catalog, "0.0.1"].save(catalog)
      Puppet.notice "Saved catalog for #{Puppet[:certname]} to #{Puppet::Resource::Catalog.indirection.terminus.path(Puppet[:certname])}"
      nil
    end
  end
end
