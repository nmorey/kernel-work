require 'net/http'
require 'uri'
require 'json'
require 'set'
require 'yaml'
require 'fileutils'

module KernelWork
    # Command-line interface controllers and action handlers
    module CLI
        # Module exposing CVE commands nested under 'cve'
        module CVE
            # Short description of the CVE CLI subcommand.
            CLI_DESCRIPTION = "Manage CVE fixes and tracking"
            # CLI command name registered for autodiscovery.
            CLI_COMMAND_NAME = "cve"
            # Help banner title for CVE commands.
            CLI_HELP_EXPAND = "*** CVE commands ***"

            # Custom error class for CVE CLI errors required by CLIClassTool.
            class CVEError < KernelWork::KernelWorkError; end

            # Base action class for CVE CLI commands.
            class Action < KernelWork::Common
                # Retrieve the parent module namespace.
                # @return [Module] The CVE module namespace.
                def parent_module
                    KernelWork::CLI::CVE
                end
            end

            # CVE Action class providing fetch, apply, and push subcommands nested under cve
            class CveAction < Action
                include ModelAccess

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
                    :push => "Push applied commits and set their status to Pushed",
                    :status => "Show the status of active CVEs",
                    :refresh => "Refresh CVE status for the current branch",
                    :reassign => "Reassign fully merged CVE bugs in Bugzilla and remove from local tracker",
                }

                # Set options for CVE actions
                # @param action [Symbol] The action
                # @param opts_parser [OptionParser] The option parser
                # @param opts [Hash] The options hash
                def self.set_opts(action, opts_parser, opts)
                    opts[:force] = false
                    opts[:force_push] = false
                    opts[:skip_broken] = false
                    opts[:dry_run] = false
                    opts[:fetch] = true
                    opts[:hyperlinks] = nil
                    opts[:bz_list] = []
                    opts[:bugzilla_user] = nil
                    opts[:assignee] = nil
                    opts[:comment] = nil
                    opts[:yn_default] = nil
                    opts[:bugzilla_id] = nil
                    opts[:bugzilla_ref] = nil
                    opts[:ref] = nil
                    opts[:full_check] = false

                    case action
                    when :fetch
                        opts_parser.on("-u", "--user <email>", String, "Bugzilla user email (overrides config).") do |val|
                            opts[:bugzilla_user] = val
                        end
                        opts_parser.on("-f", "--force", "Force full refresh (clears cache and re-fetches details for all CVEs).") do
                            opts[:force] = true
                        end
                        opts_parser.on("-b", "--bz <bug id>", String, "Only refresh the specified bugs (can be specified multiple times)") do |val|
                            opts[:bz_list] << val
                            opts[:force] = true
                        end
                    when :apply
                        opts_parser.on("-S", "--skip-broken", "Automatically skip patches that do not apply.") { opts[:skip_broken] = true }
                        opts_parser.on("-y", "--yes", "Apply fixes automatically without confirmation.") { opts[:yn_default] = :yes }
                        BuildOpts.add_options(opts_parser, opts, with_build: true)
                    when :push
                        opts_parser.on("-f", "--force", "Force push.") { opts[:force_push] = true }
                    when :status, :ls
                        opts_parser.on("--[no-]hyperlinks", "Enable or disable terminal hyperlinks in output.") do |val|
                            opts[:hyperlinks] = val
                        end
                    when :reassign
                        opts_parser.on("-d", "--dry-run", "List CVEs/commits that would be updated without making changes.") do
                            opts[:dry_run] = true
                        end
                        opts_parser.on("--[no-]fetch", "Fetch bugs from Bugzilla before reassigning (pass --no-fetch to skip).") do |val|
                            opts[:fetch] = val
                        end
                        opts_parser.on("-u", "--user <email>", String, "Bugzilla user email (overrides config).") do |val|
                            opts[:bugzilla_user] = val
                        end
                        opts_parser.on("-f", "--force", "Force full refresh (clears cache and re-fetches details for all CVEs).") do
                            opts[:force] = true
                        end
                        opts_parser.on("-a", "--assignee <email>", String, "Assignee email (default: kernel-security-sentinel@lists.suse.com).") do |val|
                            opts[:assignee] = val
                        end
                        opts_parser.on("-m", "--message <msg>", String, "Private comment message (default: Merged).") do |val|
                            opts[:comment] = val
                        end
                        opts_parser.on("-y", "--yes", "Apply reassignments automatically without confirmation.") do
                            opts[:yn_default] = :yes
                        end
                        opts_parser.on("--[no-]hyperlinks", "Enable or disable terminal hyperlinks in output.") do |val|
                            opts[:hyperlinks] = val
                        end
                    when :blacklist
                        opts_parser.on("-b", "--bug <bugzilla id or CVE>", String, "bsc#XXXX or XXXX or CVE-YYYY-NNNNN") do |val|
                            opts[:bugzilla_id] = val
                        end
                        opts_parser.on("-r", "--ref <ref>", String, "Bugzilla comment, e.g. 1234567#c1 or a full URL") do |val|
                            opts[:bugzilla_ref] = val
                        end
                    end
                end

                # Validate options before running an action.
                # @param opts [Hash] The options hash.
                # @return [void]
                # @raise [MissingArgumentError] If required arguments are missing
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

                # Initialize a CveAction object
                def initialize
                    @path = KernelWork.config.kernel_source_dir
                end

                # Initialize repositories and determine current branch
                # @return [String] The branch name
                def initialize_repo
                    branch
                end

                # Get current branch from kernel-source
                # @return [String] Branch name
                def branch
                    @branch ||= kernel_source.branch
                end

                # Blacklist a specific CVE on the current branch.
                # @param opts [Hash] Options hash containing :bugzilla_id and :bugzilla_ref.
                # @return [void]
                def blacklist(opts)
                    cve = cve_tracker.read_id(opts[:bugzilla_id])
                    kernel_source.runSystem("./scripts/cve_tools/blacklist-cve add #{cve.cve} #{branch} '#{opts[:bugzilla_ref]}'")
                    cve.set_status(branch, KernelWork::CVE::STATE_BLACKLISTED)
                end

                # Push action
                # @param opts [Hash] Options hash
                # @return [void]
                def push(opts)
                    unpushed_logs = kernel_source.runGit(kernel_source.unpushed_commits_cmd)
                    bug_ids_to_push = unpushed_logs.scan(/bsc#(\d+)/).flatten.uniq

                    if bug_ids_to_push.empty?
                        log(:INFO, "No bug references (bsc#ID) found in unpushed commits.")
                    else
                        log(:INFO, "Found unpushed commits referencing Bug ID(s): #{bug_ids_to_push.join(', ')}")
                    end

                    kernel_source.push(force: opts[:force_push])

                    return if bug_ids_to_push.empty?

                    refresh(opts)
                end

                # Reassign fully merged CVE bugs back to the security team and remove from tracking
                # @param opts [Hash] Action options
                # @return [void]
                # @raise [BugzillaTimeoutError] If the Bugzilla request times out
                # @raise [BugzillaError] If the Bugzilla update fails
                def reassign(opts)
                    fetch(opts) if opts[:fetch] != false

                    cve_files = cve_tracker.read_all
                    if cve_files.empty?
                        log(:INFO, "No CVE tracking data found.")
                        return
                    end

                    merged_cves = cve_files.select(&:all_merged?)
                    if merged_cves.empty?
                        log(:INFO, "No merged CVEs found to reassign.")
                        return
                    end

                    config = KernelWork.config.cve.to_h
                    assignee = opts[:assignee] || config[:reassign_to] ||
                               config[:reassign_assignee] || "kernel-security-sentinel@lists.suse.com"
                    comment_msg = opts[:comment] || config[:reassign_comment] ||
                                  config[:reassign_message] || "Merged"

                    reassigned_count = 0
                    merged_cves.each do |cve|
                        cve_s = cve.to_s(hyperlinks: opts[:hyperlinks])
                        commit_str = (cve.fix_sha && !cve.fix_sha.empty?) ? "#{cve.fix_sha} " : ""
                        summary_str = (cve.summary && !cve.summary.empty?) ? " - #{cve.summary.brown}" : ""
                        puts "#{commit_str}#{cve_s.blue}#{summary_str}"

                        next if opts[:dry_run]

                        msg = "reassign #{cve_s.blue} to #{assignee}"
                        rep = confirm(opts, msg)
                        if rep != 'y'
                            log(:INFO, "Skipping #{cve_s}.")
                            next
                        end

                        log(:INFO, "Reassigning #{cve_s} to #{assignee}...")
                        bugzilla.update_bug(cve.bug_id, {
                            assigned_to: assignee,
                            comment: {
                                body: comment_msg,
                                is_private: true
                            }
                        })

                        cve_tracker.delete_bug(cve.bug_id)
                        log(:INFO, "Successfully reassigned #{cve_s} to #{assignee} and dropped from tracker.")
                        reassigned_count += 1
                    end

                    if reassigned_count == 0
                        log(:INFO, "No CVEs were reassigned.")
                    else
                        log(:INFO, "Successfully reassigned #{reassigned_count} CVE bug(s).")
                    end
                end

                private

                # Find build subset based on modified files
                # @param sha [String] Commit SHA to identify changes in
                # @return [String, nil] Build subset path or nil
                def find_build_subset(sha)
                    subsets = linux.find_build_subset(sha)
                    if subsets.is_a?(Array) && subsets.length == 1 && subsets[0] != '.'
                        subsets[0]
                    elsif subsets.is_a?(String) && !subsets.empty? && subsets != '.'
                        subsets
                    else
                        nil
                    end
                end

                # Determine the aggregate workflow state for a column or row header based on CVE statuses.
                # @param statuses [Array<String>] List of all statuses to consider
                # @return [String] The workflow state constant representing the column status.
                def status_global_state(statuses)
                    if statuses.any? { |s| s == KernelWork::CVE::STATE_TODO }
                        KernelWork::CVE::STATE_TODO
                    elsif statuses.any? { |s| s == KernelWork::CVE::STATE_APPLIED }
                        KernelWork::CVE::STATE_APPLIED
                    elsif statuses.any? { |s| s == KernelWork::CVE::STATE_PUSHED }
                        KernelWork::CVE::STATE_PUSHED
                    else
                        KernelWork::CVE::STATE_MERGED
                    end
                end
            end

            # Action classes exposed by the CVE module.
            ACTION_CLASS = [ CveAction ]
            extend CLIClassTool::Utils
        end
    end
end

# Load all the sub-actions
require_relative 'cve/apply'
require_relative 'cve/fetch'
require_relative 'cve/refresh'
require_relative 'cve/status'
