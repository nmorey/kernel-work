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
expected2 = 'log --no-merges --format=oneline HEAD ^HEAD~1 -- :(exclude)drivers/net/wireless'
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
expected3 = 'log --no-merges --format=oneline HEAD ^HEAD~1 -- drivers/net :(exclude)drivers/net/wireless'
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
expected4 = 'log --no-merges --format=oneline HEAD ^HEAD~1 -- drivers/net :(exclude)drivers/net/wireless'
if test.last_git_command == expected4
  puts "Test Case 4 Passed"
else
  puts "Test Case 4 FAILED!"
  puts "  Expected: #{expected4}"
  puts "  Got:      #{test.last_git_command}"
  failures += 1
end

if failures == 0
  puts "All tests passed successfully!"
  exit 0
else
  puts "#{failures} test(s) failed."
  exit 1
end
