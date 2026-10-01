require 'tmpdir'
require 'fileutils'
require 'open3'
require_relative '../lib/kernel-work'

# Helper methods and test harness fixtures for KernelWork unit tests
module TestHelper
  # Execute a git command in the target directory
  # @param dir [String] Working directory
  # @param cmd [String] Git command string
  # @return [String] Output of git command
  # @raise [RuntimeError] If git command fails
  def self.run_git(dir, cmd)
    out, status = Open3.capture2e("git #{cmd}", chdir: dir)
    raise "Git command 'git #{cmd}' failed in #{dir}:\n#{out}" unless status.success?
    out
  end

  # Create real temporary git repositories for Linux and KernelSource and yield initialized models
  # @yieldparam env [Hash] Hash with :linux, :kernel_source, :workflow, :linux_dir, :ks_dir, :base_sha
  # @return [void]
  def self.with_test_repos
    Dir.mktmpdir("kernel-work-test-") do |tmp|
      linux_dir = File.join(tmp, "linux")
      kernel_source_dir = File.join(tmp, "kernel-source")
      Dir.mkdir(linux_dir)
      Dir.mkdir(kernel_source_dir)

      # Init Linux repo
      run_git(linux_dir, "init -b master")
      run_git(linux_dir, "config user.name 'Test Committer'")
      run_git(linux_dir, "config user.email 'test@example.com'")
      run_git(linux_dir, "config commit.gpgsign false")
      File.write(File.join(linux_dir, "Makefile"), "VERSION = 6\nPATCHLEVEL = 4\nSUBLEVEL = 0\nEXTRAVERSION =\n")
      File.write(File.join(linux_dir, "file.txt"), "Initial content\n")
      run_git(linux_dir, "add .")
      run_git(linux_dir, "commit -m 'Initial commit'")
      base_sha = run_git(linux_dir, "rev-parse HEAD").strip

      # Init KernelSource repo
      run_git(kernel_source_dir, "init -b master")
      run_git(kernel_source_dir, "config user.name 'Test Committer'")
      run_git(kernel_source_dir, "config user.email 'test@example.com'")
      run_git(kernel_source_dir, "config commit.gpgsign false")
      FileUtils.mkdir_p(File.join(kernel_source_dir, "patches.suse"))
      FileUtils.mkdir_p(File.join(kernel_source_dir, "series"))
      FileUtils.mkdir_p(File.join(kernel_source_dir, "scripts", "git_sort"))
      series_insert_path = File.join(kernel_source_dir, "scripts", "git_sort", "series_insert")
      File.write(series_insert_path, "#!/bin/sh\necho \"$1\" >> series.conf\n")
      File.chmod(0755, series_insert_path)
      seq_patch_path = File.join(kernel_source_dir, "scripts", "sequence-patch")
      File.write(seq_patch_path, "#!/bin/sh\nexit 0\n")
      File.chmod(0755, seq_patch_path)
      File.write(File.join(kernel_source_dir, "series.conf"), "# Series file\n")
      run_git(kernel_source_dir, "add .")
      run_git(kernel_source_dir, "commit -m 'Initial kernel-source commit'")

      # Setup mock config and environment
      orig_linux_env = ENV["LINUX_GIT"]
      orig_ks_env = ENV["KERNEL_SOURCE_DIR"]
      ENV["LINUX_GIT"] = linux_dir
      ENV["KERNEL_SOURCE_DIR"] = kernel_source_dir

      orig_config = KernelWork.config
      mock_config = KernelWork::Config.new
      mock_config.linux_git = linux_dir
      mock_config.kernel_source_dir = kernel_source_dir
      KernelWork.instance_variable_set(:@config, mock_config)

      linux = KernelWork::Linux.new(linux_dir)
      kernel_source = KernelWork::KernelSource.new(kernel_source_dir)
      workflow = KernelWork::Workflow.new(linux: linux, kernel_source: kernel_source)

      begin
        yield({
          linux: linux,
          kernel_source: kernel_source,
          workflow: workflow,
          tmp: tmp,
          linux_dir: linux_dir,
          ks_dir: kernel_source_dir,
          base_sha: base_sha
        })
      ensure
        ENV["LINUX_GIT"] = orig_linux_env
        ENV["KERNEL_SOURCE_DIR"] = orig_ks_env
        KernelWork.instance_variable_set(:@config, orig_config)
      end
    end
  end
end
