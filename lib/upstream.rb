require 'csv'
module KernelWork

    # SCP Abort by user input
    class SCPAbort < RuntimeError
    end
    # SCP of this patch skipped by user
    class SCPSkip < RuntimeError
        def initialize(s="")
            super("Skipping patch #{s}")
        end
    end
    # Failed to retrieve GitFixes
    class GitFixesFetchError < RuntimeError
    end
    # Failed to find a mainline tag containing a sha
    class NoSuchMainline < RuntimeError
    end
    # Failed to find which kernel version we are based on
    class BaseKernelError < RuntimeError
    end

    class Upstream < Common
        @@UPSTREAM_REMOTE="SUSE"
        @@GIT_FIXES_URL="http://w3.suse.de/~jroedel/fixes-csv/"
        @@GIT_FIXES_SUBTREE="infiniband"

        DEFAULT_J_OPT="$(nproc --all --ignore=4)"
        SUPPORTED_ARCHS = {
            "x86_64" => {
                :CC => "CC=\"ccache gcc\"",
            },
            "arm64" => {
                :CC => "CC=\"ccache aarch64-suse-linux-gcc\"",
                :CROSS_COMPILE => "CROSS_COMPILE=aarch64-suse-linux-",
                :ARCH => "ARCH=arm64",
            }
        }
        ACTION_LIST = [
            :apply_pending,
            :scp,
            :build_oldconfig,
            :build_all,
            :build_infiniband,
            :build_subset,
            :diffpaths,
            :kabi_check,
            :backport_todo,
            :git_fixes,
        ]
        ACTION_HELP = {
            :"*** LINUX_GIT commands *** *" => "",
            :apply_pending => "Reset LINUX_GIT branch and reapply all unmerged patches from kernel-source",
            :scp => "Show commit, cherry-pick to LINUX_GIT then apply to KERNEL_SOURCE if all is OK",
            :build_oldconfig => "Copy config from KERNEL_SOURCE to LINUX_GIT",
            :build_all => "Build all",
            :build_infiniband => "Build infiniband subdirs",
            :build_subset => "Build specified subdirs",
            :diffpaths => "List changed paths (dir) since reference branch",
            :kabi_check => "Check kABI compatibility",
            :backport_todo => "List all patches in origin/master that are not applied to the specified tree",
            :git_fixes => "Fetch git-fixes list from #{@@GIT_FIXES_URL}/../#{@@GIT_FIXES_SUBTREE} and try to scp them.",
        }

        def self.set_opts(action, optsParser, opts)
            opts[:sha1] = []
            opts[:arch] = "x86_64"
            opts[:j] = DEFAULT_J_OPT
            opts[:backport_apply] = false
            opts[:skip_broken] = false
            opts[:old_kernel] = false
            opts[:build_subset] = nil
            opts[:git_fixes_subtree] = @@GIT_FIXES_SUBTREE
            opts[:git_fixes_listonly] = false

            # Option commonds to multiple commands
            case action
            when :scp, :backport_todo, :git_fixes
                optsParser.on("-r", "--ref <ref>", String, "Bug reference.") {
                    |val| opts[:ref] = val }
                optsParser.on("-y", "--yes", "Reply yes by default to whether patch should be applied.") {
                    |val| opts[:yn_default] = :yes }
                optsParser.on("-S", "--skip-broken", "Automatically skip patches that do not apply.") {
                    |val| opts[:skip_broken] = true }
            when :build_oldconfig, :build_all, :build_infiniband, :build_subset, :kabi_check
                optsParser.on("-a", "--arch <arch>", String, "Arch to build for. Default=x86_64. Supported=" +
                                                             SUPPORTED_ARCHS.map(){|x, y| x}.join(", ")) {
                    |val|
                    raise ("Unsupported arch '#{val}'") if SUPPORTED_ARCHS[val] == nil
                    opts[:arch] = val
                }
                optsParser.on("-j<num>", Integer, "Number of // builds. Default '#{DEFAULT_J_OPT}'") {
                    |val|
                    opts[:j] = val
                }
                optsParser.on("-o", "--old-kernel", "Use M= option to build for old kernels") {
                    |val| opts[:old_kernel] = true
                }
                optsParser.on("-c", "--cc <compiler>", String, "Override default compiler") {
                    |val| opts[:cc] = val
                }
            end

            # Command specific opts
            case action
            when :scp
                optsParser.on("-c", "--sha1 <SHA1>", String, "Commit to backport.") {
                    |val| opts[:sha1] << val}
                optsParser.on("-C", "--cve", "Auto extract reference from VULNS."){
                    |val| opts[:cve] = true }
            when :build_subset
                optsParser.on("-p", "--path <path>", String,
                              "Path to subtree to build.") {
                    |val| opts[:build_subset] = val}
            when :backport_todo
                optsParser.on("-p", "--path <path>", String,
                              "Path to subtree to monitor for non-backported patches.") {
                    |val| opts[:path] = val}
                optsParser.on("-A", "--apply",
                              "Apply all patches using the scp command.") {
                    |val| opts[:backport_apply] = true}
            when :git_fixes
                optsParser.on("-s", "--subtree <subtree>", String,
                              "Which subtree to check git-fixes from.") {
                    |val| opts[:git_fixes_subtree] = val}
                optsParser.on("-l", "--list-only",
                              "Only list pending patches.") {
                    |val| opts[:git_fixes_listonly] = true}

            else
            end
        end
        def self.check_opts(opts)
            case opts[:action]
            when :backport_todo
                raise("Path to sub-tree is needed") if opts[:path].to_s() == ""
            when :build_subset
                raise("Path to build is needed") if opts[:build_subset].to_s() == ""
            end
        end

        def initialize(suse = nil)
            @path=ENV["LINUX_GIT"].chomp()
            begin
                set_branches()
            rescue UnknownBranch
                @branch = nil
            end

            @suse = suse
            @suse = Suse.new(self) if @suse == nil

        end
        def branch()
            raise UnknownBranch.new(@path) if @branch == nil
            @suse.branch?(@branch)
            return @branch
        end

        def local_branch()
            raise UnknownBranch.new(@path) if @local_branch == nil
            return @local_branch
        end
        def branch?(br)
            raise UnknownBranch.new(@path) if @branch == nil
            raise BranchMismatch.new(@branch, br) if @branch != br

            return @branch == br
        end
        def get_kernel_base()
            begin
                return runGit("describe --tags --match='v*' HEAD").gsub(/v([0-9.]+)-.*$/, '\1').to_f()
            rescue
                raise BaseKernelError.new()
            end
        end
        def runBuild(opts, flags="")
            archName, arch, bDir=optsToBDir(opts)
            cc = arch[:CC].to_s()
            if opts[:cc] != nil
                cc = "CC=#{opts[:cc]}"
            else
                # For very old kernel, use an ancient GCC if none is specified
                cc.gsub!(/gcc/, "gcc-4.8") if get_kernel_base() < 4.0
            end
            runSystem("nice -n 19 make #{cc} -j#{opts[:j]} O=#{bDir} "+
                      " #{arch[:ARCH].to_s()} #{arch[:CROSS_COMPILE].to_s()} " + flags)
            return $?.exitstatus
        end
        def get_mainline(sha)
            begin
                return runGit("describe --contains --match 'v*' #{sha}").gsub(/~.*/, '')
            rescue
                raise NoSuchMainline.new()
            end
        end
        def optsToBDir(opts)
            archName=opts[:arch]
            raise ("Unsupported arch '#{archName}'") if SUPPORTED_ARCHS[archName] == nil
            arch=SUPPORTED_ARCHS[archName]
            bDir="build-#{archName}/"
            return archName, arch, bDir
        end

        def genBackportList(ahead, trailing, path)
            patches = runGit("log --no-merges --format=oneline #{ahead} ^#{trailing} -- #{path}").
                       split("\n")
            nPatches = patches.length
            idx = 0
            list = patches.map(){|x|
                log(:PROGRESS, "Checking patches in #{ahead} ^#{trailing} (#{idx}/#{nPatches})") if (idx % 10) == 0
                idx += 1
                sha = x.gsub(/^([0-9a-f]*) .*$/, '\1')
                name = x.gsub(/^[0-9a-f]* (.*)$/, '\1')
                patch_id = run("git format-patch -n1 #{sha} --stdout | git patch-id | awk '{ print $1}'").chomp()

                { :sha => sha, :name => name, :patch_id => patch_id}
            }
            log(:INFO, "Checking patches in #{ahead} ^#{trailing} (#{nPatches}/#{nPatches})")
            return list
        end
        def filterInHouse(opts, head, house)
            houseList = house.inject({}){|h, x|
                h[x[:patch_id]] = true
                h
            }
            # Filter the easy one first
            head.delete_if(){|x| houseList[x[:patch_id]] == true }
            # Some patches may have conflicted and the fix changes the patch-id
            # so look for the originalcommit id in the .patches files in the SUSE tree.
            # We could do only this, but it's much much slower, so filter as much as we can first

            houseList = @suse.gen_commit_id_list(opts)
            head.delete_if(){|x| houseList[x[:sha]] == true }

        end
        #
        # ACTIONS
        #
        def apply_pending(opts)
            # Ignore errors here, we're aborting just in case
            runGit("am --abort", {}, false)
            runGitInteractive("reset --hard #{@@UPSTREAM_REMOTE}/#{branch()}")
            return $?.exitstatus if $?.exitstatus != 0
            patches = @suse.gen_ordered_patchlist()

            if patches.length == 0 then
                log(:INFO, "No patches to apply")
                return 0
            end

            amList=""
            patches.each(){|p|
                if p =~ /^-([a-f0-9]+)$/
                    runGitInteractive("revert --no-edit #{$1}")
                else
                    amList += "#{p} "
                end
            }
            runGitInteractive("am #{amList}")
            return $?.exitstatus
        end
        def scp(opts)
            branch()
            if opts[:sha1].length == 0 then
                log(:ERROR, "No SHA1 provided")
                return 1
            end
            @suse.fill_patchInfo_ref(opts)
            opts[:sha1].each(){ |sha|
                begin
                     _scp_one(opts, sha)
                rescue SCPAbort
                    log(:INFO, "Aborted")
                    return 1
                end
            }
            return 0
        end

        def build_oldconfig(opts)
            archName, arch, bDir=optsToBDir(opts)

            runSystem("rm -Rf #{bDir} && " +
                      "mkdir #{bDir} && " +
                      "cp #{ENV["KERNEL_SOURCE_DIR"]}/config/#{archName}/default #{bDir}/.config && "+
                      "make olddefconfig #{arch[:ARCH].to_s()} O=#{bDir}")
            return $?.exitstatus
        end
        def build_all(opts)
            return runBuild(opts)
        end
        def build_subset(opts)
            sub=opts[:build_subset]
            buildTarget=""

            if opts[:old_kernel] != true then
                ver=get_kernel_base()
                opts[:old_kernel] = true if ver < 5.3
            end
            if opts[:old_kernel] == true then
                # M= does not like trailing /
                sub=sub.gsub(/\/*$/, '')
                buildTarget="SUBDIRS=#{sub}"
            else
                # Newer build system do require one and only one though
                sub=sub.gsub(/\/+$/, '') + '/'
                buildTarget="#{sub}"
            end
            return runBuild(opts, "#{buildTarget}")
        end
        def build_infiniband(opts)
            opts[:build_subset] = "drivers/infiniband"
            return build_subset(opts)
        end

        def diffpaths(opts)
            puts runGit("diff #{@@UPSTREAM_REMOTE}/#{branch()}..HEAD --stat=500").split("\n").map() {|l|
                next if l =~ /files changed/
                p = File.dirname(l.strip.gsub(/[ \t]+.*$/, ''))
            }.uniq!().compact!()
            return 0
        end

        def kabi_check(opts)
            branch()
            archName, arch, bDir=optsToBDir(opts)
            kDir=ENV["KERNEL_SOURCE_DIR"]

            runSystem("#{kDir}/rpm/kabi.pl --rules #{kDir}/kabi/severities " +
                      " #{kDir}/kabi/#{archName}/symvers-default "+
                      " #{bDir}/Module.symvers")
            return $?.exitstatus
        end

        def backport_todo(opts)
            head=("origin/master")
            tBranch=local_branch()

            inHead = genBackportList(head, tBranch, opts[:path])
            inHouse = genBackportList(tBranch, head, opts[:path])

            filterInHouse(opts, inHead, inHouse)

            if inHead.length == 0 then
                log(:INFO, "No patch left to backport ! Congrats !")
                return 0
            end

            runGitInteractive("show --no-patch --format=oneline #{inHead.map(){|x| x[:sha]}.join(" ")}")

            if opts[:backport_apply] == true then
                opts[:sha1] = inHead.map(){|x| x[:sha]}.reverse
                return scp(opts)
            end
            return 0
        end

        def git_fixes(opts)
            branch()
            shas = []
            begin
                shas = _fetch_git_fixes(opts)
            rescue GitFixesFetchError
                log(:ERROR, "Failed to retrieve git-fixes list")
                return 1
            end
            if shas.length == 0 then
                log(:INFO, "Great job. Nothing to do here")
                return 0
            end
            log(:INFO, "List of patches to apply")
            opts[:sha1] = shas.map(){|sha|
                applied = @suse.is_applied?(sha)
                status = applied ? "APPLIED".green() : "PENDING".brown()
                log(:INFO, "  #{status}\t"+
                           runGit("log -n1 --abbrev=12 --pretty='%h (\"%s\")' #{sha}"))
                applied ? nil : sha
            }.compact()
            if opts[:sha1].length == 0 then
                log(:INFO, "Great job. Nothing to do here")
                return 0
            end
            return 0 if opts[:git_fixes_listonly] == true

            scp(opts)
            return 0
        end

        ###########################################
        #### PRIVATE methods                   ####
        ###########################################
        private
        def _fetch_git_fixes(opts)
            str = nil
            begin
                str = run("curl -f -s #{@@GIT_FIXES_URL}/#{opts[:git_fixes_subtree]}-#{branch()}.csv")
            rescue RunError => e
                if e.err_code != 22
                    raise(GitFixesFetchError) if $?.exitstatus != 0
                else
                    log(:WARNING, "curl HTTP failure. Assuming 404 so nothing more to do here")
                    return []
                end
            end

            return CSV.parse(str).map(){|row|
                case row[0]
                when /Id/
                    # Title line
                    next
                when /^[0-9a-f]+$/
                    row[0]
                else
                    raise("Unexpected line #{row} in CSV")
                end
            }.compact()
        end

        def _cherry_pick_one(opts, sha)
            begin
                runGitInteractive("cherry-pick #{sha}")
            rescue
                if opts[:skip_broken] == true then
                    e = SCPSkip.new("#{sha}")
                    log(:WARNING, e.to_s())
                    runGitInteractive("cherry-pick --abort")
                    raise(e)
                end
                runGitInteractive("diff")
                log( :INFO, "Entering subshell to fix conflicts. Exit when done")
                runSystem("PS1_WARNING='SCP FIX' bash", false)
                rep = confirm(opts, "continue with scp [y(es), n(o), s(kip)]?", true, ["y", "n", "s"])
                case rep
                when "n"
                    runGitInteractive("cherry-pick --abort")
                    raise(SCPAbort)
                when "s"
                    runGitInteractive("cherry-pick --abort")
                    e = SCPSkip.new("#{sha}")
                    log(:INFO, e.to_s())
                    raise(e)
                end
            end
            return
        end

        def _tune_last_patch(opts)
            run("rm -f 0001*.patch")
            runGit("format-patch -n1 HEAD")

            ret = 1
            while ret == 1  do
                begin
                    @suse.do_checkpatch(opts)
                    ret = 0
                rescue CheckPatchError
                    @suse.do_meld_lastpatch(opts)
                end
            end
            return 0
        end

        def _scp_one(opts, sha)
            rep="t"
            desc=runGit("log -n1 --abbrev=12 --pretty='%h (\"%s\")' #{sha}")

            if @suse.is_applied?(sha)
                log(:INFO, "Patch already applied in KERNEL_SOURCE_DIR: #{desc}")
                return 0
            end
            while rep != "y"
                rep = confirm(opts, "pick commit '#{desc}' up",
                              false, ["y", "n", "?"])
                case rep
                when "n"
                    break
                when "?"
                    runGitInteractive("show #{sha}")
                end
            end

            return 0 if rep != "y"

            begin
                _cherry_pick_one(opts, sha)
            rescue SCPSkip
                return 0
            end

            if @suse.extract_single_patch(opts, sha) != 0 then
                log(:ERROR, "Failed to extract patch in KERNEL_SOURCE_DIR, reverting in LINUX_GIT")
                runGitInteractive("reset --hard HEAD~1")
                return 1
            end

            return _tune_last_patch(opts)
        end
    end
end
