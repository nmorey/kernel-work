module KernelWork
module CveCLI
    class CveAction
        public
        # Fetch CVE bugs assigned to the user from Bugzilla.
        #
        # Reassigned and resolved bugs are pruned from local cache.
        # By default, details (comments) are fetched only for new/unknown CVE bugs,
        # keeping known cached CVEs as-is. Passing opts[:force] forces a complete
        # refresh and re-fetches details for all CVEs. Passing opts[:bz_list] selectively
        # clears and re-fetches details only for the specified bugs or CVE IDs.
        #
        # @param opts [Hash] Options hash (:bugzilla_user, :force, :bz_list)
        # @return [Integer] 0 on success, non-zero on failure
        def fetch(opts)
            config = KernelWork.config.cve.to_h

            bz_user = opts[:bugzilla_user] || config[:bugzilla_user]
            bz_list = opts[:bz_list] || []

            if bz_user.nil? || bz_user.empty?
                log(:ERROR, "Bugzilla user email is required. Please set it in config or pass via -u.")
                return 1
            end

            log(:INFO, "Fetching bug list for #{bz_user} from Bugzilla...")
            params = {
                product: "SUSE Security Incidents",
                assigned_to: bz_user
            }

            res = @bugzilla.request("bug", params)
            bugs = res["bugs"] || []

            resolved_statuses = ["RESOLVED", "VERIFIED", "CLOSED"]
            filtered_bugs = bugs.select do |bug|
                status = bug["status"].to_s.upcase
                !resolved_statuses.include?(status) && bug["summary"] =~ /CVE-\d{4}-\d+:\s+kernel:/i
            end

            # Identify and drop reassigned/resolved bugs from local cache
            fetched_ids = filtered_bugs.map { |bug| bug["id"].to_s }

            if opts[:force]
                if bz_list.length == 0 then
                    log(:INFO, "Force option specified. Clearing tracking data...")
                    @tracker.delete_all
                else
                    log(:INFO, "Force option specified. Clearing tracking data for bugs #{bz_list.join(" ")}...")
                    bz_list.each(){|bz|
                        begin
                            cve = @tracker.read_id(bz)
                            @tracker.delete_bug(cve.bug_id)
                        rescue BugNotFoundError
                            # Ignore if we do not know this one
                        end
                    }
                end
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

            known_ids = local_ids - orphaned_ids
            bugs_to_fetch = filtered_bugs.reject { |bug| known_ids.include?(bug["id"].to_s) }

            log_str = "Found #{filtered_bugs.length} CVE bugs (#{known_ids.length} already known). "
            if bugs_to_fetch.empty?
                log(:INFO, log_str + "No new CVE bugs to fetch.")
                return 0
            else
                log(:INFO, log_str + "Fetching comments for #{bugs_to_fetch.length} bugs.")
            end

            updates_count = 0
            bugs_to_fetch.each do |bug|
                bug_id = bug["id"].to_s
                log(:INFO, "Fetching comments #{updates_count + 1}/#{bugs_to_fetch.length} for Bug ##{bug_id}...")
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

        private
        # Parse CVE Bugzilla Comments
        def parse_cve_comment(comments)
            comments.reverse_each do |comment|
                text = comment["text"] || ""
                next if text !~ /Security fix for (CVE-\d{4}-\d+)\s+bsc#(\d+)/i

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

                return {
                    cve: cve,
                    bug_id: bug_id,
                    mainstream_sha: mainstream_sha,
                    distros: distros
                } if !distros.empty?
            end
        end
    end
end
end
