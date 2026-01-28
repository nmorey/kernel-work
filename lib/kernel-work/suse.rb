require 'yaml'
require 'fileutils'

module KernelWork

    # Class for handling SUSE kernel source directory operations
    class Suse < Common

        # List of available actions for Suse class
        ACTION_LIST = [
            :source_rebase,
            :meld_lastpatch,
            :extract_patch,
            :fix_series,
            :checkpatch,
            :fix_mainline,
            :fix_ref,
            :check_fixes,
            :list_commits, :lc,
            :push,
            :register_branch,
        ]
        # Help text for actions
        ACTION_HELP = {
            :"*** KERNEL_SOURCE_DIR commands *** *" => "",
            :source_rebase => "Rebase KERNEL_SOURCE_DIR branch to the latest tip",
            :meld_lastpatch => "Meld the last KERNEL_SOURCE_DIR patch with LINUX_GIT/0001-*.patch and amend it",
            :extract_patch => "Pick a patch from the LINUX_GIT and commits it into KERNEL_SOURCE_DIR",
            :fix_series => "Auto fix conflicts in series.conf during rebases",
            :checkpatch => "Fast checkpatch pass on all pending patches",
            :fix_mainline => "Fix Git-mainline in the last KERNEL_SOURCE_DIR patch",
            :fix_ref => "Fix ref in the in the last KERNEL_SOURCE_DIR commit",
            :check_fixes => "Use KERNEL_SOURCE_DIR script to detect missing git-fixes pulled by commited patches",
            :list_commits => "List pending commits (default = unmerged)",
            :push=> "Push KERNEL_SOURCE_DIR pending patches",
            :register_branch => "Register a branch for maintenance in config.yml",
        }

        # Set options for Suse actions
        #
        # @param action [Symbol] The action
        # @param optsParser [OptionParser] The option parser
        # @param opts [Hash] The options hash
        def self.set_opts(action, optsParser, opts)
            opts[:commits] = []
            opts[:full_check] = false
            opts[:autofix] = false
            opts[:force_push] = false
            opts[:list_commits] = :unmerged

            case action
            when :source_rebase
                 optsParser.on("-A", "--autofix", "Try to autofix series.conf.") {
                    |val| opts[:autofix] = true}
                 optsParser.on("-I", "--no-interactive", "Rebase 'dumbly' not interactively.") {
                    |val| opts[:no_interactive] = true}
            when :extract_patch
                optsParser.on("-c", "--sha1 <SHA1>", String, "Commit to backport.") {
                    |val| opts[:commits] << KernelWork::Commit.new(val)}
                optsParser.on("-r", "--ref <ref>", String, "Bug reference.") {
                    |val| opts[:ref] = val}
                optsParser.on("-C", "--cve", "Auto extract reference from VULNS."){
                    |val| opts[:cve] = true }
                optsParser.on("-i", "--ignore-tag", "Ignore missing tag or maintainer branch.") {
                    |val| opts[:ignore_tag] = true}
                optsParser.on("-f", "--filename <file.patch>", "Custom patch filename.") {
                    |val| opts[:filename] = val}
                optsParser.on("-P", "--patch-path <patch/dir/>", "Custom patch dir. Default is patches.suse unless overriden by branch settings") {
                    |val| opts[:patch_path] = val}
            when :push
                optsParser.on("-f", "--force", "Force push.") {
                    |val| opts[:force_push] = true}
            when :checkpatch
                optsParser.on("-F", "--full", "Slower but thorougher checkpatch.") {
                    |val| opts[:full_check] = true}
            when :list_commits, :lc
                optsParser.on("--unpushed", "List unpushed commits.") {
                    |val| opts[:list_commits] = :unpushed}
                optsParser.on("--unmerged", "List unmerged commits.") {
                    |val| opts[:list_commits] = :unmerged}
            when :register_branch
                optsParser.on("-b", "--branch <branch>", String, "Branch name.") {
                    |val| opts[:branch] = val}
                optsParser.on("-r", "--ref <ref>", String, "Default reference.") {
                    |val| opts[:ref] = val}
            when :fix_ref
                optsParser.on("-r", "--ref <ref>", String, "Bug reference.") {
                    |val| opts[:ref] = val}
            else
            end
        end

        # Check options for validity
        #
        # @param opts [Hash] The options hash
        # @raise [RuntimeError] If required options are missing
        def self.check_opts(opts)
            case opts[:action]
            when :register_branch
                if opts[:branch].nil?
                    raise("Branch name is required. Use -b <branch>")
                end
            when :fix_ref
                if opts[:ref].nil?
                    raise("Ref is required. Use -r <ref>")
                end
            end
        end

        # Initialize a new Suse object
        #
        # @param upstream [Upstream, nil] Upstream object
        def initialize(upstream = nil)
            @path=KernelWork.config.kernel_source_dir
           begin
               set_branches()
           rescue UnknownBranch
               @branch = nil
           end

           @upstream = upstream
           @upstream = Upstream.new(self) if @upstream == nil

            @patch_path = "patches.suse"

            # Access branches directly from config
            branches = KernelWork.config.suse.branches

            # Find branch info
            @branch_infos = branches.find { |b| b[:name] == @branch }

            if @branch_infos == nil then
                log(:WARNING, "Branch '#{@branch}' not in supported list")
                @branch_infos = {}
            else
                @patch_path = @branch_infos[:patch_path] if @branch_infos[:patch_path] != nil
            end
        end

        # Get current branch
        # @return [String] Branch name
        # @raise [UnknownBranch] If branch is not detected
        def branch()
            raise UnknownBranch.new(@path) if @branch == nil
            return @branch
        end

        # Check if current branch matches expected
        # @param br [String] Expected branch
        # @return [Boolean] True if match
        # @raise [UnknownBranch] If branch is not detected
        # @raise [BranchMismatch] If branches do not match
        def branch?(br)
            raise UnknownBranch.new(@path) if @branch == nil
            raise BranchMismatch.new(br, @branch) if br != @branch

            return @branch == br
        end

        # Get local branch name
        # @return [String] Local branch name
        # @raise [UnknownBranch] If branch is not detected
        def local_branch()
            raise UnknownBranch.new(@path) if @local_branch == nil
            return @local_branch
        end

        # Get the filename of the last applied patch
        # @param opts [Hash] Options hash
        # @return [String] Filename
        def get_last_patch(opts)
            runGit("show HEAD --stat --stat-width=1000 --no-decorate").
                split("\n").each().grep(/patches\.[^\/]*/).grep(/ \++$/)[0].lstrip().split(/[ \t]/)[0]
        end

        # Get the filename of the currently modified patch
        # @param opts [Hash] Options hash
        # @return [String] Filename
        def get_current_patch(opts)
            runGit("diff --cached --stat --stat-width=1000").
                split("\n").each().grep(/patches\.[^\/]*/).grep(/ \++$/)[0].lstrip().split(/[ \t]/)[0]
        end

        # Get the Git-commit ID from a patch file
        # @param patchfile [String] Path to patch file
        # @return [String] Commit SHA
        def get_patch_commit_id(patchfile = nil)
            return runGit("grep Git-commit #{patchfile}").split(/[ \t]/)[-1]
        end

        # Check for blacklist.conf conflict
        # @param opts [Hash] Options hash
        # @return [Boolean] True if conflict exists
        def is_blacklist_conflict?(opts)
            begin
                return runGit("status --porcelain -- blacklist.conf").lstrip().split(/[ \t]/)[0] == "UU"
            rescue
                return false
            end
            # Useless but just in case
            return false
        end

        # Generate ordered list of patches to apply/revert
        # @return [Array<String>] List of patch paths or revert commands
        def gen_ordered_patchlist()
            up_ref = get_upstream_base()
            patchOrder = []
            toDoList = []
            kernGitCommit = {}
            f = File.open("#{@path}/series.conf", "r")
            f.each(){|l|
                next if l !~ /^[ \t]+(patches.*)/
                patchOrder << $1
            }

            newPatches = runGit("diff \"#{up_ref}\"..HEAD -- series.conf").
                          split("\n").each().grep(/^\+[^+]/).grep_v(/^\+\s*#/).compact().map(){|l|
                 patch = l.split(/[ \t]/)[1]
                 toDoList[patchOrder.index(patch)] = "#{@path}/#{patch}"
                 patch
            }

            allPatches = runGit("diff \"#{up_ref}\"..HEAD --name-only").
                             split("\n").grep(/patches/).compact()
            refreshedPatches = allPatches - newPatches
            # Queue refreshed patches to be reapplied at the right moment
            refreshedPatches.each(){|p|
                # Reverted patch. Will be seen as refreshed without a new one being applied
                next if patchOrder.index(p) == nil

                # Regular refresh
                toDoList[patchOrder.index(p)] = "#{@path}/#{p}"
            }
            toDoList.compact!()
            # Start the list by reverting the refreshed patches
            # But we actually need the linux tree commit id here...
            refreshedPatches.each(){|p|
                kernSha = runGit("log -n1 --diff-filter=A --format='%H' -- #{p}").chomp()
                linSha = @upstream.runGit("log -n1 --format='%H'  --grep 'suse-commit: #{kernSha}'").chomp()
                toDoList.insert(0, "-#{linSha}")
            }
            return toDoList
        end

        # Generate a list of commit IDs already in the patch directory
        # @param opts [Hash] Options hash
        # @return [Hash] Hash with SHA keys and true values
        def gen_commit_id_list(opts)
            h={}
            run("git grep Git-commit: #{get_patch_dir(opts)} | awk '{ print $NF}'").
                chomp().split("\n").map(){|x|
                h[x] = true
            }
            return h
        end

        # Get the patch directory path
        # @param opts [Hash] Options hash
        # @return [String] Path to patch directory
        def get_patch_dir(opts)
            return opts[:patch_path] if opts[:patch_path] != nil
            return @patch_path
        end

        # Convert patch name to local path
        # @param opts [Hash] Options hash
        # @param pname [String] Patch name
        # @return [String] Local path
        def patchname_to_local_path(opts, pname)
            return get_patch_dir(opts) + "/" + pname
        end

        # Convert patch name to absolute path
        # @param opts [Hash] Options hash
        # @param pname [String] Patch name
        # @return [String] Absolute path
        def patchname_to_absolute_path(opts, pname)
            return KernelWork.config.kernel_source_dir + "/" + patchname_to_local_path(opts, pname)
        end

        # Fill in target patch reference if missing
        # @param h [Hash] Target patch info
        # @param override_cve [Boolean] Whether to override CVE
        # @raise [NoRefError] If no reference can be found
        def fill_targetPatch_ref(h, override_cve = false)
            return if h[:cve] == true && override_cve == false
            if h[:ref] == nil then
                h[:ref] = @branch_infos[:ref]
            end

            if h[:ref] == nil then
                e = NoRefError.new()
                log(:ERROR, e.to_s())
                raise e
            end
        end

        # Find commit local branch started from upstream
        # so we can check local changes not in upstream and not break everything
        # when upstream has moved forward
        # @return [String] SHA of merge base
        def get_upstream_base()
            return runGit("merge-base HEAD #{KernelWork.config.suse.remote}/#{branch()}")
        end

        # Meld the last patch with changes
        # @param opts [Hash] Options hash
        # @return [void]
        def do_meld_lastpatch(opts)
            file = get_last_patch(opts)
            runSystem("meld \"#{file}\" \"#{KernelWork.config.linux_git}\"/0001-*.patch")
            runSystem("git add \"#{file}\" && git amend --no-verify")
        end

        # Run checkpatch on the current state
        # @param opts [Hash] Options hash
        # @return [void]
        # @raise [CheckPatchError] If checkpatch fails
        def do_checkpatch(opts)
            rOpt = " --rapid "
            rOpt = "" if opts[:full_check] == true
            begin
                runSystem("./scripts/sequence-patch #{rOpt}")
            rescue
                raise CheckPatchError
            end
        end

        # Check if a commit is already applied
        # @param sha [Commit, String] Commit or SHA
        # @return [Boolean] True if applied
        def is_applied?(sha)
            sha = sha.sha if sha.is_a?(Commit)
            begin
                runGit("grep -q #{sha}", {})
                return true
            rescue
                return false
            end
        end

        # List unmerged commits
        # @param opts [Hash] Options hash
        # @return [void]
        def list_unmerged(opts)
            runGitInteractive("log --no-decorate  --format=oneline \"^#{KernelWork.config.suse.remote}/#{branch()}\" HEAD")
        end

        # List unpushed commits
        # @param opts [Hash] Options hash
        # @return [void]
        def list_unpushed(opts)
            remoteRefs=" \"^#{KernelWork.config.suse.remote}/#{branch()}\""
            begin
                runGit("rev-parse --verify --quiet #{KernelWork.config.suse.remote}/#{local_branch()}")
                remoteRefs += " \"^#{KernelWork.config.suse.remote}/#{local_branch()}\""
            rescue
                log(:INFO, "Remote user branch does not exists. Checking against main branch only.")
                # Remote user branch does not exists
            end
            runGitInteractive("log --no-decorate  --format=oneline #{remoteRefs} HEAD")
        end

        #
        # ACTIONS
        #
        public
        # Rebase kernel-source directory
        # @param opts [Hash] Options hash
        # @return [Integer] Exit code
        def source_rebase(opts)
            intOpts="-i"
            if opts[:no_interactive] == true
                intOpts = ""
            end
            begin
                runGitInteractive("rebase #{intOpts} #{KernelWork.config.suse.remote}/#{branch()}")
            rescue
                ret = 1
                while opts[:autofix] == true && ret != 0
                    log(:WARNING, "Trying to autofix series.conf")
                    rebaseOpt="--continue"
                    begin
                        fix_series(opts)
                    rescue EmptyCommitError
                        rebaseOpt="--skip"
                    rescue => e
                        log(:ERROR, e.to_s())
                        log(:ERROR, "Unable to handle auto fixing")
                        return 1
                    end
                    log(:WARNING, "Get on with rebasing")

                    begin
                        runGitInteractive("rebase #{rebaseOpt}", { :env => "GIT_EDITOR=true"})
                        ret = 0
                    rescue
                        ret = 1
                    end
                end
                return ret
            end
        end

        # Meld last patch action
        # @param opts [Hash] Options hash
        # @return [void]
        def meld_lastpatch(opts)
            begin
                do_meld_lastpatch(opts)
            rescue
                return 1
            end
        end

        # Extract a single patch
        # @param opts [Hash] Options hash
        # @param commit [Commit] Commit to extract
        # @return [void]
        # @raise [ShaNotCommitError] If commit is not a Commit object
        # @raise [PatchInfoError] If patch info check fails
        def extract_single_patch(opts, commit)
            raise ShaNotCommitError.new() if !commit.is_a?(KernelWork::Commit)
            commit.check_patch_info(opts)

            # Generate the patch name in KERN tree and check its availability
            targetPatch = _gen_patch_name(opts, commit)

            _copy_and_fill_patch(opts, commit, targetPatch)

            runGitInteractive("add #{targetPatch[:local_path]}")

            refs = opts[:ref]
            if opts[:cve] == true then
                _patch_fill_in_CVE(opts, commit, targetPatch)
            end

            _insert_and_commit_patch(opts, commit, targetPatch)
        end

        # Extract patches action
        # @param opts [Hash] Options hash
        # @return [void]
        # @raise [MissingArgumentError] If no commits are provided
        def extract_patch(opts)
            fill_patchInfo_ref(opts)
            if opts[:commits].length == 0 then
                raise MissingArgumentError.new("No SHA1 provided")
            end

            opts[:commits].each(){|sha|
                extract_single_patch(opts, sha)
            }
        end

        # Fix series.conf action
        # @param opts [Hash] Options hash
        # @return [void]
        # @raise [BlacklistConflictError] If blacklist.conf conflicts
        # @raise [EmptyCommitError] If no current patch found
        def fix_series(opts)
            runGit("checkout -f HEAD -- series.conf")
            patch = nil
            if is_blacklist_conflict?(opts) then
                raise BlacklistConflictError.new()
            end
            begin
                patch = get_current_patch(opts)
            rescue
                log(:WARNING, "No current patch found. Skipping this commit")
                raise EmptyCommitError.new()
            end
            _series_insert(opts, patch)
            runGitInteractive("status")
        end

        # Checkpatch action
        # @param opts [Hash] Options hash
        # @return [void]
        def checkpatch(opts)
            begin
                do_checkpatch(opts)
            rescue => e
                log(:ERROR, e.to_s())
                return 1
            end
        end

        # Fix mainline tag in patch
        # @param opts [Hash] Options hash
        # @return [void]
        def fix_mainline(opts)
            patch = get_last_patch(opts)
            sha = get_patch_commit_id(patch)
            tag = @upstream.get_mainline(sha)
            runSystem("sed -i -e 's/Patch-mainline:.*/Patch-mainline: #{tag}/' \"#{patch}\"")
            runGit("add \"#{patch}\"")
            runGitInteractive("diff --cached")
        end

        # Fix ref tag in patch and commit message
        # @param opts [Hash] Options hash
        # @return [void]
        def fix_ref(opts)
            patch = get_last_patch(opts)
            runSystem("sed -i -e 's/^References: git-fixes/References: #{opts[:ref]}/' \"#{patch}\"")
            runGit("add \"#{patch}\"")
            runGitInteractive("diff --cached")
            cname=run("mktemp")
            begin
                runGit("log -1 --pretty=%B > #{cname}")
                run("sed -i -e 's/(git-fixes)/(#{opts[:ref]})/' #{cname}")
                runGitInteractive("commit --amend -F #{cname}")
            rescue => e
                run("rm -f #{cname}")
                raise e
            end
        end

        # Check for missing fixes
        # @param opts [Hash] Options hash
        # @return [void]
        def check_fixes(opts)
            log(:INFO, "Checking potential missing git-fixes between #{KernelWork.config.suse.remote}/#{branch()} and HEAD")
            runSystem("./scripts/git-fixes  $(git rev-parse \"#{KernelWork.config.suse.remote}/#{branch()}\")")
        end

        # List commits action
        # @param opts [Hash] Options hash
        # @return [void]
        def list_commits(opts)
            case opts[:list_commits]
            when :unpushed
                return list_unpushed(opts)
            when :unmerged
                return list_unmerged(opts)
            end
        end
        alias_method :lc, :list_commits

        # Push action
        # @param opts [Hash] Options hash
        # @return [void]
        def push(opts)
            pOpts=""
            log(:INFO, "Pending patches")
            list_unpushed(opts)
            pOpts+= "--force " if opts[:force_push] == true
            runGitInteractive("push #{pOpts}")
        end

        # Register a branch
        # @param opts [Hash] Options hash
        # @return [void]
        def register_branch(opts)
            branches = KernelWork.config.settings[:suse][:branches]

            # Check if branch exists
            idx = branches.index { |b| b[:name] == opts[:branch] }

            entry = { :name => opts[:branch], :ref => opts[:ref] }

            if idx
                log(:INFO, "Updating existing branch '#{opts[:branch]}'")
                branches[idx] = entry
            else
                log(:INFO, "Registering new branch '#{opts[:branch]}'" )
                branches << entry
            end

            KernelWork.config.save_config
            log(:INFO, "Configuration saved to #{KernelWork.config.config_file}")
        end
        ###########################################
        #### PRIVATE methods                   ####
        ###########################################
        private

        # Generate a unique patch name, prompting the user if a conflict exists.
        #
        # @param opts [Hash] Options including potential custom filename
        # @param commit [Commit] The commit to generate a name for
        # @return [Hash] Patch metadata (pname, local_path, full_path, ref)
        # @raise [TargetFileExistsError] If target file exists and filename is provided via opts
        # @raise [SCPAbort] If user aborts conflict resolution
        def _gen_patch_name(opts, commit)
            pname= commit.patchname().gsub(/^0001-/,"")
            # Default name might be overriden from CLI
            pname = opts[:filename] if opts[:filename] != nil

            fpath=patchname_to_absolute_path(opts, pname)
            while File.exist?(fpath) do
                if opts[:filename] != nil
                    raise TargetFileExistsError.new(pname)
                end

                log(:ERROR, "File '#{pname}' already exists in KERNEL_SOURCE_DIR")

                # If user has not specified a name, try to prompt him for one
                rep= confirm(opts, "set a custom filename", true, ["y", "n"])
                if rep == "n" then
                    raise SCPAbort.new("User aborted filename selection")
                end

                rep="t"
                nName=nil
                while rep != "y"
                    puts "Enter a filename (auto name was: #{pname} ):"
                    nName=STDIN.gets.chomp()
                    rep = confirm(opts, "keep the filename '#{nName}'", true, ["y", "n", "A" ])
                    if rep == "A" then
                        raise SCPAbort.new("User aborted filename selection")
                    end
                end
                pname = nName
                fpath=patchname_to_absolute_path(opts, pname)
            end

            return {
                :pname => pname,
                :local_path => patchname_to_local_path(opts, pname),
                :full_path => patchname_to_absolute_path(opts, pname),
                :ref => opts[:ref],
            }
        end

        # Copy a patch from the Linux tree and fill in custom headers (Git-commit, Patch-mainline, etc.)
        #
        # @param opts [Hash] Options hash
        # @param commit [Commit] The source commit
        # @param targetPatch [Hash] Destination patch metadata
        # @return [void]
        def _copy_and_fill_patch(opts, commit, targetPatch)
            i = File.open(KernelWork.config.linux_git + "/" + commit.patchname,"r")
            o = File.open(targetPatch[:full_path] , "w+")

            p_split=0
            in_subj=false
            i.each(){|l|
                case l
                when /^Subject: \[PATCH/
                    in_subj=true
                    o.puts l
                when /^\n$/
                    if in_subj == true
                        o.puts "Git-commit: #{commit.f_sha()}" if commit.f_sha() != ""
                        o.puts "Patch-mainline: #{commit.orig_tag()}" if commit.orig_tag() != nil
                        o.puts "References: #{targetPatch[:ref]}"
                        o.puts "Git-repo: #{commit.git_repo()}" if commit.git_repo() != nil
                        in_subj=false
                    end
                    o.puts l
                when /^---\n$/
                    if p_split == 0 then
                        name=runGit("config --get user.name")
                        email=runGit("config --get user.email")
                        o.puts "Acked-by: #{name} <#{email}>"
                        p_split = 1
                    end
                    o.puts l
                else
                    o.puts l
                end
            }
            i.close()
            o.close()
            File.delete(i)
        end

        # Insert the patch into series.conf and commit it to the SUSE repository
        #
        # @param opts [Hash] Options hash
        # @param commit [Commit] The source commit
        # @param targetPatch [Hash] Target patch metadata
        # @return [void]
        def _insert_and_commit_patch(opts, commit, targetPatch)
            lpath = targetPatch[:local_path]
            cname=run("mktemp")

            log(:INFO, "Generating commit message in #{cname}")
            subject="#{commit.subject()} (#{targetPatch[:ref]})"
            f = File.open(cname, "w+")
            f.puts subject
            f.close()

            log(:INFO, "Inserting patch")
            _series_insert(opts, lpath)
            runGitInteractive("add #{lpath}")

            log(:INFO, "Commiting '#{subject}'")
            runGitInteractive("commit -F #{cname}")
            run("rm -f #{cname}")
        end

        # Automatically extract CVE and BSC references for a patch using suse-add-cves
        #
        # @param opts [Hash] Options hash
        # @param commit [Commit] The source commit
        # @param targetPatch [Hash] Target patch metadata
        # @return [void]
        def _patch_fill_in_CVE(opts, commit, targetPatch)
            lpath = targetPatch[:local_path]
            log(:INFO, "Auto referencing CVE id and BSC")
            runSystem("echo '#{lpath}' | suse-add-cves  -v $VULNS_GIT  -f")
            begin
                newRefs=run("git diff -U0 -- #{lpath}").split("\n").
                            grep(/^\+References/)[0].gsub(/^\+References: +/, "")
                targetPatch[:ref] = newRefs
            rescue => e
                log(:WARNING, "No CVE reference found")

                if targetPatch[:ref] == nil then
                    # We have not set any ref as we were expecting CVE ones.
                    # Get the default ref and we need to update the patch file with it
                    fill_targetPatch_ref(targetPatch, true)

                    run("sed -i -e 's/^References: $/References: #{targetPatch[:ref]}/' #{lpath}")
                end
            end
            runGitInteractive("add #{lpath}")
        end

        # Insert a patch file into series.conf using the project's sort script
        #
        # @param opts [Hash] Options hash
        # @param file [String] Path to the patch file
        def _series_insert(opts, file)
            runSystem("./scripts/git_sort/series_insert \"#{file}\"")
            runGit("add series.conf")
        end
    end
end
