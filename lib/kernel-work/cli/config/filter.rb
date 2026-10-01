require 'yaml'

module KernelWork
    module CLI
        module Config
            # Tertiary Level Filter Actions (config filter add/list/show/delete)
            module FilterCLI
                # Short description of the Filter subcommand.
                CLI_DESCRIPTION = "Manage saved configuration filters"
                # Command name registered with CLIClassTool.
                CLI_COMMAND_NAME = "filter"

                # Custom error class for Filter CLI errors.
                class FilterCLIError < KernelWork::KernelWorkError; end

                # Action handler for configuration filters.
                class FilterAction < KernelWork::Common
                    # Retrieve the parent module namespace.
                    # @return [Module] FilterCLI module namespace.
                    def parent_module
                        FilterCLI
                    end

                    # List of supported filter actions.
                    ACTION_LIST = [ :add, :list, :show, :delete ]

                    # Help text for filter actions.
                    ACTION_HELP = {
                        :add => "Save a named filter containing paths, grep, fixes, or author",
                        :list => "List all available filters in config.yml",
                        :show => "Show the detailed options of a saved named filter",
                        :delete => "Delete a saved named filter from config.yml"
                    }

                    # Define and configure CLI command-line options for filter actions.
                    # @param action [Symbol] Selected filter action.
                    # @param optsParser [OptionParser] Command-line option parser instance.
                    # @param opts [Hash] Target hash where parsed options are stored.
                    # @return [void]
                    def self.set_opts(action, optsParser, opts)
                        opts[:raw] = false
                        opts[:filter_name] = nil

                        case action
                        when :add
                            KernelWork::CLI::CommitFilter.add_options(optsParser, opts)
                            opts[:filter_may_be_missing] = true
                        when :list
                            optsParser.on("--raw", "Output only the names of the filters.") {
                                |_val| opts[:raw] = true}
                        when :show, :delete
                            optsParser.on("--filter <name>", String, "Name of the saved filter.") {
                                |val| opts[:filter_name] = val}
                        end
                    end

                    # Validate options for filter actions.
                    # @param opts [Hash] Selected action options.
                    # @return [void]
                    # @raise [RuntimeError] If filter name option is missing.
                    def self.check_opts(opts)
                        case opts[:action]
                        when :add, :show, :delete
                            if opts[:filter_name].nil? || opts[:filter_name].empty?
                                raise("Filter name is required. Use -n <name>")
                            end
                        end

                        if opts[:action] == :add
                            opts[:filter] = KernelWork::CLI::CommitFilter.from_opts(opts, may_be_missing: true)
                        end
                    end

                    # Save a named filter to the configuration file.
                    # @param opts [Hash] Options hash with filter details.
                    # @return [void]
                    # @raise [SCPAbort] If update is canceled by user.
                    def add(opts)
                        name = opts[:filter_name]
                        cfg = KernelWork.config.settings
                        cfg[:filters] ||= {}

                        if cfg[:filters][name.to_sym] != nil then
                            rep = confirm(opts, "update the existing #{name} filter",
                                          ignore_default: true,
                                          allowed_reps: ["y", "n"])
                            if rep == "n" then
                                raise SCPAbort.new("User aborted filter update")
                            end
                            log(:INFO, "Updating filter #{name} with new settings")
                        end
                        cfg[:filters][name.to_sym] = opts[:filter].to_h

                        KernelWork.config.save_config
                        log(:INFO, "Saved filter '#{name}' to configuration in #{KernelWork.config.config_file}")
                    end

                    # List all registered filters saved in config.yml.
                    # @param opts [Hash] Options hash.
                    # @return [void]
                    def list(opts)
                        cfg = KernelWork.config.settings
                        filters = cfg[:filters] || {}

                        if opts[:raw]
                            filters.keys.each { |name| puts name }
                        else
                            if filters.empty?
                                log(:INFO, "No saved filters found in configuration.")
                            else
                                log(:INFO, "Saved filters:")
                                filters.each do |name, f_opts|
                                    filter = KernelWork::CommitFilter.from_h(f_opts)
                                    details = []
                                    details << "paths: #{filter.paths.join(', ')}" unless filter.paths.empty?
                                    details << "exclude_paths: #{filter.exclude_paths.join(', ')}" unless filter.exclude_paths.empty?
                                    details << "fixes: true" if filter.fixes
                                    details << "grep: '#{filter.grep}'" if filter.grep
                                    details << "author: '#{filter.author}'" if filter.author
                                    details << "skip_treewide: true" if filter.skip_treewide

                                    puts "  - #{name}: #{details.join(', ')}"
                                end
                            end
                        end
                    end

                    # Show the properties of a specific saved filter.
                    # @param opts [Hash] Options hash.
                    # @return [void]
                    # @raise [SavedFilterNotFoundError] If the filter is not found.
                    def show(opts)
                        name = opts[:filter_name]
                        cfg = KernelWork.config.settings
                        filters = cfg[:filters] || {}
                        f_opts = filters[name.to_sym]

                        if f_opts.nil?
                            raise SavedFilterNotFoundError.new(name)
                        end

                        filter = KernelWork::CommitFilter.from_h(f_opts)
                        log(:INFO, "Filter '#{name}' details:")
                        puts filter.to_h.to_yaml
                    end

                    # Remove a specific filter from the configuration settings.
                    # @param opts [Hash] Options hash.
                    # @return [void]
                    # @raise [SavedFilterNotFoundError] If the filter is not found.
                    def delete(opts)
                        name = opts[:filter_name]
                        cfg = KernelWork.config.settings
                        filters = cfg[:filters] || {}

                        if !filters.key?(name.to_sym)
                            raise SavedFilterNotFoundError.new(name)
                        end

                        filters.delete(name.to_sym)
                        KernelWork.config.save_config
                        log(:INFO, "Deleted filter '#{name}' from configuration in #{KernelWork.config.config_file}")
                    end
                end

                # Subcommand action classes registered for FilterCLI module.
                ACTION_CLASS = [ FilterAction ]
                extend CLIClassTool::Utils
            end
        end
    end
end
