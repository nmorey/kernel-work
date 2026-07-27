require_relative '../lib/kernel-work'

module KernelWork
  class TestUpstream < Upstream
    attr_reader :last_git_command

    def initialize
      # Skip standard initialization since it requires environment vars
      @path = "."
    end

    def runGit(cmd, opts = {}, raise_error = true)
      @last_git_command = cmd
      "" # Return empty string to prevent split error
    end

    def local_branch
      "mock-local-branch"
    end

    def filterInHouse(opts, head, house)
      # No-op for test
    end
  end

  class TestCommit < Commit
    attr_writer :commit_message

    def initialize(sha)
      super(sha)
    end

    def runGit(cmd, opts = {}, raise_error = true)
      if cmd.start_with?("log -n1 --format=%B")
        return @commit_message || ""
      end
      ""
    end
  end
end

test = KernelWork::TestUpstream.new

failures = 0

# Test Case 1: Standard paths only
test.genBackportList("HEAD", "HEAD~1", { :paths => ["drivers/net", "drivers/ib"] })
expected1 = 'log --no-merges --format=oneline HEAD ^HEAD~1 -- drivers/net drivers/ib'
if test.last_git_command == expected1
  puts "Test Case 1 Passed"
else
  puts "Test Case 1 FAILED!"
  puts "  Expected: #{expected1}"
  puts "  Got:      #{test.last_git_command}"
  failures += 1
end

# Test Case 2: Exclude paths only
test.genBackportList("HEAD", "HEAD~1", { :exclude_paths => ["drivers/net/wireless"] })
expected2 = "log --no-merges --format=oneline HEAD ^HEAD~1 -- ':(exclude)drivers/net/wireless'"
if test.last_git_command == expected2
  puts "Test Case 2 Passed"
else
  puts "Test Case 2 FAILED!"
  puts "  Expected: #{expected2}"
  puts "  Got:      #{test.last_git_command}"
  failures += 1
end

# Test Case 3: Both paths and exclude paths
test.genBackportList("HEAD", "HEAD~1", { :paths => ["drivers/net"], :exclude_paths => ["drivers/net/wireless"] })
expected3 = "log --no-merges --format=oneline HEAD ^HEAD~1 -- drivers/net ':(exclude)drivers/net/wireless'"
if test.last_git_command == expected3
  puts "Test Case 3 Passed"
else
  puts "Test Case 3 FAILED!"
  puts "  Expected: #{expected3}"
  puts "  Got:      #{test.last_git_command}"
  failures += 1
end

# Test Case 4: Exclude path already starting with :(exclude)
test.genBackportList("HEAD", "HEAD~1", { :paths => ["drivers/net"], :exclude_paths => [":(exclude)drivers/net/wireless"] })
expected4 = "log --no-merges --format=oneline HEAD ^HEAD~1 -- drivers/net ':(exclude)drivers/net/wireless'"
if test.last_git_command == expected4
  puts "Test Case 4 Passed"
else
  puts "Test Case 4 FAILED!"
  puts "  Expected: #{expected4}"
  puts "  Got:      #{test.last_git_command}"
  failures += 1
end

# Test Case 5: Option Parsing for base_ref with -B
require 'optparse'
parser = OptionParser.new
opts = {}
KernelWork::TestUpstream.set_opts(:backport_todo, parser, opts)
parser.parse!(["-B", "my-custom-base"])
if opts[:base_ref] == "my-custom-base"
  puts "Test Case 5 Passed"
else
  puts "Test Case 5 FAILED!"
  puts "  Expected: my-custom-base"
  puts "  Got:      #{opts[:base_ref]}"
  failures += 1
end

# Test Case 6: Option Parsing for base_ref with --base-ref
parser = OptionParser.new
opts = {}
KernelWork::TestUpstream.set_opts(:backport_todo, parser, opts)
parser.parse!(["--base-ref", "another-custom-base"])
if opts[:base_ref] == "another-custom-base"
  puts "Test Case 6 Passed"
else
  puts "Test Case 6 FAILED!"
  puts "  Expected: another-custom-base"
  puts "  Got:      #{opts[:base_ref]}"
  failures += 1
end

# Test Case 7: backport_todo behavior with custom base_ref
opts = { :upstream_ref => "origin/master", :base_ref => "custom-base-branch", :filter => {} }
test.backport_todo(opts)
expected7 = "log --no-merges --format=oneline mock-local-branch ^origin/master"
if test.last_git_command == expected7
  puts "Test Case 7 Passed"
else
  puts "Test Case 7 FAILED!"
  puts "  Expected: #{expected7}"
  puts "  Got:      #{test.last_git_command}"
  failures += 1
end

# Test Case 8: backport_todo behavior with default base_ref (nil) falling back to local_branch()
opts = { :upstream_ref => "origin/master", :base_ref => nil, :filter => {} }
test.backport_todo(opts)
expected8 = "log --no-merges --format=oneline mock-local-branch ^origin/master"
if test.last_git_command == expected8
  puts "Test Case 8 Passed"
else
  puts "Test Case 8 FAILED!"
  puts "  Expected: #{expected8}"
  puts "  Got:      #{test.last_git_command}"
  failures += 1
end

# Test Case 9: Commit#fixes_shas tag parsing
test_commit = KernelWork::TestCommit.new("some-sha")
test_commit.commit_message = <<~MSG
  This is a commit message
  
  Fixes: 1234567890abcdef1234567890abcdef12345678 ("some description")
  Fixes: fedcba0987654321fedcba0987654321fedcba09 ("another description")
MSG

shas = test_commit.fixes_shas()
expected_shas = ["1234567890abcdef1234567890abcdef12345678", "fedcba0987654321fedcba0987654321fedcba09"]
if shas == expected_shas
  puts "Test Case 9 Passed"
else
  puts "Test Case 9 FAILED!"
  puts "  Expected: #{expected_shas}"
  puts "  Got:      #{shas}"
  failures += 1
end

if failures == 0
  puts "All tests passed successfully!"
  exit 0
else
  puts "#{failures} test(s) failed."
  exit 1
end
