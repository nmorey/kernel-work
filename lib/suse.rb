module KernelWork
    class NoRefError < RuntimeError
        def initialize()
            super("No bug/CVE ref provided nor default set")
        end
    end
    class CheckPatchError < RuntimeError
        def initialize()
            super("Patchlist does not apply")
        end
    end
    class EmptyCommitError < RuntimeError
    end
    class BlacklistConflictError < RuntimeError
        def initialize()
            super("Cannot auto-resolve blacklist.conf conflicts")
        end
    end
    class Suse < Common
        @@SUSE_REMOTE="origin"
        @@MAINT_BRANCHES=[
            { :name => "SLE12-SP3-TD",
              :ref => nil,
            },
            { :name => "SLE12-SP5",
              :ref => "git-fixes",
            },
            { :name => "SLE15-SP1",
              :ref => "bsc#1111666",
            },
            { :name => "SLE15-SP2",
              :ref => "bsc#1152489",
            },
            { :name => "SLE15-SP3",
              :ref => "git-fixes",
            },
            { :name => "SLE15-SP4",
              :ref => "git-fixes",
            },
            { :name => "SLE15-SP5",
              :ref => "git-fixes",
            },
            { :name => "SLE15-SP5-LTSS",
              :ref => "git-fixes",
            },
            { :name => "SLE15-SP6",
              :ref => "git-fixes",
            },
            { :name => "SLE15-SP7",
              :ref => "git-fixes",
            },
            { :name => "SUSE-2025",
              :ref => "git-fixes",
            },
            { :name => "SL-16.0",
              :ref => "git-fixes",
            },
            { :name => "SL-16.1",
              :ref => "git-fixes",
            },
            { :name => "SLE11-SP4-LTSS",
              :ref => nil,
            },
            { :name => "cve/linux-5.14-LTSS",
              :ref => nil,
            },
            { :name => "cve/linux-5.3-LTSS",
              :ref => nil,
            },
            { :name => "cve/linux-4.4-LTSS",
              :ref => nil,
            },
            { :name => "cve/linux-4.12",
              :ref => nil,
            },
        ]
        @@BR_LIST=@@MAINT_BRANCHES.map(){|x| x[:name]}
        @@Q_BRANCHES = [ "linux-rdma/for-rc", "linux-rdma/for-next" ]

        ACTION_LIST = [
            :source_rebase,
            :meld_lastpatch,
            :extract_patch,
            :fix_series,
            :checkpatch,
            :fix_mainline,
            :check_fixes,
            :list_commits, :lc,
            :push,
        ]
        ACTION_HELP = {
            :"*** KERNEL_SOURCE_DIR commands *** *" => "",
            :source_rebase => "Rebase KERNEL_SOURCE_DIR branch to the latest tip",
            :meld_lastpatch => "Meld the last KERNEL_SOURCE_DIR patch with LINUX_GIT/0001-*.patch and amend it",
            :extract_patch => "Pick a patch from the LINUX_GIT and commits it into KERNEL_SOURCE_DIR",
            :fix_series => "Auto fix conflicts in series.conf during rebases",
            :checkpatch => "Fast checkpatch pass on all pending patches",
            :fix_mainline => "Fix Git-mainline in the last KERNEL_SOURCE_DIR patch",
            :check_fixes => "Use KERNEL_SOURCE_DIR script to detect missing git-fixes pulled by commited patches",
            :list_commits => "List pending commits (default = unmerged)",
            :push=> "Push KERNEL_SOURCE_DIR pending patches",
        }

        def self.set_opts(action, optsParser, opts)
            opts[:sha1] = []
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
                    |val| opts[:sha1] << val}
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
            else
            end
        end

        def initialize(upstream = nil)
            @path=ENV["KERNEL_SOURCE_DIR"].chomp()
           begin
               set_branches()
           rescue UnknownBranch
               @branch = nil
           end

           @upstream = upstream
           @upstream = Upstream.new(self) if @upstream == nil

            @patch_path = "patches.suse"
            idx = @@BR_LIST.index(@branch)
            if idx == nil then
                log(:WARNING, "Branch '#{@branch}' not in supported list")
            else
                @branch_infos = @@MAINT_BRANCHES[idx]
                @patch_path = @branch_infos[:patch_path] if @branch_infos[:patch_path] != nil
            end
        end
        def branch()
            raise UnknownBranch.new(@path) if @branch == nil
            return @branch
        end
        def branch?(br)
            raise UnknownBranch.new(@path) if @branch == nil
            raise BranchMismatch.new(br, @branch) if br != @branch

            return @branch == br
        end
        def local_branch()
            raise UnknownBranch.new(@path) if @local_branch == nil
            return @local_branch
        end

        def get_last_patch(opts)
            runGit("show HEAD --stat --stat-width=1000 --no-decorate").
                split("\n").each().grep(/patches\.[^\/]*/)[0].lstrip().split(/[ \t]/)[0]
        end
        def get_current_patch(opts)
            runGit("diff --cached --stat --stat-width=1000").
                split("\n").each().grep(/patches\.[^\/]*/)[0].lstrip().split(/[ \t]/)[0]
        end
        def get_patch_commit_id(patchfile = nil)
            return runGit("grep Git-commit #{patchfile}").split(/[ \t]/)[-1]
        end
        def is_blacklist_conflict?(opts)
            begin
                return runGit("status --porcelain -- blacklist.conf").lstrip().split(/[ \t]/)[0] == "UU"
            rescue
                return false
            end
            # Useless but just in case
            return false
        end
        def get_mainline(sha)
            git_repo = nil
            orig_tag = nil
            begin
                orig_tag = @upstream.get_mainline(sha)
            rescue NoSuchMainline
                log(:INFO, "Commit not in any tag. Trying to find a maintainer branch")

                remote_branches=@upstream.runGit("branch -a --contains #{sha}").split("\n").
                                    each().grep(/remotes\//).map(){|x|
                    x.lstrip.split(/[ \t]/)[0].gsub(/remotes\//,'')}.
                                    each(){|r|
                    idx = @@Q_BRANCHES.index(r)
                    next if idx ==nil

                    log(:INFO, "Found it in #{@@Q_BRANCHES[idx]}")
                    orig_tag = "Queued in subsystem maintainer repository"
                    remote=@@Q_BRANCHES[idx].gsub(/\/.*/,'')
                    git_repo=@upstream.runGit("config remote.#{remote}.url")
                    break
                }
            end
            return orig_tag, git_repo
        end
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

        def gen_commit_id_list(opts)
            h={}
            run("git grep Git-commit: #{get_patch_dir(opts)} | awk '{ print $NF}'").
                chomp().split("\n").map(){|x|
                h[x] = true
            }
            return h
        end

        def get_patch_dir(opts)
            return opts[:patch_path] if opts[:patch_path] != nil
            return @patch_path
        end

        def patchname_to_local_path(opts, pname)
            return get_patch_dir(opts) + "/" + pname
        end
        def patchname_to_absolute_path(opts, pname)
            return ENV["KERNEL_SOURCE_DIR"] + "/" + patchname_to_local_path(opts, pname)
        end

        def fill_patchInfo_ref(h, override_cve = false)
            return if h[:cve] == true && override_cve == false 
            if h[:ref] == nil then
                h[:ref] = @branch_infos[:ref]
            end

            if h[:ref] == nil then
                e = NoRefError.new()
                log(:ERROR, e.to_s())
                raise e
            end
            return 0
        end

        # Find commit local branch started from upstream
        # so we can check local changes not in upstream and not break everything
        # when upstream has moved forward
        def get_upstream_base()
            return runGit("merge-base HEAD #{@@SUSE_REMOTE}/#{branch()}")
        end

        def do_meld_lastpatch(opts)
            file = get_last_patch(opts)
            runSystem("meld \"#{file}\" \"#{ENV["LINUX_GIT"]}\"/0001-*.patch")
            runSystem("git add \"#{file}\" && git amend --no-verify")
            return
        end

        def do_checkpatch(opts)
            rOpt = " --rapid "
            rOpt = "" if opts[:full_check] == true
            begin
                runSystem("./scripts/sequence-patch #{rOpt}")
            rescue
                raise CheckPatchError
            end
            return 0
        end

        def is_applied?(sha)
            begin
                runGit("grep -q #{sha}", {})
                return true
            rescue
                return false
            end
        end
        def list_unmerged(opts)
            runGitInteractive("log --no-decorate  --format=oneline \"^#{@@SUSE_REMOTE}/#{branch()}\" HEAD")
            return 0
        end
        def list_unpushed(opts)
            remoteRefs=" \"^#{@@SUSE_REMOTE}/#{branch()}\""
            begin
                runGit("rev-parse --verify --quiet #{@@SUSE_REMOTE}/#{local_branch()}")
                remoteRefs += " \"^#{@@SUSE_REMOTE}/#{local_branch()}\""
            rescue
                log(:INFO, "Remote user branch does not exists. Checking against main branch only.")
                # Remote user branch does not exists
            end
            runGitInteractive("log --no-decorate  --format=oneline #{remoteRefs} HEAD")

            return 0
        end

        #
        # ACTIONS
        #
        public
        def source_rebase(opts)
            intOpts="-i"
            if opts[:no_interactive] == true
                intOpts = ""
            end
            begin
                runGitInteractive("rebase #{intOpts} #{@@SUSE_REMOTE}/#{branch()}")
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

        def meld_lastpatch(opts)
            begin
                do_meld_lastpatch(opts)
            rescue
                return 1
            end
            return 0
        end

        def extract_single_patch(opts, sha)
            patchInfos = _check_patch_info(opts, sha)
            return 1 if patchInfos == nil

            # Generate the patch in the linux tree and get its name at the same time
            patchInfos[:lin_ppath] = @upstream.runGit("format-patch -n1 #{sha}")

            # Generate the patch name in KERN tree and check its availability
            ret = _gen_patch_name(opts, patchInfos)
            return ret if ret != 0

            _copy_and_fill_patch(opts, patchInfos)

            runGitInteractive("add #{patchInfos[:ker_local_path]}")

            refs = opts[:ref]
            if opts[:cve] == true then
                ret = _patch_fill_in_CVE(opts, patchInfos)
                return ret if ret != 0
           end

            return _insert_and_commit_patch(opts, patchInfos)
        end

        def extract_patch(opts)
            fill_patchInfo_ref(opts)
            if opts[:sha1].length == 0 then
                log(:ERROR, "No SHA1 provided")
                return 1
            end

            opts[:sha1].each(){|sha|
                ret = extract_single_patch(opts, sha)
                return ret if ret != 0
            }
            return 0
        end
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
            return 0
        end
        def checkpatch(opts)
            begin
                do_checkpatch(opts)
            rescue => e
                log(:ERROR, e.to_s())
            end
            return 0
        end
        def fix_mainline(opts)
            patch = get_last_patch(opts)
            sha = get_patch_commit_id(patch)
            tag = @upstream.get_mainline(sha)
            runSystem("sed -i -e 's/Patch-mainline:.*/Patch-mainline: #{tag}/' \"#{patch}\"")
            runGit("add \"#{patch}\"")
            runGitInteractive("diff --cached")
            return 0
        end
        def check_fixes(opts)
            log(:INFO, "Checking potential missing git-fixes between #{@@SUSE_REMOTE}/#{branch()} and HEAD")
            runSystem("./scripts/git-fixes  $(git rev-parse \"#{@@SUSE_REMOTE}/#{branch()}\")")
            return 0
        end

        def list_commits(opts)
            case opts[:list_commits]
            when :unpushed
                return list_unpushed(opts)
            when :unmerged
                return list_unmerged(opts)
            end
        end
        alias_method :lc, :list_commits

        def push(opts)
            pOpts=""
            log(:INFO, "Pending patches")
            list_unpushed(opts)
            pOpts+= "--force " if opts[:force_push] == true
            runGitInteractive("push #{pOpts}")
            return 0
        end
        ###########################################
        #### PRIVATE methods                   ####
        ###########################################
        private
        def _check_patch_info(opts, sha)
            f_sha1 = nil
            begin
                f_sha1 = @upstream.runGit("rev-parse #{sha}")
            rescue RunError
                log(:ERROR, "Failed to find commit #{sha}")
                return nil
            end

            orig_tag, git_repo = get_mainline(sha)
            if orig_tag == "" then
                if opts[:ignore_tag] != true then
                    log(:ERROR, "Commit is not contained in any tag nor maintainer repo")
                    return nil
                else
                    orig_tag="Never, in-house patch"
                    f_sha1=nil
                end
            end

            return {
                :sha => sha,
                :f_sha => f_sha1,
                :orig_tag => orig_tag,
                :git_repo => git_repo,
                :ref => opts[:ref]
            }
        end

        def _gen_patch_name(opts, patchInfos)
            pname= patchInfos[:lin_ppath].gsub(/^0001-/,"")
            # Default name might be overriden from CLI
            pname = opts[:filename] if opts[:filename] != nil

            fpath=patchname_to_absolute_path(opts, pname)
            while File.exist?(fpath) do
                log(:ERROR, "File '#{pname}' already exists in KERNEL_SOURCE_DIR")
                return 1 if opts[:filename] != nil

                # If user has not specified a name, try to prompt him for one
                rep= confirm(opts, "set a custom filename", true, ["y", "n"])
                if rep == "n" then
                    log(:ERROR, "Aborting")
                    return 1
                end

                rep="t"
                nName=nil
                while rep != "y"
                    puts "Enter a filename (auto name was: #{pname} ):"
                    nName=STDIN.gets.chomp()
                    rep = confirm(opts, "keep the filename '#{nName}'", true, ["y", "n", "A" ])
                    if rep == "A" then
                        log(:ERROR, "Aborting")
                        return 1
                    end
                end
                pname = nName
                fpath=patchname_to_absolute_path(opts, pname)
            end
            patchInfos[:ker_pname] = pname
            patchInfos[:ker_local_path] = patchname_to_local_path(opts, pname)
            patchInfos[:ker_full_path] = patchname_to_absolute_path(opts, pname)
            return 0
        end

        def _copy_and_fill_patch(opts, patchInfos)
            i = File.open(ENV["LINUX_GIT"] + "/" + patchInfos[:lin_ppath],"r")
            o = File.open(patchInfos[:ker_full_path] , "w+")

            p_split=0
            in_subj=false
            i.each(){|l|
                case l
                when /^Subject: \[PATCH/
                    in_subj=true
                    o.puts l
                when /^\n$/
                    if in_subj == true
                        o.puts "Git-commit: #{patchInfos[:f_sha]}" if patchInfos[:f_sha] != nil
                        o.puts "Patch-mainline: #{patchInfos[:orig_tag]}" if patchInfos[:orig_tag] != nil
                        o.puts "References: #{patchInfos[:ref]}"
                        o.puts "Git-repo: #{patchInfos[:git_repo]}" if patchInfos[:git_repo] != nil
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
            return 0
        end

        def _insert_and_commit_patch(opts, patchInfos)
            lpath = patchInfos[:ker_local_path]
            cname=run("mktemp")

            log(:INFO, "Generating commit message in #{cname}")
            subject=@upstream.runGit("show --format='format:%s' --no-patch #{patchInfos[:sha]}") +
                    " (#{patchInfos[:ref]})"
            f = File.open(cname, "w+")
            f.puts subject
            f.close()

            log(:INFO, "Inserting patch")
            _series_insert(opts, lpath)
            runGitInteractive("add #{lpath}")

            log(:INFO, "Commiting '#{subject}'")
            runGitInteractive("commit -F #{cname}")
            run("rm -f #{cname}")
            return 0
        end

        def _patch_fill_in_CVE(opts, patchInfos)
            lpath = patchInfos[:ker_local_path]
            log(:INFO, "Auto referencing CVE id and BSC")
            runSystem("echo '#{lpath}' | suse-add-cves  -v $VULNS_GIT  -f")
            begin
                newRefs=run("git diff -U0 -- #{lpath}").split("\n").
                            grep(/^\+References/)[0].gsub(/^\+References: +/, "")
                patchInfos[:ref] = newRefs
            rescue => e
                log(:WARNING, "No CVE reference found")

                if patchInfos[:ref] == nil then
                    # We have not set any ref as we were expecting CVE ones.
                    # Get the default ref and we need to update the patch file with it
                    ret = fill_patchInfo_ref(patchInfos, true)
                    return ret if ret != 0

                    run("sed -i -e 's/^References: $/References: #{patchInfos[:ref]}/' #{lpath}")
                end
            end
            runGitInteractive("add #{lpath}")
            return 0
        end

        def _series_insert(opts, file)
            runSystem("./scripts/git_sort/series_insert \"#{file}\"")
            runGit("add series.conf")
        end
   end
end
