require_relative '../lib/kernel-work'
require 'tempfile'
require 'tmpdir'
require 'stringio'

# Temporary override of File.expand_path for ~/.bugzillarc testing and File.exist? for Makefiles
class << File
  alias_method :orig_expand_path, :expand_path
  def expand_path(path, dir = nil)
    if path == "~/.bugzillarc" && $mock_bugzillarc_path
      $mock_bugzillarc_path
    else
      orig_expand_path(path, dir)
    end
  end

  alias_method :orig_exist?, :exist?
  def exist?(path)
    if path =~ %r{/Makefile$} && !path.include?(".c/")
      true
    else
      orig_exist?(path)
    end
  end
end

module KernelWork
  class TestCve < CveCLI::CveAction
    attr_accessor :mocked_git_files
    attr_accessor :bugzilla_mock_proc

    def initialize
      # Skip standard parent initialization which triggers git branch commands
      @path = "."
      config = KernelWork.config.cve.to_h
      @tracker = KernelWork::CveCLI::CveTracker.create(config, self)
      @bugzilla = CveCLI::BugzillaClient.new(config)

      # Delegate bugzilla client request to our local mock proc
      class << @bugzilla
        attr_accessor :test_cve_inst
        def request(path, params = {})
          @test_cve_inst.bugzilla_request(path, params)
        end
      end
      @bugzilla.test_cve_inst = self
    end

    def log(level, msg)
      # Suppress logging in tests
    end

    # Mock bugzilla_request for testing
    def bugzilla_request(path, params = {})
      if @bugzilla_mock_proc
        @bugzilla_mock_proc.call(path, params)
      else
        {}
      end
    end
  end

  class TestUpstream < Upstream
    attr_accessor :mocked_git_output

    def initialize
      @path = "."
    end

    def runGit(cmd, opts = {}, raise_error = true)
      if cmd.start_with?("diff-tree")
        @mocked_git_output
      else
        ""
      end
    end
  end
end

failures = 0

# --- Test Case 1: Bugzillarc INI parsing ---
Tempfile.create('bugzillarc') do |temp|
  temp.write(<<~INI)
    [apibugzilla.suse.com]
    api_key = MY_SECRET_API_KEY_12345
    other_option = some_value
    
    [another.suse.com]
    api_key = OTHER_KEY
  INI
  temp.flush
  $mock_bugzillarc_path = temp.path

  parsed = KernelWork::CveCLI::BugzillaClient.read_bugzillarc
  expected_section = "apibugzilla.suse.com"
  
  if parsed[expected_section] && parsed[expected_section]["api_key"] == "MY_SECRET_API_KEY_12345"
    puts "Test Case 1 (Bugzillarc Parser) Passed"
  else
    puts "Test Case 1 (Bugzillarc Parser) FAILED!"
    puts "  Expected api_key: 'MY_SECRET_API_KEY_12345'"
    puts "  Got: #{parsed[expected_section].inspect}"
    failures += 1
  end
end

# Reset mock path
$mock_bugzillarc_path = nil


# --- Test Case 2: parse_cve_comment comment parsing ---
sample_comments = [
  {
    "text" => "Some random pre-comment text, maybe a greeting."
  },
  {
    "text" => <<~COMMENT
      Security fix for CVE-2026-74712 bsc#1276577 with CVSS 0.0
      = 727e1f569855 ("vdpa/mlx5: Fix buffer length in create_direct_keys()") merged v7.2-rc7~34^2~4
      Fixes: 0071b138d44af ("vdpa/mlx5: Create direct MKEYs in parallel") merged v6.12-rc1~46^2~9
      Link: https://git.kernel.org/linus/727e1f569855df83579edbd73dcb4a0723543a12
      SL-16.0: MANUAL: backport 727e1f569855df83579edbd73dcb4a0723543a12 (Fixes: v6.12)
      SLE15-SP7: MANUAL: backport 727e1f569855df83579edbd73dcb4a0723543a12 (Fixes: 0071b138d44a)
      ACTION NEEDED!
      
      Potential git-fixes for 727e1f569855df83579edbd73dcb4a0723543a12 
      Nothing found
    COMMENT
  }
]

