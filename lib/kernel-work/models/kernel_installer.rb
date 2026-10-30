# frozen_string_literal: true

require 'set'
require 'tempfile'

module KernelWork
    # Handles deployment, installation, and testing of Linux kernels on remote or local targets.
    # Supports kexec fast reboot, GRUB boot configuration, and minimal lsmod module synchronization.
    class KernelInstaller < Common
        # Abstract base class representing a deployment target environment
        class Target < Common
            # @!attribute [r] opts
            #   @return [TargetOpts] Target configuration options
            attr_reader :opts

            # @!attribute [r] dry_run
            #   @return [Boolean] Whether running in dry-run mode
            attr_reader :dry_run

            # Initialize a new Target instance
            # @param opts [TargetOpts] Target options
            # @param dry_run [Boolean] Whether to execute in dry-run mode
            def initialize(opts, dry_run: false)
                @opts = opts
                @dry_run = !!dry_run
            end

            # Factory method to instantiate the appropriate Target subclass
            # @param target_opts [TargetOpts] Target options
            # @param dry_run [Boolean] Whether to execute in dry-run mode
            # @return [Target] Instance of LocalTarget or RemoteTarget
            def self.build(target_opts, dry_run: false)
                if target_opts.local?
                    LocalTarget.new(target_opts, dry_run: dry_run)
                else
                    RemoteTarget.new(target_opts, dry_run: dry_run)
                end
            end

            # Fetch active kernel module names from the target
            # @return [Array<String>] List of active kernel module names
            def fetch_lsmod
                output = run_target("cat /proc/modules 2>/dev/null || lsmod", capture: true, dry_run_return: "")
                output.lines.map do |line|
                    mod = line.split(/\s+/).first
                    mod ? mod.tr('-', '_') : nil
                end.compact.reject(&:empty?).uniq
            end

            # Synchronize kernel binary image to target boot directory
            # @param kernel_release [String] Target kernel release version string
            # @param kernel_image_path [String] Local path to kernel binary image
            # @return [void]
            def install_kernel(kernel_release, kernel_image_path)
                dest = "#{@opts.boot_dir}/vmlinuz-#{kernel_release}"
                copy_to_target(kernel_image_path, dest)
            end

            # Synchronize kernel modules to target modules directory
            # @param kernel_release [String] Target kernel release version string
            # @param staging_dir [String] Local staging directory containing kernel modules
            # @param file_list [Array<String>, nil] List of relative files to sync, or nil for all
            # @return [void]
            def install_modules(kernel_release, staging_dir, file_list: nil)
                dest = "#{@opts.modules_dir}/#{kernel_release}/"
                if file_list && !file_list.empty?
                    file_list_content = file_list.join("\n") + "\n"
                    if @dry_run
                        log(:INFO, "[DRY-RUN] rsync --files-from=(#{file_list.length} files) #{staging_dir}/ -> #{dest}")
                        return
                    end

                    temp = Tempfile.new('kwork_modules')
                    begin
                        temp.write(file_list_content)
                        temp.flush
                        copy_to_target("#{staging_dir}/", dest, ["--files-from=#{temp.path}"])
                    ensure
                        temp.close
                        temp.unlink
                    end
                else
                    copy_to_target("#{staging_dir}/", dest)
                end
            end

            # Run depmod and optionally dracut on the target
            # @param kernel_release [String] Target kernel release version string
            # @param run_dracut [Boolean] Whether to generate initrd via dracut
            # @return [void]
            def depmod_and_dracut(kernel_release, run_dracut: true)
                commands = ["depmod -a #{kernel_release}"]
                if run_dracut
                    commands << "dracut -f #{@opts.boot_dir}/initrd-#{kernel_release} #{kernel_release}"
                end
                run_target(commands.join(" && "))
            end

            # Configure target GRUB bootloader to select test kernel for next boot
            # @param kernel_release [String] Target kernel release version string
            # @return [void]
            def grub_setup(kernel_release)
                target_cmd = "grub2-mkconfig -o /boot/grub2/grub.cfg && (grub2-reboot \"vmlinuz-#{kernel_release}\" || grub2-once \"vmlinuz-#{kernel_release}\" || true)"
                run_target(target_cmd)
            end

            # Boot target into newly installed kernel using kexec or reboot
            # @param kernel_release [String] Target kernel release version string
            # @param method [Symbol, nil] Boot method override (:kexec or :reboot)
            # @param update_grub [Boolean, nil] Whether to update GRUB boot order in reboot mode
            # @return [void]
            def boot(kernel_release, method: nil, update_grub: nil)
                return unless @opts.reboot

                boot_method = (method || @opts.reboot_method || :kexec).to_sym
                if boot_method == :kexec
                    target_cmd = "kexec -l #{@opts.boot_dir}/vmlinuz-#{kernel_release} --initrd=#{@opts.boot_dir}/initrd-#{kernel_release} --reuse-cmdline && systemctl kexec"
                    log(:INFO, "Rebooting target via kexec...") unless @dry_run
                    run_target(target_cmd, catch_err: true)
                else
                    should_update_grub = update_grub.nil? ? @opts.update_grub : update_grub
                    grub_setup(kernel_release) if should_update_grub
                    log(:INFO, "Rebooting target via systemctl reboot...") unless @dry_run
                    run_target("systemctl reboot", catch_err: true)
                end
            end

            # Hot-reload a single kernel module on the target without rebooting
            # @param local_ko_path [String] Local path to compiled .ko file
            # @return [void]
            def hot_reload_module(local_ko_path)
                file_base = File.basename(local_ko_path)
                mod_name = file_base.sub(/\.ko(\.zst|\.xz|\.gz)?$/, '').tr('-', '_')
                target_dest = "#{@opts.modules_dir}/$(uname -r)/extra/#{file_base}"

                run_target("mkdir -p #{@opts.modules_dir}/$(uname -r)/extra")
                copy_to_target(local_ko_path, target_dest)
                log(:INFO, "Deploying and reloading module #{mod_name} on #{@opts.name || @opts.host || 'local'}...") unless @dry_run
                run_target("modprobe -r #{mod_name} ; insmod #{target_dest} || modprobe #{mod_name}")
            end

            protected

            # Low-level execution of a command on the target environment
            # @param cmd [String] Shell command to execute on target
            # @param capture [Boolean] Whether to capture and return stdout
            # @param catch_err [Boolean] Whether runSystem should catch errors
            # @return [String, Integer] Output when capture is true, or exit status
            # @raise [NotImplementedError] Must be implemented by subclasses
            def exec_target(cmd, capture: false, catch_err: false)
                raise NotImplementedError, "#{self.class} must implement #exec_target"
            end

            # Copy local files to the target destination
            # @param local_src [String] Local source file or directory
            # @param target_dest [String] Target destination path
            # @param extra_args [Array<String>] Additional rsync CLI flags
            # @return [void]
            # @raise [NotImplementedError] Must be implemented by subclasses
            def copy_to_target(local_src, target_dest, extra_args = [])
                raise NotImplementedError, "#{self.class} must implement #copy_to_target"
            end

            # Execute a command on the target environment, intercepted during dry-run
            # @param cmd [String] Shell command to execute
            # @param capture [Boolean] Whether to capture and return stdout
            # @param catch_err [Boolean] Whether runSystem should catch errors
            # @param dry_run_return [Object] Value to return during dry run
            # @return [String, Integer] Stdout output when capture is true, or exit status
            def run_target(cmd, capture: false, catch_err: false, dry_run_return: "")
                if @dry_run
                    target_label = @opts.name || @opts.host || "local"
                    log(:INFO, "[DRY-RUN] (#{target_label}) #{cmd}")
                    return capture ? dry_run_return : 0
                end

                exec_target(cmd, capture: capture, catch_err: catch_err)
            end

            # Execute a command locally on the host machine, intercepted during dry-run
            # @param cmd [String] Shell command to execute
            # @param catch_err [Boolean] Whether runSystem should catch errors
            # @return [Integer] Exit status code
            def run_local(cmd, catch_err: false)
                if @dry_run
                    log(:INFO, "[DRY-RUN] #{cmd}")
                    0
                else
                    runSystem(cmd, catch_err: catch_err)
                end
            end
        end

        # Deployment target implementation for remote hosts via SSH and rsync
        class RemoteTarget < Target
            protected

            # Low-level execution of a command on the remote host via SSH
            # @param cmd [String] Command to execute on remote host
            # @param capture [Boolean] Whether to capture stdout
            # @param catch_err [Boolean] Whether to catch errors
            # @return [String, Integer] Output or exit code
            def exec_target(cmd, capture: false, catch_err: false)
                port_arg = (@opts.port && @opts.port.to_i != 22) ? "-p #{@opts.port} " : ""
                escaped_cmd = cmd.gsub('"', '\"')
                ssh_cmd = "ssh -o StrictHostKeyChecking=accept-new #{port_arg}#{@opts.host} \"#{escaped_cmd}\""
                capture ? run(ssh_cmd) : runSystem(ssh_cmd, catch_err: catch_err)
            end

            # Copy local files to remote destination using rsync over SSH
            # @param local_src [String] Local source file or directory
            # @param target_dest [String] Destination path on remote host
            # @param extra_args [Array<String>] Additional rsync CLI flags
            # @return [void]
            def copy_to_target(local_src, target_dest, extra_args = [])
                port_arg = (@opts.port && @opts.port.to_i != 22) ? "-e 'ssh -p #{@opts.port}' " : ""
                flags = extra_args.empty? ? "" : "#{extra_args.join(' ')} "
                cmd = "rsync -avzP --checksum #{port_arg}#{flags}#{local_src} #{@opts.host}:#{target_dest}"
                run_local(cmd)
            end
        end

        # Deployment target implementation for local installations using sudo and direct copying/rsync
        class LocalTarget < Target
            protected

            # Low-level execution of a command on the local target, optionally elevated with sudo
            # @param cmd [String] Command to execute on local system
            # @param capture [Boolean] Whether to capture stdout
            # @param catch_err [Boolean] Whether to catch errors
            # @return [String, Integer] Output or exit code
            def exec_target(cmd, capture: false, catch_err: false)
                final_cmd = if @opts.sudo
                    escaped_cmd = cmd.gsub('"', '\"')
                    "sudo sh -c \"#{escaped_cmd}\""
                else
                    cmd
                end
                capture ? run(final_cmd) : runSystem(final_cmd, catch_err: catch_err)
            end

            # Copy local files to destination directory using rsync with optional sudo
            # @param local_src [String] Local source file or directory
            # @param target_dest [String] Destination path on local system
            # @param extra_args [Array<String>] Additional rsync CLI flags
            # @return [void]
            def copy_to_target(local_src, target_dest, extra_args = [])
                sudo_arg = @opts.sudo ? "--rsync-path='sudo rsync' " : ""
                flags = extra_args.empty? ? "" : "#{extra_args.join(' ')} "
                cmd = "rsync -avzP --checksum #{sudo_arg}#{flags}#{local_src} #{target_dest}"
                run_local(cmd)
            end
        end

        # @!attribute [r] linux
        #   @return [Linux] Linux model instance
        attr_reader :linux

        # Initialize a new KernelInstaller instance
        # @param linux [Linux, nil] Linux model object
        def initialize(linux = nil)
            @linux = linux || Linux.new
        end

        # Create a Target instance from a TargetOpts configuration
        # @param target_opts [TargetOpts] Target configuration options
        # @param dry_run [Boolean] Whether to execute in dry-run mode
        # @return [Target] Instance of LocalTarget or RemoteTarget
        def create_target(target_opts, dry_run: false)
            Target.build(target_opts, dry_run: dry_run)
        end

        # Resolve target configuration by target name or by matching active working branch
        # @param target_name [String, Symbol, nil] Explicit target name if provided
        # @param current_branch [String, nil] Current active git branch name
        # @param force [Boolean] Override branch mismatch error
        # @return [TargetOpts] Resolved TargetOpts object
        # @raise [TestTargetNotFoundError] If explicit target name is not found
        # @raise [NoTestTargetForBranchError] If no target matches the active branch
        # @raise [TargetBranchMismatchError] If explicit target branch conflicts with active branch
        def resolve_target(target_name = nil, current_branch = nil, force: false)
            target = KernelWork.config.find_test_target(target_name, current_branch)

            if target_name && target.nil?
                if target_name.to_s.include?("@") || target_name.to_s.include?(".") || %w[localhost local].include?(target_name.to_s)
                    target = TargetOpts.new(name: target_name.to_s, host: target_name.to_s)
                else
                    raise TestTargetNotFoundError.new(target_name)
                end
            end

            if target.nil?
                raise NoTestTargetForBranchError.new(current_branch || "unknown")
            end

            if target_name && target.branch && current_branch && target.branch.to_s != current_branch.to_s && !force
                raise TargetBranchMismatchError.new(target.branch, current_branch)
            end

            target
        end

        # Calculate minimal module file list based on active modules and dependencies
        # @param staging_modules_dir [String] Path to local modules directory containing modules.dep
        # @param active_modules [Array<String>] Active module names from target
        # @param extra_subsets [Array<String>] Additional subtree paths to include
        # @return [Array<String>] Relative file paths of required modules and metadata
        def calculate_module_subset(staging_modules_dir, active_modules, extra_subsets: [])
            dep_file = File.join(staging_modules_dir, "modules.dep")
            mod_map = {}

            if File.exist?(dep_file)
                File.readlines(dep_file).each do |line|
                    line = line.strip
                    next if line.empty? || line.start_with?("#")

                    parts = line.split(':')
                    ko_path = parts[0].strip
                    deps = parts[1] ? parts[1].strip.split(/\s+/) : []

                    base_name = File.basename(ko_path).sub(/\.ko(\.zst|\.xz|\.gz)?$/, '').tr('-', '_')
                    mod_map[base_name] = { path: ko_path, deps: deps }
                end
            end

            needed_paths = Set.new
            visited_mods = Set.new
            queue = active_modules.dup

            while !queue.empty?
                mod_name = queue.shift
                next if visited_mods.include?(mod_name)
                visited_mods << mod_name

                entry = mod_map[mod_name]
                next unless entry

                needed_paths << entry[:path]
                entry[:deps].each do |dep_path|
                    needed_paths << dep_path
                    dep_name = File.basename(dep_path).sub(/\.ko(\.zst|\.xz|\.gz)?$/, '').tr('-', '_')
                    queue << dep_name unless visited_mods.include?(dep_name)
                end
            end

            # Include any files matching extra subsets
            if extra_subsets && !extra_subsets.empty?
                mod_map.each_value do |entry|
                    if extra_subsets.any? { |sub| entry[:path].include?(sub) }
                        needed_paths << entry[:path]
                        entry[:deps].each { |d| needed_paths << d }
                    end
                end
            end

            # Include standard module metadata files if present
            ["modules.order", "modules.builtin", "modules.builtin.modinfo"].each do |f|
                needed_paths << f if File.exist?(File.join(staging_modules_dir, f))
            end

            needed_paths.to_a
        end
    end
end
