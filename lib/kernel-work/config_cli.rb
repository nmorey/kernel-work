require 'yaml'
require 'tempfile'

module KernelWork
    # CLI commands for managing application configurations.
    module ConfigCLI
        # Short description of the Config subcommand.
        CLI_DESCRIPTION = "Manage application configurations"
        # Command name registered with CLIClassTool.
        CLI_COMMAND_NAME = "config"
        # Help banner title for Config commands.
        CLI_HELP_EXPAND = "*** config commands ***"

        # Custom error class for Config CLI errors.
        class ConfigCLIError < KernelWork::KernelWorkError; end

        # Secondary Level Actions (config diff)
        class Action < KernelWork::Common
            # Retrieve the parent module namespace.
            # @return [Module] ConfigCLI module namespace.
            def parent_module
                KernelWork::ConfigCLI
            end
        end

        # Core Config CLI action handler class.
        class ConfigAction < Action
            # List of supported config actions.
            ACTION_LIST = [ :diff, :show ]

            # Help text for config actions.
            ACTION_HELP = {
                :diff => "Compare the current config.yml with the default values",
                :show => "Display the loaded config.yml settings"
            }

            # Generate and print a diff between defaults and current configuration settings.
            # @param opts [Hash] Unused options hash.
            # @return [Integer] Command exit status code.
            def diff(opts)
                defaults_yaml = KernelWork::Config::DEFAULTS.to_yaml
                current_yaml = KernelWork.config.settings.to_yaml

                Tempfile.create('kw_defaults') do |f_defaults|
                    f_defaults.write(defaults_yaml)
                    f_defaults.flush

                    Tempfile.create('kw_current') do |f_current|
                        f_current.write(current_yaml)
                        f_current.flush

                        system("diff -u #{f_defaults.path} #{f_current.path}")
                    end
                end
                return 0
            end

            # Display the currently loaded configuration settings in YAML.
            # @param opts [Hash] Unused options hash.
            # @return [Integer] Command exit status code.
            def show(opts)
                puts KernelWork.config.settings.to_yaml
                return 0
            end
        end

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
                    KernelWork::ConfigCLI::FilterCLI
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
                    case action
                    when :add
                        Common.set_filter_opts(optsParser, opts)
                        # filter_name is already part of the default filter opts
                        opts[:filter_may_be_missing] = true
                    when :list
                        optsParser.on("--raw", "Output only the names of the filters.") {
                            |val| opts[:raw] = true}
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

                    Common.check_filter_opts(opts)
                end

                # Save a named filter to the configuration file.
                # @param opts [Hash] Options hash with filter details.
                # @return [Integer] Exit status code.
                # @raise [SCPAbort] If update is canceled by user.
                def add(opts)
                    name = opts[:filter_name]
                    cfg = KernelWork.config.settings
                    cfg[:filters] ||= {}

                    if cfg[:filters][name.to_sym] != nil then

                        rep= confirm(opts, "update the existing #{name} filter", true, ["y", "n"])
                        if rep == "n" then
                            raise SCPAbort.new("User aborted filter update")
                        end
                        log(:INFO, "Updating filter #{name} with new settings")
                   end
                    cfg[:filters][name.to_sym] = opts[:filter]

                    KernelWork.config.save_config
                    log(:INFO, "Saved filter '#{name}' to configuration in #{KernelWork.config.config_file}")
                    return 0
                end

                # List all registered filters saved in config.yml.
                # @param opts [Hash] Options hash.
                # @return [Integer] Exit status code.
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
                                details = []
                                details << "paths: #{f_opts[:paths].join(', ')}" if f_opts[:paths] && !f_opts[:paths].empty?
                                details << "exclude_paths: #{f_opts[:exclude_paths].join(', ')}" if f_opts[:exclude_paths] && !f_opts[:exclude_paths].empty?
                                details << "fixes: true" if f_opts[:fixes]
                                details << "grep: '#{f_opts[:grep]}'" if f_opts[:grep]
                                details << "author: '#{f_opts[:author]}'" if f_opts[:author]
                                details << "skip_treewide: true" if f_opts[:skip_treewide]

                                puts "  - #{name}: #{details.join(', ')}"
                            end
                        end
                    end
                    return 0
                end

                # Show the properties of a specific saved filter.
                # @param opts [Hash] Options hash.
                # @return [Integer] Exit status code.
                def show(opts)
                    name = opts[:filter_name]
                    cfg = KernelWork.config.settings
                    filters = cfg[:filters] || {}
                    f_opts = filters[name.to_sym]

                    if f_opts.nil?
                        log(:ERROR, "Filter '#{name}' not found.")
                        return 1
                    end

                    log(:INFO, "Filter '#{name}' details:")
                    puts f_opts.to_yaml
                    return 0
                end

                # Remove a specific filter from the configuration settings.
                # @param opts [Hash] Options hash.
                # @return [Integer] Exit status code.
                def delete(opts)
                    name = opts[:filter_name]
                    cfg = KernelWork.config.settings
                    filters = cfg[:filters] || {}

                    if !filters.key?(name.to_sym)
                        log(:ERROR, "Filter '#{name}' not found.")
                        return 1
                    end

                    filters.delete(name.to_sym)
                    KernelWork.config.save_config
                    log(:INFO, "Deleted filter '#{name}' from configuration in #{KernelWork.config.config_file}")
                    return 0
                end
            end

            # Subcommand action classes registered for FilterCLI module.
            ACTION_CLASS = [ FilterAction ]
            extend CLIClassTool::Utils
        end

        # Tertiary Level Branch Actions (config branch add/list/show/delete)
        module BranchCLI
            # Short description of the Branch subcommand.
            CLI_DESCRIPTION = "Manage registered SUSE branches"
            # Command name registered with CLIClassTool.
            CLI_COMMAND_NAME = "branch"

            # Custom error class for Branch CLI errors.
            class BranchCLIError < KernelWork::KernelWorkError; end

            # Action handler for SUSE branches settings.
            class BranchAction < KernelWork::Common
                # Retrieve the parent module namespace.
                # @return [Module] BranchCLI module namespace.
                def parent_module
                    KernelWork::ConfigCLI::BranchCLI
                end

                # List of supported branch actions.
                ACTION_LIST = [ :add, :list, :show, :delete ]

                # Help text for branch actions.
                ACTION_HELP = {
                    :add => "Register or update a SUSE branch in config.yml",
                    :list => "List all registered SUSE branches",
                    :show => "Show the detailed options of a registered branch",
                    :delete => "Delete a registered branch from config.yml"
                }

                # Define and configure CLI options for branch actions.
                # @param action [Symbol] Selected branch action.
                # @param optsParser [OptionParser] Option parser instance.
                # @param opts [Hash] Target hash where parsed options are stored.
                # @return [void]
                def self.set_opts(action, optsParser, opts)
                    case action
                    when :add
                        optsParser.on("-b", "--branch <branch>", String, "Branch name.") {
                            |val| opts[:branch] = val}
                        optsParser.on("-r", "--ref <ref>", String, "Default reference.") {
                            |val| opts[:ref] = val}
                        optsParser.on("-n", "--no-sorted-series", "Do not sort patch series for this branch.") {
                            |val| opts[:no_sorted_series] = true}
                    when :list
                        optsParser.on("--raw", "Output only the names of the branches.") {
                            |val| opts[:raw] = true}
                    when :show, :delete
                        optsParser.on("-b", "--branch <branch>", String, "Branch name.") {
                            |val| opts[:branch] = val}
                    end
                end

                # Validate options for branch actions.
                # @param opts [Hash] Selected action options.
                # @return [void]
                # @raise [RuntimeError] If branch name option is missing.
                def self.check_opts(opts)
                    case opts[:action]
                    when :add, :show, :delete
                        if opts[:branch].nil? || opts[:branch].empty?
                            raise("Branch name is required. Use -b <branch>")
                        end
                    end
                end

                # Register or update a SUSE branch in configuration.
                # @param opts [Hash] Branch options hash.
                # @return [Integer] Exit status code.
                def add(opts)
                    branches = KernelWork.config.settings[:suse][:branches]

                    idx = branches.index { |b| b[:name] == opts[:branch] }
                    entry = { :name => opts[:branch], :ref => opts[:ref], :no_sorted_series => opts[:no_sorted_series] || false }

                    if idx
                        log(:INFO, "Updating existing branch '#{opts[:branch]}'")
                        branches[idx] = entry
                    else
                        log(:INFO, "Registering new branch '#{opts[:branch]}'")
                        branches << entry
                    end

                    KernelWork.config.save_config
                    log(:INFO, "Configuration saved to #{KernelWork.config.config_file}")
                    return 0
                end

                # List all registered SUSE branches.
                # @param opts [Hash] Options hash.
                # @return [Integer] Exit status code.
                def list(opts)
                    cfg = KernelWork.config.settings
                    branches = cfg[:suse][:branches] || []

                    if opts[:raw]
                        branches.each { |b| puts b[:name] }
                    else
                        if branches.empty?
                            log(:INFO, "No registered branches found in configuration.")
                        else
                            log(:INFO, "Registered branches:")
                            branches.each do |b|
                                details = []
                                details << "ref: '#{b[:ref]}'" if b[:ref]
                                details << "no_sorted_series: true" if b[:no_sorted_series]

                                puts "  - #{b[:name]}: #{details.join(', ')}"
                            end
                        end
                    end
                    return 0
                end

                # Display detailed properties of a registered branch.
                # @param opts [Hash] Options hash with branch name.
                # @return [Integer] Exit status code.
                def show(opts)
                    cfg = KernelWork.config.settings
                    branches = cfg[:suse][:branches] || []
                    b = branches.find { |x| x[:name] == opts[:branch] }

                    if b.nil?
                        log(:ERROR, "Branch '#{opts[:branch]}' not found.")
                        return 1
                    end

                    log(:INFO, "Branch '#{opts[:branch]}' details:")
                    puts b.to_yaml
                    return 0
                end

                # Remove a SUSE branch registration from the configuration.
                # @param opts [Hash] Options hash.
                # @return [Integer] Exit status code.
                def delete(opts)
                    cfg = KernelWork.config.settings
                    branches = cfg[:suse][:branches] || []
                    b_idx = branches.index { |x| x[:name] == opts[:branch] }

                    if b_idx.nil?
                        log(:ERROR, "Branch '#{opts[:branch]}' not found.")
                        return 1
                    end

                    branches.delete_at(b_idx)
                    KernelWork.config.save_config
                    log(:INFO, "Deleted branch '#{opts[:branch]}' from configuration in #{KernelWork.config.config_file}")
                    return 0
                end
            end

            # Subcommand action classes registered for BranchCLI module.
            ACTION_CLASS = [ BranchAction ]
            extend CLIClassTool::Utils
        end

        # Subcommand action/modules classes registered for ConfigCLI module.
        ACTION_CLASS = [ ConfigAction, FilterCLI, BranchCLI ]
        extend CLIClassTool::Utils
    end
end
