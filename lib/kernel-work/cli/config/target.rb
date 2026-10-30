# frozen_string_literal: true

require 'yaml'

module KernelWork
    module CLI
        module Config
            # Tertiary Level Target Actions (config target add/list/show/delete/default)
            module TargetCLI
                # Short description of the Target subcommand.
                CLI_DESCRIPTION = "Manage test deployment targets"
                # Command name registered with CLIClassTool.
                CLI_COMMAND_NAME = "target"

                # Custom error class for Target CLI errors.
                class TargetCLIError < KernelWork::KernelWorkError; end

                # Action handler for test deployment targets settings.
                class TargetAction < KernelWork::Common
                    # Retrieve the parent module namespace.
                    # @return [Module] TargetCLI module namespace.
                    def parent_module
                        TargetCLI
                    end

                    # List of supported target actions.
                    ACTION_LIST = [ :add, :list, :show, :delete, :default, :defaults ]

                    # Help text for target actions.
                    ACTION_HELP = {
                        :add => "Register or update a test target in config.yml",
                        :list => "List all registered test targets",
                        :show => "Show the detailed options of a registered target",
                        :delete => "Delete a registered test target from config.yml",
                        :default => "Get, set, or clear the default test target",
                        :defaults => "Get, set, or clear global default options applied to all test targets"
                    }

                    # Define and configure CLI command-line options for target actions.
                    # @param action [Symbol] Selected target action.
                    # @param optsParser [OptionParser] Command-line option parser instance.
                    # @param opts [Hash] Target hash where parsed options are stored.
                    # @return [void]
                    def self.set_opts(action, optsParser, opts)
                        opts[:raw] = false
                        opts[:target] = nil
                        opts[:branch] = nil
                        opts[:host] = nil
                        opts[:port] = nil
                        opts[:type] = nil
                        opts[:sudo] = nil
                        opts[:reboot] = nil
                        opts[:reboot_method] = nil
                        opts[:minimal_modules] = nil
                        opts[:strip_modules] = nil
                        opts[:extra_modules] = nil
                        opts[:clear_extra_modules] = false
                        opts[:dracut] = nil
                        opts[:update_grub] = nil
                        opts[:boot_dir] = nil
                        opts[:modules_dir] = nil
                        opts[:default] = false
                        opts[:clear] = false

                        case action
                        when :add
                            optsParser.on("-t", "--target <name>", String, "Target name.") { |val| opts[:target] = val }
                            optsParser.on("-b", "--branch <branch>", String, "Associated kernel branch.") { |val| opts[:branch] = val }
                            optsParser.on("-H", "--host <host>", String, "Target host (user@host, hostname, or 'localhost').") { |val| opts[:host] = val }
                            optsParser.on("-p", "--port <port>", Integer, "SSH port.") { |val| opts[:port] = val }
                            optsParser.on("--type <type>", String, "Target type ('remote' or 'local').") { |val| opts[:type] = val }
                            optsParser.on("--[no-]sudo", "Execute commands with sudo.") { |val| opts[:sudo] = val }
                            optsParser.on("-r", "--[no-]reboot", "Reboot target after installation.") { |val| opts[:reboot] = val }
                            optsParser.on("--reboot-method <method>", String, "Boot method ('kexec' or 'reboot').") { |val| opts[:reboot_method] = val }
                            optsParser.on("--[no-]minimal-modules", "Install only active kernel modules.") { |val| opts[:minimal_modules] = val }
                            optsParser.on("-e", "--extra-module <module>", String, "Extra module to include when using --minimal-modules (comma-separated or repeatable).") do |val|
                                opts[:extra_modules] ||= []
                                opts[:extra_modules].concat(val.split(',').map(&:strip))
                            end
                            optsParser.on("--clear-extra-modules", "Clear extra modules list for target.") { opts[:clear_extra_modules] = true }
                            optsParser.on("--[no-]strip", "Strip debug symbols from modules during deployment.") { |val| opts[:strip_modules] = val }
                            optsParser.on("--[no-]dracut", "Run dracut to generate initrd.") { |val| opts[:dracut] = val }
                            optsParser.on("--[no-]grub", "Update GRUB bootloader configuration.") { |val| opts[:update_grub] = val }
                            optsParser.on("--boot-dir <dir>", String, "Boot directory path (default '/boot').") { |val| opts[:boot_dir] = val }
                            optsParser.on("--modules-dir <dir>", String, "Modules directory path (default '/lib/modules').") { |val| opts[:modules_dir] = val }
                            optsParser.on("--default", "Set as the default test target.") { opts[:default] = true }
                        when :list
                            optsParser.on("--raw", "Output only the names of the targets.") { opts[:raw] = true }
                        when :show, :delete
                            optsParser.on("-t", "--target <name>", String, "Target name.") { |val| opts[:target] = val }
                        when :default
                            optsParser.on("-t", "--target <name>", String, "Set target as default.") { |val| opts[:target] = val }
                            optsParser.on("--clear", "Clear default target.") { opts[:clear] = true }
                        when :defaults
                            optsParser.on("-p", "--port <port>", Integer, "SSH port.") { |val| opts[:port] = val }
                            optsParser.on("--type <type>", String, "Target type ('remote' or 'local').") { |val| opts[:type] = val }
                            optsParser.on("--[no-]sudo", "Execute commands with sudo.") { |val| opts[:sudo] = val }
                            optsParser.on("-r", "--[no-]reboot", "Reboot target after installation.") { |val| opts[:reboot] = val }
                            optsParser.on("--reboot-method <method>", String, "Boot method ('kexec' or 'reboot').") { |val| opts[:reboot_method] = val }
                            optsParser.on("--[no-]minimal-modules", "Install only active kernel modules.") { |val| opts[:minimal_modules] = val }
                            optsParser.on("-e", "--extra-module <module>", String, "Extra module to include when using --minimal-modules (comma-separated or repeatable).") do |val|
                                opts[:extra_modules] ||= []
                                opts[:extra_modules].concat(val.split(',').map(&:strip))
                            end
                            optsParser.on("--clear-extra-modules", "Clear extra modules list for defaults.") { opts[:clear_extra_modules] = true }
                            optsParser.on("--[no-]strip", "Strip debug symbols from modules during deployment.") { |val| opts[:strip_modules] = val }
                            optsParser.on("--[no-]dracut", "Run dracut to generate initrd.") { |val| opts[:dracut] = val }
                            optsParser.on("--[no-]grub", "Update GRUB bootloader configuration.") { |val| opts[:update_grub] = val }
                            optsParser.on("--boot-dir <dir>", String, "Boot directory path (default '/boot').") { |val| opts[:boot_dir] = val }
                            optsParser.on("--modules-dir <dir>", String, "Modules directory path (default '/lib/modules').") { |val| opts[:modules_dir] = val }
                            optsParser.on("--clear", "Clear all global test target defaults.") { opts[:clear] = true }
                        end
                    end

                    # Validate options for target actions.
                    # @param opts [Hash] Selected action options.
                    # @return [void]
                    # @raise [RuntimeError] If target name option is missing when required.
                    def self.check_opts(opts)
                        if (opts[:target].nil? || opts[:target].empty?) && !ARGV.empty? && !ARGV[0].start_with?("-")
                            opts[:target] = ARGV.shift
                        end

                        case opts[:action]
                        when :add, :show, :delete
                            if opts[:target].nil? || opts[:target].empty?
                                raise("Target name is required. Use -t <target>")
                            end
                        end
                    end

                    # Register or update a test target in configuration.
                    # @param opts [Hash] Target options hash.
                    # @return [void]
                    def add(opts)
                        cfg = KernelWork.config.settings
                        cfg[:test] ||= {}
                        cfg[:test][:targets] ||= {}

                        target_name = opts[:target]
                        targets = cfg[:test][:targets]

                        existing_key = targets.keys.find { |k| k.to_s == target_name.to_s }
                        existing_cfg = existing_key ? targets[existing_key] : nil

                        if existing_cfg
                            log(:INFO, "Updating existing test target '#{target_name}'")
                            target_obj = TargetOpts.from_config(target_name, existing_cfg)
                            target_obj.branch = opts[:branch] unless opts[:branch].nil?
                            target_obj.port = opts[:port] unless opts[:port].nil?
                            target_obj.sudo = opts[:sudo] unless opts[:sudo].nil?
                            target_obj.reboot = opts[:reboot] unless opts[:reboot].nil?
                            target_obj.reboot_method = opts[:reboot_method].to_sym unless opts[:reboot_method].nil?
                            target_obj.minimal_modules = opts[:minimal_modules] unless opts[:minimal_modules].nil?
                            target_obj.strip_modules = opts[:strip_modules] unless opts[:strip_modules].nil?
                            if opts[:clear_extra_modules]
                                target_obj.extra_modules = []
                            elsif opts[:extra_modules]
                                target_obj.extra_modules = (target_obj.extra_modules + opts[:extra_modules]).uniq
                            end
                            target_obj.dracut = opts[:dracut] unless opts[:dracut].nil?
                            target_obj.update_grub = opts[:update_grub] unless opts[:update_grub].nil?
                            target_obj.boot_dir = opts[:boot_dir] unless opts[:boot_dir].nil?
                            target_obj.modules_dir = opts[:modules_dir] unless opts[:modules_dir].nil?

                            if opts[:host]
                                target_obj.host = opts[:host]
                                target_obj.type = opts[:type] ? opts[:type].to_sym : target_obj.send(:determine_type, nil, opts[:host])
                            elsif opts[:type]
                                target_obj.type = opts[:type].to_sym
                            end
                        else
                            log(:INFO, "Registering new test target '#{target_name}'")
                            target_obj = TargetOpts.new(
                                name: target_name,
                                branch: opts[:branch],
                                host: opts[:host],
                                port: opts[:port],
                                type: opts[:type],
                                sudo: opts[:sudo],
                                reboot: opts[:reboot],
                                reboot_method: opts[:reboot_method],
                                minimal_modules: opts[:minimal_modules],
                                strip_modules: opts[:strip_modules],
                                extra_modules: opts[:extra_modules] || [],
                                dracut: opts[:dracut],
                                update_grub: opts[:update_grub],
                                boot_dir: opts[:boot_dir],
                                modules_dir: opts[:modules_dir]
                            )
                        end

                        save_key = existing_key || target_name.to_sym
                        entry = target_obj.to_h
                        entry.delete(:name)
                        targets[save_key] = entry

                        if opts[:default]
                            cfg[:test][:default_target] = target_name
                        end

                        KernelWork.config.save_config
                        log(:INFO, "Configuration saved to #{KernelWork.config.config_file}")
                    end

                    # List all registered test targets.
                    # @param opts [Hash] Options hash.
                    # @return [void]
                    def list(opts)
                        cfg = KernelWork.config.settings
                        targets = cfg.dig(:test, :targets) || {}
                        default_target = cfg.dig(:test, :default_target)&.to_s

                        if opts[:raw]
                            targets.keys.each { |k| puts k }
                        else
                            if targets.empty?
                                log(:INFO, "No registered test targets found in configuration.")
                            else
                                log(:INFO, "Registered test targets:")
                                targets.each do |key, t_cfg|
                                    t = TargetOpts.from_config(key.to_s, t_cfg)
                                    is_default = (key.to_s == default_target)
                                    details = []
                                    details << "branch: '#{t.branch}'" if t.branch
                                    details << "host: '#{t.host}'" if t.host
                                    details << "type: :#{t.type}"
                                    details << "port: #{t.port}" if t.port && t.port != 22
                                    details << "sudo: #{t.sudo}"
                                    details << "reboot: false" unless t.reboot
                                    details << "reboot_method: :#{t.reboot_method}" if t.reboot_method != :kexec
                                    details << "minimal_modules: false" unless t.minimal_modules
                                    details << "dracut: false" unless t.dracut
                                    details << "update_grub: false" unless t.update_grub

                                    default_str = is_default ? " [default]" : ""
                                    puts "  - #{key}#{default_str}: #{details.join(', ')}"
                                end
                            end
                        end
                    end

                    # Display detailed properties of a registered test target.
                    # @param opts [Hash] Options hash with target name.
                    # @return [void]
                    # @raise [TestTargetNotFoundError] If the target is not found.
                    def show(opts)
                        cfg = KernelWork.config.settings
                        targets = cfg.dig(:test, :targets) || {}
                        target_name = opts[:target]

                        t_key = targets.keys.find { |k| k.to_s == target_name.to_s }
                        if t_key.nil?
                            raise TestTargetNotFoundError.new(target_name)
                        end

                        t = TargetOpts.from_config(t_key.to_s, targets[t_key])
                        is_default = (t_key.to_s == cfg.dig(:test, :default_target)&.to_s)
                        log(:INFO, "Test target '#{target_name}'#{is_default ? ' [default]' : ''} details:")
                        puts t.to_h.to_yaml
                    end

                    # Remove a test target from configuration.
                    # @param opts [Hash] Options hash.
                    # @return [void]
                    # @raise [TestTargetNotFoundError] If the target is not found.
                    def delete(opts)
                        cfg = KernelWork.config.settings
                        targets = cfg.dig(:test, :targets) || {}
                        target_name = opts[:target]

                        t_key = targets.keys.find { |k| k.to_s == target_name.to_s }
                        if t_key.nil?
                            raise TestTargetNotFoundError.new(target_name)
                        end

                        targets.delete(t_key)
                        if cfg.dig(:test, :default_target)&.to_s == target_name.to_s
                            cfg[:test][:default_target] = nil
                        end

                        KernelWork.config.save_config
                        log(:INFO, "Deleted test target '#{target_name}' from configuration in #{KernelWork.config.config_file}")
                    end

                    # Get, set, or clear the default test target.
                    # @param opts [Hash] Options hash.
                    # @return [void]
                    # @raise [TestTargetNotFoundError] If requested default target does not exist.
                    def default(opts)
                        cfg = KernelWork.config.settings
                        cfg[:test] ||= {}
                        targets = cfg[:test][:targets] || {}

                        if opts[:clear]
                            cfg[:test][:default_target] = nil
                            KernelWork.config.save_config
                            log(:INFO, "Cleared default test target in #{KernelWork.config.config_file}")
                            return
                        end

                        if opts[:target]
                            target_name = opts[:target]
                            t_key = targets.keys.find { |k| k.to_s == target_name.to_s }
                            if t_key.nil?
                                raise TestTargetNotFoundError.new(target_name)
                            end

                            cfg[:test][:default_target] = t_key.to_s
                            KernelWork.config.save_config
                            log(:INFO, "Set '#{target_name}' as default test target in #{KernelWork.config.config_file}")
                        else
                            def_target = cfg[:test][:default_target]
                            if def_target
                                puts def_target
                            else
                                log(:INFO, "No default test target configured.")
                            end
                        end
                    end

                    # Get, set, or clear global test target defaults.
                    # @param opts [Hash] Options hash.
                    # @return [void]
                    def defaults(opts)
                        cfg = KernelWork.config.settings
                        cfg[:test] ||= {}
                        cfg[:test][:defaults] ||= {}

                        if opts[:clear]
                            cfg[:test][:defaults] = {}
                            KernelWork.config.save_config
                            log(:INFO, "Cleared global test target defaults in #{KernelWork.config.config_file}")
                            return
                        end

                        modifications = false
                        defs = cfg[:test][:defaults]

                        [:port, :sudo, :reboot, :minimal_modules, :strip_modules, :dracut, :update_grub, :boot_dir, :modules_dir].each do |k|
                            unless opts[k].nil?
                                defs[k] = opts[k]
                                modifications = true
                            end
                        end

                        if opts[:type]
                            defs[:type] = opts[:type].to_sym
                            modifications = true
                        end

                        if opts[:reboot_method]
                            defs[:reboot_method] = opts[:reboot_method].to_sym
                            modifications = true
                        end

                        if opts[:clear_extra_modules]
                            defs[:extra_modules] = []
                            modifications = true
                        elsif opts[:extra_modules] && !opts[:extra_modules].empty?
                            defs[:extra_modules] = ((defs[:extra_modules] || []) + opts[:extra_modules]).uniq
                            modifications = true
                        end

                        if modifications
                            KernelWork.config.save_config
                            log(:INFO, "Updated global test target defaults in #{KernelWork.config.config_file}")
                        else
                            if defs.empty?
                                log(:INFO, "No global test target defaults configured.")
                            else
                                puts defs.to_yaml
                            end
                        end
                    end
                end

                # Subcommand action classes registered for TargetCLI module.
                ACTION_CLASS = [ TargetAction ]
                extend CLIClassTool::Utils
            end
        end
    end
end
