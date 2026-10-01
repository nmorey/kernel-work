require_relative 'test_helper'
require 'optparse'

puts "Running CLI unit tests..."

# Test Case 1: CLI::Kernel option definitions and validation
opts = {}
parser = OptionParser.new
KernelWork::CLI::Kernel.set_opts(:backport_todo, parser, opts)
parser.parse(["--upstream-ref", "v6.4", "--base-ref", "v6.3", "--fixes"])

raise "opts[:upstream_ref] not parsed" unless opts[:upstream_ref] == "v6.4"
raise "opts[:base_ref] not parsed" unless opts[:base_ref] == "v6.3"
raise "opts[:filter][:fixes] not parsed" unless opts.dig(:filter, :fixes) == true

KernelWork::CLI::Kernel.check_opts(opts)
puts "Test Case 1 (CLI::Kernel.set_opts and check_opts) Passed"

# Test Case 2: CLI::Kernel execution with test repos
TestHelper.with_test_repos do |env|
  linux = env[:linux]
  ks = env[:kernel_source]
  cli = KernelWork::CLI::Kernel.new
  cli.linux = linux
  cli.kernel_source = ks

  raise "cli.linux not set" unless cli.linux == linux
  raise "cli.kernel_source not set" unless cli.kernel_source == ks
  raise "cli.workflow not set" unless cli.workflow.is_a?(KernelWork::Workflow)

  # Run backport_todo when there are no commits left
  cli.backport_todo(upstream_ref: "HEAD", base_ref: "HEAD", filter: KernelWork::CommitFilter.new)

  puts "Test Case 2 (CLI::Kernel initialization and backport_todo) Passed"
end

# Test Case 3: CLI::Config Actions
TestHelper.with_test_repos do |_env|
  action = KernelWork::CLI::Config::ConfigAction.new
  action.diff({})

  branch_action = KernelWork::CLI::Config::BranchCLI::BranchAction.new
  branch_action.list({ raw: true })

  filter_action = KernelWork::CLI::Config::FilterCLI::FilterAction.new
  filter_action.list({ raw: true })

  puts "Test Case 3 (CLI::Config actions) Passed"
end

# Test Case 4: LinuxBuildOpts & CLI::BuildOpts unit tests
l_default = KernelWork::LinuxBuildOpts.new
raise "LinuxBuildOpts default arch should be :x86_64" unless l_default.arch == :x86_64
raise "LinuxBuildOpts default build should be false" unless l_default.build == false
raise "LinuxBuildOpts default build_subset should be empty" unless l_default.build_subset.empty?
raise "LinuxBuildOpts to_h failed" unless l_default.to_h[:arch] == :x86_64

b_default = KernelWork::CLI::BuildOpts.new
raise "CLI::BuildOpts should inherit from LinuxBuildOpts" unless b_default.is_a?(KernelWork::LinuxBuildOpts)
raise "Default arch should be :x86_64" unless b_default.arch == :x86_64
raise "Default build should be false" unless b_default.build == false
raise "Default build_subset should be empty" unless b_default.build_subset.empty?

b_custom = KernelWork::CLI::BuildOpts.new(
  arch: :aarch64,
  j: 8,
  cc: "clang",
  hostcc: "clang",
  verbose: true,
  old_kernel: true,
  full: true,
  build: true,
  build_subset: ["drivers/infiniband"]
)
raise "arch mismatch" unless b_custom.arch == :aarch64
raise "j mismatch" unless b_custom.j == 8
raise "cc mismatch" unless b_custom.cc == "clang"
raise "verbose mismatch" unless b_custom.verbose == true
raise "old_kernel mismatch" unless b_custom.old_kernel == true
raise "full mismatch" unless b_custom.full == true
raise "build mismatch" unless b_custom.build == true
raise "subset mismatch" unless b_custom.build_subset == ["drivers/infiniband"]

