require 'yaml'
require 'fileutils'

module KernelWork
    # Class for handling SUSE kernel source repository operations and series management
    class KernelSource < Common
        # @!attribute [r] path
        #   @return [String] Kernel source directory path
        attr_reader :path

        # Initialize a new KernelSource model object
        # @param path [String, nil] Path to kernel-source repository
        def initialize(path = nil)
            @path = path || KernelWork.config.kernel_source_dir
            begin
                set_branches()
            rescue UnknownBranch
                @branch = nil
            end

            @patch_path = "patches.suse"

            # Access branches directly from config
            branches = KernelWork.config.kernel_source.branches

            # Find branch info
            @branch_infos = branches.find { |b| b[:name] == @branch }

            if @branch_infos.nil?
                log(:WARNING, "Branch '#{@branch}' not in supported list") if @branch != nil
                @branch_infos = {}
            else
                @patch_path = @branch_infos[:patch_path] if @branch_infos[:patch_path] != nil
            end
        end

        # Get current branch
        # @return [String] Branch name
        # @raise [UnknownBranch] If branch is not detected
        def branch
            raise UnknownBranch.new(@path) if @branch.nil?
            @branch
        end

        # Check if current branch matches expected
        # @param br [String] Expected branch
        # @return [Boolean] True if match
        # @raise [UnknownBranch] If branch is not detected
        # @raise [BranchMismatch] If branches do not match
        def branch?(br)
            raise UnknownBranch.new(@path) if @branch.nil?
            raise BranchMismatch.new(br, @branch) if br != @branch

            @branch == br
        end

        # Get local branch name
        # @return [String] Local branch name
        # @raise [UnknownBranch] If branch is not detected
        def local_branch
            raise UnknownBranch.new(@path) if @local_branch.nil?
            @local_branch
        end

        # Get the patch directory path
        # @return [String] Path to patch directory
        def patch_dir
            @patch_path
        end

        # Returns default patch references
        # @param ref [String, Hash, nil] Explicit reference string or options hash
        # @return [String] Default reference
        # @raise [NoRefError] If no reference can be found
        def default_patch_references(ref = nil)
            ref_val = ref.is_a?(Hash) ? ref[:ref] : ref
            return ref_val if ref_val != nil && !ref_val.empty?
            return @branch_infos[:ref] if @branch_infos && @branch_infos[:ref] != nil

            e = NoRefError.new()
            log(:ERROR, e.to_s)
            raise e
        end

        # Find commit local branch started from upstream
        # @return [String] SHA of merge base
        def base
            runGit("merge-base HEAD #{KernelWork.config.kernel_source.remote}/#{branch}")
        end

        # Get architecture config file path
        # @param arch [Symbol, String] Architecture name
        # @return [String] Absolute path to default config file
        def config_file(arch)
            "#{@path}/config/#{arch}/default"
        end

        # Get kabi directory path
        # @return [String] Path to kabi directory
        def kabi_dir
            "#{@path}/kabi"
        end

        # Get the filename of the last applied patch
        # @return [String] Filename
        def last_patch
            runGit("show HEAD --stat --stat-width=1000 --no-decorate").
                split("\n").each.grep(/patches\.[^\/]*/).grep(/ \++$/)[0].lstrip.split(/[ \t]/)[0]
        end

        # Get the filename of the currently modified patch
        # @return [String] Filename
        def current_patch
            runGit("diff --cached --stat --stat-width=1000").
                split("\n").each.grep(/patches\.[^\/]*/).grep(/ \++$/)[0].lstrip.split(/[ \t]/)[0]
        end

        # Get the Git-commit from a patch file
        # @param patchfile [String] Path to patch file
        # @return [Commit] Commit object
        def get_patch_commit(patchfile)
            Commit.new(runGit("grep Git-commit #{patchfile}").split(/[ \t]/)[-1], safe_sha: true)
        end

        # Check for blacklist.conf conflict
        # @return [Boolean] True if conflict exists
        def blacklist_conflict?
            begin
                runGit("status --porcelain -- blacklist.conf").lstrip.split(/[ \t]/)[0] == "UU"
            rescue
                false
            end
        end

        # Check if a commit is already applied
        # @param sha [Commit, String] Commit or SHA
        # @return [Boolean] True if applied
        def is_applied?(sha)
            sha_str = sha.is_a?(Commit) ? sha.sha : sha
            begin
                runGit("grep -q #{sha_str}")
                true
            rescue
                false
            end
        end

        # Return the last kernel source commit that touched the patch matching a linux upstream sha
        # @param sha [Commit, String] Commit or SHA
        # @return [String, nil] Kernel source SHA or nil
        def get_suse_commit(sha)
            sha_str = sha.is_a?(Commit) ? sha.sha : sha
            begin
                file = runGit("grep -l #{sha_str}")
                runGit("log -n1 --format='%H' -- #{file}")
            rescue
                nil
            end
        end

        # Gets a list of commit IDs already in the patch directory
        # @return [Hash{String => Boolean}] Hash with SHA keys and true values
        def commit_ids
            return @commit_ids if @commit_ids != nil

            @commit_ids = {}
            run("git grep Git-commit: patches.* | awk '{ print $NF}'").
                chomp.split("\n").each do |x|
                @commit_ids[x] = true
            end
            @commit_ids
        end

        # Git command to list unmerged commits
        # @param remote_branch [String, nil] Remote branch to compare against
        # @return [String] String to pass to git
        def unmerged_commits_cmd(remote_branch = nil)
            target = remote_branch || "#{KernelWork.config.kernel_source.remote}/#{branch}"
            "log --no-decorate --format=oneline \"^#{target}\" HEAD"
        end

        # List unmerged commits
        # @param remote_branch [String, nil] Remote branch to compare against
        # @return [void]
        def unmerged_commits(remote_branch = nil)
            runGitInteractive(unmerged_commits_cmd(remote_branch))
        end

        # Git command to list unpushed commits
        # @param remote_branch [String, nil] Remote branch to compare against
        # @return [String] String to pass to git
        def unpushed_commits_cmd(remote_branch = nil)
            main_target = remote_branch || "#{KernelWork.config.kernel_source.remote}/#{branch}"
            remote_refs = " \"^#{main_target}\""
            begin
                runGit("rev-parse --verify --quiet #{KernelWork.config.kernel_source.remote}/#{local_branch}")
                remote_refs += " \"^#{KernelWork.config.kernel_source.remote}/#{local_branch}\""
            rescue
                log(:INFO, "Remote user branch does not exist. Checking against main branch only.")
            end
            "log --no-decorate --format=oneline #{remote_refs} HEAD"
        end

        # List unpushed commits
        # @param remote_branch [String, nil] Remote branch to compare against
        # @return [void]
        def unpushed_commits(remote_branch = nil)
            runGitInteractive(unpushed_commits_cmd(remote_branch))
        end

        # Generate ordered list of patches to apply/revert
        # @param sha_resolver [#call, nil] Optional resolver mapping suse commit SHA to linux git commit SHA
        # @yieldparam kern_sha [String] Kernel-source commit SHA
        # @yieldreturn [String, nil] Linux git commit SHA
        # @return [Array<String>] List of patch paths or revert commands
        def gen_ordered_patchlist(sha_resolver = nil, &block)
            up_ref = base()
            patch_order = []
            to_do_list = []
            f = File.open("#{@path}/series.conf", "r")
            f.each do |l|
                next if l !~ /^[ \t]+(patches.*)/
                patch_order << $1
            end
            f.close

            new_patches = runGit("diff \"#{up_ref}\"..HEAD -- series.conf").
                          split("\n").grep(/^\+[^+]/).grep_v(/^\+\s*#/).compact.map do |l|
                patch = l.split(/[ \t]/)[1]
                to_do_list[patch_order.index(patch)] = "#{@path}/#{patch}"
                patch
            end

            all_patches = runGit("diff \"#{up_ref}\"..HEAD --name-only").
                          split("\n").grep(/patches/).compact
            refreshed_patches = all_patches - new_patches

            # Queue refreshed patches to be reapplied at the right moment
            refreshed_patches.each do |p|
                next if patch_order.index(p).nil?

                to_do_list[patch_order.index(p)] = "#{@path}/#{p}"
            end
            to_do_list.compact!

            # Start the list by reverting the refreshed patches
            refreshed_patches.each do |p|
                kern_sha = runGit("log -n1 --diff-filter=A --format='%H' -- #{p}").chomp
                lin_sha = if block_given?
                              yield(kern_sha)
                          elsif sha_resolver
                              sha_resolver.call(kern_sha)
                          else
                              nil
                          end

                if lin_sha && !lin_sha.empty?
                    to_do_list.insert(0, "-#{lin_sha}")
                else
                    log(:WARNING, "Patch #{p} was edited but no matching commit found in linux tree")
                end
            end
            to_do_list
        end

        # Extract a single patch into kernel-source
        # @param commit [Commit] Commit to extract
        # @param ref [String, nil] Reference string override
        # @param filename [String, nil] Custom patch filename override
        # @param patch_path [String, nil] Custom patch path override
        # @param ignore_tag [Boolean] Ignore tag flag
        # @param yn_default [Symbol, nil] Default auto-reply (:yes or :no)
        # @return [void]
        # @raise [ShaNotCommitError] If commit is not a Commit object
        def extract_single_patch(commit, ref: nil, filename: nil, patch_path: nil, ignore_tag: false, yn_default: nil)
            raise ShaNotCommitError.new if !commit.is_a?(KernelWork::Commit)
            commit.check_patch_info(ignore_tag: ignore_tag)

            patch = Patch.new(self, commit, filename: filename)
            patch.generate(filename: filename, ref: ref, yn_default: yn_default)
            commit.patch = patch

            insert_and_commit_patch(commit, patch, yn_default: yn_default)
            @commit_ids[commit.sha] = true if @commit_ids != nil
        end

        # Insert the patch into series.conf and commit it to the SUSE repository
        # @param commit [Commit] The source commit
        # @param patch [Patch] Patch to commit
        # @param yn_default [Symbol, nil] Default auto-reply (:yes or :no)
        # @return [void]
        def insert_and_commit_patch(commit, patch, yn_default: nil)
            lpath = patch.localpath
            cname = run("mktemp")

            log(:INFO, "Generating commit message in #{cname}")
            subject = "#{commit.subject} (#{patch.ref})"
            f = File.open(cname, "w+")
            f.puts subject
            f.close

            log(:INFO, "Inserting patch")
            begin
                series_insert(lpath, yn_default: yn_default)
                runGitInteractive("add #{lpath}")
            rescue SCPAbort, SCPSkip => e
                runGit("rm -f #{lpath}")
                run("rm -f #{lpath} #{cname}")
                raise e
            end
            log(:INFO, "Commiting '#{subject}'")
            runGitInteractive("commit -F #{cname}")
            run("rm -f #{cname}")
        end

        # Insert a patch file into series.conf using the project's sort script
        # @param file [String] Path to the patch file
        # @param yn_default [Symbol, nil] Default auto-reply (:yes or :no)
        # @return [void]
        # @raise [SCPAbort] If user aborts interactive series insert
        # @raise [SCPSkip] If user skips interactive series insert
        def series_insert(file, yn_default: nil)
            if @branch_infos[:no_sorted_series] != true
                runSystem("./scripts/git_sort/series_insert \"#{file}\"")
                runGit("add series.conf")
            else
                log(:INFO, "No auto-sorted patch series on this branch")
                log(:INFO, "Please insert it yourself.")
                runSystem("PS1_WARNING='SERIES INSERT' bash", catch_err: true)
                rep = confirm({ yn_default: yn_default }, "continue with scp",
                              ignore_default: true,
                              allowed_reps: ["y", "n", "s"],
                              usage: "[y]es/[n]o/[s]kip")
                case rep
                when "n"
                    raise(SCPAbort)
                when "s"
                    e = SCPSkip.new(file)
                    log(:INFO, e.to_s)
                    raise(e)
                end
            end
        end

        # Auto fix conflicts in series.conf during rebases
        # @param yn_default [Symbol, nil] Default auto-reply (:yes or :no)
        # @return [void]
        # @raise [BlacklistConflictError] If blacklist.conf conflicts
        # @raise [EmptyCommitError] If no current patch found
        def fix_series(yn_default: nil)
            runGit("checkout -f HEAD -- series.conf")
            if blacklist_conflict?
                raise BlacklistConflictError.new
            end
            patch = nil
            begin
                patch = current_patch
            rescue
                log(:WARNING, "No current patch found. Skipping this commit")
                raise EmptyCommitError.new
            end
            series_insert(patch, yn_default: yn_default)
            runGitInteractive("status")
        end

        # Fix Git-mainline in the last patch
        # @return [void]
        def fix_mainline
            patch = last_patch
            commit = get_patch_commit(patch)
            tag = commit.get_mainline
            runSystem("sed -i -e 's/Patch-mainline:.*/Patch-mainline: #{tag}/' \"#{patch}\"")
            runGit("add \"#{patch}\"")
            runGitInteractive("diff --cached")
        end

        # Fix reference tag in patch and commit message
        # @param ref [String] New reference identifier
        # @return [void]
        def fix_ref(ref)
            patch = last_patch
            runSystem("sed -i -e 's/^References: git-fixes/References: #{ref}/' \"#{patch}\"")
            runGit("add \"#{patch}\"")
            runGitInteractive("diff --cached")
            cname = run("mktemp")
            begin
                runGit("log -1 --pretty=%B > #{cname}")
                run("sed -i -e 's/(git-fixes)/(#{ref})/' #{cname}")
                runGitInteractive("commit --amend -F #{cname}")
            rescue => e
                run("rm -f #{cname}")
                raise e
            end
        end

        # Fast or full checkpatch pass on pending patches
        # @param full [Boolean] Slower but thorougher checkpatch
        # @return [void]
        # @raise [CheckPatchError] If checkpatch fails
        def checkpatch(full: false)
            r_opt = full ? "" : " --rapid "
            begin
                runSystem("./scripts/sequence-patch #{r_opt}")
            rescue
                raise CheckPatchError
            end
        end

        # Meld the last patch with changes
        # @param linux_git_path [String, nil] Optional path to linux git repository
        # @return [void]
        def meld_lastpatch(linux_git_path = nil)
            lg_path = linux_git_path || KernelWork.config.linux_git
            file = last_patch
            runSystem("meld \"#{file}\" \"#{lg_path}\"/0001-*.patch")
            runSystem("git add \"#{file}\" && git amend --no-verify")
        end

        # Check for missing fixes using scripts/git-fixes
        # @return [void]
        def check_fixes
            log(:INFO, "Checking potential missing git-fixes between #{KernelWork.config.kernel_source.remote}/#{branch} and HEAD")
            runSystem("./scripts/git-fixes $(git rev-parse \"#{KernelWork.config.kernel_source.remote}/#{branch}\")")
        end

        # Rebase kernel-source directory to latest remote branch
        # @param remote_branch [String, nil] Target remote branch
        # @param autofix [Boolean] Attempt to autofix series.conf conflicts
        # @param interactive [Boolean] Use interactive rebase (-i)
        # @return [Integer] Exit code
        def rebase(remote_branch = nil, autofix: false, interactive: true)
            target = remote_branch || "#{KernelWork.config.kernel_source.remote}/#{branch}"
            int_opts = interactive ? "-i" : ""
            begin
                runGitInteractive("rebase #{int_opts} #{target}")
                0
            rescue
                ret = 1
                while autofix == true && ret != 0
                    log(:WARNING, "Trying to autofix series.conf")
                    rebase_opt = "--continue"
                    begin
                        fix_series
                    rescue EmptyCommitError
                        rebase_opt = "--skip"
                    rescue => e
                        log(:ERROR, e.to_s)
                        log(:ERROR, "Unable to handle auto fixing")
                        return 1
                    end
                    log(:WARNING, "Get on with rebasing")

                    begin
                        runGitInteractive("rebase #{rebase_opt}", env: "GIT_EDITOR=true")
                        ret = 0
                    rescue
                        ret = 1
                    end
                end
                ret
            end
        end

        # Push pending commits
        # @param force [Boolean] Force push
        # @return [void]
        def push(force: false)
            p_opts = force ? "--force " : ""
            log(:INFO, "Pending patches")
            unpushed_commits
            runGitInteractive("push #{p_opts}")
        end
    end
end