test_cve = KernelWork::TestCve.new
# Call private helper parse_cve_comment
parsed_info = test_cve.send(:parse_cve_comment, sample_comments)

if parsed_info &&
   parsed_info[:cve] == "CVE-2026-74712" &&
   parsed_info[:bug_id] == "1276577" &&
   parsed_info[:mainstream_sha] == "727e1f569855df83579edbd73dcb4a0723543a12" &&
   parsed_info[:distros].length == 2 &&
   parsed_info[:distros][0][:branch] == "SL-16.0" &&
   parsed_info[:distros][1][:branch] == "SLE15-SP7" &&
   parsed_info[:distros][0][:sha] == "727e1f569855df83579edbd73dcb4a0723543a12"

  puts "Test Case 2 (Comment Parser) Passed"
else
  puts "Test Case 2 (Comment Parser) FAILED!"
  puts "  Got parsed info: #{parsed_info.inspect}"
  failures += 1
end


# --- Test Case 3: find_build_subset smart build subtree ---
upstream_mock = KernelWork::TestUpstream.new
test_cve.instance_variable_set(:@upstream, upstream_mock)

# Scenario A: Files inside drivers/vdpa/mlx5
upstream_mock.mocked_git_output = <<~FILES
  drivers/vdpa/mlx5/main.c
  drivers/vdpa/mlx5/net.c
FILES

subset_a = test_cve.send(:find_build_subset, "mock_sha")
if subset_a == "drivers/vdpa/mlx5"
  puts "Test Case 3A (Smart Build subset drivers/vdpa/mlx5) Passed"
else
  puts "Test Case 3A FAILED!"
  puts "  Expected: 'drivers/vdpa/mlx5'"
  puts "  Got: #{subset_a.inspect}"
  failures += 1
end

# Scenario B: Files inside drivers/net/ethernet/intel/ice
upstream_mock.mocked_git_output = <<~FILES
  drivers/net/ethernet/intel/ice/ice_main.c
  drivers/net/ethernet/intel/ice/ice_txrx.c
FILES

subset_b = test_cve.send(:find_build_subset, "mock_sha")
if subset_b == "drivers/net/ethernet/intel/ice"
  puts "Test Case 3B (Smart Build subset drivers/net/ethernet/intel/ice) Passed"
else
  puts "Test Case 3B FAILED!"
  puts "  Expected: 'drivers/net/ethernet/intel/ice'"
  puts "  Got: #{subset_b.inspect}"
  failures += 1
end

# Scenario C: Diverse files falling back to nil (full build)
upstream_mock.mocked_git_output = <<~FILES
  drivers/vdpa/mlx5/main.c
  kernel/sched/core.c
FILES

subset_c = test_cve.send(:find_build_subset, "mock_sha")
if subset_c.nil?
  puts "Test Case 3C (Smart Build subset fallback) Passed"
else
  puts "Test Case 3C FAILED!"
  puts "  Expected: nil"
  puts "  Got: #{subset_c.inspect}"
  failures += 1
end


# --- Test Case 5: CveLocalTracker operations ---
Dir.mktmpdir('cve-data') do |dir_path|
  config = {
    data_repo: dir_path,
    tracker_type: "local"
  }
  
  tracker = KernelWork::CveCLI::CveTracker.create(config)
  
  if tracker.is_a?(KernelWork::CveCLI::CveLocalTracker)
    puts "Test Case 5A (Tracker Factory) Passed"
  else
    puts "Test Case 5A (Tracker Factory) FAILED!"
    failures += 1
  end
  
  # Test writing bug
  bug_data = {
    bug_id: "12345",
    cve: "CVE-2026-99999",
    summary: "Test bug",
    branches: {
      "SLE15-SP7": "ToDo"
    }
  }
  
  tracker.write_bug("12345", bug_data)
  
  # Test reading bug
  read_data = tracker.read_bug("12345")
  if read_data && read_data[:cve] == "CVE-2026-99999" && read_data[:branches][:"SLE15-SP7"] == "ToDo"
    puts "Test Case 5B (Local Tracker Read/Write) Passed"
  else
    puts "Test Case 5B (Local Tracker Read/Write) FAILED!"
    puts "  Got: #{read_data.inspect}"
    failures += 1
  end
  
  # Test read_all
  all_cves = tracker.read_all
  if all_cves.length == 1 && all_cves[0][:bug_id] == "12345"
    puts "Test Case 5C (Local Tracker read_all) Passed"
  else
    puts "Test Case 5C (Local Tracker read_all) FAILED!"
    failures += 1
  end
  
  # Test delete_all
  tracker.delete_all
  if tracker.read_all.empty?
    puts "Test Case 5D (Local Tracker delete_all) Passed"
  else
    puts "Test Case 5D (Local Tracker delete_all) FAILED!"
    failures += 1
  end
