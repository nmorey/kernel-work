module KernelWork
    # Command-line interface controllers and action handlers
    module CLI
        # Module exposing CVE commands nested under 'cve'
        module CVE
            class CveAction
                # Apply action: apply missing CVE fixes to the current branch
                # @param opts [Hash] Options hash
                # @return [void]
                def apply(opts)
                    initialize_repo
                    cve_files = @tracker.read_all
                    if cve_files.empty?
                        log(:INFO, "No CVE tracking data found.")
                        return
                    end

                    patchlist = cves_to_patch_list(opts, cve_files)
                    if patchlist.empty?
                        log(:INFO, "Nothing to apply")
                        return
                    end

                    workflow.backport_commits(
                        patchlist,
                        build_opts: BuildOpts.from_opts(opts),
                        tracker: @tracker,
                        skip_broken: opts[:skip_broken],
                        yn_default: opts[:yn_default],
                        ref: opts[:ref],
                        full_check: opts[:full_check]
                    )
                end

                private

                # Map active CVE bugs needing backports to a list of Commit objects.
                # @param _opts [Hash] Options hash.
                # @param cve_datas [Array<CVE>] CVE data records.
                # @return [Array<Commit>] List of target commits to patch.
                # @raise [ShaNotFoundError] If any CVE is missing its fix SHA.
                def cves_to_patch_list(_opts, cve_datas)
                    patchlist = []
                    cve_datas.each do |cve|
                        status = cve.get_status(branch)
                        next if status.nil?
                        next if status != KernelWork::CVE::STATE_TODO

                        bug_id = cve.bug_id
                        cve_id = cve.cve
                        sha    = cve.fix_sha

                        raise ShaNotFoundError.new(bug_id) if sha.nil? || sha.empty?

                        c = Commit.new(sha, path: linux.path)
                        c.extra_desc = "#{cve_id} bsc##{bug_id}"
                        patchlist << c
                    end
                    patchlist
                end
            end
        end
    end
end
