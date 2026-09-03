require 'net/http'
require 'uri'
require 'json'
require 'set'
require 'yaml'
require 'fileutils'

module KernelWork
    # Module exposing CVE commands nested under 'cve'
    module CveCLI
        # Short description of the CVE CLI subcommand.
        CLI_DESCRIPTION = "Manage CVE fixes and tracking"
        # CLI command name registered for autodiscovery.
        CLI_COMMAND_NAME = "cve"
        # Help banner title for CVE commands.
        CLI_HELP_EXPAND = "*** CVE commands ***"

        class CveCLIError < KernelWork::KernelWorkError; end

        # Base action class for CVE CLI commands.
        class Action < KernelWork::Common
            # Retrieve the parent module namespace.
            # @return [Module] The CveCLI module namespace.
            def parent_module
                KernelWork::CveCLI
            end
        end

        # CVE Action class providing fetch, apply, and push subcommands nested under cve
        class CveAction < Action
            # List of supported actions.
            ACTION_LIST = [
                :fetch,
                :apply,
                :push,
                :status, :ls,
                :refresh,
            ]

            # Brief help description for each action.
            ACTION_HELP = {
                :fetch => "Fetch my CVE bugs from Bugzilla and populate Google Sheet or Local file",
                :apply => "Apply the missing CVE fixes to the current branch",
                :push  => "Push applied commits and set their status to Pushed",
                :status => "Show the status of active CVEs",
                :refresh => "Refresh CVE status for the current branch",
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

            # Validate options before running an action.
            # @param opts [Hash] The options hash.
            # @return [void]
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
                config = KernelWork.config.cve.to_h
                @tracker = CveTracker.create(config, self)
                @bugzilla = CveCLI::BugzillaClient.new(config)

            end

            # Get current branch
            def branch
                raise KernelWork::UnknownBranch.new(@path) if @branch == nil
                @branch
            end

            # Fetch action
            def fetch(opts)
                config = KernelWork.config.cve.to_h

                bz_user = opts[:bugzilla_user] || config[:bugzilla_user]
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
                    response = @bugzilla.request("bug", params)
                end

                bugs = response["bugs"] || []
                resolved_statuses = ["RESOLVED", "VERIFIED", "CLOSED"]
                filtered_bugs = bugs.select do |bug|
                    status = bug["status"].to_s.upcase
                    !resolved_statuses.include?(status) && bug["summary"] =~ /CVE-\d{4}-\d+:\s+kernel:/i
                end

                # Identify and drop reassigned/resolved bugs from local cache
                fetched_ids = filtered_bugs.map { |bug| bug["id"].to_s }

                if opts[:force]
                    log(:INFO, "Force option specified. Clearing tracking data...")
                    @tracker.delete_all
                end

                local_bugs = @tracker.read_all
                local_ids = local_bugs.map { |bug| bug[:bug_id].to_s }
                orphaned_ids = local_ids - fetched_ids
                unless orphaned_ids.empty?
                    log(:INFO, "Dropping #{orphaned_ids.length} reassigned/resolved bug(s) from cache: #{orphaned_ids.join(', ')}")
                    orphaned_ids.each { |bug_id| @tracker.delete_bug(bug_id) }
                end

                if filtered_bugs.empty?
                    log(:INFO, "No CVE bugs found for #{bz_user}.")
                    return 0
                end

                log(:INFO, "Found #{filtered_bugs.length} CVE bugs. Fetching comments...")

                updates_count = 0
                filtered_bugs.each do |bug|
                    bug_id = bug["id"].to_s
                    log(:INFO, "Fetching comments for Bug ##{bug_id}...")
                    comments_response = @bugzilla.request("bug/#{bug_id}/comment")
                    comments = comments_response["bugs"][bug_id]["comments"] || []
                    fix_info = parse_cve_comment(comments)

                    if fix_info == nil then
                        log(:WARNING, "No matching security fix comment found in Bug ##{bug_id}")
                        next
                    end

                    # Prepare/merge with existing local data
                    begin
                        existing_data = @tracker.read_bug(bug_id)
                        branches = existing_data ? existing_data.branches : {}
                    rescue BugNotFoundError
                        existing_data = nil
                        branches = {}
                    end

                    # Merge in target branches from parsed distros
                    (fix_info[:distros] || []).each do |distro|
                        branch_name = distro[:branch].to_sym()
                         branches[branch_name] ||= CVE::STATE_TODO
                    end
                    # Construct consolidated bug data
                    bug_data = CVE.new(
                        bug_id: bug_id,
                        cve: fix_info[:cve],
                        summary: bug["summary"],
                        fix_sha: fix_info[:mainstream_sha],
                        distros: fix_info[:distros],
                        branches: branches,
                        tracker: @tracker,
                    )
                    @tracker.write_bug(bug_id, bug_data)
                    updates_count += 1
                end

                if updates_count == 0
                    log(:INFO, "No valid CVE fix comments extracted.")
                else
                    log(:INFO, "CVE tracking successfully updated! Updated #{updates_count} bugs.")
                end
                return 0
            end

            # Apply action
            def apply(opts)
                config = KernelWork.config.cve.to_h
                cve_files = @tracker.read_all
                if cve_files.empty?
                    log(:INFO, "No CVE tracking data found.")
                    return 0
                end

                patchlist = cves_to_patch_list(opts, cve_files)
                if patchlist.length == 0
                    log(:INFO, "Nothing to apply")
                    return
                end

                scp_opts = opts.dup
                scp_opts[:cve] = true

                @upstream._scp(scp_opts, patchlist) do |commit, error = nil|
                    cve    = commit.data
                    bug_id = cve.bug_id
                    sha    = cve.fix_sha
                    newState = nil

                    if error == nil
                        @upstream.build_commit(opts, commit)
                        newState = CVE::STATE_APPLIED
                    elsif error.class == SCPAlreadyApplied
                        newState = CVE::STATE_APPLIED
                    end
                    cve.set_status(branch(), newState) if newState != nil
                end
            end

            # Push action
            def push(opts)
                config = KernelWork.config.cve.to_h
                current_br = branch()

                unpushed_logs = @suse.runGit(@suse._list_unpushed_cmd(opts))
                bug_ids_to_push = unpushed_logs.scan(/bsc#(\d+)/).flatten.uniq

                if bug_ids_to_push.empty?
                    log(:INFO, "No bug references (bsc#ID) found in unpushed commits.")
                else
                    log(:INFO, "Found unpushed commits referencing Bug ID(s): #{bug_ids_to_push.join(', ')}")
                end

                @suse.push(opts)

                return 0 if bug_ids_to_push.empty?

                refresh(opts)
                return 0
            end

            # Refresh CVE status for the current branch.
            # @param opts [Hash] Options hash.
            # @return [void]
            def refresh(opts)
                all_cves = @tracker.read_all.select {|cve|
                     cve.get_status(branch()) != nil}

                # Return now if there are no CVEs
                # It avoids warnings/errs on dev branches that have
                # no upstream to compare tro but would have no CVE either
                return 0 if all_cves.length == 0

                # Cache unpushed/unmerged commits to figure out the state
                unpushed_commits = @suse.runGit(@suse._list_unpushed_cmd(opts)).
                                       split("\n").map(){ |line| line.split.first }
                unmerged_commits = @suse.runGit(@suse._list_unmerged_cmd(opts)).
                                       split("\n").map(){ |line| line.split.first }

                all_cves.each(){|cve|
                    status = cve.get_status(branch())
                    next if status == nil

                    newState = nil

                    # Check if it's applied locally, already pushed or even merged
                    kSha = @suse.get_suse_commit(cve.fix_sha)
                    next if kSha == nil # Patch is not applied !

                    if unpushed_commits.index(kSha) != nil
                        # Commit is unpushed, let's go normaly
                        newState = CVE::STATE_APPLIED
                    elsif unmerged_commits.index(kSha) != nil
                        # Commit is pushed but unmerge. Mark as pushed
                        newState = CVE::STATE_PUSHED
                    else
                        # It's neither unpushed not unmerge. It's merged then !
                        newState = CVE::STATE_MERGED
                    end
                    cve.set_status(branch, newState) if status != newState
                }
            end

            # Status action
            def status(opts)
                config = KernelWork.config.cve.to_h
                cve_files = @tracker.read_all

                if cve_files.empty?
                    log(:INFO, "No CVE tracking data found.")
                    return 0
                end

                active_distros = Set.new
                matching_cves = cve_files.select do |cve|
                    active = cve.active_branches
                    unless active.empty?
                        active_distros.merge(active.keys.map(&:to_s))
                        true
                    else
                        false
                    end
                end

                if matching_cves.empty?
                    log(:INFO, "No active CVEs found.")
                    return 0
                end

                distros_list = active_distros.to_a.sort

                # Determine the maximum width for the first column "CVE (Bug ID)"
                cve_col_header = "CVE BugID"
                max_cve_width = [cve_col_header.length, matching_cves.map { |cve|
                                     "#{cve.cve} bsc##{cve.bug_id}".length }.max || 0].max + 3

                # Determine width for each distro column
                distro_widths = {}
                distros_list.each do |distro|
                    distro_widths[distro] = [distro.length, CVE::MAX_STATE_LEN].max + 3
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
                matching_cves.each do |cve|
                    cve_bug_str = "#{cve.cve} bsc##{cve.bug_id}"
                    cve_bug_str = sprintf("%-#{max_cve_width}s", cve_bug_str)
                    statuses_str = ""

                    distros_list.each do |distro|
                        status = cve.get_status(distro) || ""
                        status_str = sprintf("%-#{distro_widths[distro]}s", status)
                        statuses_str += CVE.colour(status, status_str)
                    end
                    cve_bug_str = CVE.colour(CVE::STATE_MERGED, cve_bug_str) if cve.all_merged?
                    puts "#{cve_bug_str}#{statuses_str}"
                end

                return 0
            end
            alias_method :ls, :status

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

            # Generate a list of CVE tracking bugs that apply to the current branch.
            # @param opts [Hash] Options hash.
            # @param cve_datas [Array<CVE>] All CVE data records.
            # @return [Array<CVE>] List of relevant CVE bugs.
            def gen_cve_list(opts, cve_datas)
                bugs = []
                cve_datas.each do |cve_data|
                    status = cve_data.get_status(branch())
                    next if status == nil
                    bugs << cve_data
                end
                return bugs
            end

            # Map active CVE bugs needing backports to a list of Commit objects.
            # @param opts [Hash] Options hash.
            # @param cve_datas [Array<CVE>] CVE data records.
            # @return [Array<Commit>] List of target commits to patch.
            # @raise [ShaNotCommitError] If any CVE is missing its fix SHA.
            def cves_to_patch_list(opts, cve_datas)
                patchlist = []
                cve_datas.each do |cve|
                    status = cve.get_status(branch())
                    next if status == nil
                    next if status != CVE::STATE_TODO

                    bug_id = cve.bug_id
                    cve_id = cve.cve
                    sha    = cve.fix_sha

                    raise ShaNotFoundError(bug_id) if sha.nil? || sha.empty?

                    c = Commit.new(sha)
                    c.data = cve
                    c.extra_desc = "#{cve_id} bsc##{bug_id}"
                    patchlist << c
                end
                return patchlist
            end

            def cve_calc_new_state(commit, unpushed_commits, unmerged_commits)
                newState = nil
                # Check if it's applied locally, already pushed or even merged
                kSha = @suse.get_suse_commit(commit.sha)
                raise KernelWorkError.new() if kSha == nil

                if unpushed_commits.index(kSha) != nil
                    # Commit is unpushed, let's go normaly
                    newState = CVE::STATE_APPLIED
                elsif unmerged_commits.index(kSha) != nil
                    # Commit is pushed but unmerge. Mark as pushed
                    newState = CVE::STATE_PUSHED
                else
                    # It's neither unpushed not unmerge. It's merged then !
                    newState = CVE::STATE_MERGED
                end
                return newState
            end
        end

        # Action classes exposed by the CveCLI module.
        ACTION_CLASS = [ CveAction ]
        extend CLIClassTool::Utils
    end
end