end


# --- Test Case 6: Safe Merge fetch simulation ---
Dir.mktmpdir('cve-data-merge') do |dir_path|
  # Save original config
  orig_config = KernelWork.config.settings[:cve]
  
  KernelWork.config.settings[:cve] = {
    bugzilla_url: "https://apibugzilla.suse.com",
    bugzilla_user: "tester@suse.com",
    data_repo: dir_path,
    tracker_type: "local"
  }
  
  test_cve = KernelWork::TestCve.new
  
  # Set up bugzilla mock block
  test_cve.bugzilla_mock_proc = Proc.new do |path, params|
    if path == "bug"
      { "bugs" => [ { "id" => 12345, "status" => "CONFIRMED", "summary" => "CVE-2026-99999: kernel: fix bug" } ] }
    elsif path == "bug/12345/comment"
      {
        "bugs" => {
          "12345" => {
            "comments" => [
              { "text" => "Security fix for CVE-2026-99999 bsc#12345\nSLE15-SP7: AUTO: backport 727e1f569855\n" }
            ]
          }
        }
      }
    end
  end
  
  # 1. First fetch - should create the file with status 'ToDo'
  test_cve.fetch({})
  
  tracker = KernelWork::CveCLI::CveTracker.create(KernelWork.config.cve.to_h)
  read_data = tracker.read_bug("12345")
  
  if read_data && read_data[:branches] && read_data[:branches][:"SLE15-SP7"] == "ToDo"
    puts "Test Case 6A (First Fetch - Create) Passed"
  else
    puts "Test Case 6A (First Fetch - Create) FAILED!"
    puts "  Got: #{read_data.inspect}"
    failures += 1
  end
  
  # 2. Modify status locally to 'Applied'
  if read_data
    read_data[:branches][:"SLE15-SP7"] = "Applied"
    tracker.write_bug("12345", read_data)
  end
  
  # 3. Second fetch - should safe merge and preserve 'Applied'
  test_cve.fetch({})
  
  read_data_after = tracker.read_bug("12345")
  if read_data_after && read_data_after[:branches] && read_data_after[:branches][:"SLE15-SP7"] == "Applied"
    puts "Test Case 6B (Second Fetch - Safe Merge) Passed"
  else
    puts "Test Case 6B (Second Fetch - Safe Merge) FAILED!"
    puts "  Got: #{read_data_after.inspect}"
    failures += 1
  end
  
  # Restore config
  KernelWork.config.settings[:cve] = orig_config
end


