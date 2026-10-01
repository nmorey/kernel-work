module KernelWork
    module CLI
        # Encapsulates build configuration options and CLI flags for kernel build operations
        class BuildOpts < LinuxBuildOpts
            # Initialize build options from CLI options hash, existing LinuxBuildOpts, or defaults
            # @param opts [Hash, LinuxBuildOpts, nil] CLI options hash or existing LinuxBuildOpts
            def initialize(opts = nil)
                if opts.is_a?(Hash)
                    super(
                        arch: opts[:arch] || :x86_64,
                        j: opts[:j],
                        cc: opts[:cc],
                        hostcc: opts[:hostcc],
                        verbose: opts[:build_verbose] || opts[:verbose] || false,
                        old_kernel: opts[:old_kernel] || false,
                        full: opts[:oldconfig_full] || opts[:full] || false,
                        build: opts[:build] || false,
                        build_subset: opts[:build_subset] || []
                    )
                elsif opts.is_a?(LinuxBuildOpts)
                    super(
                        arch: opts.arch,
                        j: opts.j,
                        cc: opts.cc,
                        hostcc: opts.hostcc,
                        verbose: opts.verbose,
                        old_kernel: opts.old_kernel,
                        full: opts.full,
                        build: opts.build,
                        build_subset: opts.build_subset
                    )
                else
                    super()
                end
            end

            # Construct a BuildOpts instance from a Hash, LinuxBuildOpts, or nil
            # @param opts [Hash, LinuxBuildOpts, nil] Source options
            # @return [BuildOpts] Build options instance
            def self.from_opts(opts)
                return opts if opts.is_a?(BuildOpts)
                return new(opts) if opts.is_a?(LinuxBuildOpts)
                return new if opts.nil? || !opts.is_a?(Hash)
                return opts[:build_opts] if opts[:build_opts].is_a?(BuildOpts)
                return new(opts[:build_opts]) if opts[:build_opts].is_a?(LinuxBuildOpts)

                new(opts)
            end

            # Add target architecture option (-a / --arch) to OptionParser
            # @param opts_parser [OptionParser] Option parser
            # @param target [Hash, LinuxBuildOpts] Options destination
            # @return [void]
            def self.add_arch_option(opts_parser, target)
                b_opts = target.is_a?(LinuxBuildOpts) ? target : (target[:build_opts] ||= new)
                supported = Linux.supported_archs.map { |x, _y| x }.join(", ")
                opts_parser.on("-a", "--arch <arch>", String, "Arch to build for. Default=x86_64. Supported=#{supported}") do |val|
                    val_sym = val.to_sym
                    raise ("Unsupported arch '#{val_sym}'") if Linux.supported_archs[val_sym].nil?
                    b_opts.arch = val_sym
                    target[:arch] = val_sym if target.is_a?(Hash)
                end
            end

            # Add build options to OptionParser
            # @param opts_parser [OptionParser] Option parser
            # @param target [Hash, LinuxBuildOpts] Options destination
            # @param with_build [Boolean] Include -B / --build flag
            # @param with_compiler [Boolean] Include -a, -j, -c, --hostcc
            # @param with_verbose [Boolean] Include -v / --verbose flag
            # @param with_old_kernel [Boolean] Include -o / --old-kernel flag
            # @param with_full [Boolean] Include -F / --full flag
            # @param with_subset [Boolean] Include -p, -I flags
            # @return [void]
            def self.add_options(opts_parser, target, with_build: false, with_compiler: true, with_verbose: false, with_old_kernel: false, with_full: false, with_subset: false)
                b_opts = target.is_a?(LinuxBuildOpts) ? target : (target[:build_opts] ||= new)

                if with_build
                    opts_parser.on("-B", "--build", "Build commit after applying.") do |_val|
                        b_opts.build = true
                        target[:build] = true if target.is_a?(Hash)
                    end
                end

                if with_compiler
                    add_arch_option(opts_parser, target)

                    default_j = KernelWork.config.linux.default_j_opt
                    opts_parser.on("-j<num>", Integer, "Number of // builds. Default '#{default_j}'") do |val|
                        b_opts.j = val
                        target[:j] = val if target.is_a?(Hash)
                    end

                    opts_parser.on("-c", "--cc <compiler>", String, "Override default compiler") do |val|
                        b_opts.cc = val
                        target[:cc] = val if target.is_a?(Hash)
                    end

                    opts_parser.on("--hostcc <compiler>", String, "Override default host compiler") do |val|
                        b_opts.hostcc = val
                        target[:hostcc] = val if target.is_a?(Hash)
                    end
                end

                if with_verbose
                    opts_parser.on("-v", "--verbose", "Build with V=1") do |_val|
                        b_opts.verbose = true
                        target[:build_verbose] = true if target.is_a?(Hash)
                    end
                end

                if with_old_kernel
                    opts_parser.on("-o", "--old-kernel", "Use M= option to build for old kernels") do |_val|
                        b_opts.old_kernel = true
                        target[:old_kernel] = true if target.is_a?(Hash)
                    end
                end

                if with_full
                    opts_parser.on("-F", "--full", "Do not disable MODVERSIONS.") do |_val|
                        b_opts.full = true
                        target[:oldconfig_full] = true if target.is_a?(Hash)
                    end
                end

                if with_subset
                    opts_parser.on("-p", "--path <path>", String, "Path to subtree to build. Can be specified multiple times.") do |val|
                        b_opts.build_subset << val
                        (target[:build_subset] ||= []) << val if target.is_a?(Hash)
                    end
                    opts_parser.on("-I", "--infiniband", String, "Build infiniband subtree") do |_val|
                        b_opts.build_subset << "drivers/infiniband"
                        (target[:build_subset] ||= []) << "drivers/infiniband" if target.is_a?(Hash)
                    end
                end
            end
        end
    end
end