# Test from_opts conversion from hash
opts_hash = {
  arch: "s390x",
  j: 16,
  cc: "gcc-10",
  hostcc: "gcc-10",
  build_verbose: true,
  old_kernel: false,
  oldconfig_full: true,
  build: true,
  build_subset: ["kernel/"]
}
b_from_hash = KernelWork::CLI::BuildOpts.from_opts(opts_hash)
raise "from_opts should return a LinuxBuildOpts" unless b_from_hash.is_a?(KernelWork::LinuxBuildOpts)
raise "from_opts arch mismatch" unless b_from_hash.arch == :s390x
raise "from_opts j mismatch" unless b_from_hash.j == 16
raise "from_opts cc mismatch" unless b_from_hash.cc == "gcc-10"
raise "from_opts verbose mismatch" unless b_from_hash.verbose == true
raise "from_opts full mismatch" unless b_from_hash.full == true
raise "from_opts build mismatch" unless b_from_hash.build == true
raise "from_opts subset mismatch" unless b_from_hash.build_subset == ["kernel/"]

# Test OptionParser integration
parser = OptionParser.new
parsed_opts = {}
KernelWork::CLI::BuildOpts.add_options(parser, parsed_opts, with_build: true, with_verbose: true, with_old_kernel: true, with_full: true, with_subset: true)
parser.parse(["-B", "-a", "x86_64", "-j", "4", "-v", "-o", "-F", "-p", "drivers/net"])

raise "parsed build flag failed" unless parsed_opts[:build] == true
raise "parsed arch failed" unless parsed_opts[:arch] == :x86_64
raise "parsed j failed" unless parsed_opts[:j] == 4
raise "parsed verbose failed" unless parsed_opts[:build_verbose] == true
raise "parsed old_kernel failed" unless parsed_opts[:old_kernel] == true
raise "parsed full failed" unless parsed_opts[:oldconfig_full] == true
raise "parsed path failed" unless parsed_opts[:build_subset] == ["drivers/net"]
raise "parsed build_opts obj failed" unless parsed_opts[:build_opts].is_a?(KernelWork::CLI::BuildOpts)
raise "parsed build_opts.build failed" unless parsed_opts[:build_opts].build == true

puts "Test Case 4 (LinuxBuildOpts and CLI::BuildOpts unit tests and option parsing) Passed"

# Test Case 5: CommitFilter and CLI::CommitFilter unit tests and option parsing
f_default = KernelWork::CommitFilter.new
raise "default paths should be empty" unless f_default.paths == []
raise "default exclude_paths should be empty" unless f_default.exclude_paths == []
raise "default fixes should be false" unless f_default.fixes == false
raise "default grep should be nil" unless f_default.grep.nil?
raise "default author should be nil" unless f_default.author.nil?
raise "default skip_treewide should be false" unless f_default.skip_treewide == false

f_custom = KernelWork::CommitFilter.new(
  paths: ["drivers/net"],
  exclude_paths: ["drivers/net/wireless"],
  fixes: true,
  grep: "mlx5",
  author: "Alice",
  skip_treewide: true
)
raise "custom paths failed" unless f_custom.paths == ["drivers/net"]
raise "custom exclude_paths failed" unless f_custom.exclude_paths == ["drivers/net/wireless"]
raise "custom fixes failed" unless f_custom.fixes == true
raise "custom grep failed" unless f_custom.grep == "mlx5"
raise "custom author failed" unless f_custom.author == "Alice"
raise "custom skip_treewide failed" unless f_custom.skip_treewide == true

# Test to_h and from_h
f_hash = f_custom.to_h
f_from_h = KernelWork::CommitFilter.from_h(f_hash)
raise "from_h paths mismatch" unless f_from_h.paths == ["drivers/net"]
raise "from_h fixes mismatch" unless f_from_h.fixes == true
raise "from_h grep mismatch" unless f_from_h.grep == "mlx5"

# Test overlay
f_overlay = f_custom.overlay(KernelWork::CommitFilter.new(paths: ["drivers/infiniband"], grep: "rdma"))
raise "overlay paths failed" unless f_overlay.paths == ["drivers/net", "drivers/infiniband"]
raise "overlay grep failed" unless f_overlay.grep == "rdma"
raise "overlay fixes preserved failed" unless f_overlay.fixes == true

