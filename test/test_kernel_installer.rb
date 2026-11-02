require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

puts "Running KernelInstaller and TargetOpts unit tests..."

# Verify backward-compatibility alias
raise "Expected KernelWork::InstallTarget to alias TargetOpts" unless KernelWork::InstallTarget == KernelWork::TargetOpts

# Test Case 1: TargetOpts defaults and type detection
target_remote = KernelWork::TargetOpts.new(name: "vm1", host: "root@192.168.1.50")
raise "Expected remote target" unless target_remote.remote? && !target_remote.local?
raise "Expected default port 22" unless target_remote.port == 22
raise "Expected default sudo false for remote" unless target_remote.sudo == false
raise "Expected default reboot true" unless target_remote.reboot == true
raise "Expected default reboot_method :kexec" unless target_remote.reboot_method == :kexec
raise "Expected default minimal_modules true" unless target_remote.minimal_modules == true
raise "Expected default strip_modules true" unless target_remote.strip_modules == true
raise "Expected default dracut true" unless target_remote.dracut == true
raise "Expected default update_grub true" unless target_remote.update_grub == true

target_local = KernelWork::TargetOpts.new(name: "local1", host: "localhost")
raise "Expected local target for localhost" unless target_local.local? && !target_local.remote?
raise "Expected default sudo true for local" unless target_local.sudo == true

target_empty = KernelWork::TargetOpts.new(name: "local2")
raise "Expected local target for empty host" unless target_empty.local?

target_override = KernelWork::TargetOpts.new(name: "local3", host: "root@remote", type: :local, sudo: false)
raise "Expected explicit type override" unless target_override.local? && target_override.sudo == false

puts "Test Case 1 (TargetOpts defaults and type detection) Passed"

# Test Case 2: TargetOpts.from_config and to_h
cfg_hash = {
    "branch" => "SLE15-SP5",
    "host" => "testbox.suse.cz",
    "port" => "2222",
    "reboot_method" => "reboot",
    "reboot" => false,
    "minimal_modules" => false,
    "strip_modules" => false,
    "extra_modules" => ["mlx5_ib", "kvm_intel"],
    "dracut" => false,
    "update_grub" => false,
    "boot_dir" => "/custom/boot",
    "modules_dir" => "/custom/lib/modules"
}
target_from_cfg = KernelWork::TargetOpts.from_config("testbox", cfg_hash)
raise "Expected branch SLE15-SP5" unless target_from_cfg.branch == "SLE15-SP5"
raise "Expected port 2222" unless target_from_cfg.port == 2222
raise "Expected reboot_method :reboot" unless target_from_cfg.reboot_method == :reboot
raise "Expected reboot false" unless target_from_cfg.reboot == false
raise "Expected minimal_modules false" unless target_from_cfg.minimal_modules == false
raise "Expected strip_modules false" unless target_from_cfg.strip_modules == false
raise "Expected extra_modules" unless target_from_cfg.extra_modules == ["mlx5_ib", "kvm_intel"]
raise "Expected dracut false" unless target_from_cfg.dracut == false
raise "Expected update_grub false" unless target_from_cfg.update_grub == false
raise "Expected custom boot dir" unless target_from_cfg.boot_dir == "/custom/boot"
raise "Expected custom modules dir" unless target_from_cfg.modules_dir == "/custom/lib/modules"

h = target_from_cfg.to_h
raise "Expected to_h to contain name" unless h[:name] == "testbox"
raise "Expected to_h to contain reboot false" unless h[:reboot] == false

# Test Case 2B: Global defaults inheritance in TargetOpts.from_config
defaults_hash = {
    reboot_method: "reboot",
    dracut: false,
    extra_modules: ["mlx5_ib"],
    port: 2222
}
target_with_defaults = KernelWork::TargetOpts.from_config("vm_default", { "host" => "vmhost", "extra_modules" => ["kvm_intel"] }, defaults: defaults_hash)
raise "Expected inherited reboot_method :reboot" unless target_with_defaults.reboot_method == :reboot
raise "Expected inherited dracut false" unless target_with_defaults.dracut == false
raise "Expected inherited port 2222" unless target_with_defaults.port == 2222
raise "Expected merged extra_modules" unless target_with_defaults.extra_modules.sort == ["kvm_intel", "mlx5_ib"]

# Test Case 2C: Target specific override over global defaults
target_override = KernelWork::TargetOpts.from_config("vm_override", { "host" => "vmhost", "reboot_method" => "kexec", "dracut" => true }, defaults: defaults_hash)
raise "Expected override reboot_method :kexec" unless target_override.reboot_method == :kexec
raise "Expected override dracut true" unless target_override.dracut == true

