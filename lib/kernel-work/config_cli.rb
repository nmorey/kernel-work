require 'yaml'
require 'tempfile'

module KernelWork
    module ConfigCLI
        CLI_DESCRIPTION = "Manage application configurations"
        CLI_COMMAND_NAME = "config"
        CLI_HELP_EXPAND = "*** config commands ***"

        class ConfigCLIError < KernelWork::KernelWorkError; end

        # Secondary Level Actions (config diff)
        class Action < KernelWork::Common
            def parent_module
                KernelWork::ConfigCLI
            end
        end

        class ConfigAction < Action
            ACTION_LIST = [ :diff, :show ]

            ACTION_HELP = {
                :diff => "Compare the current config.yml with the default values",
                :show => "Display the loaded config.yml settings"
            }

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

            def show(opts)
                puts KernelWork.config.settings.to_yaml
                return 0
            end
        end

        # Tertiary Level Filter Actions (config filter add/list/show/delete)
        module FilterCLI
            CLI_DESCRIPTION = "Manage saved configuration filters"
            CLI_COMMAND_NAME = "filter"

            class FilterCLIError < KernelWork::KernelWorkError; end

            class FilterAction < KernelWork::Common
                def parent_module
                    KernelWork::ConfigCLI::FilterCLI
                end

                ACTION_LIST = [ :add, :list, :show, :delete ]

                ACTION_HELP = {
                    :add => "Save a named filter containing paths, grep, fixes, or author",
                    :list => "List all available filters in config.yml",
                    :show => "Show the detailed options of a saved named filter",
                    :delete => "Delete a saved named filter from config.yml"
                }

                def self.set_opts(action, optsParser, opts)
                    case action
                    when :add
                        optsParser.on("-n", "--name <name>", String, "Name of the filter to save.") {
                            |val| opts[:filter_name] = val}
                        Common.set_filter_opts(optsParser, opts)
                        optsParser.on("-T", "--skip-treewide", "Automatically skip tree wide patches.") {
                            |val| opts[:filter][:skip_treewide] = true}
                    when :list
                        optsParser.on("--raw", "Output only the names of the filters.") {
                            |val| opts[:raw] = true}
                    when :show, :delete
                        optsParser.on("-n", "--name <name>", String, "Name of the saved filter.") {
                            |val| opts[:filter_name] = val}
                    end
                end

                def self.check_opts(opts)
                    case opts[:action]
                    when :add, :show, :delete
                        if opts[:filter_name].nil? || opts[:filter_name].empty?
                            raise("Filter name is required. Use -n <name>")
                        end
                    end

                    Common.check_filter_opts(opts)
                end

                def add(opts)
                    name = opts[:filter_name]
                    cfg = KernelWork.config.settings
                    cfg[:filters] ||= {}

                    cfg[:filters][name.to_sym] = opts[:filter]

                    KernelWork.config.save_config
                    log(:INFO, "Saved filter '#{name}' to configuration in #{KernelWork.config.config_file}")
                    return 0
                end

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

            ACTION_CLASS = [ FilterAction ]
            extend CLIClassTool::Utils
        end

        # Tertiary Level Branch Actions (config branch add/list/show/delete)
        module BranchCLI
            CLI_DESCRIPTION = "Manage registered SUSE branches"
            CLI_COMMAND_NAME = "branch"

            class BranchCLIError < KernelWork::KernelWorkError; end

            class BranchAction < KernelWork::Common
                def parent_module
                    KernelWork::ConfigCLI::BranchCLI
                end

                ACTION_LIST = [ :add, :list, :show, :delete ]

                ACTION_HELP = {
                    :add => "Register or update a SUSE branch in config.yml",
                    :list => "List all registered SUSE branches",
                    :show => "Show the detailed options of a registered branch",
                    :delete => "Delete a registered branch from config.yml"
                }

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

                def self.check_opts(opts)
                    case opts[:action]
                    when :add, :show, :delete
                        if opts[:branch].nil? || opts[:branch].empty?
                            raise("Branch name is required. Use -b <branch>")
                        end
                    end
                end

                # Branch Action Methods
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

            ACTION_CLASS = [ BranchAction ]
            extend CLIClassTool::Utils
        end

        ACTION_CLASS = [ ConfigAction, FilterCLI, BranchCLI ]
        extend CLIClassTool::Utils
    end
end
