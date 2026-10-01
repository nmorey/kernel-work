require 'yaml'
require 'tempfile'

module KernelWork
    module CLI
        # CLI commands for managing application configurations.
        module Config
            # Short description of the Config subcommand.
            CLI_DESCRIPTION = "Manage application configurations"
            # Command name registered with CLIClassTool.
            CLI_COMMAND_NAME = "config"
            # Help banner title for Config commands.
            CLI_HELP_EXPAND = "*** config commands ***"

            # Custom error class for Config CLI errors.
            class ConfigError < KernelWork::KernelWorkError; end

            # Secondary Level Actions (config diff)
            class Action < KernelWork::Common
                # Retrieve the parent module namespace.
                # @return [Module] Config module namespace.
                def parent_module
                    KernelWork::CLI::Config
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
            end

            # Display the currently loaded configuration settings in YAML.
            # @param opts [Hash] Unused options hash.
            # @return [void]
            def show(opts)
                puts KernelWork.config.settings.to_yaml
            end
        end

        require_relative 'config/filter'

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
                    BranchCLI
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
                    opts[:raw] = false
                    opts[:branch] = nil
                    opts[:ref] = nil
                    opts[:no_sorted_series] = false

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

                # Register or update a kernel-source branch in configuration.
                # @param opts [Hash] Branch options hash.
                # @return [void]
                def add(opts)
                    branches = KernelWork.config.settings[:kernel_source][:branches]

                    idx = branches.index { |b| b[:name] == opts[:branch] }
                    entry = { :name => opts[:branch], :ref => opts[:ref], :no_sorted_series => opts[:no_sorted_series] }

                    if idx
                        log(:INFO, "Updating existing branch '#{opts[:branch]}'")
                        branches[idx] = entry
                    else
                        log(:INFO, "Registering new branch '#{opts[:branch]}'")
                        branches << entry
                    end

                    KernelWork.config.save_config
                    log(:INFO, "Configuration saved to #{KernelWork.config.config_file}")
                end

                # List all registered kernel-source branches.
                # @param opts [Hash] Options hash.
                # @return [void]
                def list(opts)
                    cfg = KernelWork.config.settings
                    branches = cfg[:kernel_source][:branches] || []

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
                end

                # Display detailed properties of a registered branch.
                # @param opts [Hash] Options hash with branch name.
                # @return [void]
                # @raise [UnknownBranch] If the branch is not found.
                def show(opts)
                    cfg = KernelWork.config.settings
                    branches = cfg[:kernel_source][:branches] || []
                    b = branches.find { |x| x[:name] == opts[:branch] }

                    if b.nil?
                        raise UnknownBranch.new(opts[:branch])
                    end

                    log(:INFO, "Branch '#{opts[:branch]}' details:")
                    puts b.to_yaml
                end

                # Remove a kernel-source branch registration from the configuration.
                # @param opts [Hash] Options hash.
                # @return [void]
                # @raise [UnknownBranch] If the branch is not found.
                def delete(opts)
                    cfg = KernelWork.config.settings
                    branches = cfg[:kernel_source][:branches] || []
                    b_idx = branches.index { |x| x[:name] == opts[:branch] }

                    if b_idx.nil?
                        raise UnknownBranch.new(opts[:branch])
                    end

                    branches.delete_at(b_idx)
                    KernelWork.config.save_config
                    log(:INFO, "Deleted branch '#{opts[:branch]}' from configuration in #{KernelWork.config.config_file}")
                end
            end

            # Subcommand action classes registered for BranchCLI module.
            ACTION_CLASS = [ BranchAction ]
            extend CLIClassTool::Utils
        end

        # Subcommand action/modules classes registered for Config module.
        ACTION_CLASS = [ ConfigAction, FilterCLI, BranchCLI ]
        extend CLIClassTool::Utils
        end
    end
end