puts "Test Case 2 (TargetOpts.from_config and to_h) Passed"

# Test Case 3: Target hierarchy instantiation and exec_target implementation
module KernelWork
    class TestRemoteTarget < KernelWork::KernelInstaller::RemoteTarget
        attr_reader :last_run, :last_run_system

        def run(cmd)
            @last_run = cmd
            ""
        end

        def runSystem(cmd, catch_err: false)
            @last_run_system = cmd
            0
        end
    end

    class TestLocalTarget < KernelWork::KernelInstaller::LocalTarget
        attr_reader :last_run, :last_run_system

        def run(cmd)
            @last_run = cmd
            ""
        end

        def runSystem(cmd, catch_err: false)
            @last_run_system = cmd
            0
        end
    end
end

remote_target = KernelWork::TestRemoteTarget.new(target_remote)
raise "Expected RemoteTarget instance" unless remote_target.is_a?(KernelWork::KernelInstaller::RemoteTarget)
remote_target.send(:exec_target, "uname -r", capture: true)
raise "Expected ssh command with capture, got: #{remote_target.last_run}" unless remote_target.last_run.include?("ssh -o StrictHostKeyChecking=accept-new") && remote_target.last_run.include?("root@192.168.1.50")

local_target = KernelWork::TestLocalTarget.new(target_local)
raise "Expected LocalTarget instance" unless local_target.is_a?(KernelWork::KernelInstaller::LocalTarget)
local_target.send(:exec_target, "depmod -a")
raise "Expected sudo command, got: #{local_target.last_run_system}" unless local_target.last_run_system.include?("sudo sh -c")

local_no_sudo = KernelWork::TestLocalTarget.new(KernelWork::TargetOpts.new(name: "rootlocal", sudo: false))
local_no_sudo.send(:exec_target, "depmod -a")
raise "Expected non-sudo command, got: #{local_no_sudo.last_run_system}" unless local_no_sudo.last_run_system == "depmod -a"

puts "Test Case 3 (Target instantiation and exec_target) Passed"

# Test Case 4: Centralized dry-run execution wrappers
dry_target = KernelWork::KernelInstaller::Target.build(target_remote, dry_run: true)
out = dry_target.send(:run_target, "cat /proc/modules", capture: true, dry_run_return: "test_output")
raise "Expected dry_run_return" unless out == "test_output"

status = dry_target.send(:run_target, "reboot")
raise "Expected dry-run exit 0" unless status == 0

local_status = dry_target.send(:run_local, "rsync src dst")
raise "Expected dry-run local exit 0" unless local_status == 0

puts "Test Case 4 (Dry-run execution wrappers) Passed"

# Test Case 5: Target high-level deployment routines (install_kernel, install_modules, depmod, grub, boot)
executed_commands = []
dummy_target_opts = KernelWork::TargetOpts.new(name: "dummytarget", host: "testhost")

module KernelWork
    class MockTarget < KernelWork::KernelInstaller::RemoteTarget
        attr_accessor :log_commands

        def initialize(opts)
            super(opts, dry_run: false)
            @log_commands = []
        end

        def exec_target(cmd, capture: false, catch_err: false)
            @log_commands << [:target, cmd, capture]
            capture ? "dummy_module 12345 0 -\n" : 0
        end

        def run_local(cmd, catch_err: false)
            @log_commands << [:local, cmd]
            0
        end
    end
end

mock = KernelWork::MockTarget.new(dummy_target_opts)

# fetch_lsmod
mods = mock.fetch_lsmod
raise "Expected ['dummy_module'], got: #{mods}" unless mods == ["dummy_module"]

# install_kernel (kexec: installs to modules_dir)
mock.install_kernel("6.4.0-default", "/tmp/vmlinuz")
mkdir_cmd = mock.log_commands[-2]
raise "Expected mkdir -p on target, got: #{mkdir_cmd}" unless mkdir_cmd[0] == :target && mkdir_cmd[1] == "mkdir -p /lib/modules/6.4.0-default"
last_local = mock.log_commands.last
raise "Expected rsync in run_local, got: #{last_local}" unless last_local[0] == :local && last_local[1].include?("rsync") && last_local[1].include?("/lib/modules/6.4.0-default/vmlinuz")

# install_modules (verifies exclusion of vmlinuz and initrd)
mock.install_modules("6.4.0-default", "/tmp/staging")
last_local = mock.log_commands.last
raise "Expected exclude args in module rsync, got: #{last_local}" unless last_local[1].include?("--exclude=vmlinuz*") && last_local[1].include?("--exclude=initrd*")

