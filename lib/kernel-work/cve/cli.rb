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
                :blacklist,
                :push,
                :status, :ls,
                :refresh,
                :reassign,
            ]

            # Brief help description for each action.
            ACTION_HELP = {
                :fetch => "Fetch my CVE bugs from Bugzilla and populate local cache",
                :apply => "Apply the missing CVE fixes to the current branch",
                :blacklist => "Blacklist a specific CVE on the current branch",
                :push  => "Push applied commits and set their status to Pushed",
                :status => "Show the status of active CVEs",
                :refresh => "Refresh CVE status for the current branch",
                :reassign => "Reassign fully merged CVE bugs in Bugzilla and remove from local tracker",
            }

            # Set options for CVE actions
            #
            # @param action [Symbol] The action
            # @param optsParser [OptionParser] The option parser
            # @param opts [Hash] The options hash
            def self.set_opts(action, optsParser, opts)
                case action
                when :fetch
                    opts[:bz_list] = []
                    optsParser.on("-u", "--user <email>", String, "Bugzilla user email (overrides config).") {
                        |val| opts[:bugzilla_user] = val}
                    optsParser.on("-f", "--force",
                                  "Force full refresh (clears cache and re-fetches details for all CVEs).") {
                        |val| opts[:force] = true}
                    optsParser.on("-b", "--bz <bug id>", String,
                                  "Only refresh the specified bugs (can be specified multiple times)") {
                        |val| opts[:bz_list] << val
                        opts[:force] = true
                    }
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
                when :status, :ls
                    optsParser.on("--[no-]hyperlinks", "Enable or disable terminal hyperlinks in output.") {
                        |val| opts[:hyperlinks] = val}
                when :reassign
                    optsParser.on("-d", "--dry-run", "List CVEs/commits that would be updated without making changes.") {
                        |val| opts[:dry_run] = true}
                    optsParser.on("--[no-]fetch", "Fetch bugs from Bugzilla before reassigning (pass --no-fetch to skip).") {
                        |val| opts[:fetch] = val}
                    optsParser.on("-u", "--user <email>", String, "Bugzilla user email (overrides config).") {
                        |val| opts[:bugzilla_user] = val}
                    optsParser.on("-f", "--force", "Force full refresh (clears cache and re-fetches details for all CVEs).") {
                        |val| opts[:force] = true}
                    optsParser.on("-a", "--assignee <email>", String,
                                  "Assignee email (default: kernel-security-sentinel@lists.suse.com).") {
                        |val| opts[:assignee] = val}
                    optsParser.on("-m", "--message <msg>", String,
                                  "Private comment message (default: Merged).") {
                        |val| opts[:comment] = val}
                    optsParser.on("-y", "--yes", "Apply reassignments automatically without confirmation.") {
                        |val| opts[:yn_default] = :yes}
                    optsParser.on("--[no-]hyperlinks", "Enable or disable terminal hyperlinks in output.") {
                        |val| opts[:hyperlinks] = val}
                when :blacklist
                    optsParser.on("-b", "--bug <bugzilla id or CVE>", String,
                                  "bsc#XXXX or XXXX or CVE-YYYY-NNNNN") {
                        |val| opts[:bugzilla_id] = val}
                    optsParser.on("-r", "--ref <ref>", String,
                                  "Bugzilla comment, e.g. 1234567#c1 or a full URL") {
                        |val| opts[:bugzilla_ref] = val}
                end

            end

            # Validate options before running an action.
            # @param opts [Hash] The options hash.
            # @return [void]
            def self.check_opts(opts)
                case opts[:action]
                when :blacklist
                    if opts[:bugzilla_id].to_s == ""
                        raise MissingArgumentError.new("bugzilla id")
                    end
                    if opts[:bugzilla_ref].to_s == ""
                        raise MissingArgumentError.new("bugzilla reference comment")
                    end
                end
            end

            # Initialize a CveAction object, linking suse and upstream instances
            def initialize(upstream = nil, suse = nil)
                @path = KernelWork.config.kernel_source_dir
                config = KernelWork.config.cve.to_h
                @tracker = CveTracker.create(config, self)
                @bugzilla = CveCLI::BugzillaClient.new(config)
                @suse = suse
                @upstream = upstream
            end

            # Initialize Suse and Upstream repositories and determine the current branch
            #
            # @return [String] The branch name
            def initialize_repo()
                if @suse == nil
                    @suse = Suse.new(@upstream)
                end
                if @upstream == nil
                    @upstream = @suse.upstream
                end
                @branch = @suse.branch()
            end
            # Get current branch
            def branch
                initialize_repo() if @branch == nil
                @branch
            end

            # Blacklist a specific CVE on the current branch.
            #
            # @param opts [Hash] Options hash containing :bugzilla_id and :bugzilla_ref.
            # @return [void]
            def blacklist(opts)
                initialize_repo()
                config = KernelWork.config.cve.to_h
                cve = @tracker.read_id(opts[:bugzilla_id])
                bzId = cve.bug_id
                @suse.runSystem("./scripts/cve_tools/blacklist-cve add #{cve.cve} #{branch()} '#{opts[:bugzilla_ref]}'")
                cve.set_status(branch(), CVE::STATE_BLACKLISTED)
            end

            # Push action
            def push(opts)
                initialize_repo()
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



            # Reassign fully merged CVE bugs back to the security team and remove from tracking
            #
            # Fetches current CVE bugs from Bugzilla (unless opts[:fetch] is false), identifies
            # all bugs where all active target branches are merged, requests user confirmation,
            # updates Bugzilla with the new assignee and a private comment, and deletes the bug
            # from the local tracker.
            # If opts[:dry_run] is set, lists all candidate CVEs/commits without confirmation
            # and without modifying Bugzilla or the local tracker.
            #
            # @param opts [Hash] Action options
            # @return [Integer] 0 on success
            # @raise [BugzillaTimeoutError] If the Bugzilla request times out
            # @raise [BugzillaError] If the Bugzilla update fails
            def reassign(opts)
                fetch(opts) if opts[:fetch] != false

                cve_files = @tracker.read_all
                if cve_files.empty?
                    log(:INFO, "No CVE tracking data found.")
                    return 0
                end

                merged_cves = cve_files.select(&:all_merged?)
                if merged_cves.empty?
                    log(:INFO, "No merged CVEs found to reassign.")
                    return 0
                end

                config = KernelWork.config.cve.to_h
                assignee = opts[:assignee] || config[:reassign_to] ||
                           config[:reassign_assignee] || "kernel-security-sentinel@lists.suse.com"
                comment_msg = opts[:comment] || config[:reassign_comment] ||
                              config[:reassign_message] || "Merged"

                reassigned_count = 0
                merged_cves.each do |cve|
                    cve_s = cve.to_s(opts)
                    commit_str = (cve.fix_sha && !cve.fix_sha.empty?) ? "#{cve.fix_sha} " : ""
                    summary_str = (cve.summary && !cve.summary.empty?) ? " - #{cve.summary.brown}" : ""
                    puts "#{commit_str}#{cve_s.blue()}#{summary_str}"

                    next if opts[:dry_run]

                    msg = "reassign #{cve_s.blue} to #{assignee}"
                    rep = confirm(opts, msg)
                    if rep != 'y'
                        log(:INFO, "Skipping #{cve_s}.")
                        next
                    end

                    log(:INFO, "Reassigning #{cve_s} to #{assignee}...")
                    @bugzilla.update_bug(cve.bug_id, {
                        assigned_to: assignee,
                        comment: {
                            body: comment_msg,
                            is_private: true
                        }
                    })

                    @tracker.delete_bug(cve.bug_id)
                    log(:INFO, "Successfully reassigned #{cve_s} to #{assignee} and dropped from tracker.")
                    reassigned_count += 1
                end

                if reassigned_count == 0
                    log(:INFO, "No CVEs were reassigned.")
                else
                    log(:INFO, "Successfully reassigned #{reassigned_count} CVE bug(s).")
                end
                return 0
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

            # Determine the aggregate workflow state for a column or row header based on CVE statuses.
            #
            # The workflow state precedence is:
            # - {CVE::STATE_TODO} if any CVE on the distro has a ToDo status
            # - {CVE::STATE_APPLIED} if any CVE on the distro has an Applied status
            # - {CVE::STATE_PUSHED} if any CVE on the distro has a Pushed status
            # - {CVE::STATE_MERGED} otherwise (all CVEs are Merged or Blacklisted)
            #
            # @param statuses [Array<String>] List of all status to consider
            # @return [String] The workflow state constant representing the column status.
            def status_global_state(statuses)
                if statuses.any? { |s| s == CVE::STATE_TODO }
                    CVE::STATE_TODO
                elsif statuses.any? { |s| s == CVE::STATE_APPLIED }
                    CVE::STATE_APPLIED
                elsif statuses.any? { |s| s == CVE::STATE_PUSHED }
                    CVE::STATE_PUSHED
                else
                    CVE::STATE_MERGED
                end
            end

        end

        # Action classes exposed by the CveCLI module.
        ACTION_CLASS = [ CveAction ]
        extend CLIClassTool::Utils

    end
    # Load all the actions
    require_relative 'apply'
    require_relative 'fetch'
    require_relative 'refresh'
    require_relative 'status'
end