# --- Test Case 7: Status command filtering and display ---
Dir.mktmpdir('cve-data-status') do |dir_path|
  # Save original config
  orig_config = KernelWork.config.settings[:cve]
  
  KernelWork.config.settings[:cve] = {
    bugzilla_url: "https://apibugzilla.suse.com",
    bugzilla_user: "tester@suse.com",
    data_repo: dir_path,
    tracker_type: "local"
  }
  
  tracker = KernelWork::CveCLI::CveTracker.create(KernelWork.config.cve.to_h)
  
  # 1. Write a matching bug (active status 'ToDo')
  tracker.write_bug("12345", {
    bug_id: "12345",
    cve: "CVE-2026-00001",
    summary: "First bug description",
    branches: {
      "SLE15-SP7": "ToDo"
    }
  })
  
  # 2. Write a bug with reassigned status (should be filtered out)
  tracker.write_bug("12346", {
    bug_id: "12346",
    cve: "CVE-2026-00002",
    summary: "Second bug description",
    branches: {
      "SLE15-SP7": "Reassigned"
    }
  })
  
  # 3. Write a bug with empty status (should be filtered out)
  tracker.write_bug("12347", {
    bug_id: "12347",
    cve: "CVE-2026-00003",
    summary: "Third bug description",
    branches: {
      "SLE15-SP7": ""
    }
  })

  # 4. Write a bug with another active status ('Applied')
  tracker.write_bug("12348", {
    bug_id: "12348",
    cve: "CVE-2026-00004",
    summary: "Fourth bug description",
    branches: {
      "SLE15-SP6-LTSS": "Applied"
    }
  })
  
  test_cve = KernelWork::TestCve.new
  
  # Capture puts output
  captured_output = []
  original_stdout = $stdout
  begin
    # Redirect stdout to capture puts statements
    $stdout = StringIO.new
    test_cve.status({})
    captured_output = $stdout.string.split("\n")
  ensure
    $stdout = original_stdout
  end
  
  # Validate that only CVE-2026-00001 and CVE-2026-00004 are outputted
  has_cve1 = captured_output.any? { |line| line.include?("CVE-2026-00001") }
  has_cve2 = captured_output.any? { |line| line.include?("CVE-2026-00002") }
  has_cve3 = captured_output.any? { |line| line.include?("CVE-2026-00003") }
  has_cve4 = captured_output.any? { |line| line.include?("CVE-2026-00004") }
  
  if has_cve1 && !has_cve2 && !has_cve3 && has_cve4
    puts "Test Case 7 (Status Filter & Output) Passed"
  else
    puts "Test Case 7 (Status Filter & Output) FAILED!"
    puts "  Captured output lines: #{captured_output.inspect}"
    failures += 1
  end
  
  # Restore config
  KernelWork.config.settings[:cve] = orig_config
end


# --- Test Case 8: CveRestTracker operations with Mocked HTTP ---
begin
  # 1. Create a CveRestTracker instance
  config_rest = {
    tracker_type: "rest",
    tracker_url: "http://localhost:4567/"
  }
  rest_tracker = KernelWork::CveCLI::CveTracker.create(config_rest)

  # 2. Mock Net::HTTP and Net::HTTP#request to simulate a REST API
  class << Net::HTTP
    alias_method :orig_get_response, :get_response
    attr_accessor :mock_responses

    def get_response(uri)
      if @mock_responses && @mock_responses[:get] && @mock_responses[:get][uri.to_s]
        @mock_responses[:get][uri.to_s]
      else
        orig_get_response(uri)
      end
    end
  end

  class MockHttpResponse
    attr_reader :code, :body, :message

    def initialize(code, body, message = "OK")
      @code = code.to_s
      @body = body
      @message = message
    end

    def is_a?(klass)
      if klass == Net::HTTPSuccess
        @code.start_with?("2")
      else
        super
      end
    end
  end

  # Setup our mocks for GET
  Net::HTTP.mock_responses = {
    get: {
      "http://localhost:4567/cves" => MockHttpResponse.new(200, '[{"bug_id":"12345","cve":"CVE-2026-99999"}]'),
      "http://localhost:4567/cves/12345" => MockHttpResponse.new(200, '{"bug_id":"12345","cve":"CVE-2026-99999"}'),
      "http://localhost:4567/cves/99999" => MockHttpResponse.new(404, '{"error":"not found"}', "Not Found")
    }
  }

  # Setup mock for instance-level request method (PUT and DELETE)
  class MockHttpInstance
    attr_accessor :use_ssl
    attr_reader :last_request

    def initialize(host, port)
      @host = host
      @port = port
    end

    def request(req)
      @last_request = req
      case req.method
      when "PUT"
        if req.path == "/cves/12345"
          MockHttpResponse.new(200, '{"success":true}')
        else
          MockHttpResponse.new(500, '{"error":"failed"}')
        end
      when "DELETE"
        if req.path == "/cves"
          MockHttpResponse.new(200, '{"success":true}')
        elsif req.path == "/cves/12345"
          MockHttpResponse.new(200, '{"success":true}')
        else
          MockHttpResponse.new(500, '{"error":"failed"}')
        end
      else
        MockHttpResponse.new(404, '{"error":"not found"}')
      end
    end
  end

  class << Net::HTTP
    alias_method :orig_new, :new
    attr_accessor :mock_instance

    def new(host, port)
      if @mock_instance
        @mock_instance
      else
        orig_new(host, port)
      end
    end
  end

  mock_inst = MockHttpInstance.new("localhost", 4567)
  Net::HTTP.mock_instance = mock_inst

  # 3. Perform CveRestTracker tests
  # Test read_all
  all_cves = rest_tracker.read_all
  test_8a_passed = (all_cves.length == 1 && all_cves[0][:bug_id] == "12345")

  # Test read_bug (exist)
  bug_data = rest_tracker.read_bug("12345")
  test_8b_passed = (bug_data && bug_data[:cve] == "CVE-2026-99999")

  # Test read_bug (404)
  begin
    rest_tracker.read_bug("99999")
    test_8c_passed = false
  rescue KernelWork::CveCLI::BugNotFoundError
    test_8c_passed = true
  end

  # Test write_bug
  rest_tracker.write_bug("12345", { bug_id: "12345", cve: "CVE-2026-99999" })
  test_8d_passed = (mock_inst.last_request && mock_inst.last_request.method == "PUT" && mock_inst.last_request.path == "/cves/12345")

  # Test delete_all
  rest_tracker.delete_all
  test_8e_passed = (mock_inst.last_request && mock_inst.last_request.method == "DELETE" && mock_inst.last_request.path == "/cves")

  # Test delete_bug
  rest_tracker.delete_bug("12345")
  test_8f_passed = (mock_inst.last_request && mock_inst.last_request.method == "DELETE" && mock_inst.last_request.path == "/cves/12345")

  if test_8a_passed && test_8b_passed && test_8c_passed && test_8d_passed && test_8e_passed && test_8f_passed
    puts "Test Case 8 (CveRestTracker client operations with Mocked HTTP) Passed"
  else
    puts "Test Case 8 (CveRestTracker client operations with Mocked HTTP) FAILED!"
    puts "  8a (read_all): #{test_8a_passed ? "Pass" : "FAIL"}"
    puts "  8b (read_bug): #{test_8b_passed ? "Pass" : "FAIL"}"
    puts "  8c (read_missing): #{test_8c_passed ? "Pass" : "FAIL"}"
    puts "  8d (write_bug): #{test_8d_passed ? "Pass" : "FAIL"}"
    puts "  8e (delete_all): #{test_8e_passed ? "Pass" : "FAIL"}"
    puts "  8f (delete_bug): #{test_8f_passed ? "Pass" : "FAIL"}"
    failures += 1
  end

