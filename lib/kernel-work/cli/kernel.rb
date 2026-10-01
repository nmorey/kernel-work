require 'readline'

module KernelWork
    # Command-line interface controllers and action handlers
    module CLI
        # Root CLI action handler for kernel development workflows
        class Kernel < Common
            include ModelAccess
            # List of available actions for Kernel CLI
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
                :apply_pending,
                :scp,
                :oldconfig,
                :build,
                :diffpaths,
                :kabi_check,
                :backport_todo,
                :git_fixes,
            ]

            # Help text for actions
            ACTION_HELP = {
                :source_rebase => "Rebase KERNEL_SOURCE_DIR branch to the latest tip",
                :meld_lastpatch => "Meld the last KERNEL_SOURCE_DIR patch with LINUX_GIT/0001-*.patch and amend it",
                :extract_patch => "Pick a patch from the LINUX_GIT and commit it into KERNEL_SOURCE_DIR",
                :fix_series => "Auto fix conflicts in series.conf during rebases",
                :checkpatch => "Fast checkpatch pass on all pending patches",
                :fix_mainline => "Fix Git-mainline in the last KERNEL_SOURCE_DIR patch",
                :fix_ref => "Fix ref in the last KERNEL_SOURCE_DIR commit",
                :check_fixes => "Use KERNEL_SOURCE_DIR script to detect missing git-fixes pulled by committed patches",
                :list_commits => "List pending commits (default = unmerged)",
                :push => "Push KERNEL_SOURCE_DIR pending patches",
                :apply_pending => "Reset LINUX_GIT branch and reapply all unmerged patches from kernel-source",
                :scp => "Show commit, cherry-pick to LINUX_GIT then apply to KERNEL_SOURCE if all is OK",
                :oldconfig => "Copy config from KERNEL_SOURCE to LINUX_GIT",
                :build => "Build all the kernel or some subset of it",
                :diffpaths => "List changed paths (dir) since reference branch",
                :kabi_check => "Check kABI compatibility",
                :backport_todo => "List all patches in upstream reference that are not applied to the specified tree",
                :git_fixes => "Fetch git-fixes list from configured upstream url and subtree and try to scp them",
            }

            # Set options for Kernel CLI actions
            # @param action [Symbol] Action name
            # @param opts_parser [OptionParser] Option parser
            # @param opts [Hash] The options hash
            def self.set_opts(action, opts_parser, opts)
                opts[:commits] = []
                opts[:backport_apply] = false
                opts[:skip_broken] = false
                opts[:git_fixes_subtree] = KernelWork.config.linux.git_fixes_subtree
                opts[:git_fixes_listonly] = false
                opts[:upstream_ref] = "origin/master"
                opts[:base_ref] = nil
                opts[:backport_include] = []
                opts[:backport_exclude] = []
                opts[:full_check] = false
                opts[:autofix] = false
                opts[:no_interactive] = false
                opts[:ignore_tag] = false
                opts[:force_push] = false
                opts[:list_commits] = :unmerged
                opts[:filename] = nil
                opts[:patch_path] = nil
                opts[:file] = nil
                opts[:ref] = nil
                opts[:yn_default] = nil

                # Initialize build options defaults
                opts[:build_opts] = BuildOpts.new
                opts[:arch] = opts[:build_opts].arch
                opts[:j] = opts[:build_opts].j
                opts[:build] = opts[:build_opts].build
                opts[:old_kernel] = opts[:build_opts].old_kernel
                opts[:oldconfig_full] = opts[:build_opts].full
                opts[:build_subset] = opts[:build_opts].build_subset

                case action
                when :scp, :backport_todo, :git_fixes
                    opts_parser.on("-r", "--ref <ref>", String, "Bug reference.") { |val| opts[:ref] = val }
                    opts_parser.on("-y", "--yes", "Reply yes by default to whether patch should be applied.") { |_val| opts[:yn_default] = :yes }
                    opts_parser.on("-S", "--skip-broken", "Automatically skip patches that do not apply.") { |_val| opts[:skip_broken] = true }
                when :kabi_check
                    BuildOpts.add_arch_option(opts_parser, opts)
                when :oldconfig
                    BuildOpts.add_options(opts_parser, opts, with_full: true, with_verbose: true)
                when :build
                    BuildOpts.add_options(opts_parser, opts, with_verbose: true, with_old_kernel: true, with_subset: true)
                end

                case action
                when :source_rebase
                    opts_parser.on("-A", "--autofix", "Try to autofix series.conf.") { |_val| opts[:autofix] = true }
                    opts_parser.on("-I", "--no-interactive", "Rebase 'dumbly' not interactively.") { |_val| opts[:no_interactive] = true }
                when :extract_patch
                    opts_parser.on("-c", "--sha1 <SHA1>", String, "Commit to backport.") { |val| opts[:commits] << KernelWork::Commit.new(val) }
                    opts_parser.on("-r", "--ref <ref>", String, "Bug reference.") { |val| opts[:ref] = val }
                    opts_parser.on("-i", "--ignore-tag", "Ignore missing tag or maintainer branch.") { |_val| opts[:ignore_tag] = true }
                    opts_parser.on("-f", "--filename <file.patch>", "Custom patch filename.") { |val| opts[:filename] = val }
                    opts_parser.on("-P", "--patch-path <patch/dir/>", "Custom patch dir. Default is patches.suse unless overriden by branch settings") { |val| opts[:patch_path] = val }
                when :push
                    opts_parser.on("-f", "--force", "Force push.") { |_val| opts[:force_push] = true }
                when :checkpatch
                    opts_parser.on("-F", "--full", "Slower but thorougher checkpatch.") { |_val| opts[:full_check] = true }
                when :list_commits, :lc
                    opts_parser.on("--unpushed", "List unpushed commits.") { |_val| opts[:list_commits] = :unpushed }
                    opts_parser.on("--unmerged", "List unmerged commits.") { |_val| opts[:list_commits] = :unmerged }
                when :fix_ref
                    opts_parser.on("-r", "--ref <ref>", String, "Bug reference.") { |val| opts[:ref] = val }
                when :scp
                    opts_parser.on("-c", "--sha1 <SHA1>", String, "Commit to backport.") { |val| opts[:commits] << KernelWork::Commit.new(val) }
                    opts_parser.on("-f", "--file <FILE>", String, "File containing list of SHA1 to backport.") { |val| opts[:file] = val }
                    BuildOpts.add_options(opts_parser, opts, with_build: true, with_compiler: false)
                when :backport_todo
                    CommitFilter.add_options(opts_parser, opts)
                    opts_parser.on("-R", "--upstream-ref <ref>", String, "Check patches up to <ref> in upstream kernel. Default is origin/master.") { |val| opts[:upstream_ref] = val }
                    opts_parser.on("-B", "--base-ref <ref>", String, "Check patches starting from <ref> in the kernel base. Default is local_branch().") { |val| opts[:base_ref] = val }
                    opts_parser.on("-A", "--apply", "Apply all patches using the scp command.") { |_val| opts[:backport_apply] = true }
                    opts_parser.on("-f", "--file <FILE>", String, "Save the list to a file (load it if --apply).") { |val| opts[:file] = val }
                    opts_parser.on("-i", "--include <sha>", String, "Force including this SHA in the TODO list.") { |val| opts[:backport_include] << KernelWork::Commit.new(val) }
                    opts_parser.on("-x", "--exclude <sha>", String, "Force excluding this SHA from the TODO list.") { |val| opts[:backport_exclude] << KernelWork::Commit.new(val) }
                when :git_fixes
                    opts_parser.on("-s", "--subtree <subtree>", String, "Which subtree to check git-fixes from.") { |val| opts[:git_fixes_subtree] = val }
                    opts_parser.on("-l", "--list-only", "Only list pending patches.") { |_val| opts[:git_fixes_listonly] = true }
                end
            end

            # Check options for validity
            # @param opts [Hash] The options hash
            # @raise [RuntimeError] If required options are missing
            def self.check_opts(opts)
                opts[:filter] = CommitFilter.from_opts(opts) if opts[:action] == :backport_todo
                case opts[:action]
                when :fix_ref
                    if opts[:ref].nil?
                        raise("Ref is required. Use -r <ref>")
                    end
                end
            end

            # Rebase kernel-source directory to latest remote branch
            # @param opts [Hash] Options hash
            # @return [void]
            def source_rebase(opts)
                kernel_source.rebase(autofix: opts[:autofix], interactive: !opts[:no_interactive])
            end

            # Meld last patch action
            # @param _opts [Hash] Options hash
            # @return [void]
            def meld_lastpatch(_opts)
                kernel_source.meld_lastpatch(linux.path)
            end

            # Extract patches action
            # @param opts [Hash] Options hash
            # @return [void]
            # @raise [MissingArgumentError] If no commits are provided
            def extract_patch(opts)
                if opts[:commits].empty?
                    raise MissingArgumentError.new("No SHA1 provided")
                end

                opts[:commits].each do |sha|
                    commit = sha.is_a?(Commit) ? sha : Commit.new(sha, path: linux.path)
                    kernel_source.extract_single_patch(
                        commit,
                        ref: opts[:ref],
                        filename: opts[:filename],
                        patch_path: opts[:patch_path],
                        ignore_tag: opts[:ignore_tag],
                        yn_default: opts[:yn_default]
                    )
                end
            end

            # Fix series.conf action
            # @param opts [Hash] Options hash
            # @return [void]
            def fix_series(opts)
                kernel_source.fix_series(yn_default: opts[:yn_default])
            end

            # Checkpatch action
            # @param opts [Hash] Options hash
            # @return [void]
            def checkpatch(opts)
                kernel_source.checkpatch(full: opts[:full_check])
            end

            # Fix mainline tag in patch
            # @param _opts [Hash] Options hash
            # @return [void]
            def fix_mainline(_opts)
                kernel_source.fix_mainline
            end

            # Fix ref tag in patch and commit message
            # @param opts [Hash] Options hash
            # @return [void]
            def fix_ref(opts)
                kernel_source.fix_ref(opts[:ref])
            end

            # Check for missing fixes
            # @param _opts [Hash] Options hash
            # @return [void]
            def check_fixes(_opts)
                kernel_source.check_fixes
            end

            # List commits action
            # @param opts [Hash] Options hash
            # @return [void]
            def list_commits(opts)
                case opts[:list_commits]
                when :unpushed
                    kernel_source.unpushed_commits
                when :unmerged
                    kernel_source.unmerged_commits
                end
            end
            alias_method :lc, :list_commits

            # Push action
            # @param opts [Hash] Options hash
            # @return [void]
            def push(opts)
                kernel_source.push(force: opts[:force_push])
            end

            # Apply pending patches action
            # @param _opts [Hash] Options hash
            # @return [void]
            def apply_pending(_opts)
                workflow.apply_pending_patches
            end

            # SCP (cherry-pick and extract) action
            # @param opts [Hash] Options hash
            # @return [void]
            # @raise [FileNotFoundError] If the provided file does not exist
            # @raise [MissingArgumentError] If no commits are provided
            def scp(opts)
                linux.branch
                kernel_source.branch

                if opts[:file]
                    if !File.exist?(opts[:file])
                        raise FileNotFoundError.new(opts[:file])
                    end
                    opts[:commits] = File.readlines(opts[:file]).map do |l|
                        l = l.strip
                        next if l.empty?
                        if l =~ /^([0-9a-f]+)\s+#(.*)$/
                            Commit.new($1, subject: $2, path: linux.path)
                        else
                            Commit.new(l.split(/\s+/).first, path: linux.path)
                        end
                    end.compact
                end

                if opts[:commits].empty?
                    raise MissingArgumentError.new("No SHA1 provided")
                end

                commits = opts[:commits].dup
                begin
                    workflow.backport_commits(
                        commits,
                        build_opts: BuildOpts.from_opts(opts),
                        skip_broken: opts[:skip_broken],
                        yn_default: opts[:yn_default],
                        ref: opts[:ref],
                        full_check: opts[:full_check]
                    )
                ensure
                    save_scp_commits(opts, commits)
                end
            end

            # Oldconfig action
            # @param opts [Hash] Options hash
            # @return [void]
            def oldconfig(opts)
                workflow.oldconfig(BuildOpts.from_opts(opts))
            end

            # Build action
            # @param opts [Hash] Options hash
            # @return [void]
            def build(opts)
                workflow.build(BuildOpts.from_opts(opts))
            end

            # Diff paths action
            # @param _opts [Hash] Options hash
            # @return [void]
            def diffpaths(_opts)
                paths = linux.diffpaths(linux.branch)
                paths.each { |p| puts p }
            end

            # Check kABI action
            # @param opts [Hash] Options hash
            # @return [void]
            def kabi_check(opts)
                linux.branch
                _arch_name, _arch, b_dir = linux.arch_to_bdir(opts[:arch])
                linux.kabi_check(
                    symvers_path: "#{b_dir}/Module.symvers",
                    arch: opts[:arch],
                    kabi_dir: kernel_source.path
                )
            end

            # Backport TODO list action
            # @param opts [Hash] Options hash
            # @return [void]
            def backport_todo(opts)
                head = opts[:upstream_ref]
                t_branch = opts[:base_ref] || linux.local_branch

                filter = CommitFilter.from_opts(opts[:filter] || opts)
                in_head = linux.gen_filtered_list(head, t_branch, filter)
                if linux.respond_to?(:filterInHouse)
                    linux.filterInHouse(opts, in_head)
                else
                    workflow.filter_in_house(in_head, include_shas: opts[:backport_include], exclude_shas: opts[:backport_exclude])
                end

                if in_head.empty?
                    log(:INFO, "No patch left to backport ! Congrats !")
                    return
                end

                if opts[:file]
                    File.open(opts[:file], 'w') do |f|
                        in_head.reverse.each do |x|
                            f.puts x.to_s
                        end
                    end
                    log(:INFO, "#{in_head.length} patches written to #{opts[:file]}")
                else
                    linux.runGitInteractive("show --no-patch --format=oneline #{in_head.map(&:sha).join(' ')}", catch_err: true)
                end

                if opts[:backport_apply] == true
                    opts[:commits] = in_head.reverse
                    scp(opts)
                end
            end

            # Git fixes action
            # @param opts [Hash] Options hash
            # @return [void]
            def git_fixes(opts)
                linux.branch
                commits = linux.fetch_git_fixes(subtree: opts[:git_fixes_subtree], branch: linux.branch)

                if commits.empty?
                    log(:INFO, "Great job. Nothing to do here")
                    return
                end

                log(:INFO, "List of patches to apply")
                opts[:commits] = commits.map do |commit|
                    applied = kernel_source.is_applied?(commit)
                    status = applied ? "APPLIED".green : "PENDING".brown
                    desc = commit.desc

                    log(:INFO, "  #{status}\t" + desc)
                    applied ? nil : commit
                end.compact

                if opts[:commits].empty?
                    log(:INFO, "Great job. Nothing to do here")
                    return
                end
                return if opts[:git_fixes_listonly] == true

                scp(opts)
            end

            private

            # Save unhandled SCP commits back to a file if requested
            # @param opts [Hash] Options hash containing :file
            # @param commits [Array<Commit>] List of commits to save
            # @return [void]
            def save_scp_commits(opts, commits)
                if opts[:file]
                    File.open(opts[:file], 'w') do |f|
                        commits.each { |u| f.puts u.to_s }
                    end
                    if !commits.empty?
                        log(:INFO, "Unhandled patches written back to #{opts[:file]}")
                    end
                end
            end
        end
    end
end
