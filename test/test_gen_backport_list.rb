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

    def initialize(sha, opts = {})
      super(sha, opts)
    end

    def runGit(cmd, opts = {}, raise_error = true)
      if cmd.start_with?("log -n1 --format=%B")
        return @commit_message || ""
      end
      ""
    end
  end

  class TestSeriesCommit < Commit
    attr_accessor :git_mocks, :git_calls, :debug_logs

    def initialize(sha, opts = {})
      super(sha, opts)
      @git_mocks = {}
      @git_calls = []
      @debug_logs = []
    end

    def lore_links
      ["https://patch.msgid.link/20260713-restrack-uaf-fix-resub-v2-1-bbe8bb270d51@nvidia.com"]
    end

    def log(level, msg)
      @debug_logs << msg if level == :DEBUG
      super(level, msg) rescue nil
    end

    def runGit(cmd, opts = {}, fatal = true)
      @git_calls << cmd
      @git_mocks.each do |pattern, response|
        return response if cmd.include?(pattern)
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

# Test Case 10: Commit#lore_links tag parsing
test_commit_link = KernelWork::TestCommit.new("link-sha")
test_commit_link.commit_message = <<~MSG
  Subject line

  Some description
  Link: https://patch.msgid.link/20260713-restrack-uaf-fix-resub-v2-1-bbe8bb270d51@nvidia.com
  Link: https://lore.kernel.org/r/abc-123@example.com
  Link: https://github.com/torvalds/linux/commit/1234
MSG

links = test_commit_link.lore_links()
expected_links = [
  "https://patch.msgid.link/20260713-restrack-uaf-fix-resub-v2-1-bbe8bb270d51@nvidia.com",
  "https://lore.kernel.org/r/abc-123@example.com"
]
if links == expected_links
  puts "Test Case 10 Passed"
else
  puts "Test Case 10 FAILED!"
  puts "  Expected: #{expected_links}"
  puts "  Got:      #{links}"
  failures += 1
end

# Test Case 11: Commit.parse_series_html from local fixture file
fixture_path = File.join(File.dirname(__FILE__), "fixtures", "patch_series.html")
if File.exist?(fixture_path)
  html_content = File.read(fixture_path)
  series_entries = KernelWork::Commit.parse_series_html(html_content)
  expected_series = [
    "RDMA/core: Add rdma_restrack_begin/abort/commit_del() operations",
    "RDMA/core: Fix use after free in ib_query_qp()",
    "RDMA/core: Fix potential use after free in ib_destroy_cq_user()",
    "RDMA/core: Fix potential use after free in ib_destroy_srq_user()",
    "RDMA/core: Fix potential use after free in counter_release()",
    "RDMA/core: Fix potential use after free in ib_free_cq()",
    "RDMA/core: Fix potential use after free in uverbs_free_dmah()",
    "RDMA/core: Fix potential use after free in ib_dealloc_pd_user()"
  ]
  if series_entries.is_a?(Array) &&
     series_entries.length == 8 &&
     series_entries.map { |e| e[:subject] } == expected_series &&
     series_entries.map { |e| e[:idx] } == (1..8).to_a &&
     series_entries[0][:msgid] == "20260713-restrack-uaf-fix-resub-v2-1-bbe8bb270d51@nvidia.com" &&
     series_entries[1][:msgid] == "20260713-restrack-uaf-fix-resub-v2-2-bbe8bb270d51@nvidia.com"
    puts "Test Case 11 Passed"
  else
    puts "Test Case 11 FAILED!"
    puts "  Expected subjects: #{expected_series}"
    puts "  Got:               #{series_entries}"
    failures += 1
  end
end

# Test Case 12: Commit#initialize with options hash
c_default = KernelWork::Commit.new("0123456789ab")
if c_default.sha == "0123456789ab" &&
   c_default.path == KernelWork.config.linux_git &&
   c_default.instance_variable_get(:@subject).nil? &&
   c_default.instance_variable_get(:@patch_id).nil? &&
   c_default.extra_desc.nil? &&
   c_default.data.nil? &&
   c_default.series.nil?
  puts "Test Case 12A Passed"
else
  puts "Test Case 12A FAILED!"
  failures += 1
end

