module KernelWork
module CveCLI
    class CveAction
        public
        # Apply action
        def apply(opts)
            initialize_repo()
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

            @upstream._scp(opts, patchlist) do |commit, error = nil|
                next if error.class == SCPSkip
                next if error.class == SCPNotApplied

                cve = nil
                patch = commit.patch
                if patch.ref =~ /(CVE-[0-9]+-[0-9]+)/ then
                    # It has a CVE
                    begin
                        cve = @tracker.read_cve($1)
                    rescue BugNotFoundError
                        # Not a CVE in our pool. Ignore it
                    end
                end

                newState = nil
                if error == nil
                    @upstream.build_commit(opts, commit)
                    newState = CVE::STATE_APPLIED
                elsif error.class == SCPAlreadyApplied
                    newState = CVE::STATE_APPLIED
                end
                next if cve == nil
                bug_id = cve.bug_id
                cve.set_status(branch(), newState) if newState != nil
            end
        end

        private

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
                c.extra_desc = "#{cve_id} bsc##{bug_id}"
                patchlist << c
            end
            return patchlist
        end
    end
end
end
