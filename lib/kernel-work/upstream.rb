require 'csv'
require 'yaml'
require 'fileutils'
module KernelWork

    class Upstream < Common
        @@UPSTREAM_REMOTE="SUSE"
        @@GIT_FIXES_URL="http://fixes.prg2.suse.org/current/"
        @@GIT_FIXES_SUBTREE="infiniband"

        DEFAULT_J_OPT="$(nproc --all --ignore=4)"


        def self.load_supported_archs
            defaults = {
                "x86_64" => {
                    :CC => "CC=\"ccache gcc\"",
                },
                "arm64" => {
                    :CC => "CC=\"ccache gcc\"",
                    :CROSS_COMPILE => "aarch64-suse-linux-",
                    :ARCH => "ARCH=arm64",
                },
                "s390x" => {
                    :CC => "CC=\"ccache gcc\"",
                    :CROSS_COMPILE => "s390x-suse-linux-",
                    :ARCH => "ARCH=s390",
                }
            }

            f = Common.get_config_file('archs.yml')
            if !File.exist?(f)
                d = File.dirname(f)
                FileUtils.mkdir_p(d) unless File.directory?(d)
                File.open(f, 'w') {|file| file.write(defaults.to_yaml)}
            end

            # YAML.load_file returns string keys by default. 
            # We want String keys for Arch names, but Symbol keys for inner attributes.
            data = YAML.load_file(f)

            # Convert inner keys to symbols to match existing code usage
            data.each { |k, v| 
                data[k] = v.transform_keys(&:to_sym) 
            }
            return data
        end
        SUPPORTED_ARCHS = load_supported_archs()
        ACTION_LIST = [
            :apply_pending,
            :scp,
            :oldconfig,
            :build,
            :diffpaths,
            :kabi_check,
            :backport_todo,
            :git_fixes,
        ]
        ACTION_HELP = {
            :"*** LINUX_GIT commands *** *" => "",
            :apply_pending => "Reset LINUX_GIT branch and reapply all unmerged patches from kernel-source",
            :scp => "Show commit, cherry-pick to LINUX_GIT then apply to KERNEL_SOURCE if all is OK",
            :oldconfig => "Copy config from KERNEL_SOURCE to LINUX_GIT",
            :build => "Build all the kernel or some subset of it",
            :diffpaths => "List changed paths (dir) since reference branch",
            :kabi_check => "Check kABI compatibility",
            :backport_todo => "List all patches in origin/master that are not applied to the specified tree",
            :git_fixes => "Fetch git-fixes list from #{@@GIT_FIXES_URL}/../#{@@GIT_FIXES_SUBTREE} and try to scp them.",
        }

        def self.set_opts(action, optsParser, opts)
            opts[:commits] = []
            opts[:arch] = "x86_64"
            opts[:j] = DEFAULT_J_OPT
            opts[:backport_apply] = false
            opts[:skip_broken] = false
            opts[:skip_treewide] = false
            opts[:old_kernel] = false
            opts[:build_subset] = nil
            opts[:git_fixes_subtree] = @@GIT_FIXES_SUBTREE
            opts[:git_fixes_listonly] = false
            opts[:upstream_ref] = "origin/master"
            opts[:backport_include] = []
            opts[:backport_exclude] = []

            # Option commonds to multiple commands
            case action
            when :scp, :backport_todo, :git_fixes
                optsParser.on("-r", "--ref <ref>", String, "Bug reference.") {
                    |val| opts[:ref] = val }
                optsParser.on("-y", "--yes", "Reply yes by default to whether patch should be applied.") {
                    |val| opts[:yn_default] = :yes }
                optsParser.on("-S", "--skip-broken", "Automatically skip patches that do not apply.") {
                    |val| opts[:skip_broken] = true }
                optsParser.on("-T", "--skip-treewide", "Automatically skip tree wide patches.") {
                    |val| opts[:skip_treewide] = true }
            when :oldconfig, :build,:kabi_check
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
                optsParser.on("--hostcc <compiler>", String, "Override default host compiler") {
                    |val| opts[:hostcc] = val
                }
            end

            # Command specific opts
            case action
            when :scp
                optsParser.on("-c", "--sha1 <SHA1>", String, "Commit to backport.") {
                    |val| opts[:commits] << KernelWork::Commit.new(val)}
                optsParser.on("-C", "--cve", "Auto extract reference from VULNS."){
                    |val| opts[:cve] = true }
                optsParser.on("-f", "--file <FILE>", String, "File containing list of SHA1 to backport.") {
                    |val| opts[:file] = val }
            when :build
                optsParser.on("-p", "--path <path>", String,
                              "Path to subtree to build.") {
                    |val| opts[:build_subset] = val}
                optsParser.on("-I", "--infiniband", String,
                              "Build infiniband subtree") {
                    |val| opts[:build_subset] = "drivers/infiniband"}
                optsParser.on("-v", "--verbose", 
                              "Build with V=1") {
                    |val| opts[:build_verbose] = true}
            when :backport_todo
                optsParser.on("-p", "--path <path>", String,
                              "Path to subtree to monitor for non-backported patches.") {
                    |val| opts[:path] = val}
                optsParser.on("-R", "--upstream-ref <ref>", String,
                              "Check patches up to <ref> in upstream kernel. Default is origin/master.") {
                    |val| opts[:upstream_ref] = val}
                optsParser.on("-A", "--apply",
                              "Apply all patches using the scp command.") {
                    |val| opts[:backport_apply] = true}
                optsParser.on("-f", "--file <FILE>", String,
                              "Save the list to a file (load it if --apply).") {
                              |val| opts[:file] = val}
                optsParser.on("-i", "--include <sha>", String,
                              "Force including this SHA in the TODO list.") {
                    |val| opts[:backport_include] << KernelWork::Commit.new(val)}
                optsParser.on("-x", "--exclude <sha>", String,
                              "Force excluding this SHA from the TODO list.") {
                    |val| opts[:backport_exclude] << KernelWork::Commit.new(val)}
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
            return @kv if @kv != nil
            begin
                @kv = KV.new(runGit("describe --tags --match='v*' HEAD").gsub(/v([0-9.]+)-.*$/, '\1'))
                return @kv
            rescue
                raise BaseKernelError.new()
            end
        end

        def self.load_compiler_config
            defaults = [
                { :range => "0.0...4.0", :gcc => "gcc-4.8" },
                { :range => "4.0..5.3",  :gcc => "gcc-7"   },
                {                        :gcc => "gcc -std=gnu11" }
            ]
            f = Common.get_config_file('kernel-compiler.yml')
             if !File.exist?(f)
                d = File.dirname(f)
                FileUtils.mkdir_p(d) unless File.directory?(d)
                File.open(f, 'w') {|file| file.write(defaults.to_yaml)}
            end

            rules = YAML.load_file(f, symbolize_names: true)
            # Parse ranges
            rules.each do |r|
                if r[:range]
                    if r[:range] =~ /^(.*)\.\.\.(.*)$/
                        r[:range_obj] = Range.new(KV.new($1), KV.new($2), true)
                    elsif r[:range] =~ /^(.*)\.\.(.*)$/
                        r[:range_obj] = Range.new(KV.new($1), KV.new($2), false)
                    end
                 end
            end
            return rules
        end
        COMPILER_RULES = load_compiler_config()

        def genMakeFlags(opts)
            archName, arch, bDir=optsToBDir(opts)
            cc = arch[:CC].to_s()
            hostCC = "HOSTCC=\"ccache gcc\""
            crossCompile=""
            extraOpts=""

            # For very old kernel, use an ancient GCC if none is specified
            gccVer="gcc"

            kv = get_kernel_base()
            found_rule = COMPILER_RULES.find do |rule|
                if rule[:range_obj]
                    rule[:range_obj].cover?(kv)
                else
                    true # Default fallback
                end
            end
            gccVer = found_rule[:gcc] if found_rule

            cc = cc.gsub(/gcc/, gccVer)
            hostCC = hostCC.gsub(/gcc/, gccVer)

            if arch[:CROSS_COMPILE] != nil
                cc = cc.gsub(/gcc/, arch[:CROSS_COMPILE] + "gcc")
                crossCompile="CROSS_COMPILE=\"#{arch[:CROSS_COMPILE]}\""
            end
            if opts[:cc] != nil
                cc = "CC=#{opts[:cc]}"
            end
            if opts[:hostcc] != nil
                hostCC = "HOSTCC=#{opts[:hostcc]}"
            end
            if opts[:build_verbose] == true then
                extraOpts="#{extraOpts} V=1"
            end
            return "#{cc} #{hostCC} -j#{opts[:j]} O=#{bDir} #{extraOpts}"+
                    " #{arch[:ARCH].to_s()} #{crossCompile} "
        end

        def runBuild(opts, flags="")
            makeFlags = genMakeFlags(opts)

            runSystem("nice -n 19 make #{makeFlags} " + flags)
            return 0
        end

        def runOldConfig(opts, force=true)
            archName, arch, bDir=optsToBDir(opts)

            return if force != true && File.exist?("#{bDir}/.config")

            runSystem("rm -Rf #{bDir} && " +
                      "mkdir #{bDir} && " +
                      "cp #{ENV["KERNEL_SOURCE_DIR"]}/config/#{archName}/default #{bDir}/.config")

            case get_kernel_base()
            when KV.new(0,0) ... KV.new(3,7)
                runBuild(opts, "oldnoconfig")
            else
                runBuild(opts, "olddefconfig")
            end
        end

        def get_mainline(commit)
            raise ShaNotCommitError.new() if !commit.is_a(KernelWork::Commit)
            begin
                return runGit("describe --contains --match 'v*' #{commit.sha}").gsub(/~.*/, '')
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

                Commit.new(sha, name, patch_id)
            }
            log(:INFO, "Checking patches in #{ahead} ^#{trailing} (#{nPatches}/#{nPatches})")
            return list
        end

        def filterInHouse(opts, head, house)
            houseList = house.inject({}){|h, x|
                h[x.patch_id] = true
                h
            }
            # Filter the easy one first
            head.delete_if(){|x|
                # DROP: Patch is excluded
                next true if opts[:backport_exclude].index(x.sha) != nil
                # KEEP: Patch is force included
                next false if opts[:backport_include].index(x.sha) != nil
                # DROP: We already have this patch in house
                next true if houseList[x.patch_id] == true
                # DROP: if tree wide and we were asked to drop them
                (opts[:skip_treewide] == true && x.subject =~ /(tree|kernel)-?wide/)
            }

            # Some patches may have conflicted and the fix changes the patch-id
            # so look for the originalcommit id in the .patches files in the SUSE tree.
            # We could do only this, but it's much much slower, so filter as much as we can first
            houseList = @suse.gen_commit_id_list(opts)
            head.delete_if(){|x| houseList[x.sha] == true }
        end

        #
        # ACTIONS
        #
        def apply_pending(opts)
            # Ignore errors here, we're aborting just in case
            runGit("am --abort", {}, false)
            runGitInteractive("reset --hard #{@@UPSTREAM_REMOTE}/#{branch()}")

            patches = @suse.gen_ordered_patchlist()

            if patches.length == 0 then
                log(:INFO, "No patches to apply")
                return 0
            end

            amList=[]
            patches.each(){|p|
                if p =~ /^-([a-f0-9]+)$/
                    runGitInteractive("revert --no-edit #{$1}")
                else
                    amList << "#{p}"
                end
            }
            runGitInteractive("am #{amList.join(" ")}") if amList.length > 0
            return 0
        end
        def scp(opts)
            branch()

            # If a file is provided, read the SHAs from it
            if opts[:file]
                if !File.exist?(opts[:file])
                    log(:ERROR, "File #{opts[:file]} does not exist")
                    return 1
                end
                # Read file, ignoring comments or empty lines, assuming SHA is first word
                opts[:commits] = File.readlines(opts[:file]).map { |l|
                    l = l.strip
                    next if l.empty?
                    if l =~ /^([0-9a-f]+)\s+#(.*)$/
                        Commit.new($1, $2)
                    else
                        Commit.new(l.split(/\s+/).first)
                    end
                }.compact
            end

            if opts[:commits].length == 0 then
                log(:ERROR, "No SHA1 provided")
                return 1
            end
            @suse.fill_targetPatch_ref(opts)

            status, unhandled = _scp(opts, opts[:commits])

            # If we used a file and have unhandled patches, write them back
            if opts[:file] && (!unhandled.empty? || status != 0)
                # Write back remaining SHAs
                File.open(opts[:file], 'w') do |f|
                    unhandled.each { |u| f.puts u.to_s }
                end
                log(:INFO, "Unhandled patches written back to #{opts[:file]}")
            end

            return status
        end

        def oldconfig(opts)
            return runOldConfig(opts, true)
        end

        def build(opts)
            buildTarget=""
            if opts[:build_subset] != nil then
                sub=opts[:build_subset]
                buildTarget=""

                if opts[:old_kernel] != true then
                    ver=get_kernel_base()
                    opts[:old_kernel] = true if ver < KV.new(5,3)
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
            end

            # Auto run olddefconfig if necessart
            runOldConfig(opts, false)
            return runBuild(opts, buildTarget)
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
            return 0
        end

        def backport_todo(opts)
            head=(opts[:upstream_ref])
            tBranch=local_branch()

            inHead = genBackportList(head, tBranch, opts[:path])
            inHouse = genBackportList(tBranch, head, opts[:path])

            filterInHouse(opts, inHead, inHouse)

            if inHead.length == 0 then
                log(:INFO, "No patch left to backport ! Congrats !")
                return 0
            end

            if opts[:file]
                File.open(opts[:file], 'w') do |f|
                    inHead.reverse.each do |x|
                        # Write SHA and Name for better readability
                        f.puts x.to_s
                    end
                end
                log(:INFO, "Patch list written to #{opts[:file]}")
            end

            runGitInteractive("show --no-patch --format=oneline #{inHead.map(){|x| x.sha}.join(" ")}")

            if opts[:backport_apply] == true then
                opts[:commits] = inHead.reverse
                # opts[:file] is already set if provided, so scp will use it for state management
                return scp(opts)
            end
            return 0
        end

        def git_fixes(opts)
            branch()
            commits = []
            begin
                commits = _fetch_git_fixes(opts)
            rescue GitFixesFetchError
                log(:ERROR, "Failed to retrieve git-fixes list")
                return 1
            end
            if commits.length == 0 then
                log(:INFO, "Great job. Nothing to do here")
                return 0
            end
            log(:INFO, "List of patches to apply")
            opts[:commits] = commits.map(){|commit|
                applied = @suse.is_applied?(commit)
                status = applied ? "APPLIED".green() : "PENDING".brown()
                desc = commit.desc()

                log(:INFO, "  #{status}\t"+ desc)
                applied ? nil : commit
            }.compact()
            if opts[:commits].length == 0 then
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
                str = run("curl -f -s #{@@GIT_FIXES_URL}/#{opts[:git_fixes_subtree]}")
            rescue RunError => e
                if e.err_code() != 22
                    raise(GitFixesFetchError)
                else
                    log(:WARNING, "curl HTTP failure. Assuming 404 so nothing more to do here")
                    return []
                end
            end

            pre=true
            cur_sha=nil
            cur_subject=nil
            fixes = str.lines().map() {|line|
                commit = nil

                case line.chomp()
                when /^=+$/
                    # End of header
                    pre = false
                when /^([0-9a-f]+) (.*)$/
                    cur_sha=$1
                    cur_subject=$2
                when /^[\t ]+Considered for ([^ ]+)/
                    commit = Commit.new(cur_sha, cur_subject) if pre == false && $1 == branch()
                when /^$/
                    cur_sha=nil
                    cur_subject=nil
                end
                commit
            }.compact()
            return fixes
        end

        def _cherry_pick_one(opts, commit)
            raise ShaNotCommitError.new() if !commit.is_a?(KernelWork::Commit)

            begin
                runGitInteractive("cherry-pick #{commit.sha}")
            rescue
                if opts[:skip_broken] == true then
                    e = SCPSkip.new(commit.to_s())
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
                    e = SCPSkip.new(commit.to_s())
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

        def _scp_one(opts, commit)
            rep="t"
            raise ShaNotCommitError.new() if !commit.is_a?(KernelWork::Commit)

            begin
                desc=commit.desc()
            rescue ShaNotFoundError => e
                log(:ERROR, "'#{commit.sha}' does not seems to be a valid  SHA in this repo")
                raise e
            end

            if @suse.is_applied?(commit)
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
                    runGitInteractive("show #{commit.sha}", {}, false)
                end
            end

            return 0 if rep != "y"

            begin
                _cherry_pick_one(opts, commit)
            rescue SCPSkip
                return 0
            end

            if @suse.extract_single_patch(opts, commit) != 0 then
                log(:ERROR, "Failed to extract patch in KERNEL_SOURCE_DIR, reverting in LINUX_GIT")
                runGitInteractive("reset --hard HEAD~1")
                return 1
            end

            return _tune_last_patch(opts)
        end

        # Returns [status, unhandled_shas]
        def _scp(opts, commits)
            unhandled = commits.dup
            commits.each(){ |commit|
                begin
                     _scp_one(opts, commit)
                     unhandled.shift # Remove success from list
                rescue SCPAbort
                    log(:INFO, "Aborted")
                    return 1, unhandled
                rescue Interrupt
                    log(:INFO, "Interrupted")
                    return 1, unhandled
#                rescue ShaNotFoundError
#                    return 1, unhandled
                end
            }
            return 0, []
        end

    end
end