# depmod_and_dracut with dracut: false
mock.depmod_and_dracut("6.4.0-default", run_dracut: false)
last_target = mock.log_commands.last
raise "Expected depmod only" unless last_target[1] == "depmod -a 6.4.0-default"

# depmod_and_dracut with dracut: true (kexec: builds initrd in modules_dir)
mock.depmod_and_dracut("6.4.0-default", run_dracut: true)
last_target = mock.log_commands.last
raise "Expected depmod and dracut in modules_dir" unless last_target[1].include?("depmod") && last_target[1].include?("dracut -f /lib/modules/6.4.0-default/initrd")

# grub_setup
mock.grub_setup("6.4.0-default")
last_target = mock.log_commands.last
raise "Expected grub2-mkconfig" unless last_target[1].include?("grub2-mkconfig")

# boot with kexec
mock.boot("6.4.0-default", method: :kexec)
last_target = mock.log_commands.last
raise "Expected kexec boot" unless last_target[1].include?("kexec -l /lib/modules/6.4.0-default/vmlinuz --initrd=/lib/modules/6.4.0-default/initrd") && last_target[1].include?("systemctl kexec")

# Test :reboot method behavior (installs to boot_dir)
mock.opts.reboot_method = :reboot
mock.install_kernel("6.4.0-default", "/tmp/vmlinuz")
last_local = mock.log_commands.last
raise "Expected rsync to boot_dir, got: #{last_local}" unless last_local[1].include?("/boot/vmlinuz-6.4.0-default")

mock.depmod_and_dracut("6.4.0-default", run_dracut: true)
last_target = mock.log_commands.last
raise "Expected dracut to boot_dir, got: #{last_target}" unless last_target[1].include?("dracut -f /boot/initrd-6.4.0-default")

mock.opts.reboot_method = :kexec

# boot with reboot
mock.boot("6.4.0-default", method: :reboot, update_grub: false)
last_target = mock.log_commands.last
raise "Expected systemctl reboot" unless last_target[1] == "systemctl reboot"

# boot with reboot: false
cmd_count_before = mock.log_commands.length
mock.opts.reboot = false
mock.boot("6.4.0-default")
raise "Expected no commands when reboot is false" unless mock.log_commands.length == cmd_count_before
mock.opts.reboot = true

# hot_reload_module
mock.hot_reload_module("/tmp/my_driver.ko")
has_modprobe = mock.log_commands.any? { |c| c[1].to_s.include?("modprobe -r my_driver") }
raise "Expected hot reload modprobe commands" unless has_modprobe

puts "Test Case 5 (Target high-level deployment routines) Passed"

# Test Case 6: calculate_module_subset dependency resolution
Dir.mktmpdir do |dir|
    dep_content = <<~DEP
        kernel/drivers/net/ethernet/intel/e1000e/e1000e.ko: kernel/drivers/net/mdio/mdio.ko kernel/net/core/netcore.ko
        kernel/drivers/net/mdio/mdio.ko: kernel/drivers/base/regmap/regmap-core.ko
        kernel/drivers/base/regmap/regmap-core.ko:
        kernel/net/core/netcore.ko:
        kernel/fs/btrfs/btrfs.ko: kernel/lib/zstd/zstd.ko
        kernel/lib/zstd/zstd.ko:
    DEP
    File.write(File.join(dir, "modules.dep"), dep_content)
    File.write(File.join(dir, "modules.builtin"), "kernel/block/elevator.ko\n")
    File.write(File.join(dir, "modules.order"), "kernel/net/core/netcore.ko\n")

    installer = KernelWork::KernelInstaller.new
    needed = installer.calculate_module_subset(dir, ["e1000e"])

    raise "Missing e1000e.ko" unless needed.include?("kernel/drivers/net/ethernet/intel/e1000e/e1000e.ko")
    raise "Missing direct dependency mdio.ko" unless needed.include?("kernel/drivers/net/mdio/mdio.ko")
    raise "Missing transitive dependency regmap-core.ko" unless needed.include?("kernel/drivers/base/regmap/regmap-core.ko")
    raise "Missing netcore.ko" unless needed.include?("kernel/net/core/netcore.ko")
    raise "Unexpected btrfs.ko" if needed.include?("kernel/fs/btrfs/btrfs.ko")
    raise "Missing modules.builtin" unless needed.include?("modules.builtin")
    raise "Missing modules.order" unless needed.include?("modules.order")

    # Test with extra_modules
    needed_with_extra = installer.calculate_module_subset(dir, ["e1000e"], extra_modules: ["btrfs"])
    raise "Missing btrfs.ko from extra_modules" unless needed_with_extra.include?("kernel/fs/btrfs/btrfs.ko")
    raise "Missing zstd.ko dependency for extra module btrfs" unless needed_with_extra.include?("kernel/lib/zstd/zstd.ko")

    puts "Test Case 6 (calculate_module_subset transitive dependencies) Passed"
