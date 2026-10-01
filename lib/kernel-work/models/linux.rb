require 'csv'
require 'yaml'
require 'fileutils'

module KernelWork
    # Class for handling upstream Linux kernel git operations and builds
    class Linux < Common
        # @!attribute [r] path
        #   @return [String] Linux git directory path
        attr_reader :path

        # Helper to access supported archs from config
        # @return [Hash] Supported architectures
        def self.supported_archs
            KernelWork.config.linux.archs
        end

        # Helper to access compiler rules from config and process ranges
        # @return [Array<Hash>] Compiler rules with parsed ranges
        def self.compiler_rules
            rules = KernelWork.config.linux.compiler_rules.to_a.map(&:dup)
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
            rules
        end

        # Initialize a new Linux model object
        # @param path [String, nil] Path to linux git tree
        def initialize(path = nil)
            @path = path || KernelWork.config.linux_git
            begin
                set_branches()
            rescue UnknownBranch
                @branch = nil
            end
        end

        # Get current branch
        # @return [String] Branch name
        # @raise [UnknownBranch] If branch is not detected
        def branch
            raise UnknownBranch.new(@path) if @branch.nil?
            @branch
        end

        # Get local branch name
        # @return [String] Local branch name
        # @raise [UnknownBranch] If branch is not detected
        def local_branch
            raise UnknownBranch.new(@path) if @local_branch.nil?
            @local_branch
        end

        # Check if current branch matches expected
        # @param br [String] Expected branch
        # @return [Boolean] True if match
        # @raise [UnknownBranch] If branch is not detected
        # @raise [BranchMismatch] If branches do not match
        def branch?(br)
            raise UnknownBranch.new(@path) if @branch.nil?
            raise BranchMismatch.new(@branch, br) if @branch != br

            @branch == br
        end

        # Check if commit is an ancestor of a given git reference
        # @param commit [Commit, String] Commit or SHA to check
        # @param ref [String] Reference to check ancestry against (default: HEAD)
        # @return [Boolean] True if commit is an ancestor of ref
        def is_ancestor?(commit, ref = "HEAD")
            sha = commit.is_a?(Commit) ? commit.sha : commit
            begin
                runGit("merge-base --is-ancestor #{sha} #{ref}")
                true
            rescue
                false
            end
        end

        # Get the kernel base version
        # @return [KV] Kernel version object
        # @raise [BaseKernelError] If version cannot be determined
        def kernel_base
            return @kv if @kv != nil
            begin
                @kv = KV.new(runGit("describe --tags --match='v*' HEAD").gsub(/v([0-9.]+)-.*$/, '\1'))
                @kv
            rescue
                raise BaseKernelError.new()
            end
        end

        # Convert architecture to build directory and arch info
        # @param arch [Symbol, String] Architecture name
        # @return [Array(Symbol, Hash, String)] Arch name, Arch info, Build dir
        # @raise [RuntimeError] If arch is unsupported
        def arch_to_bdir(arch)
            arch_sym = arch.to_sym
            raise ("Unsupported arch '#{arch_sym}'") if Linux.supported_archs[arch_sym].nil?
            arch_info = Linux.supported_archs[arch_sym]
            b_dir = "build-#{arch_sym}/"
            [arch_sym, arch_info, b_dir]
        end


        # Generate make flags for build
        # @param build_opts [LinuxBuildOpts] Build options instance
        # @return [String] Make flags string
        def gen_make_flags(build_opts)
            arch_name, arch_info, b_dir = arch_to_bdir(build_opts.arch)
            comp_cc = arch_info[:CC].to_s
            host_cc = "HOSTCC=\"ccache gcc\""
            cross_compile = ""
            extra_opts = ""

            gcc_ver = "gcc"
            cflags = ""

            kv = kernel_base
            found_rule = Linux.compiler_rules.find do |rule|
                if rule[:range_obj]
                    rule[:range_obj].cover?(kv)
                else
                    true # Default fallback
                end
            end
            gcc_ver = found_rule[:gcc] if found_rule
            cflags = found_rule[:cflags] if found_rule
            comp_cc = comp_cc.gsub(/gcc/, gcc_ver)
            host_cc = host_cc.gsub(/gcc/, gcc_ver)

            if arch_info[:CROSS_COMPILE] != nil
                comp_cc = comp_cc.gsub(/gcc/, arch_info[:CROSS_COMPILE] + "gcc")
                cross_compile = "CROSS_COMPILE=\"#{arch_info[:CROSS_COMPILE]}\""
            end
            if build_opts.cc != nil
                comp_cc = "CC=#{build_opts.cc}"
            end
            if build_opts.hostcc != nil
                host_cc = "HOSTCC=#{build_opts.hostcc}"
            end
            extra_opts = "KERNELRELEASE=\"devel\" KBUILD_NOCMDDEP=1 KBUILD_BUILD_TIMESTAMP=\"2024-01-01 00:00:00\""
            if build_opts.verbose == true
                extra_opts += " #{extra_opts} V=1"
            end
            if cflags.to_s != ""
                extra_opts += " KCFLAGS=\"#{cflags}\" HOSTCFLAGS=\"#{cflags}\""
            end
            "#{comp_cc} #{host_cc} -j#{build_opts.j} O=#{b_dir} #{extra_opts} #{arch_info[:ARCH].to_s} #{cross_compile} "
        end


        # Run kernel build
        # @param build_opts [LinuxBuildOpts] Build options instance
        # @param flags [String] Additional make targets or flags
        # @return [Integer] Exit code
        def run_build(build_opts, flags = "")
            make_flags = gen_make_flags(build_opts)
            runSystem("nice -n 19 make #{make_flags} #{flags}")
            0
        end


        # Run oldconfig or olddefconfig
        # @param build_opts [LinuxBuildOpts] Build options instance
        # @param config_file [String] Source kernel config file path
        # @param force [Boolean] Force regeneration of config
        # @return [void]
        def run_oldconfig(build_opts, config_file, force: true)
            _arch_name, _arch_info, b_dir = arch_to_bdir(build_opts.arch)

            return if force != true && File.exist?("#{@path}/#{b_dir}/.config")

            runSystem("rm -Rf #{b_dir} && mkdir #{b_dir} && cp #{config_file} #{b_dir}/.config")
            if build_opts.full == false
                runSystem("./scripts/config --file #{b_dir}/.config --disable CONFIG_DEBUG_INFO")
                runSystem("./scripts/config --file #{b_dir}/.config --disable CONFIG_DEBUG_INFO_BTF")
                runSystem("./scripts/config --file #{b_dir}/.config --disable CONFIG_DEBUG_INFO_REDUCED")
                runSystem("./scripts/config --file #{b_dir}/.config --disable CONFIG_GDB_SCRIPTS")
                runSystem("./scripts/config --file #{b_dir}/.config --disable CONFIG_GCC_PLUGINS")
                runSystem("./scripts/config --file #{b_dir}/.config --disable CONFIG_LIVEPATCH_IPA_CLONES")
                runSystem("./scripts/config --file #{b_dir}/.config --disable CONFIG_MODVERSIONS")
            end
            case kernel_base
            when KV.new(0, 0)...KV.new(3, 7)
                run_build(build_opts, "oldnoconfig")
                run_build(build_opts, "modules_prepare")
            else
                run_build(build_opts, "olddefconfig")
                run_build(build_opts, "modules_prepare")
            end
        end


        # Find build subset based on modified files in a commit
        # @param commit [Commit, String] Commit or SHA to inspect
        # @return [Array<String>, String] Target directory paths or empty string
        # @raise [PatchSubsetNotFoundError] If no changed files or valid subset found
        def find_build_subset(commit)
            c = commit.is_a?(Commit) ? commit : Commit.new(commit.to_s, safe_sha: true)
            files = []
            begin
                files_raw = runGit("diff-tree --no-commit-id --name-only -r #{c.f_sha}")
                files = files_raw.split("\n").map(&:strip).reject(&:empty?)
            rescue => _e
                raise PatchSubsetNotFoundError.new() if files.empty?
            end

            raise PatchSubsetNotFoundError.new() if files.empty?
            dirs = files.map do |f|
                if f =~ /^include\//
                    nil
                else
                    f = File.dirname(f) while !File.exist?("#{@path}/#{f}/Makefile") && f != "." && f != "/"
                    f == "." || f == "/" ? nil : f
                end
            end.uniq.compact
            return "" if dirs.empty?

            merged_dirs = [dirs[0]]
            dirs[1..-1].each do |dir|
                matched = false
                merged_dirs.each_with_index do |mdir, idx|
                    if dir =~ /^#{mdir}\//
                        matched = true
                        break
                    end
                    if mdir =~ /^#{dir}\//
                        merged_dirs[idx] = dir
                        matched = true
                        next
                    end
                end
                merged_dirs << dir if matched == false
            end
            merged_dirs.compact
        end

        # Build the kernel at a specific commit, only building the relevant subset of files changed by that commit.
        # @param commit [Commit, String] Commit object or SHA representing the commit to build
        # @param build_opts [LinuxBuildOpts] Build options instance
        # @return [Integer] Exit code
        def build_commit(commit, build_opts = LinuxBuildOpts.new)
            b_opts = build_opts || LinuxBuildOpts.new

            subset = find_build_subset(commit)
            log(:INFO, "building subtree '#{subset}'...")
            sub_targets = []
            if subset.is_a?(Array) && !subset.empty?
                sub_targets = subset
            elsif subset.is_a?(String) && !subset.empty?
                sub_targets = [subset]
            end

            build_target = ""
            if !sub_targets.empty?
                use_old = b_opts.old_kernel
                if !use_old && kernel_base < KV.new(5, 3)
                    use_old = true
                end
                formatted_sub = sub_targets.map { |s| s.gsub(/\/+$/, '') + '/' }
                build_target = formatted_sub.join(" ")
            end

            # Auto run oldconfig if necessary
            arch_name, _arch_info, _b_dir = arch_to_bdir(b_opts.arch)
            config_file = "#{KernelWork.config.kernel_source_dir}/config/#{arch_name}/default"
            run_oldconfig(b_opts, config_file, force: false)

            run_build(b_opts, build_target)
        end

        # Generate filtered list of commits between ahead and trailing references
        # @param ahead [String] Ahead reference
        # @param trailing [String] Trailing reference
        # @param filter [CommitFilter] Commit filter instance
        # @return [Array<Commit>] List of filtered commits
        def gen_filtered_list(ahead, trailing, filter)
            raise ArgumentError, "filter must be a KernelWork::CommitFilter" unless filter.is_a?(KernelWork::CommitFilter)

            rev_list_opts = ["rev-list", "--no-merges"]
            log_opts = ["|", "git", "log", "--stdin", "--no-walk", "--format=oneline"]
            if filter.fixes
                log_opts << "--grep='Fixes:'"
            end
            if filter.grep
                log_opts << "--grep='#{filter.grep}'"
            end
            if filter.author
                log_opts << "--author='#{filter.author}'"
            end
            rev_list_opts << "#{ahead} ^#{trailing}"
            paths_arg = []
            if !filter.paths.empty?
                paths_arg += filter.paths
            end
            if !filter.exclude_paths.empty?
                filter.exclude_paths.each do |p|
                    if p.start_with?(":(exclude)")
                        paths_arg << "'#{p}'"
                    else
                        paths_arg << "':(exclude)#{p}'"
                    end
                end
            end

            if !paths_arg.empty?
                rev_list_opts << "--"
                rev_list_opts << paths_arg.join(" ")
            end

            patches = runGit((rev_list_opts + log_opts).join(" ")).split("\n")
            if filter.skip_treewide
                patches.delete_if { |x| x =~ /(tree|kernel)-?wide/ }
            end
            n_patches = patches.length
            idx = 0
            list = patches.map do |x|
                log(:PROGRESS, "Checking patches in #{ahead} ^#{trailing} (#{idx}/#{n_patches})") if (idx % 10) == 0
                idx += 1
                x =~ /^([0-9a-f]*) (.*)$/
                Commit.new($1, subject: $2, safe_sha: true)
            end
            log(:INFO, "Checking patches in #{ahead} ^#{trailing} (#{n_patches}/#{n_patches})")
            list
        end

        # Cherry-pick a single commit into the Linux git tree, handling conflicts
        # @param commit [Commit] The commit to cherry-pick
        # @param skip_broken [Boolean] Automatically skip patches that fail to apply
        # @return [void]
        # @raise [ShaNotCommitError] If commit is not a Commit object
        # @raise [SCPSkip] If user skips the patch or it fails to apply and skip_broken is set
        # @raise [SCPAbort] If user aborts the operation
        def cherry_pick_one(commit, skip_broken: false)
            raise ShaNotCommitError.new() if !commit.is_a?(KernelWork::Commit)

            begin
                runGitInteractive("cherry-pick #{commit.sha}")
            rescue
                if skip_broken == true
                    e = SCPSkip.new(commit.to_s)
                    log(:WARNING, e.to_s)
                    runGitInteractive("cherry-pick --abort")
                    raise(e)
                end
                begin
                    runGitInteractive("diff")
                rescue
                    # Do not crash if diff was interrupted
                end
                log(:INFO, "Entering subshell to fix conflicts. Exit when done")
                runSystem("PS1_WARNING='SCP FIX' bash", catch_err: true)
                rep = confirm({}, "continue with scp",
                              ignore_default: true,
                              allowed_reps: ["y", "n", "s"],
                              usage: "[y]es/[n]o/[s]kip")
                case rep
                when "n"
                    runGitInteractive("cherry-pick --abort")
                    raise(SCPAbort)
                when "s"
                    runGitInteractive("cherry-pick --abort")
                    e = SCPSkip.new(commit.to_s)
                    log(:INFO, e.to_s)
                    raise(e)
                end
            end
        end

        # Diff paths action: list changed directories since reference branch
        # @param branch [String] Reference branch to compare against
        # @return [Array<String>] List of unique changed directory paths
        def diffpaths(branch)
            output = runGit("diff #{KernelWork.config.linux.remote}/#{branch}..HEAD --stat=500")
            output.split("\n").map do |l|
                next if l =~ /files changed/
                File.dirname(l.strip.gsub(/[ \t]+.*$/, ''))
            end.uniq.compact
        end

        # Fetch git fixes from remote service for a given subtree and branch
        # @param subtree [String] Target kernel subtree
        # @param branch [String] Target branch name
        # @return [Array<Commit>] List of fixes identified for the given branch
        # @raise [GitFixesFetchError] If retrieval fails
        def fetch_git_fixes(subtree:, branch:)
            str = nil
            begin
                str = run("curl -f -s #{KernelWork.config.linux.git_fixes_url}/#{subtree}")
            rescue RunError => e
                if e.err_code() != 22
                    raise(GitFixesFetchError)
                else
                    log(:WARNING, "curl HTTP failure. Assuming 404 so nothing more to do here")
                    return []
                end
            end

            pre = true
            cur_sha = nil
            cur_subject = nil
            fixes = str.lines.map do |line|
                commit = nil
                case line.chomp
                when /^=+$/
                    pre = false
                when /^([0-9a-f]+) (.*)$/
                    cur_sha = $1
                    cur_subject = $2
                when /^[ \t]+Considered for ([^ ]+)/
                    commit = Commit.new(cur_sha, subject: cur_subject) if pre == false && $1 == branch
                when /^$/
                    cur_sha = nil
                    cur_subject = nil
                end
                commit
            end.compact
            fixes
        end

        # Run kABI compatibility verification
        # @param symvers_path [String] Path to built Module.symvers
        # @param arch [Symbol] Target architecture
        # @param kabi_dir [String, nil] Path to kabi directory
        # @return [void]
        def kabi_check(symvers_path:, arch: :x86_64, kabi_dir: nil)
            arch_name, _arch_info, _b_dir = arch_to_bdir(arch)
            k_dir = kabi_dir || KernelWork.config.kernel_source_dir
            runSystem("#{k_dir}/rpm/kabi.pl --rules #{k_dir}/kabi/severities #{k_dir}/kabi/#{arch_name}/symvers-default #{symvers_path}")
        end

    end
end
