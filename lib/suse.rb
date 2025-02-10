module KernelWork
    class Suse
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
            :list_unmerged,
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
            :list_unmerged => "List KERNEL_SOURCE_DIR commits not yet merged",
        }

        def self.set_opts(action, optsParser, opts)
            opts[:sha1] = []
            opts[:full_check] = false
            opts[:autofix] = false

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
                optsParser.on("-i", "--ignore-tag", "Ignore missing tag or maintainer branch.") {
                    |val| opts[:ignore_tag] = true}
                optsParser.on("-f", "--filename <file.patch>", "Custom patch filename.") {
                    |val| opts[:filename] = val}
            when :checkpatch
                optsParser.on("-F", "--full", "Slower but thorougher checkpatch.") {
                    |val| opts[:full_check] = true}
            else
            end
        end
        def self.execAction(opts, action)
            up   = Suse.new()
            return up.send(action, opts)
        end

        def initialize(upstream = nil)
            @path=ENV["KERNEL_SOURCE_DIR"].chomp()
            begin
                @local_branch = runGit("branch --show current").chomp()
                @branch = @local_branch.split('/')[2..-2].join('/')
            rescue
                raise "Failed to detect branch name"
            end
            @patch_path = "patches.suse"

            @upstream = upstream
            @upstream = Upstream.new(self) if @upstream == nil
            raise("Branch mismatch") if @branch != @upstream.branch

            idx = @@BR_LIST.index(@branch)
            if idx == nil then
                log(:WARNING, "Branch '#{@branch}' not in supported list")
            else
                @branch_infos = @@MAINT_BRANCHES[idx]
                @patch_path = @branch_infos[:patch_path] if @branch_infos[:patch_path] != nil
            end
        end
        attr_reader :branch
 
        def log(lvl, str)
            KernelWork::log(lvl, str)
        end
        def run(cmd)
            return `cd #{@path} && #{cmd}`.chomp()
        end
        def runSystem(cmd)
            return system("cd #{@path} && #{cmd}")
        end
        def runGit(cmd, opts={})
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running git command '#{cmd}'")
            return `cd #{@path} && #{opts[:env]} git #{cmd}`.chomp()
        end
        def runGitInteractive(cmd, opts={})
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running interactive git command '#{cmd}'")
            return system("cd #{@path} && #{opts[:env]} git #{cmd}")
        end

        def get_last_patch()
            runGit("show HEAD --stat --stat-width=1000 --no-decorate").
                split("\n").each().grep(/#{@patch_path}/)[0].lstrip().split(/[ \t]/)[0]
        end
        def get_current_patch()
            runGit("diff --cached --stat --stat-width=1000").
                split("\n").each().grep(/#{@patch_path}/)[0].lstrip().split(/[ \t]/)[0]
        end
        def get_patch_commit_id(patchfile = nil)
            return runGit("grep Git-commit #{patchfile}").split(/[ \t]/)[-1]
        end
        def get_mainline(sha)
            git_repo = nil
            orig_tag = @upstream.get_mainline(sha)
            if orig_tag == "" then
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
                    git_repo=runGit("config remote.#{remote}.url")
                    break
                }
            end
            return orig_tag, git_repo
        end
        def gen_ordered_patchlist()
            return runGit("diff \"#{@@SUSE_REMOTE}/#{@branch}\"..HEAD -- series.conf").
                       split("\n").each().grep(/^\+[^+]/).grep_v(/^\+\s*#/).compact().map(){|l|
                @path + "/" + l.split(/[ \t]/)[1]
            }
        end

        def gen_commit_id_list()
            h={}
            run("git grep Git-commit: patches.suse | awk '{ print $NF}'").
                chomp().split("\n").map(){|x|
                h[x] = true
            }
            return h
        end
        def patchname_to_path(pname)
            return ENV["KERNEL_SOURCE_DIR"] + "/" + @patch_path + "/" + pname
        end
        #
        # ACTIONS
        #
        def source_rebase(opts)
            intOpts="-i"
            if opts[:no_interactive] == true
                intOpts = ""
            end
            runGitInteractive("rebase #{intOpts} #{@@SUSE_REMOTE}/#{@branch}")
            ret = $?.exitstatus
            while opts[:autofix] == true && ret != 0
                log(:WARNING, "Trying to autofix series.conf")
                ret = fix_series(opts)
                break if ret != 0
                log(:WARNING, "Get on with rebasing")
                runGitInteractive("rebase --continue", { :env => "GIT_EDITOR=true"})
                ret = $?.exitstatus
            end
            return $?.exitstatus
        end

        def meld_lastpatch(opts)
            file = get_last_patch()
            runSystem("meld \"#{file}\" \"#{ENV["LINUX_GIT"]}\"/0001-*.patch && "+
                   "git add \"#{file}\" && git amend --no-verify")
            return $?.exitstatus
        end


        def extract_single_patch(opts, sha)
            f_sha1 = @upstream.runGit("rev-parse #{sha}")
            if $?.exitstatus != 0 then
                log(:ERROR, "Failed to find commit #{sha}")
                return 1
            end

            orig_tag, git_repo = get_mainline(sha)
            if orig_tag == "" then
                if opts[:ignore_tag] != true then
                    log(:ERROR, "Commit is not contained in any tag nor maintainer repo")
                    return 1
                else
                    orig_tag="Never, in-house patch"
                    f_sha1=nil
                end
            end
            full_pname=@upstream.runGit("format-patch -n1 #{sha}")
            pname=full_pname.gsub(/^0001-/,"")
            pname = opts[:filename] if opts[:filename] != nil

            fpath=patchname_to_path(pname)
            while File.exist?(fpath) do
                log(:ERROR, "File '#{pname}' already exists in KERNEL_SOURCE_DIR")
                return 1 if opts[:filename] != nil

                # If user has not specified a name, try to prompt him for one
                rep= KernelWork::confirm(opts, "set a custom filename", true, ["y", "n"])
                if rep == "n" then
                    log(:ERROR, "Aborting")
                    return 1
                end

                rep="t"
                nName=nil
                while rep != "y"
                    puts "Enter a filename (auto name was: #{pname} ):"
                    nName=STDIN.gets.chomp()
                    rep = KernelWork::confirm(opts, "keep the filename '#{nName}'", true, ["y", "n", "A" ])
                    if rep == "A" then
                        log(:ERROR, "Aborting")
                        return 1
                    end
                end
                pname = nName
                fpath=patchname_to_path(pname)
            end
            i = File.open(ENV["LINUX_GIT"] + "/" + full_pname,"r")
            o = File.open(fpath , "w+")

            p_split=0
            in_subj=false
            i.each(){|l|
                case l
                when /^Subject: \[PATCH/
                    in_subj=true
                    o.puts l
                when /^\n$/
                    if in_subj == true
                        o.puts "Git-commit: #{f_sha1}" if f_sha1 != nil
                        o.puts "Patch-mainline: #{orig_tag}" if orig_tag != nil
                        o.puts "References: #{opts[:ref]}" if opts[:ref] != nil
                        o.puts "Git-repo: #{git_repo}" if git_repo != nil
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
            o.close()
            run("rm -f \"#{full_pname}\"")
            runGitInteractive("add #{@patch_path}/#{pname}")

            log(:INFO, "Inserting patch")
            runSystem("./scripts/git_sort/series_insert.py #{@patch_path}/#{pname}")
            return $?.exitstatus if $?.exitstatus != 0
            runGitInteractive("add series.conf #{@patch_path}/#{pname}")
            return $?.exitstatus if $?.exitstatus != 0
            subject=@upstream.runGit("show --format='format:%s' --no-patch #{sha}") +
                    " (#{opts[:ref]})"
            cname=run("mktemp")
            f = File.open(cname, "w+")
            f.puts subject
            f.close()
            log(:INFO, "Commiting '#{subject}'")
            runGitInteractive("commit -F #{cname}")
            return $?.exitstatus if $?.exitstatus != 0
            run("rm -f #{cname}")
            return 0
        end

        def extract_patch(opts)
            if opts[:ref] == nil then
                opts[:ref] = @branch_infos[:ref]
            end

            if opts[:ref] == nil then
                log(:ERROR, "No bug/CVE ref provided nor default set")
                return 1
            end
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
            patch = get_current_patch()
            runSystem("./scripts/git_sort/series_insert.py \"#{patch}\"")
            return $?.exitstatus if $?.exitstatus != 0
            runGit("add series.conf")
            runGitInteractive("status")
            return 0
        end
        def checkpatch(opts)
            rOpt = " --rapid "
            rOpt = "" if opts[:full_check] == true
            runSystem("./scripts/sequence-patch.sh #{rOpt}")
            return $?.exitstatus
        end
        def fix_mainline(opts)
            patch = get_last_patch()
            sha = get_patch_commit_id(patch)
            tag = @upstream.get_mainline(sha)
            runSystem("sed -i -e 's/Patch-mainline:.*/Patch-mainline: #{tag}/' \"#{patch}\"")
            runGit("add \"#{patch}\"")
            runGitInteractive("diff --cached")
            return 0
        end
        def check_fixes(opts)
            log(:INFO, "Checking potential missing git-fixes between #{@@SUSE_REMOTE}/#{@branch} and HEAD")
            runSystem("./scripts/git-fixes  $(git rev-parse \"#{@@SUSE_REMOTE}/#{@branch}\")")
            return $?.exitstatus
        end
        def list_unmerged(opts)
            runGitInteractive("log --no-decorate  --format=oneline \"^#{@@SUSE_REMOTE}/#{@branch}\" HEAD")
            return 0
        end
   end
end
