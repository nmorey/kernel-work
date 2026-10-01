require_relative 'test_helper'

puts "Running KernelSource and Patch unit tests with real git repositories..."

# Test Case 1: Patch extraction and series update
TestHelper.with_test_repos do |env|
  linux = env[:linux]
  ks = env[:kernel_source]
  linux_dir = env[:linux_dir]

  # Create a real commit in linux
  File.write(File.join(linux_dir, "driver.c"), "int foo = 1;\n")
  TestHelper.run_git(linux_dir, "add driver.c")
  TestHelper.run_git(linux_dir, "commit -m 'net: add foo support\n\nFixes: 1234567890ab (\"old bug\")'")
  sha = TestHelper.run_git(linux_dir, "rev-parse HEAD").strip

  # Tag commit in linux tree
  TestHelper.run_git(linux_dir, "tag v6.4-rc1")

  commit = KernelWork::Commit.new(sha, path: linux_dir)
  raise "Expected commit not to be applied yet" if ks.is_applied?(commit)

  # Extract patch
  ks.extract_single_patch(commit, ref: "bsc#123456", yn_default: :yes)

  raise "Expected commit to be applied now" unless ks.is_applied?(commit)

  # Verify series.conf contains patch
  series_content = File.read(File.join(env[:ks_dir], "series.conf"))
  patch_file = ks.last_patch
  raise "Patch not found in series.conf" unless series_content.include?(patch_file)

  # Verify patch file content has Git-commit and Patch-mainline
  patch_content = File.read(File.join(env[:ks_dir], patch_file))
  raise "Missing Git-commit header" unless patch_content.include?("Git-commit: #{sha}")
  raise "Missing Patch-mainline header" unless patch_content.include?("Patch-mainline: v6.4-rc1")
  raise "Missing Reference header" unless patch_content.include?("References: bsc#123456")

  puts "Test Case 1 (Extract Single Patch & Verify Headers) Passed"
end

# Test Case 2: Patch conflict and series_insert
TestHelper.with_test_repos do |env|
  ks = env[:kernel_source]
  ks_dir = env[:ks_dir]

  # Create a series.conf with existing patches
  File.write(File.join(ks_dir, "series.conf"), "patch1.patch\npatch2.patch\n")
  TestHelper.run_git(ks_dir, "commit -am 'Add initial patches'")

  # Insert a patch
  ks.series_insert("patch3.patch", yn_default: :yes)

  content = File.read(File.join(ks_dir, "series.conf"))
  raise "patch3.patch not inserted at top of active series" unless content.include?("patch3.patch")

  puts "Test Case 2 (series_insert) Passed"
end

# Test Case 3: Patch model methods
TestHelper.with_test_repos do |env|
  linux = env[:linux]
  ks = env[:kernel_source]
  linux_dir = env[:linux_dir]

  File.write(File.join(linux_dir, "file2.txt"), "hello world\n")
  TestHelper.run_git(linux_dir, "add file2.txt")
  TestHelper.run_git(linux_dir, "commit -m 'test commit for patch object'")
  sha = TestHelper.run_git(linux_dir, "rev-parse HEAD").strip
  commit = KernelWork::Commit.new(sha, path: linux_dir)

  patch = KernelWork::Patch.new(ks, commit, filename: "my-custom-patch.patch")
  patch.compute_ref(ref: "FATE#333333")
  raise "Ref not set correctly" unless patch.ref == "FATE#333333"

  patch.generate(yn_default: :yes)
  raise "Custom filename not applied" unless patch.name == "my-custom-patch.patch"

  patch_file = File.join(ks.path, patch.localpath)
  raise "Patch file was not generated" unless File.exist?(patch_file)

  puts "Test Case 3 (Patch Model API) Passed"
end

puts "All KernelSource and Patch tests passed successfully!"