ensure
  # Restore mocked Net::HTTP methods
  class << Net::HTTP
    if method_defined?(:orig_get_response)
      alias_method :get_response, :orig_get_response
      remove_method :orig_get_response
    end
    if method_defined?(:orig_new)
      alias_method :new, :orig_new
      remove_method :orig_new
    end
    remove_method :mock_responses if respond_to?(:mock_responses)
    remove_method :mock_responses= if respond_to?(:mock_responses=)
    remove_method :mock_instance if respond_to?(:mock_instance)
    remove_method :mock_instance= if respond_to?(:mock_instance=)
  end
end


# --- Test Case 9: Drop reassigned/resolved bugs from cache ---
Dir.mktmpdir('cve-data-drop') do |dir_path|
  # Save original config
  orig_config = KernelWork.config.settings[:cve]

  KernelWork.config.settings[:cve] = {
    bugzilla_url: "https://apibugzilla.suse.com",
    bugzilla_user: "tester@suse.com",
    data_repo: dir_path,
    tracker_type: "local"
  }

  tracker = KernelWork::CveCLI::CveTracker.create(KernelWork.config.cve.to_h)

  # Write two bugs initially
  tracker.write_bug("12345", {
    bug_id: "12345",
    cve: "CVE-2026-99999",
    summary: "Active bug",
    branches: { "SLE15-SP7": "ToDo" }
  })

  tracker.write_bug("12346", {
    bug_id: "12346",
    cve: "CVE-2026-88888",
    summary: "Reassigned bug",
    branches: { "SLE15-SP7": "ToDo" }
  })

  test_cve = KernelWork::TestCve.new

  # Mock Bugzilla to only return bug 12345 (bug 12346 is reassigned/resolved)
  test_cve.bugzilla_mock_proc = Proc.new do |path, params|
    if path == "bug"
      { "bugs" => [ { "id" => 12345, "status" => "CONFIRMED", "summary" => "CVE-2026-99999: kernel: active bug" } ] }
    elsif path == "bug/12345/comment"
      {
        "bugs" => {
          "12345" => {
            "comments" => [
              { "text" => "Security fix for CVE-2026-99999 bsc#12345\nSLE15-SP7: AUTO: backport 727e1f569855\n" }
            ]
          }
        }
      }
    end
  end

  # Perform fetch - this should trigger the cleanup of 12346
  test_cve.fetch({})

  # Verify bug 12345 still exists
  has_bug1 = false
  begin
    tracker.read_bug("12345")
    has_bug1 = true
  rescue KernelWork::CveCLI::BugNotFoundError
  end

  # Verify bug 12346 was dropped
  has_bug2 = false
  begin
    tracker.read_bug("12346")
    has_bug2 = true
  rescue KernelWork::CveCLI::BugNotFoundError
  end

  if has_bug1 && !has_bug2
    puts "Test Case 9 (Drop Reassigned Bugs from Cache) Passed"
  else
    puts "Test Case 9 (Drop Reassigned Bugs from Cache) FAILED!"
    puts "  has_bug1 (12345, should be true): #{has_bug1}"
    puts "  has_bug2 (12346, should be false): #{has_bug2}"
    failures += 1
  end

  # Restore config
  KernelWork.config.settings[:cve] = orig_config
