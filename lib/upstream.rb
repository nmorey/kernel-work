module KernelWork
    class Upstream < Common
        @@UPSTREAM_REMOTE="SUSE"
        @@GIT_FIXES_URL="https://w3.suse.de/~tiwai/git-fixes/branches"
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
            opts[:old_kernel] = false
            opts[:build_subset] = nil
            opts[:git_fixes_subtree] = @@GIT_FIXES_SUBTREE

            # Option commonds to multiple commands
            case action
            when :scp, :backport_todo, :git_fixes
                optsParser.on("-r", "--ref <ref>", String, "Bug reference.") {
                    |val| opts[:ref] = val }
                optsParser.on("-y", "--yes", "Reply yes by default to whether patch should be applied.") {
                    |val| opts[:yn_default] = :yes }
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
            set_branches()

            @suse = suse
            @suse = Suse.new(self) if @suse == nil
            raise("Branch mismatch") if @branch != @suse.branch
        end
        attr_reader :branch

        def runBuild(opts, flags="")
            archName, arch, bDir=optsToBDir(opts)
            runSystem("nice -n 19 make #{arch[:CC].to_s()} -j#{opts[:j]} O=#{bDir} "+
                      " #{arch[:ARCH].to_s()} #{arch[:CROSS_COMPILE].to_s()} " + flags)
            return $?.exitstatus
        end
        def get_mainline(sha)
            return runGit("describe --contains --match 'v*' #{sha}").gsub(/~.*/, '')
        end
        def optsToBDir(opts)
            archName=opts[:arch]
            raise ("Unsupported arch '#{archName}'") if SUPPORTED_ARCHS[archName] == nil
            arch=SUPPORTED_ARCHS[archName]
            bDir="build-#{archName}/"
            return archName, arch, bDir
        end

        def genBackportList(ahead, trailing, path)
            return runGit("log --no-merges --format=oneline #{ahead} ^#{trailing} -- #{path}").
                       split("\n").map(){|x|
                sha = x.gsub(/^([0-9a-f]*) .*$/, '\1')
                name = x.gsub(/^[0-9a-f]* (.*)$/, '\1')
                patch_id = run("git format-patch -n1 #{sha} --stdout | git patch-id | awk '{ print $1}'").chomp()

                { :sha => sha, :name => name, :patch_id => patch_id}
            }
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
            runGit("am --abort")
            runGitInteractive("reset --hard #{@@UPSTREAM_REMOTE}/#{@branch}")
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
            if opts[:sha1].length == 0 then
                log(:ERROR, "No SHA1 provided")
                return 1
            end
            @suse.fill_patchInfo_ref(opts)
            opts[:sha1].each(){ |sha|
                ret = _scp_one(opts, sha)
                return ret if ret != 0
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

            if opts[:old_kernel] == true then
                # M= does not like trailing /
                sub=sub.gsub(/\/*$/, '')
                buildTarget="M=#{sub}"
            else
                # Newer build system do require one and only one though
                sub=sub.gsub(/\/+$/, '') + '/'
                buildTarget="SUBDIRS=#{sub} #{sub}"
            end
            return runBuild(opts, "#{buildTarget}")
        end
        def build_infiniband(opts)
            opts[:build_subset] = "drivers/infiniband"
            return build_subset(opts)
        end

        def diffpaths(opts)
            puts runGit("diff #{@@UPSTREAM_REMOTE}/#{@branch}..HEAD --stat=500").split("\n").map() {|l|
                next if l =~ /files changed/
                p = File.dirname(l.strip.gsub(/[ \t]+.*$/, ''))
            }.uniq!().compact!()
            return 0
        end

        def kabi_check(opts)
            archName, arch, bDir=optsToBDir(opts)
            kDir=ENV["KERNEL_SOURCE_DIR"]

            runSystem("#{kDir}/rpm/kabi.pl --rules #{kDir}/kabi/severities " +
                      " #{kDir}/kabi/#{archName}/symvers-default "+
                      " #{bDir}/Module.symvers")
            return $?.exitstatus
        end

        def backport_todo(opts)
            head=("origin/master")
            tBranch="HEAD"

            inHead = genBackportList(head, tBranch, opts[:path])
            inHouse = genBackportList(tBranch, head, opts[:path])

            filterInHouse(opts, inHead, inHouse)

            if inHead.length == 0 then
                puts "No patch left to backport ! Congrats !"
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
            opts[:sha1] = _fetch_git_fixes(opts)
            log(:INFO, "List of patches to apply")
            opts[:sha1].each(){|sha|
                log(:INFO, "\t"+
                           runGit("log -n1 --abbrev=12 --pretty='%h (\"%s\")' #{sha}"))
            }
            scp(opts)
            return 0
        end

        ###########################################
        #### PRIVATE methods                   ####
        ###########################################
        private
        def _fetch_git_fixes(opts)
             return run("curl -s #{@@GIT_FIXES_URL}/#{@branch}/#{opts[:git_fixes_subtree]}.html").
                split("\n").each().grep(/href="https:\/\/git.kernel.org\/pub/).map(){|line|
                 line.gsub(/^.*">([0-9a-f]+)<\/a><\/td>$/, '\1')
             }
        end

        def _cherry_pick_one(opts, sha)
            runGitInteractive("cherry-pick #{sha}")
            if $?.exitstatus != 0 then
                runGitInteractive("diff")
                log( :INFO, "Entering subshell to fix conflicts. Exit when done")
                runSystem("PS1_WARNING='SCP FIX' bash")
                rep = confirm(opts, "continue with scp?", true)
                if rep == "n"
                    runGitInteractive("cherry-pick --abort")
                    return 1
                end
            end
            return 0
        end

        def _tune_last_patch(opts)
            run("rm -f 0001*.patch")
            runGit("format-patch -n1 HEAD")

            while @suse.checkpatch(opts) != 0 do
                ret = @suse.meld_lastpatch(opts)
                return ret if ret != 0
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

            ret = _cherry_pick_one(opts, sha)
            return ret if ret != 0

            if @suse.extract_single_patch(opts, sha) != 0 then
                log(:ERROR, "Failed to extract patch in KERNEL_SOURCE_DIR, reverting in LINUX_GIT")
                runGitInteractive("reset --hard HEAD~1")
                return 1
            end

            return _tune_last_patch(opts)
        end
    end
end
