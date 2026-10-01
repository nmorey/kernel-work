module KernelWork
    # Command-line interface controllers and action handlers
    module CLI
        # Module exposing CVE commands nested under 'cve'
        module CVE
            class CveAction
                # Refresh CVE status for the current branch.
                # @param _opts [Hash] Options hash.
                # @return [void]
                def refresh(_opts)
                    initialize_repo
                    all_cves = cve_tracker.read_all.select do |cve|
                        cve.get_status(branch) != nil
                    end

                    # Return now if there are no CVEs
                    # It avoids warnings/errs on dev branches that have
                    # no upstream to compare to but would have no CVE either
                    return if all_cves.empty?

                    # Cache unpushed/unmerged commits to figure out the state
                    unpushed_commits = kernel_source.runGit(kernel_source.unpushed_commits_cmd).
                                       split("\n").map { |line| line.split.first }
                    unmerged_commits = kernel_source.runGit(kernel_source.unmerged_commits_cmd).
                                       split("\n").map { |line| line.split.first }

                    all_cves.each do |cve|
                        status = cve.get_status(branch)
                        next if status.nil?

                        new_state = cve_calc_new_state(cve.fix_sha, unpushed_commits, unmerged_commits)
                        cve.set_status(branch, new_state) if status != new_state
                    end
                end

                private

                # Calculate the new CVE state based on git commits
                # @param sha [String, nil] The fix SHA from upstream
                # @param unpushed_commits [Array<String>] List of unpushed commits
                # @param unmerged_commits [Array<String>] List of unmerged commits
                # @return [String] Calculated CVE state
                def cve_calc_new_state(sha, unpushed_commits, unmerged_commits)
                    # Check if it's applied locally, already pushed or even merged
                    k_sha = kernel_source.get_suse_commit(sha)

                    if k_sha.nil?
                        # Patch is not applied !
                        KernelWork::CVE::STATE_TODO
                    elsif unpushed_commits.include?(k_sha)
                        # Commit is unpushed, let's go normally
                        KernelWork::CVE::STATE_APPLIED
                    elsif unmerged_commits.include?(k_sha)
                        # Commit is pushed but unmerged. Mark as pushed
                        KernelWork::CVE::STATE_PUSHED
                    else
                        # It's neither unpushed nor unmerged. It's merged then !
                        KernelWork::CVE::STATE_MERGED
                    end
                end
            end
        end
    end
end