end

# Test Case 7: Target resolution from config and branch matching
KernelWork.config.settings[:test] = {
    default_target: "default_box",
    defaults: {
        reboot_method: "reboot",
        dracut: false
    },
    targets: {
        default_box: {
            host: "root@defaultbox",
            branch: "master"
        },
        sle15: {
            host: "root@sle15host",
            branch: "SLE15-SP5"
        }
    }
}

installer = KernelWork::KernelInstaller.new

# Branch matching with inherited defaults
t = installer.resolve_target(nil, "SLE15-SP5")
raise "Expected sle15 target" unless t.name == "sle15" && t.host == "root@sle15host"
raise "Expected sle15 to inherit reboot_method" unless t.reboot_method == :reboot
raise "Expected sle15 to inherit dracut false" unless t.dracut == false

# Ad-hoc host target inherits defaults
t3 = installer.resolve_target("user@adhoc-server.com", "other-branch")
raise "Expected adhoc host" unless t3.host == "user@adhoc-server.com" && t3.remote?
raise "Expected adhoc target to inherit reboot_method" unless t3.reboot_method == :reboot
raise "Expected adhoc target to inherit dracut false" unless t3.dracut == false

# Mismatch branch without force
begin
    installer.resolve_target("sle15", "master", force: false)
    raise "Expected TargetBranchMismatchError"
rescue KernelWork::TargetBranchMismatchError
    # expected
end

# Mismatch branch with force
t_forced = installer.resolve_target("sle15", "master", force: true)
raise "Expected force resolution to succeed" unless t_forced.name == "sle15"

# Target not found
begin
    installer.resolve_target("nonexistent_target", "master")
    raise "Expected TestTargetNotFoundError"
rescue KernelWork::TestTargetNotFoundError
    # expected
end

puts "Test Case 7 (Target resolution and branch matching) Passed"

# Test Case 8: CLI OptionParser test action options
opts = { action: :test }
parser = OptionParser.new
KernelWork::CLI::Kernel.set_opts(:deploy, parser, opts)

# Test --no-dracut and --dracut
parser.parse!(["--no-dracut"])
raise "Expected dracut: false" unless opts[:dracut] == false

parser.parse!(["--dracut"])
raise "Expected dracut: true" unless opts[:dracut] == true

# Test --no-grub and --grub
parser.parse!(["--no-grub"])
raise "Expected grub: false" unless opts[:grub] == false

parser.parse!(["--grub"])
raise "Expected grub: true" unless opts[:grub] == true

# Test --no-reboot and --reboot
parser.parse!(["--no-reboot"])
raise "Expected reboot: false" unless opts[:reboot] == false

parser.parse!(["--reboot"])
raise "Expected reboot: true" unless opts[:reboot] == true

# Test --no-strip and --strip
parser.parse!(["--no-strip"])
raise "Expected strip_modules: false" unless opts[:strip_modules] == false

parser.parse!(["--strip"])
raise "Expected strip_modules: true" unless opts[:strip_modules] == true

# Test -e and --extra-module
parser.parse!(["-e", "mlx5_ib,kvm_intel", "--extra-module", "e1000e"])
raise "Expected extra_modules" unless opts[:extra_modules] == ["mlx5_ib", "kvm_intel", "e1000e"]

puts "Test Case 8 (CLI OptionParser deploy action options) Passed"

puts "Test Case 8 (CLI OptionParser [no-] overrides) Passed"

# Test Case 9: CLI OptionParser defaults action options
opts_defaults = { action: :defaults }
parser_defaults = OptionParser.new
KernelWork::CLI::Config::TargetCLI::TargetAction.set_opts(:defaults, parser_defaults, opts_defaults)

parser_defaults.parse!(["--reboot-method", "reboot", "--no-dracut", "-e", "mlx5_core", "--strip"])
raise "Expected defaults reboot_method :reboot" unless opts_defaults[:reboot_method] == "reboot"
raise "Expected defaults dracut false" unless opts_defaults[:dracut] == false
raise "Expected defaults strip_modules true" unless opts_defaults[:strip_modules] == true
raise "Expected defaults extra_modules" unless opts_defaults[:extra_modules] == ["mlx5_core"]

puts "Test Case 9 (CLI OptionParser target defaults action options) Passed"

puts "\nAll KernelInstaller and TargetOpts unit tests passed successfully!"