# Test CLI::CommitFilter option parser
filter_parser = OptionParser.new
parsed_filter_opts = {}
KernelWork::CLI::CommitFilter.add_options(filter_parser, parsed_filter_opts)
filter_parser.parse(["-p", "drivers/net", "-e", "drivers/net/wireless", "-F", "-g", "fix", "--author", "Bob", "-T"])
f_resolved = KernelWork::CLI::CommitFilter.from_opts(parsed_filter_opts)
raise "f_resolved paths failed" unless f_resolved.paths == ["drivers/net"]
raise "f_resolved exclude_paths failed" unless f_resolved.exclude_paths == ["drivers/net/wireless"]
raise "f_resolved fixes failed" unless f_resolved.fixes == true
raise "f_resolved grep failed" unless f_resolved.grep == "fix"
raise "f_resolved author failed" unless f_resolved.author == "Bob"
raise "f_resolved skip_treewide failed" unless f_resolved.skip_treewide == true

puts "Test Case 5 (CommitFilter and CLI::CommitFilter unit tests and option parsing) Passed"

# Test Case 6: Config linux & kernel_source renaming and deprecated config error
cfg = KernelWork::Config.new
raise "Config linux not accessible" unless cfg.linux.remote == "SUSE"
raise "Config kernel_source not accessible" unless cfg.kernel_source.remote == "origin"
raise "Config settings[:linux] missing" unless cfg.settings[:linux].is_a?(Hash)
raise "Config settings[:kernel_source] missing" unless cfg.settings[:kernel_source].is_a?(Hash)
raise "Config upstream should not be a method" if cfg.respond_to?(:upstream)
raise "Config suse should not be a method" if cfg.respond_to?(:suse)

# Test DeprecatedConfigError on old config names
Dir.mktmpdir do |dir|
  old_upstream_file = File.join(dir, "old_upstream.yml")
  File.write(old_upstream_file, { upstream: { remote: "OLD" } }.to_yaml)
  orig_path = KernelWork::Config.custom_config_path
  begin
    KernelWork::Config.custom_config_path = old_upstream_file
    raised = false
    begin
      KernelWork::Config.new
    rescue KernelWork::DeprecatedConfigError
      raised = true
    end
    raise "DeprecatedConfigError not raised for upstream" unless raised

    old_suse_file = File.join(dir, "old_suse.yml")
    File.write(old_suse_file, { suse: { remote: "OLD" } }.to_yaml)
    KernelWork::Config.custom_config_path = old_suse_file
    raised = false
    begin
      KernelWork::Config.new
    rescue KernelWork::DeprecatedConfigError
      raised = true
    end
    raise "DeprecatedConfigError not raised for suse" unless raised
  ensure
    KernelWork::Config.custom_config_path = orig_path
  end
end

# Test Case 7: CLI::Kernel option ordering and commit resolution (-c, -b, -f)
parser = OptionParser.new
opts = {}
KernelWork::CLI::Kernel.set_opts(:scp, parser, opts)
parser.parse(["-c", "sha1", "-b", "12345", "-c", "sha2", "-b", "CVE-2026-9999"])

raise "Option ordering not preserved" unless opts[:commits] == [
  { type: :sha, value: "sha1" },
  { type: :bug, value: "12345" },
  { type: :sha, value: "sha2" },
  { type: :bug, value: "CVE-2026-9999" }
]

extract_parser = OptionParser.new
extract_opts = {}
KernelWork::CLI::Kernel.set_opts(:extract_patch, extract_parser, extract_opts)
extract_parser.parse(["-b", "bsc#12345", "-c", "sha3", "-F", "mypatch.patch", "-f", "mycommits.txt"])

raise "Extract patch options not parsed" unless extract_opts[:commits] == [
  { type: :bug, value: "bsc#12345" },
  { type: :sha, value: "sha3" },
  { type: :file, value: "mycommits.txt" }
]
raise "Extract patch filename not parsed" unless extract_opts[:filename] == "mypatch.patch"
raise "Extract patch file not parsed" unless extract_opts[:file] == "mycommits.txt"

