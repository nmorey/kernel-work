require 'readline'

module KernelWork
    # Domain workflow service coordinating cross-repository operations between Linux and KernelSource
    class Workflow < Common
        # @!attribute [r] linux
        #   @return [Linux] Upstream Linux repository model
        attr_reader :linux

        # @!attribute [r] kernel_source
        #   @return [KernelSource] SUSE kernel-source repository model
        attr_reader :kernel_source

        # Initialize a new Workflow service
        # @param linux [Linux] Upstream Linux repository model
        # @param kernel_source [KernelSource] SUSE kernel-source repository model
        def initialize(linux:, kernel_source:)
            @linux = linux
            @kernel_source = kernel_source
        end

        # Check if the commit exists in our branch (in base Linux history or backported to SUSE patch set)
        # @param commit [Commit, String] Commit or SHA to check
        # @return [Boolean] True if the commit is already present
        def has_commit?(commit)
            c = commit.is_a?(Commit) ? commit : Commit.new(commit.to_s, safe_sha: true)
            return true if @linux.is_ancestor?(c, "HEAD")
            return true if @kernel_source.commit_ids[c.f_sha] == true

            false
        end

        # Filter candidate commits against in-house patch set and base repository history
        # @param commits [Array<Commit>] List of candidate commits
        # @param include_shas [Array<String, Commit>] Commits to force include
        # @param exclude_shas [Array<String, Commit>] Commits to force exclude
        # @return [Array<Commit>] Filtered list of commits
        def filter_in_house(commits, include_shas: [], exclude_shas: [])
            inc = (include_shas || []).map { |x| x.is_a?(Commit) ? x.f_sha : x }
            exc = (exclude_shas || []).map { |x| x.is_a?(Commit) ? x.f_sha : x }

            commits.delete_if do |x|
                sha = x.f_sha
                next true if exc.include?(sha)
                next false if inc.include?(sha)
                has_commit?(x)
            end
        end

        # Reset Linux git branch and reapply all unmerged/refreshed patches from kernel-source
        # @return [Integer] Exit code
        def apply_pending_patches
            @linux.runGit("am --abort", catch_err: true)
            @linux.runGitInteractive("reset --hard #{KernelWork.config.linux.remote}/#{@linux.branch}")

            patches = @kernel_source.gen_ordered_patchlist do |kern_sha|
                @linux.runGit("log -n1 --format='%H' --grep 'suse-commit: #{kern_sha}'").chomp
            end

            if patches.empty?
                log(:INFO, "No patches to apply")
                return 0
            end

            am_list = []
            patches.each do |p|
                if p =~ /^-([a-f0-9]+)$/
                    @linux.runGitInteractive("revert --no-edit #{$1}")
                else
                    am_list << p
                end
            end
            @linux.runGitInteractive("am #{am_list.join(' ')}") if !am_list.empty?
            0
        end

        # Run checkpatch and prompt user to meld fixes if necessary
        # @param full_check [Boolean] Enable full checkpatch inspection
        # @return [void]
        def tune_last_patch(full_check: false)
            @linux.run("rm -f 0001*.patch")
            Commit.new("@", path: @linux.path).patchname

            ret = 1
            while ret == 1
                begin
                    @kernel_source.checkpatch(full: full_check)
                    ret = 0
                rescue CheckPatchError
                    @kernel_source.meld_lastpatch(@linux.path)
                end
            end
        end

        # Orchestrate backporting a sequence of commits across Linux and KernelSource
        # @param commits [Array<Commit>] List of commits to backport
        # @param build_opts [LinuxBuildOpts] Build options object
        # @param skip_broken [Boolean] Automatically skip patches that fail to apply
        # @param yn_default [Symbol, nil] Default auto-reply (:yes or :no)
        # @param ref [String, nil] Reference string override
        # @param full_check [Boolean] Enable full checkpatch inspection
        # @yieldparam commit [Commit] Current commit being processed
        # @yieldparam error [Exception, nil] Error encountered if any
        # @return [void]
        def backport_commits(commits, build_opts: LinuxBuildOpts.new, skip_broken: false, yn_default: nil, ref: nil, full_check: false, &block)
            b_opts = build_opts || LinuxBuildOpts.new

            while !commits.empty?
                commit = commits.first
                begin
                    log(:INFO, "# #{commits.length} commits left".grey)

                    begin
                        backport_single_commit(commit, skip_broken: skip_broken, yn_default: yn_default, ref: ref, full_check: full_check)
                        if b_opts.build
                            @linux.build_commit(commit, b_opts)
                        end
                        yield(commit, nil) if block_given?
                    rescue SCPSkip, SCPAlreadyApplied, SCPNotApplied => e
                        yield(commit, e) if block_given?
                    rescue SCPQueueSeries => e
                        commits.shift
                        new_commits = (e.series + commits).uniq
                        commits.replace(new_commits)
                        log(:INFO, "# Queued series (#{e.series.length} patches). #{commits.length} commits now in queue.")
                        next
                    end

                    commits.shift
                rescue SCPAbort => e
                    log(:WARNING, "Aborted")
                    raise e
                rescue Interrupt
                    log(:WARNING, "Interrupted")
                    raise SCPAbort.new()
                end
            end
        end

        # Build the kernel or a subset using configuration from the kernel source repository
        # @param build_opts [LinuxBuildOpts] Build options object
        # @return [Integer] Exit code
        def build(build_opts = LinuxBuildOpts.new)
            b = build_opts || LinuxBuildOpts.new

            build_target = ""
            if b.build_subset && !b.build_subset.empty?
                sub = b.build_subset.is_a?(Array) ? b.build_subset : [b.build_subset]
                if !b.old_kernel && @linux.kernel_base < KV.new(5, 3)
                    b.old_kernel = true
                end
                sub = sub.map { |s| s.gsub(/\/+$/, '') + '/' }
                build_target = sub.join(" ")
            end

            arch_name, _arch, _b_dir = @linux.arch_to_bdir(b.arch)
            config_file = @kernel_source.config_file(arch_name)
            @linux.run_oldconfig(b, config_file, force: false)
            @linux.run_build(b, build_target)
            0
        end

        # Run oldconfig for the target architecture using kernel-source configuration
        # @param build_opts [LinuxBuildOpts] Build options object
        # @param force [Boolean] Force regeneration of config
        # @return [Integer] Exit code
        def oldconfig(build_opts = LinuxBuildOpts.new, force: true)
            b = build_opts || LinuxBuildOpts.new

            arch_name, _arch, _b_dir = @linux.arch_to_bdir(b.arch)
            config_file = @kernel_source.config_file(arch_name)
            @linux.run_oldconfig(b, config_file, force: force)
            0
        end

        # Process a single commit through the backport workflow
        # @param commit [Commit] The commit to backport
        # @param skip_broken [Boolean] Automatically skip patches that fail to apply
        # @param yn_default [Symbol, nil] Default auto-reply (:yes or :no)
        # @param ref [String, nil] Reference string override
        # @param full_check [Boolean] Enable full checkpatch inspection
        # @return [void]
        # @raise [ShaNotCommitError] If commit is not a Commit object
        # @raise [ShaNotFoundError] If commit is not found in repository
        # @raise [SCPAlreadyApplied] If patch is already in kernel-source
        # @raise [SCPNotApplied] If user rejects the commit
        # @raise [PatchExtractionError] If patch extraction fails in kernel-source
        # @raise [SCPQueueSeries] If user requests applying the whole series
        def backport_single_commit(commit, skip_broken: false, yn_default: nil, ref: nil, full_check: false)
            current_ref = ref
            rep = "t"
            raise ShaNotCommitError.new() if !commit.is_a?(KernelWork::Commit)

            begin
                desc = commit.desc.blue
            rescue ShaNotFoundError => e
                log(:ERROR, "'#{commit.sha}' does not seem to be a valid SHA in this repo")
                raise e
            end

            if @kernel_source.is_applied?(commit)
                log(:INFO, "Patch already applied in KERNEL_SOURCE_DIR: #{desc}")
                patch = Patch.new(@kernel_source, commit)
                patch.compute_ref(ref: current_ref)
                commit.patch = patch
                raise SCPAlreadyApplied.new()
            end

            log(:INFO, "Looking at #{desc.bold}")
            fixes = commit.fixes_shas
            if !fixes.empty?
                log(:INFO, "Patch fixes:")
                fixes.each do |f_sha|
                    fixes_commit = KernelWork::Commit.new(f_sha, path: @linux.path)
                    begin
                        f_desc = fixes_commit.desc
                        if has_commit?(fixes_commit)
                            log(:INFO, "  backported #{f_desc}")
                        else
                            log(:WARNING, "  unbackported #{f_desc}")
                        end
                    rescue ShaNotFoundError
                        log(:WARNING, "  unknown sha #{f_sha}")
                    end
                end
            end

            series = commit.patch_series
            if !series.empty?
                log(:INFO, "Patch is part of a series:")
                series.each do |series_commit|
                    str = series_commit.desc
                    if commit.sha == series_commit.sha
                        str = series_commit.desc.blue.bold
                    elsif has_commit?(series_commit) == true
                        str = series_commit.desc.green
                    end
                    log(:INFO, "  #{str}")
                end
            end

            confirm_choices = ["y", "n", "?", "r"]
            confirm_msg = "pick commit '#{desc.bold}' up"
            usage = ["[y]es", "[n]o", "[?]show", "[r]ef set and apply"]
            if series.length > 1
                confirm_choices << "a"
                usage << "[a]pply series"
            end

            confirm_opts = { yn_default: yn_default }
            while rep != "y"
                rep = confirm(confirm_opts, confirm_msg,
                              ignore_default: false,
                              allowed_reps: confirm_choices,
                              usage: usage)
                case rep
                when "n"
                    break
                when "?"
                    @linux.runGitInteractive("show #{commit.sha}", catch_err: true)
                when "r"
                    user_ref = Readline.readline("Enter reference for this commit: ", true)
                    current_ref = user_ref if user_ref != nil
                    rep = "y"
                when "a"
                    raise SCPQueueSeries.new(series)
                end
            end

            raise SCPNotApplied.new() if rep != "y"

            @linux.cherry_pick_one(commit, skip_broken: skip_broken)

            begin
                @kernel_source.extract_single_patch(commit, ref: current_ref, yn_default: yn_default)
            rescue => _e
                @linux.runGitInteractive("reset --hard HEAD~1")
                raise PatchExtractionError.new("Failed to extract patch in KERNEL_SOURCE_DIR, reverted in LINUX_GIT")
            end

            tune_last_patch(full_check: full_check)
        end
    end
end
