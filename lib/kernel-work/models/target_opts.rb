# frozen_string_literal: true

module KernelWork
    # Encapsulates target machine and deployment configuration options for kernel installation and testing
    class TargetOpts
        # @!attribute [rw] name
        #   @return [String, Symbol, nil] Target identifier name
        attr_accessor :name

        # @!attribute [rw] branch
        #   @return [String, Symbol, nil] Associated kernel git branch name
        attr_accessor :branch

        # @!attribute [rw] type
        #   @return [Symbol] Target execution type (:remote or :local)
        attr_accessor :type

        # @!attribute [rw] host
        #   @return [String, nil] Remote host address or user@host
        attr_accessor :host

        # @!attribute [rw] port
        #   @return [Integer] Remote SSH port
        attr_accessor :port

        # @!attribute [rw] sudo
        #   @return [Boolean] Whether to run target commands with sudo
        attr_accessor :sudo

        # @!attribute [rw] reboot
        #   @return [Boolean] Whether to reboot or kexec target after installation
        attr_accessor :reboot

        # @!attribute [rw] reboot_method
        #   @return [Symbol] Boot method (:kexec or :reboot)
        attr_accessor :reboot_method

        # @!attribute [rw] minimal_modules
        #   @return [Boolean] Whether to install only modules active in target lsmod
        attr_accessor :minimal_modules

        # @!attribute [rw] strip_modules
        #   @return [Boolean] Whether to strip debug symbols from installed modules
        attr_accessor :strip_modules

        # @!attribute [rw] extra_modules
        #   @return [Array<String>] List of extra module names to install with minimal modules
        attr_accessor :extra_modules

        # @!attribute [rw] dracut
        #   @return [Boolean] Whether to generate initrd via dracut on target
        attr_accessor :dracut

        # @!attribute [rw] update_grub
        #   @return [Boolean] Whether to update grub boot default on target
        attr_accessor :update_grub

        # @!attribute [rw] boot_dir
        #   @return [String] Destination boot directory path on target
        attr_accessor :boot_dir

        # @!attribute [rw] modules_dir
        #   @return [String] Destination kernel modules directory path on target
        attr_accessor :modules_dir

        # Initialize install target options
        # @param name [String, Symbol, nil] Target identifier name
        # @param branch [String, Symbol, nil] Associated kernel git branch name
        # @param type [Symbol, nil] Target execution type (:remote or :local)
        # @param host [String, nil] Remote host address or user@host
        # @param port [Integer, nil] Remote SSH port
        # @param sudo [Boolean, nil] Whether to execute target commands with sudo
        # @param reboot [Boolean] Whether to reboot or kexec target after installation
        # @param reboot_method [Symbol] Boot method (:kexec or :reboot)
        # @param minimal_modules [Boolean] Whether to install only active lsmod modules
        # @param strip_modules [Boolean] Whether to strip debug symbols from installed modules
        # @param extra_modules [Array<String>, nil] List of extra module names to install
        # @param dracut [Boolean] Whether to generate initrd via dracut
        # @param update_grub [Boolean] Whether to update grub default boot entry
        # @param boot_dir [String] Target boot directory path
        # @param modules_dir [String] Target kernel modules directory path
        def initialize(name: nil, branch: nil, type: nil, host: nil, port: nil, sudo: nil,
                       reboot: true, reboot_method: :kexec, minimal_modules: true,
                       strip_modules: true, extra_modules: [], dracut: true, update_grub: true,
                       boot_dir: "/boot", modules_dir: "/lib/modules")
            @name = name
            @branch = branch
            @host = host
            @port = (port || 22).to_i
            @type = determine_type(type, host)
            @sudo = sudo.nil? ? (@type == :local) : !!sudo
            @reboot = reboot.nil? ? true : !!reboot
            @reboot_method = (reboot_method || :kexec).to_sym
            @minimal_modules = minimal_modules.nil? ? true : !!minimal_modules
            @strip_modules = strip_modules.nil? ? true : !!strip_modules
            @extra_modules = Array(extra_modules).map(&:to_s).reject(&:empty?)
            @dracut = dracut.nil? ? true : !!dracut
            @update_grub = update_grub.nil? ? true : !!update_grub
            @boot_dir = boot_dir || "/boot"
            @modules_dir = modules_dir || "/lib/modules"
        end

        # Check whether target is local
        # @return [Boolean] True if target is local
        def local?
            @type == :local
        end

        # Check whether target is remote
        # @return [Boolean] True if target is remote
        def remote?
            @type == :remote
        end

        # Convert target options to a Hash
        # @return [Hash{Symbol => Object}] Hash representation of all target options
        def to_h
            {
                name: @name,
                branch: @branch,
                type: @type,
                host: @host,
                port: @port,
                sudo: @sudo,
                reboot: @reboot,
                reboot_method: @reboot_method,
                minimal_modules: @minimal_modules,
                strip_modules: @strip_modules,
                extra_modules: @extra_modules,
                dracut: @dracut,
                update_grub: @update_grub,
                boot_dir: @boot_dir,
                modules_dir: @modules_dir
            }
        end

        # Construct a TargetOpts from configuration hash
        # @param name [String, Symbol] Target identifier name
        # @param config [Hash, nil] Raw configuration hash
        # @param defaults [Hash, nil] Optional global default options hash
        # @return [TargetOpts] Initialized TargetOpts object
        def self.from_config(name, config, defaults: nil)
            base_cfg = defaults ? defaults.transform_keys(&:to_sym) : {}
            cfg = config ? config.transform_keys(&:to_sym) : {}
            merged_cfg = base_cfg.merge(cfg)

            combined_extra = (Array(base_cfg[:extra_modules]) + Array(cfg[:extra_modules])).map(&:to_s).reject(&:empty?).uniq
            merged_cfg[:extra_modules] = combined_extra unless combined_extra.empty?

            new(
                name: name,
                branch: merged_cfg[:branch],
                type: merged_cfg[:type],
                host: merged_cfg[:host],
                port: merged_cfg[:port],
                sudo: merged_cfg[:sudo],
                reboot: merged_cfg[:reboot],
                reboot_method: merged_cfg[:reboot_method],
                minimal_modules: merged_cfg[:minimal_modules],
                strip_modules: merged_cfg[:strip_modules],
                extra_modules: merged_cfg[:extra_modules] || [],
                dracut: merged_cfg[:dracut],
                update_grub: merged_cfg[:update_grub],
                boot_dir: merged_cfg[:boot_dir],
                modules_dir: merged_cfg[:modules_dir]
            )
        end

        private

        # Determine target execution type (:local or :remote)
        # @param type [Symbol, String, nil] Explicit target type
        # @param host [String, nil] Target host specification
        # @return [Symbol] Resolved target type
        def determine_type(type, host)
            if type
                return type.to_sym
            end

            if host.nil? || host.to_s.strip.empty? || %w[localhost local 127.0.0.1 ::1].include?(host.to_s.strip.downcase)
                :local
            else
                :remote
            end
        end
    end

    # Backward compatibility alias for TargetOpts
    InstallTarget = TargetOpts
end