# Test resolve_commits in execution environment
TestHelper.with_test_repos do |env|
  linux = env[:linux]
  ks = env[:kernel_source]
  cli = KernelWork::CLI::Kernel.new
  cli.linux = linux
  cli.kernel_source = ks
  linux.instance_variable_set(:@branch, "master")
  ks.branch = "master"

  Dir.mktmpdir do |tracker_dir|
    cves_dir = File.join(tracker_dir, "cves")
    FileUtils.mkdir_p(cves_dir)
    File.write(File.join(cves_dir, "12345.json"), JSON.pretty_generate({
      bug_id: "12345",
      cve: "CVE-2026-1234",
      fix_sha: "1111111111111111111111111111111111111111",
      summary: "Test bug 1",
      distros: [],
      branches: {}
    }))
    File.write(File.join(cves_dir, "99999.json"), JSON.pretty_generate({
      bug_id: "99999",
      cve: "CVE-2026-9999",
      fix_sha: "2222222222222222222222222222222222222222",
      summary: "Test bug 2",
      distros: [],
      branches: {}
    }))
    File.write(File.join(cves_dir, "88888.json"), JSON.pretty_generate({
      bug_id: "88888",
      cve: "CVE-2026-8888",
      fix_sha: nil,
      summary: "Test bug without sha",
      distros: [],
      branches: {}
    }))

    tracker = KernelWork::CveLocalTracker.new({ data_repo: tracker_dir })
    cli.cve_tracker = tracker

    # 1. Test resolving ordered options (-c, -b)
    commits = cli.send(:resolve_commits, {
      commits: [
        { type: :sha, value: "sha1" },
        { type: :bug, value: "12345" },
        { type: :sha, value: "sha2" },
        { type: :bug, value: "CVE-2026-9999" }
      ]
    })

    raise "Wrong number of resolved commits" unless commits.length == 4
    raise "Commit 0 sha mismatch" unless commits[0].sha == "sha1"
    raise "Commit 1 sha mismatch" unless commits[1].sha == "1111111111111111111111111111111111111111"
    raise "Commit 1 extra_desc mismatch" unless commits[1].extra_desc == "CVE-2026-1234 bsc#12345"
    raise "Commit 2 sha mismatch" unless commits[2].sha == "sha2"
    raise "Commit 3 sha mismatch" unless commits[3].sha == "2222222222222222222222222222222222222222"
    raise "Commit 3 extra_desc mismatch" unless commits[3].extra_desc == "CVE-2026-9999 bsc#99999"

    # 2. Test resolving with a file
    file_path = File.join(tracker_dir, "commits.txt")
    File.write(file_path, <<~EOF
      # A comment
      3333333333333333333333333333333333333333 # Subject text
      CVE-2026-1234
      4444444444444444444444444444444444444444
    EOF
    )

    commits_file = cli.send(:resolve_commits, {
      commits: [
        { type: :sha, value: "sha_first" },
        { type: :file, value: file_path },
        { type: :sha, value: "sha_last" }
      ]
    })

    raise "Wrong number of commits from file" unless commits_file.length == 5
    raise "First commit mismatch" unless commits_file[0].sha == "sha_first"
    raise "File commit 1 mismatch" unless commits_file[1].sha == "3333333333333333333333333333333333333333"
    raise "File commit 2 (CVE) mismatch" unless commits_file[2].sha == "1111111111111111111111111111111111111111"
    raise "File commit 3 mismatch" unless commits_file[3].sha == "4444444444444444444444444444444444444444"
    raise "Last commit mismatch" unless commits_file[4].sha == "sha_last"

    # 3. Test BugNotFoundError
    begin
      cli.send(:resolve_commits, { commits: [{ type: :bug, value: "999999" }] })
      raise "BugNotFoundError not raised"
    rescue KernelWork::BugNotFoundError
      # Expected
    end

    # 4. Test FixShaNotFoundError
    begin
      cli.send(:resolve_commits, { commits: [{ type: :bug, value: "88888" }] })
      raise "FixShaNotFoundError not raised"
    rescue KernelWork::FixShaNotFoundError
      # Expected
    end

    # 5. Test FileNotFoundError
    begin
      cli.send(:resolve_commits, { file: File.join(tracker_dir, "nonexistent.txt") })
      raise "FileNotFoundError not raised"
    rescue KernelWork::FileNotFoundError
      # Expected
    end

    # 6. Test MissingArgumentError
    begin
      cli.scp({ commits: [] })
      raise "MissingArgumentError not raised for scp"
    rescue KernelWork::MissingArgumentError
      # Expected
    end
    begin
      cli.extract_patch({ commits: [] })
      raise "MissingArgumentError not raised for extract_patch"
    rescue KernelWork::MissingArgumentError
      # Expected
    end
  end
end

puts "Test Case 7 (CLI::Kernel option ordering and commit resolution) Passed"

puts "All CLI unit tests passed successfully!"
