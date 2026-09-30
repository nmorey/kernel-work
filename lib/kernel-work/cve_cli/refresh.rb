module KernelWork
module CveCLI
    class CveAction
        public
        # Refresh CVE status for the current branch.
        # @param opts [Hash] Options hash.
        # @return [void]
        def refresh(opts)
            initialize_repo()
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

                newState = cve_calc_new_state(cve.fix_sha, unpushed_commits, unmerged_commits)
                cve.set_status(branch, newState) if status != newState
            }
        end

        private
        def cve_calc_new_state(sha, unpushed_commits, unmerged_commits)
            # Check if it's applied locally, already pushed or even merged
            kSha = @suse.get_suse_commit(sha)

            if kSha == nil
                # Patch is not applied !
                return CVE::STATE_TODO
            elsif unpushed_commits.index(kSha) != nil
                # Commit is unpushed, let's go normaly
                return CVE::STATE_APPLIED
            elsif unmerged_commits.index(kSha) != nil
                # Commit is pushed but unmerge. Mark as pushed
                return CVE::STATE_PUSHED
            else
                # It's neither unpushed not unmerge. It's merged then !
                return CVE::STATE_MERGED
            end
        end
    end
end
end