dummy_series = [c_default]
c_custom = KernelWork::Commit.new("abcdef012345",
  :subject => "Test subject line",
  :patch_id => "patch-id-789",
  :path => "/custom/repo/path",
  :extra_desc => "extra notes",
  :data => { :ticket => 1234 },
  :series => dummy_series
)
if c_custom.sha == "abcdef012345" &&
   c_custom.path == "/custom/repo/path" &&
   c_custom.subject == "Test subject line" &&
   c_custom.patch_id == "patch-id-789" &&
   c_custom.extra_desc == "extra notes" &&
   c_custom.data == { :ticket => 1234 } &&
   c_custom.series == dummy_series &&
   c_custom.desc == 'abcdef012345 ("Test subject line") extra notes'
  puts "Test Case 12B Passed"
else
  puts "Test Case 12B FAILED!"
  failures += 1
end

# Test Case 12C: Commit#eql? and Commit#hash deduplication in Array#uniq
c_dup1 = KernelWork::Commit.new("02c5f9dc2efd823e061954d564ce00bacd1bebeb", :subject => "Subject A")
c_dup2 = KernelWork::Commit.new("02c5f9dc2efd823e061954d564ce00bacd1bebeb", :subject => "Subject B")
c_other = KernelWork::Commit.new("6d0c8b70739162985175cf3980c5ce60cbb919a3", :subject => "Subject C")
if c_dup1.eql?(c_dup2) &&
   c_dup1.hash == c_dup2.hash &&
   [c_dup1, c_dup2, c_other].uniq == [c_dup1, c_other]
  puts "Test Case 12C Passed"
else
  puts "Test Case 12C FAILED!"
  failures += 1
end

# Test Case 13: Commit#patch_series resolution, debug logging, omission of unmerged, and cross-attachment caching
if File.exist?(fixture_path)
  html_fixture = File.read(fixture_path)
  # Hook Open3.capture3 to supply fixture HTML
  module Open3
    class << self
      alias_method :orig_capture3_t13, :capture3
      attr_accessor :t13_html
      def capture3(*cmd)
        if cmd.first == "curl"
          status = Struct.new(:success?).new(true)
          return [@t13_html, "", status]
        end
        orig_capture3_t13(*cmd)
      end
    end
  end
  Open3.t13_html = html_fixture

  test_c1 = KernelWork::TestSeriesCommit.new("8d186210677c0322db886973bcec9aa4d21b51cd",
    :subject => "RDMA/core: Add rdma_restrack_begin/abort/commit_del() operations",
    :path => "/mock/linux"
  )

  # Mock responses for resolving sibling patches:
  # Patch 2: Found by MsgID
  test_c1.git_mocks["20260713-restrack-uaf-fix-resub-v2-2-bbe8bb270d51@nvidia.com"] = "709ba0e5311bd034eb4d9c1c00cc4e1109d6dc3e\n"
  # Patch 3: MsgID fails, found by exact subject
  test_c1.git_mocks["RDMA/core: Fix potential use after free in ib_destroy_cq_user()"] = "3481bec4dfc4aee24ffea5a547ee95b70b67d9d5\n"
  # Patch 4: MsgID & Subject fail, found in neighborhood scan
  test_c1.git_mocks["--format=\"%H %s\" -n 50"] = "88244ecc71cc0b3ed200f5ef7ddea6686adfd730 rdma/core: fix potential use after free in ib_destroy_srq_user()\n"
  # Patches 5, 6, 7, 8 will fail to resolve (unmerged/unfound)

  resolved_series = test_c1.patch_series()

  # Restore Open3.capture3
  Open3.singleton_class.send(:alias_method, :capture3, :orig_capture3_t13)

  t13_ok = true
  # 1. resolved_series must have 4 commits (patch 1 self, patch 2 msgid, patch 3 subject, patch 4 neighborhood)
  #    patches 5-8 must be omitted
  t13_ok &&= (resolved_series.length == 4)
  t13_ok &&= resolved_series.all? { |c| c.is_a?(KernelWork::Commit) }
  t13_ok &&= (resolved_series[0] == test_c1)
  t13_ok &&= (resolved_series[1].sha == "709ba0e5311bd034eb4d9c1c00cc4e1109d6dc3e")
  t13_ok &&= (resolved_series[2].sha == "3481bec4dfc4aee24ffea5a547ee95b70b67d9d5")
  t13_ok &&= (resolved_series[3].sha == "88244ecc71cc0b3ed200f5ef7ddea6686adfd730")

  # 2. Path should be forwarded
  t13_ok &&= resolved_series.all? { |c| c.path == "/mock/linux" }

  # 3. Debug logs emitted for unmerged patches (5, 6, 7, 8)
  t13_ok &&= (test_c1.debug_logs.length == 4)
  t13_ok &&= test_c1.debug_logs.any? { |m| m.include?("5/8") }

  # 4. Cross-attachment caching: all member commits should have @series populated
  t13_ok &&= (test_c1.series.object_id == resolved_series.object_id)
  t13_ok &&= (resolved_series[1].series.object_id == resolved_series.object_id)
  t13_ok &&= (resolved_series[2].series.object_id == resolved_series.object_id)

  # 5. Subsequent call to patch_series uses cache without re-running Git
  call_count_before = test_c1.git_calls.length
  cached_result = test_c1.patch_series()
  t13_ok &&= (test_c1.git_calls.length == call_count_before)
  t13_ok &&= (cached_result.object_id == resolved_series.object_id)

  if t13_ok
    puts "Test Case 13 Passed"
  else
    puts "Test Case 13 FAILED!"
    puts "  Resolved count: #{resolved_series.length} (expected 4)"
    puts "  Resolved SHAs:  #{resolved_series.map(&:sha)}"
    puts "  Debug logs:     #{test_c1.debug_logs}"
    failures += 1
  end
