require_relative 'test_helper'

puts "Running Workflow unit tests with real git repositories..."

# Test Case 1: filter_in_house with real git ancestors and series commit_ids
TestHelper.with_test_repos do |env|
  linux = env[:linux]
  ks = env[:kernel_source]
  wf = env[:workflow]
  linux_dir = env[:linux_dir]
  base_sha = env[:base_sha]

  # Base commit is already an ancestor of HEAD
  c_ancestor = KernelWork::Commit.new(base_sha, path: linux_dir)

  # Create a new commit on another branch
  TestHelper.run_git(linux_dir, "checkout -b feature")
  File.write(File.join(linux_dir, "feature.txt"), "feature commit\n")
  TestHelper.run_git(linux_dir, "add feature.txt")
  TestHelper.run_git(linux_dir, "commit -m 'Feature commit'")
  feat_sha = TestHelper.run_git(linux_dir, "rev-parse HEAD").strip
  c_feature = KernelWork::Commit.new(feat_sha, path: linux_dir)

  # Switch back to master
  TestHelper.run_git(linux_dir, "checkout master")

  # Add another commit on feature
  File.write(File.join(linux_dir, "feature2.txt"), "feature 2 commit\n")
  TestHelper.run_git(linux_dir, "checkout feature")
  TestHelper.run_git(linux_dir, "add feature2.txt")
  TestHelper.run_git(linux_dir, "commit -m 'Feature 2 commit'")
  feat2_sha = TestHelper.run_git(linux_dir, "rev-parse HEAD").strip
  c_feature2 = KernelWork::Commit.new(feat2_sha, path: linux_dir)
  TestHelper.run_git(linux_dir, "checkout master")

  # Fake that c_feature is in kernel-source commit_ids
  ks.commit_ids[c_feature.f_sha] = true

  # Commits candidate list
  commits = [c_ancestor, c_feature, c_feature2]

  # filter_in_house should remove:
  # - c_ancestor (because it is an ancestor of HEAD in linux repo)
  # - c_feature (because it is already in ks.commit_ids)
  # and keep c_feature2
  filtered = wf.filter_in_house(commits)

  raise "Expected only c_feature2 to remain, got: #{filtered.map(&:sha)}" unless filtered.map(&:sha) == [c_feature2.sha]

  puts "Test Case 1 (Workflow#filter_in_house real git ancestor & ks check) Passed"
end

# Test Case 2: Workflow#backport_single_commit on real git repo
TestHelper.with_test_repos do |env|
  linux = env[:linux]
  ks = env[:kernel_source]
  wf = env[:workflow]
  linux_dir = env[:linux_dir]

  # Create upstream branch with a commit
  TestHelper.run_git(linux_dir, "checkout -b upstream_branch")
  File.write(File.join(linux_dir, "newfile.txt"), "upstream patch\n")
  TestHelper.run_git(linux_dir, "add newfile.txt")
  TestHelper.run_git(linux_dir, "commit -m 'Upstream feature patch'")
  TestHelper.run_git(linux_dir, "tag v6.4-rc2")
  upstream_sha = TestHelper.run_git(linux_dir, "rev-parse HEAD").strip
  c_upstream = KernelWork::Commit.new(upstream_sha, path: linux_dir)

  # Switch back to master
  TestHelper.run_git(linux_dir, "checkout master")

  # Backport the commit
  wf.backport_single_commit(c_upstream, ref: "bsc#999999", yn_default: :yes)

  # Verify commit was cherry-picked onto master
  master_log = TestHelper.run_git(linux_dir, "log -n1 --format=%s").strip
  raise "Cherry-pick subject mismatch: #{master_log}" unless master_log == "Upstream feature patch"

  # Verify patch was added to kernel-source
  raise "Patch not applied to kernel-source" unless ks.is_applied?(c_upstream)

  puts "Test Case 2 (Workflow#backport_single_commit cherry-pick & extract) Passed"
end

# Test Case 3: Workflow#backport_commits batch operation
TestHelper.with_test_repos do |env|
  linux = env[:linux]
  ks = env[:kernel_source]
  wf = env[:workflow]
  linux_dir = env[:linux_dir]

  # Create branch with 2 commits
  TestHelper.run_git(linux_dir, "checkout -b branch2")
  File.write(File.join(linux_dir, "f1.txt"), "f1\n")
  TestHelper.run_git(linux_dir, "add f1.txt")
  TestHelper.run_git(linux_dir, "commit -m 'Patch 1'")
  TestHelper.run_git(linux_dir, "tag v6.4-rc3")
  sha1 = TestHelper.run_git(linux_dir, "rev-parse HEAD").strip
  c1 = KernelWork::Commit.new(sha1, path: linux_dir)

  File.write(File.join(linux_dir, "f2.txt"), "f2\n")
  TestHelper.run_git(linux_dir, "add f2.txt")
  TestHelper.run_git(linux_dir, "commit -m 'Patch 2'")
  TestHelper.run_git(linux_dir, "tag v6.4-rc4")
  sha2 = TestHelper.run_git(linux_dir, "rev-parse HEAD").strip
  c2 = KernelWork::Commit.new(sha2, path: linux_dir)

  # Switch back to master
  TestHelper.run_git(linux_dir, "checkout master")

  wf.backport_commits([c1, c2], ref: "bsc#888888", yn_default: :yes)

  raise "c1 not applied" unless ks.is_applied?(c1)
  raise "c2 not applied" unless ks.is_applied?(c2)

  puts "Test Case 3 (Workflow#backport_commits batch) Passed"