end


# --- Test Case 10: CVE Class Model Methods ---
begin
  mock_tracker = Object.new
  def mock_tracker.write_bug(bug_id, data)
    # No-op
  end

  cve_obj = KernelWork::CVE.new(
    bug_id: "98765",
    cve: "CVE-2026-12345",
    summary: "Test CVE model behavior",
    fix_sha: "abcd1234efgh",
    distros: [
      { branch: "SLE15-SP7", sha: "abcd1234efgh" }
    ],
    branches: {
      "SLE15-SP7": KernelWork::CVE::STATE_TODO,
      "SLE15-SP6": KernelWork::CVE::STATE_REASSIGNED,
      "SLE15-SP5": ""
    },
    tracker: mock_tracker
  )

  test_10_passed = true

  # Test get_status
  if cve_obj.get_status("SLE15-SP7") != KernelWork::CVE::STATE_TODO
    puts "  10a (get_status) FAILED"
    test_10_passed = false
  end

  # Test set_status
  cve_obj.set_status("SLE15-SP7", KernelWork::CVE::STATE_APPLIED)
  if cve_obj.get_status("SLE15-SP7") != KernelWork::CVE::STATE_APPLIED
    puts "  10b (set_status) FAILED"
    test_10_passed = false
  end

  # Test active_branches
  active_br = cve_obj.active_branches
  if active_br.keys != [:"SLE15-SP7"] || active_br[:"SLE15-SP7"] != KernelWork::CVE::STATE_APPLIED
    puts "  10c (active_branches) FAILED: Got #{active_br.inspect}"
    test_10_passed = false
  end

  # Test all_ok?
  if cve_obj.all_ok?
    puts "  10d (all_ok? negative) FAILED"
    test_10_passed = false
  end

  cve_obj.set_status("SLE15-SP7", KernelWork::CVE::STATE_MERGED)
  if !cve_obj.all_ok?
    puts "  10e (all_ok? positive) FAILED"
    test_10_passed = false
  end

  # Test hash compatibility reader []
  if cve_obj[:bug_id] != "98765" || cve_obj[:cve] != "CVE-2026-12345"
    puts "  10f (hash reader compatibility) FAILED"
    test_10_passed = false
  end

  # Test serialization
  h = cve_obj.to_h
  if h[:bug_id] != "98765" || h[:branches][:"SLE15-SP7"] != KernelWork::CVE::STATE_MERGED
    puts "  10g (serialization to_h) FAILED"
    test_10_passed = false
  end

  if test_10_passed
    puts "Test Case 10 (CVE Model Class Methods) Passed"
  else
    failures += 1
  end
end


# --- Test Output ---
if failures == 0
  puts "All CVE tests passed successfully!"
  exit 0
else
  puts "#{failures} CVE test(s) failed."
  exit 1
end