end

# Test Case 14: SCPQueueSeries raised on 'a' and processed by _scp
module KernelWork
  class ScpTestCommit < Commit
    def fixes_shas; []; end
    def desc; "#{@sha[0..11]} (\"#{@subject}\")"; end
  end

  class ScpQueueTestUpstream < TestUpstream
    attr_accessor :processed_commits, :confirm_responses, :allowed_reps_seen

    def initialize
      super
      @processed_commits = []
      @confirm_responses = []
      @allowed_reps_seen = []
      @suse = Object.new
      def @suse.is_applied?(c); false; end
      def @suse.extract_single_patch(opts, c); true; end
    end

    def confirm(opts, msg, ignore_default, allowed_reps)
      @allowed_reps_seen << allowed_reps
      @confirm_responses.shift || "y"
    end

    def _cherry_pick_one(opts, commit)
      @processed_commits << commit
    end

    def _tune_last_patch(opts)
      # no-op
    end

    def log(level, msg)
      # suppress test noise
    end

    public :_scp_one
  end
end

c1 = KernelWork::ScpTestCommit.new("1111111111111111111111111111111111111111", :subject => "Patch 1")
c2 = KernelWork::ScpTestCommit.new("2222222222222222222222222222222222222222", :subject => "Patch 2")
c3 = KernelWork::ScpTestCommit.new("3333333333333333333333333333333333333333", :subject => "Patch 3")
series = [c1, c2, c3]
c1.series = series
c2.series = series
c3.series = series

c_extra = KernelWork::ScpTestCommit.new("4444444444444444444444444444444444444444", :subject => "Extra patch")
c_extra.series = []

upstream = KernelWork::ScpQueueTestUpstream.new

# 1. Test _scp_one directly when user selects 'a'
upstream.confirm_responses = ["a"]
raised = false
t14_ok_exception = false
begin
  upstream._scp_one({}, c2)
rescue KernelWork::SCPQueueSeries => e
  raised = true
  t14_ok_exception = (e.series == series)
end

# 2. Test _scp queue restructuring on 'a'
upstream.confirm_responses = ["a", "y", "y", "y", "y"]
queue = [c2, c_extra]
upstream._scp({}, queue)

t14_ok = raised &&
         t14_ok_exception &&
         upstream.allowed_reps_seen.first.include?("a") &&
         upstream.processed_commits.map(&:sha) == [c1.sha, c2.sha, c3.sha, c_extra.sha] &&
         queue.empty?

if t14_ok
  puts "Test Case 14 Passed"
else
  puts "Test Case 14 FAILED!"
  puts "  Raised SCPQueueSeries: #{raised}"
  puts "  Processed commits: #{upstream.processed_commits.map(&:sha)}"
  puts "  Expected commits:  #{[c1.sha, c2.sha, c3.sha, c_extra.sha]}"
  failures += 1
end

if failures == 0
  puts "All tests passed successfully!"
  exit 0
else
  puts "#{failures} test(s) failed."
  exit 1
end