end

# Test Case 4: Workflow with BuildOpts
TestHelper.with_test_repos do |env|
  linux = env[:linux]
  ks = env[:kernel_source]
  wf = env[:workflow]
  linux_dir = env[:linux_dir]

  # Test backport_commits with BuildOpts object
  TestHelper.run_git(linux_dir, "checkout -b branch_bo")
  File.write(File.join(linux_dir, "f_bo.txt"), "f_bo\n")
  TestHelper.run_git(linux_dir, "add f_bo.txt")
  TestHelper.run_git(linux_dir, "commit -m 'Patch BuildOpts'")
  TestHelper.run_git(linux_dir, "tag v6.4-rc5")
  sha = TestHelper.run_git(linux_dir, "rev-parse HEAD").strip
  c_bo = KernelWork::Commit.new(sha, path: linux_dir)
  TestHelper.run_git(linux_dir, "checkout master")

  bo = KernelWork::CLI::BuildOpts.new(arch: :x86_64, build: false)
  wf.backport_commits([c_bo], build_opts: bo, ref: "bsc#777777", yn_default: :yes)
  raise "c_bo not applied" unless ks.is_applied?(c_bo)

  # Test oldconfig and build with BuildOpts and mock calls
  oldconfig_called = false
  build_called = false

  linux.define_singleton_method(:run_oldconfig) do |build_opts, config_file, force: true|
    oldconfig_called = true
  end

  linux.define_singleton_method(:run_build) do |build_opts, flags = ""|
    build_called = true
  end

  wf.oldconfig(bo)
  raise "oldconfig not called" unless oldconfig_called

  wf.build(bo)
  raise "build not called" unless build_called

  puts "Test Case 4 (Workflow with BuildOpts) Passed"
end

# Test Case 5: Workflow with CveTracker integration
TestHelper.with_test_repos do |env|
  linux = env[:linux]
  ks = env[:kernel_source]
  wf = env[:workflow]
  linux_dir = env[:linux_dir]
  ks.branch = "SLE15-SP7"

  # Create a commit to backport with a CVE reference
  TestHelper.run_git(linux_dir, "checkout -b branch_cve")
  File.write(File.join(linux_dir, "f_cve.txt"), "cve fix\n")
  TestHelper.run_git(linux_dir, "add f_cve.txt")
  TestHelper.run_git(linux_dir, "commit -m 'Patch CVE-2026-1234'")
  TestHelper.run_git(linux_dir, "tag v6.4-rc6")
  sha = TestHelper.run_git(linux_dir, "rev-parse HEAD").strip
  c_cve = KernelWork::Commit.new(sha, path: linux_dir)
  TestHelper.run_git(linux_dir, "checkout master")

  # Mock CVE and Mock Tracker
  cve_updated_branch = nil
  cve_updated_state = nil
  mock_cve = Object.new
  mock_cve.define_singleton_method(:set_status) do |branch, state|
    cve_updated_branch = branch
    cve_updated_state = state
  end

  mock_tracker = Object.new
  mock_tracker.define_singleton_method(:read_cve) do |cve_id|
    if cve_id == "CVE-2026-1234"
      mock_cve
    else
      raise KernelWork::BugNotFoundError.new("Unknown CVE: #{cve_id}")
    end
  end

  # Backport with tracker
  wf.backport_commits([c_cve], tracker: mock_tracker, ref: "bsc#12345 CVE-2026-1234 CVE-2026-9999", yn_default: :yes)

  raise "c_cve not applied to ks" unless ks.is_applied?(c_cve)
  raise "CVE status not updated for branch" unless cve_updated_branch == ks.branch
  raise "CVE state not set to Applied" unless cve_updated_state == KernelWork::CVE::STATE_APPLIED

  # Test SCPAlreadyApplied: run again with tracker
  cve_updated_branch = nil
  cve_updated_state = nil
  wf.backport_commits([c_cve], tracker: mock_tracker, ref: "bsc#12345 CVE-2026-1234", yn_default: :yes)
  raise "CVE status not updated on SCPAlreadyApplied" unless cve_updated_state == KernelWork::CVE::STATE_APPLIED

  puts "Test Case 5 (Workflow with CveTracker integration) Passed"
end

puts "All Workflow unit tests passed successfully!"
