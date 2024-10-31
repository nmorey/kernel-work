module KernelWork
    class Upstream
        @@UPSTREAM_REMOTE="SUSE"
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
            :diffpaths,
            :kabi_check,
            :backport_todo,
        ]
        ACTION_HELP = {
            :"*** LINUX_GIT commands *** *" => "",
            :apply_pending => "Reset LINUX_GIT branch and reapply all unmerged patches from kernel-source",
            :scp => "Show commit, cherry-pick to LINUX_GIT then apply to KERNEL_SOURCE if all is OK",
            :build_oldconfig => "Copy config from KERNEL_SOURCE to LINUX_GIT",
            :build_all => "Build all",
            :build_infiniband => "Build infiniband subdirs",
            :diffpaths => "List changed paths (dir) since reference branch",
            :kabi_check => "Check kABI compatibility",
            :backport_todo => "List all patches in origin/master that are not applied to the specified tree",
        }

        def self.set_opts(action, optsParser, opts)
            opts[:sha1] = []
            opts[:arch] = "x86_64"
            opts[:j] = DEFAULT_J_OPT
            opts[:backport_apply] = false

            # Option commonds to multiple commands
            case action
            when :scp, :backport_todo
                optsParser.on("-r", "--ref <ref>", String, "Bug reference.") {
                    |val| opts[:ref] = val }
                optsParser.on("-y", "--yes", "Reply yes by default to whether patch should be applied.") {
                    |val| opts[:yn_default] = :yes }
            end

            # Command specific opts
            case action
            when :scp
                optsParser.on("-c", "--sha1 <SHA1>", String, "Commit to backport.") {
                    |val| opts[:sha1] << val}
            when :build_oldconfig, :build_all, :build_infiniband, :kabi_check
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
            when :backport_todo
                optsParser.on("-p", "--path <path>", String,
                              "Path to subtree to monitor for non-backported patches.") {
                    |val| opts[:path] = val}
                optsParser.on("-A", "--apply",
                              "Apply all patches using the scp command.") {
                    |val| opts[:backport_apply] = true}
            else
            end
        end
        def self.check_opts(opts)
            case opts[:action]
            when :backport_todo
                raise("Path to sub-tree is needed") if opts[:path].to_s() == ""
            end
        end
        def self.execAction(opts, action)
            up   = Upstream.new()
            up.send(action, opts)
        end

        def initialize(suse = nil)
            @path=ENV["LINUX_GIT"].chomp()
            begin
                @branch = runGit("branch").split("\n").each().grep(/^\*/)[0].split('/')[2..-2].join('/')
            rescue
                raise "Failed to detect branch name"
            end

            @suse = suse
            @suse = Suse.new(self) if @suse == nil
            raise("Branch mismatch") if @branch != @suse.branch
        end
        attr_reader :branch

        def log(lvl, str)
            KernelWork::log(lvl, str)
        end
        def run(cmd)
            return `cd #{@path} && #{cmd}`
        end
        def runSystem(cmd)
            return system("cd #{@path} && #{cmd}")
        end
        def runGit(cmd)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running git command '#{cmd}'")
            return `cd #{@path} && git #{cmd}`.chomp()
        end
        def runGitInteractive(cmd)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running interactive git command '#{cmd}'")
            return system("cd #{@path} && git #{cmd}")
        end
        def runBuild(opts, flags="")
            archName, arch, bDir=optsToBDir(opts)
            runSystem("nice -n 19 make #{arch[:CC].to_s()} -j#{opts[:j]} O=#{bDir} "+
                      " #{arch[:ARCH].to_s()} #{arch[:CROSS_COMPILE].to_s()} " + flags)
            return $?.to_i()
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
        def filterInHouse(head, house)
            houseList = house.inject({}){|h, x|
                h[x[:patch_id]] = true
                h
            }
            # Filter the easy one first
            head.delete_if(){|x| houseList[x[:patch_id]] == true }
            # Some patches may have conflicted and the fix changes the patch-id
            # so look for the originalcommit id in the .patches files in the SUSE tree.
            # We could do only this, but it's much much slower, so filter as much as we can first

            houseList = @suse.gen_commit_id_list()
            head.delete_if(){|x| houseList[x[:sha]] == true }

        end
        #
        # ACTIONS
        #
        def apply_pending(opts)
            runGit("am --abort")
            runGitInteractive("reset --hard #{@@UPSTREAM_REMOTE}/#{@branch}")
            return $?.to_i() if $?.to_i != 0
            patches = @suse.gen_ordered_patchlist()
            if patches.length == 0 then
                log(:INFO, "No patches to apply")
                return 0
            end
            runGit("am #{patches.join(" ")}")
            return $?.to_i()
        end
        def scp(opts)
            if opts[:sha1].length == 0 then
                log(:ERROR, "No SHA1 provided")
                return 1
            end
            shas = opts[:sha1]
            shas.each(){ |sha|
                opts[:sha1] = [ sha ]
                rep="t"
                desc=runGit("log -n1 --abbrev=12 --pretty='%h (\"%s\")' #{sha}")
                while rep != "y"
                    rep = KernelWork::confirm(opts, "pick commit '#{desc}' up",
                                              false, ["y", "n", "?"])
                    case rep
                    when "n"
                        return 0
                    when "?"
                        runGitInteractive("show #{sha}")
                    when "y"
                    else
                        log(:ERROR, "Invalid answer '#{rep}'")
                    end
                end
                runGitInteractive("cherry-pick #{sha}")
                if $?.to_i != 0 then
                    runGitInteractive("diff")
                    log( :INFO, "Entering subshell to fix conflicts. Exit when done")
                    runSystem("bash")
                    rep = KernelWork::confirm(opts, "continue with scp?", true)
                    if rep == "n"
                        runGitInteractive("cherry-pick --abort")
                        return 1
                    end
                end

                if @suse.extract_patch(opts) != 0 then
                    log(:ERROR, "Failed to extract patch in KERNEL_SOURCE_DIR, reverting in LINUX_GIT")
                    runGitInteractive("reset --hard HEAD~1")
                    return 1
                end
                run("rm -f 0001*.patch")
                runGit("format-patch -n1 HEAD")

                while @suse.checkpatch(opts) != 0 do
                    ret = @suse.meld_lastpatch(opts)
                    return ret if ret != 0
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
            return $?.to_i()
        end
        def build_all(opts)
            return runBuild(opts)
        end
        def build_infiniband(opts)
            return runBuild(opts, "SUBDIRS=drivers/infiniband/ drivers/infiniband/")
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
            return $?.to_i()
        end

        def backport_todo(opts)
            head=("origin/master")
            tBranch="HEAD"

            inHead = genBackportList(head, tBranch, opts[:path])
            inHouse = genBackportList(tBranch, head, opts[:path])

            filterInHouse(inHead, inHouse)

            runGitInteractive("show --no-patch --format=oneline #{inHead.map(){|x| x[:sha]}.join(" ")}")

            if opts[:backport_apply] == true then
                opts[:sha1] = inHead.map(){|x| x[:sha]}.reverse
                return scp(opts)
            end
            return 0
        end
   end
end
