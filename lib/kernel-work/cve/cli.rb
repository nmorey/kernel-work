require 'net/http'
require 'uri'
require 'json'
require 'set'
require 'yaml'
require 'fileutils'

module KernelWork
    # Module exposing CVE commands nested under 'cve'
    module CveCLI
        CLI_DESCRIPTION = "Manage CVE fixes and tracking"
        CLI_COMMAND_NAME = "cve"
        CLI_HELP_EXPAND = "*** CVE commands ***"

        class CveCLIError < KernelWork::KernelWorkError; end
        class Action < KernelWork::Common
            def parent_module
                KernelWork::CveCLI
            end
        end

        # CVE Action class providing fetch, apply, and push subcommands nested under cve
        class CveAction < Action
            ACTION_LIST = [
                :fetch,
                :apply,
                :push,
                :status
            ]

            ACTION_HELP = {
                :fetch => "Fetch my CVE bugs from Bugzilla and populate Google Sheet or Local file",
                :apply => "Apply the missing CVE fixes to the current branch",
                :push  => "Push applied commits and set their status to Pushed",
                :status => "Show the status of active CVEs"
            }

            # Set options for CVE actions
            #
            # @param action [Symbol] The action
            # @param optsParser [OptionParser] The option parser
            # @param opts [Hash] The options hash
            def self.set_opts(action, optsParser, opts)
                case action
                when :fetch
                    optsParser.on("-u", "--user <email>", String, "Bugzilla user email (overrides config).") {
                        |val| opts[:bugzilla_user] = val}
                    optsParser.on("-f", "--force", "Force refresh (deletes old file).") {
                        |val| opts[:force] = true}
                when :apply
                    Upstream.set_opts(:cve_apply, optsParser, opts)
                    optsParser.on("-y", "--yes", "Apply fixes automatically without confirmation.") {
                        |val| opts[:yn_default] = :yes}
                    optsParser.on("-a", "--arch <arch>", String, "Arch to build for. Default: x86_64") {
                        |val| opts[:arch] = val.to_sym}
                    optsParser.on("-j<num>", Integer, "Number of parallel builds.") {
                        |val| opts[:j] = val}
                when :push
                    optsParser.on("-f", "--force", "Force push.") {
                        |val| opts[:force_push] = true}
                end
            end

            def self.check_opts(opts)
            end

            # Initialize a CveAction object, linking suse and upstream instances
            def initialize(upstream = nil, suse = nil)
                @path = KernelWork.config.kernel_source_dir
                begin
                    set_branches()
                rescue UnknownBranch
                    @branch = nil
                end

                @suse = suse || Suse.new(upstream)
                @upstream = upstream || @suse.upstream
            end

            # Get current branch
            def branch
                raise KernelWork::UnknownBranch.new(@path) if @branch == nil
                @branch
            end

            # Fetch action
            def fetch(opts)
                config = KernelWork.config.cve.to_h
                tracker = CveTracker.create(config, self)

                bz_user = opts[:bugzilla_user] || config[:bugzilla_user]
                if bz_user.nil? || bz_user.empty?
                    begin
                        bz_user = runGit("config user.email").strip
                    rescue
                        bz_user = nil
                    end
                end

                if bz_user.nil? || bz_user.empty?
                    log(:ERROR, "Bugzilla user email is required. Please set it in config or pass via -u.")
                    return 1
                end

                log(:INFO, "Fetching bugs for #{bz_user} from Bugzilla...")
                params = {
                    product: "SUSE Security Incidents",
                    assigned_to: bz_user
                }

                begin
                    response = bugzilla_request("bug", params)
                rescue => e
                    log(:ERROR, "Failed to connect to Bugzilla: #{e.message}")
                    return 1
                end

                bugs = response["bugs"] || []
                resolved_statuses = ["RESOLVED", "VERIFIED", "CLOSED"]
                filtered_bugs = bugs.select do |bug|
                    status = bug["status"].to_s.upcase
                    !resolved_statuses.include?(status) && bug["summary"] =~ /CVE-\d{4}-\d+:\s+kernel:/i
                end

                # Identify and drop reassigned/resolved bugs from local cache
                fetched_ids = filtered_bugs.map { |bug| bug["id"].to_s }
                begin
                    local_bugs = tracker.read_all
                    local_ids = local_bugs.map { |bug| bug[:bug_id].to_s }
                    orphaned_ids = local_ids - fetched_ids
                    unless orphaned_ids.empty?
                        log(:INFO, "Dropping #{orphaned_ids.length} reassigned/resolved bug(s) from cache: #{orphaned_ids.join(', ')}")
                        orphaned_ids.each { |bug_id| tracker.delete_bug(bug_id) }
                    end
                rescue => e
                    log(:WARNING, "Failed to clean up reassigned/resolved CVEs from cache: #{e.message}")
                end

                if filtered_bugs.empty?
                    log(:INFO, "No CVE bugs found for #{bz_user}.")
                    return 0
                end

                log(:INFO, "Found #{filtered_bugs.length} CVE bugs. Fetching comments...")

                if opts[:force]
                    log(:INFO, "Force option specified. Clearing tracking data...")
                    tracker.delete_all
                end

                updates_count = 0
                filtered_bugs.each do |bug|
                    bug_id = bug["id"].to_s
                    log(:INFO, "Fetching comments for Bug ##{bug_id}...")
                    begin
                        comments_response = bugzilla_request("bug/#{bug_id}/comment")
                        comments = comments_response["bugs"][bug_id]["comments"] || []
                        fix_info = parse_cve_comment(comments)
                        if fix_info
                            # Prepare/merge with existing local data
                            existing_data = tracker.read_bug(bug_id) || {}
                            branches = existing_data[:branches] || {}

                            # Merge in target branches from parsed distros
                            (fix_info[:distros] || []).each do |distro|
                                branch_name = distro[:branch]
                                if branches[branch_name.to_sym].nil? || branches[branch_name.to_sym].empty?
                                    branches[branch_name.to_sym] = "ToDo"
                                end
                            end

                            # Construct consolidated bug data
                            bug_data = {
                                bug_id: bug_id,
                                cve: fix_info[:cve],
                                summary: bug["summary"],
                                fix_sha: fix_info[:mainstream_sha],
                                distros: fix_info[:distros],
                                branches: branches
                            }

                            tracker.write_bug(bug_id, bug_data)
                            updates_count += 1
                            log(:INFO, "Found CVE fix info for #{fix_info[:cve]} (Bug ##{bug_id})")
                        else
                            log(:WARNING, "No matching security fix comment found in Bug ##{bug_id}")
                        end
                    rescue => e
                        log(:ERROR, "Failed to fetch comments for Bug ##{bug_id}: #{e.message}")
                    end
                end

                if updates_count == 0
                    log(:INFO, "No valid CVE fix comments extracted.")
                    return 0
                end

                log(:INFO, "CVE tracking successfully updated! Updated #{updates_count} bugs.")
                return 0
            end

            # Apply action
            def apply(opts)
                config = KernelWork.config.cve.to_h
                current_br = branch()
                if current_br.nil? || current_br.empty?
                    log(:ERROR, "Cannot detect current branch in KERNEL_SOURCE_DIR.")
                    return 1
                end

                log(:INFO, "Current branch is: #{current_br}")

                log(:INFO, "Connecting to CVE tracker...")
                tracker = CveTracker.create(config, self)
                cve_files = tracker.read_all

                if cve_files.empty?
                    log(:INFO, "No CVE tracking data found.")
                    return 0
                end

                todo_bugs = []
                cve_files.each do |cve_data|
                    branches = cve_data[:branches] || {}
                    matched_branch_key = branches.keys.find { |k| k.to_s == current_br}
                    next if matched_branch_key.nil?

                    status = branches[matched_branch_key].to_s.strip
                    if status == "ToDo"
                        todo_bugs << {
                            bug_id: cve_data[:bug_id].to_s,
                            cve: cve_data[:cve],
                            cve_data: cve_data,
                            matched_branch_key: matched_branch_key
                        }
                    end
                end

                if todo_bugs.empty?
                    log(:INFO, "No CVE fixes to apply in 'To do' status for branch '#{current_br}'.")
                    return 0
                end

                log(:INFO, "Found #{todo_bugs.length} CVE fix(es) to apply for branch '#{current_br}'")

                patchlist = []
                scp_opts = opts.dup
                scp_opts[:cve] = true

                todo_bugs.each do |todo|
                    bug_id = todo[:bug_id]
                    cve = todo[:cve]
                    sha = todo[:cve_data][:fix_sha]

                    if sha.nil? || sha.empty?
                        log(:ERROR, "Unable to find Fix SHA for Bug ##{bug_id} on branch #{current_br}. Skipping.")
                        next
                    end
                    c = Commit.new(sha)
                    c.data = todo
                    c.extra_desc = "#{cve} bsc##{bug_id}"
                    patchlist << c
                end

                if patchlist.length == 0
                    log(:INFO, "Nothing to apply")
                    return
                end
                unpushed_commits = @suse.runGit(@suse._list_unpushed_cmd(opts)).
                                       split("\n").map(){ |line| line.split.first }
                unmerged_commits = @suse.runGit(@suse._list_unmerged_cmd(opts)).
                                       split("\n").map(){ |line| line.split.first }
                @upstream._scp(scp_opts, patchlist) do |commit, error = nil|
                    todo = commit.data
                    bug_id = todo[:bug_id]
                    sha = todo[:cve_data][:fix_sha]
                    newState = nil

                    if error == nil
                        @upstream.build_commit(opts, commit)
                        newState = "Applied"
                    elsif error.class == SCPAlreadyApplied
                        # Check if it's applied locally, already pushed or even merged
                        kSha = @suse.get_suse_commit(sha)
                        raise KernelWorkError.new() if kSha == nil

                        if unpushed_commits.index(kSha) != nil
                            # Commit is unpushed, let's go normaly
                            newState = "Applied"
                        elsif unmerged_commits.index(kSha) != nil
                            # Commit is pushed but unmerge. Mark as pushed
                            newState = "Pushed"
                        else
                            # It's neither unpushed not unmerge. It's merged then !
                            newState = "Merged"
                        end
                    end

                    if newState != nil
                        begin
                            todo[:cve_data][:branches][todo[:matched_branch_key]] = newState
                            tracker.write_bug(bug_id, todo[:cve_data])
                            log(:INFO, "Successfully updated status of Bug ##{bug_id} to '#{newState}'.")
                        rescue => e
                            log(:ERROR, "Failed to update tracker: #{e.message}")
                        end
                    end
                end
            end

            # Push action
            def push(opts)
                config = KernelWork.config.cve.to_h
                current_br = branch()
                if current_br.nil? || current_br.empty?
                    log(:ERROR, "Cannot detect current branch in KERNEL_SOURCE_DIR.")
                    return 1
                end

                log(:INFO, "Checking for unpushed commits in KERNEL_SOURCE_DIR...")
                remote_branch_exists = false
                begin
                    @suse.runGit("rev-parse --verify --quiet #{KernelWork.config.suse.remote}/#{@suse.local_branch()}")
                    remote_branch_exists = true
                rescue
                end

                remoteRefs = " \"^#{KernelWork.config.suse.remote}/#{@suse.branch()}\""
                remoteRefs += " \"^#{KernelWork.config.suse.remote}/#{@suse.local_branch()}\"" if remote_branch_exists

                unpushed_logs = @suse.runGit(@suse._list_unmerged_cmd(opts))
                bug_ids_to_push = unpushed_logs.scan(/bsc#(\d+)/).flatten.uniq

                if bug_ids_to_push.empty?
                    log(:INFO, "No bug references (bsc#ID) found in unpushed/unmerged commits.")
                else
                    log(:INFO, "Found unmerged commits referencing Bug ID(s): #{bug_ids_to_push.join(', ')}")
                end

                log(:INFO, "Pushing KERNEL_SOURCE_DIR changes...")
                @suse.push(opts)

                return 0 if bug_ids_to_push.empty?

                log(:INFO, "Updating status from 'Applied' to 'Pushed' in tracker...")
                tracker = CveTracker.create(config, self)

                updates_count = 0
                bug_ids_to_push.each do |bug_id|
                    cve_data = tracker.read_bug(bug_id)
                    if ! cve_data then
                        log(:WARNING, "Bug ##{bug_id} tracking JSON file not found or failed to load.")
                        next
                    end

                    branches = cve_data[:branches] || {}
                    matched_branch_key = branches.keys.find { |k| k.to_s == current_br}
                    next if matched_branch_key.nil?

                    status = branches[matched_branch_key].to_s.strip
                    if status == "Applied"
                        cve_data[:branches][matched_branch_key] = "Pushed"
                        begin
                            tracker.write_bug(bug_id, cve_data)
                            updates_count += 1
                            log(:INFO, "Updated Bug ##{bug_id} status to 'Pushed'...")
                        rescue => e
                            log(:ERROR, "Failed to update Bug ##{bug_id} status to 'Pushed': #{e.message}")
                        end
                    end
                end

                log(:INFO, "Updated #{updates_count} bug(s) status to 'Pushed'.")
                return 0
            end

            # Status action
            def status(opts)
                config = KernelWork.config.cve.to_h
                tracker = CveTracker.create(config, self)
                cve_files = tracker.read_all

                if cve_files.empty?
                    log(:INFO, "No CVE tracking data found.")
                    return 0
                end

                matching_cves = []
                cve_files.each do |cve_data|
                    branches = cve_data[:branches] || {}
                    active_branches = {}

                    branches.each do |br, status_val|
                        status_str = status_val.to_s.strip
                        if !status_str.empty? && status_str.downcase != "reassigned"
                            active_branches[br.to_s] = status_str
                        end
                    end

                    unless active_branches.empty?
                        matching_cves << {
                            bug_id: cve_data[:bug_id],
                            cve: cve_data[:cve],
                            summary: cve_data[:summary],
                            branches: active_branches
                        }
                    end
                end

                if matching_cves.empty?
                    log(:INFO, "No active CVEs found.")
                    return 0
                end

                # Collect union of all active branch keys across matching CVEs
                active_distros = Set.new
                matching_cves.each do |item|
                    active_distros.merge(item[:branches].keys)
                end
                distros_list = active_distros.to_a.sort

                # Determine the maximum width for the first column "CVE (Bug ID)"
                cve_col_header = "CVE BugID"
                max_cve_width = [cve_col_header.length, matching_cves.map { |item| "#{item[:cve]} bsc##{item[:bug_id]}".length }.max || 0].max + 3

                # Determine width for each distro column
                distro_widths = {}
                distros_list.each do |distro|
                    max_status_len = matching_cves.map { |item| (item[:branches][distro] || "").length }.max || 0
                    distro_widths[distro] = [distro.length, max_status_len].max + 3
                end

                # Print header
                print sprintf("%-#{max_cve_width}s", cve_col_header)
                distros_list.each do |distro|
                    print sprintf("%-#{distro_widths[distro]}s", distro)
                end
                puts ""

                # Print separator
                separator_len = max_cve_width + distros_list.map { |d| distro_widths[d] }.sum
                puts "-" * separator_len

                # Print each CVE row
                matching_cves.each do |item|
                    cve_bug_str = "#{item[:cve]} bsc##{item[:bug_id]}"
                    print sprintf("%-#{max_cve_width}s", cve_bug_str)
                    distros_list.each do |distro|
                        status_str = item[:branches][distro] || ""
                        print sprintf("%-#{distro_widths[distro]}s", status_str)
                    end
                    puts ""
                end

                return 0
            end

            # Convert 0-based column index to spreadsheet column letter (A, B, ..., Z, AA, AB, ...)
            def self.col_index_to_letter(index)
                letter = ""
                temp = index
                while temp >= 0
                    letter = ((temp % 26) + 65).chr + letter
                    temp = (temp / 26) - 1
                end
                letter
            end

            # Parse ~/.bugzillarc to find Bugzilla credentials
            def self.read_bugzillarc
                path = File.expand_path("~/.bugzillarc")
                return {} unless File.exist?(path)

                config = {}
                current_section = nil

                File.foreach(path) do |line|
                    line = line.strip
                    next if line.empty? || line.start_with?("#", ";")

                    if line =~ /^\[(.*)\]$/
                        current_section = $1
                        config[current_section] = {}
                    elsif line =~ /^([^=]+)=(.*)$/ && current_section
                        key = $1.strip
                        val = $2.strip
                        val = val[1..-2] if val.start_with?('"') && val.end_with?('"')
                        val = val[1..-2] if val.start_with?("'") && val.end_with?("'")
                        config[current_section][key] = val
                    end
                end
                config
            end

            private

            # Find build subset based on modified files
            # @param sha [String] Commit SHA to identify changes in
            def find_build_subset(sha)
                subsets = @upstream.send(:_find_build_subset, Struct.new(:f_sha).new(sha))
                if subsets.length == 1 && subsets[0] != '.'
                    subsets[0]
                else
                    nil
                end
            end

            # Request wrapper to Bugzilla REST API
            def bugzilla_request(path, params = {})
                bz_config = self.class.read_bugzillarc["apibugzilla.suse.com"] || {}
                api_key = bz_config["api_key"] || KernelWork.config.cve.bugzilla_api_key

                bz_url = KernelWork.config.cve.bugzilla_url || "https://apibugzilla.suse.com"
                url = URI.parse("#{bz_url}/rest/#{path}")

                query_params = params.dup
                query_params[:api_key] = api_key if api_key && !api_key.empty?
                url.query = URI.encode_www_form(query_params) unless query_params.empty?

                http = Net::HTTP.new(url.host, url.port)
                http.use_ssl = true if url.scheme == 'https'

                req = Net::HTTP::Get.new(url.request_uri)
                req['Accept'] = 'application/json'

                res = http.request(req)
                if res.code == "200"
                    JSON.parse(res.body)
                else
                    raise "Bugzilla request failed with code #{res.code}: #{res.body}"
                end
            end

            # Parse CVE Bugzilla Comments
            def parse_cve_comment(comments)
                comments.each do |comment|
                    text = comment["text"] || ""
                    if text =~ /Security fix for (CVE-\d{4}-\d+)\s+bsc#(\d+)/i
                        cve = $1
                        bug_id = $2

                        mainstream_sha = nil
                        if text =~ /Link:\s+\S+\/([0-9a-fA-F]+)/
                            mainstream_sha = $1
                        end

                        distros = []
                        text.each_line do |line|
                            if line.strip =~ /^([A-Za-z0-9\-\.\/_]+):\s+(?:MANUAL|AUTO|\w+):\s+backport\s+([0-9a-fA-F]+)/
                                distros << {
                                    branch: $1,
                                    sha: $2
                                }
                            end
                        end

                        if !distros.empty?
                            return {
                                cve: cve,
                                bug_id: bug_id,
                                mainstream_sha: mainstream_sha,
                                distros: distros
                            }
                        end
                    end
                end
                nil
            end

        end

        ACTION_CLASS = [ CveAction ]
        extend CLIClassTool::Utils
    end
end
