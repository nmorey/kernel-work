module KernelWork
    class Upstream
        @@UPSTREAM_REMOTE="SUSE"

        ACTION_LIST = [
            :apply_pending,
            :scp,
            :build_oldconfig,
            :build_all,
            :build_infiniband,
            :diffpaths,
        ]
        ACTION_HELP = {
            :"*** LINUX_GIT commands *** *" => "",
            :apply_pending => "Reset LINUX_GIT branch and reapply all unmerged patches from kernel-source",
            :scp => "Show commit, cherry-pick to LINUX_GIT then apply to KERNEL_SOURCE if all is OK",
            :build_oldconfig => "Copy config from KERNEL_SOURCE to LINUX_GIT",
            :build_all => "Build all",
            :build_infiniband => "Build infiniband subdirs",
            :diffpaths => "List changed paths (dir) since reference branch",
        }

        def self.set_opts(action, optsParser, opts)
            opts[:sha1] = []
            case action
            when :scp
                optsParser.on("-c", "--sha1 <SHA1>", String, "Commit to backport.") {
                    |val| opts[:sha1] << val}
                optsParser.on("-r", "--ref <ref>", String, "Bug reference.") {
                    |val| opts[:ref] = val}
            else
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
        def get_mainline(sha)
            return runGit("describe --contains --match 'v*' #{sha}").gsub(/~.*/, '')
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
            if opts[:sha1].length != 1 then
                log(:ERROR, "No or multiple SHA1 provided")
                return 1
            end

            sha = opts[:sha1][0]
            rep="t"
            while rep != "y"
                rep = KernelWork::confirm(opts, "pick commit '#{sha}' up?",
                                          true, ["y", "n", "?"])
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
                rep = KernelWork::confirm(opts, "continue with scp?")
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
                @suse.meld_lastpatch(opts)
            end
        end

        def build_oldconfig(opts)
            runSystem("git purge && " +
                      "cp #{ENV["KERNEL_SOURCE_DIR"]}/config/x86_64/default .config && " +
                      "make olddefconfig")
            return $?.to_i()
        end
        def build_all(opts)
            runSystem("make CC=\"ccache gcc\" -j$(nproc --all --ignore=8)")
            return $?.to_i()
        end
        def build_infiniband(opts)
            runSystem("make CC=\"ccache gcc\" -j$(nproc --all --ignore=8) " +
                      "SUBDIRS=drivers/infiniband/ M=drivers/infiniband")
            return $?.to_i()
        end
        def diffpaths(opts)
            puts runGit("diff #{@@UPSTREAM_REMOTE}/#{@branch}..HEAD --stat=500").split("\n").map() {|l|
                next if l =~ /files changed/
                p = File.dirname(l.strip.gsub(/[ \t]+.*$/, ''))
            }.uniq!().compact!()
            return 0
        end


   end
end
