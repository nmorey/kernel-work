module KernelWork
    # Encapsulates build configuration options for kernel compilation operations
    class LinuxBuildOpts
        # @!attribute [rw] arch
        #   @return [Symbol] Target build architecture
        attr_accessor :arch

        # @!attribute [rw] j
        #   @return [Integer, nil] Parallel build jobs count
        attr_accessor :j

        # @!attribute [rw] cc
        #   @return [String, nil] Compiler override
        attr_accessor :cc

        # @!attribute [rw] hostcc
        #   @return [String, nil] Host compiler override
        attr_accessor :hostcc

        # @!attribute [rw] verbose
        #   @return [Boolean] Enable verbose build output (V=1)
        attr_accessor :verbose

        # @!attribute [rw] old_kernel
        #   @return [Boolean] Enable M= build flag for older kernels
        attr_accessor :old_kernel

        # @!attribute [rw] full
        #   @return [Boolean] If true, do not disable MODVERSIONS and debug symbols in oldconfig
        attr_accessor :full

        # @!attribute [rw] build
        #   @return [Boolean] Whether to execute build after applying commits
        attr_accessor :build

        # @!attribute [rw] build_subset
        #   @return [Array<String>] Subtree path list to restrict the build to
        attr_accessor :build_subset

        # Initialize build options
        # @param arch [Symbol] Target build architecture
        # @param j [Integer, nil] Parallel build jobs count
        # @param cc [String, nil] Compiler override
        # @param hostcc [String, nil] Host compiler override
        # @param verbose [Boolean] Enable verbose build output
        # @param old_kernel [Boolean] Enable M= build option for older kernels
        # @param full [Boolean] Keep MODVERSIONS and debug info
        # @param build [Boolean] Execute build after applying
        # @param build_subset [Array<String>] Target subtree paths
        def initialize(arch: :x86_64, j: nil, cc: nil, hostcc: nil, verbose: false, old_kernel: false, full: false, build: false, build_subset: [])
            @arch = arch.to_sym
            @j = j || KernelWork.config.linux.default_j_opt
            @cc = cc
            @hostcc = hostcc
            @verbose = verbose || false
            @old_kernel = old_kernel || false
            @full = full || false
            @build = build || false
            @build_subset = build_subset ? build_subset.dup : []
        end

        # Convert all build options to a Hash
        # @return [Hash{Symbol => Object}] Hash representation of all build options
        def to_h
            {
                arch: @arch,
                j: @j,
                cc: @cc,
                hostcc: @hostcc,
                verbose: @verbose,
                old_kernel: @old_kernel,
                full: @full,
                build: @build,
                build_subset: @build_subset
            }
        end
    end
end
