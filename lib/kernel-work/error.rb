module KernelWork

    # Base class for all KernelWork exceptions
    class KernelWorkError < RuntimeError
    end

    # Exception raised when a shell command fails
    class RunError < KernelWorkError
        # Initialize a new RunError
        # @param err_code [Integer] Exit code
        # @param msg [String] Error message
        def initialize(err_code, msg = nil)
            super("Command failed with error code '#{err_code}'")
            @err_code = err_code
            @msg = msg
        end
        # @!attribute [r] err_code
        #   @return [Integer] The exit code of the failed command
        # @!attribute [r] msg
        #   @return [String] Optional error message
        attr_reader :err_code, :msg
    end

    # Exception raised when the git branch cannot be determined
    class UnknownBranch < KernelWorkError
        # Initialize a new UnknownBranch error
        # @param path [String] Path where branch detection failed
        def initialize(path)
            super("Failed to detect branch name in #{path}")
        end
    end

    # Exception raised when upstream and SUSE branches do not match
    class BranchMismatch < KernelWorkError
        # Initialize a new BranchMismatch error
        # @param upstream_br [String] Upstream branch name
        # @param suse_br [String] SUSE branch name
        def initialize(upstream_br, suse_br)
            super("Branch mismatch. Linux tree has '#{upstream_br}'. kernel-source has '#{suse_br}'")
        end
    end

    # Exception raised when SCP is aborted by user
    class SCPAbort < KernelWorkError
    end

    # Exception raised when SCP of a patch is skipped by user
    class SCPSkip < KernelWorkError
        # Initialize a new SCPSkip error
        # @param s [String] Message or patch info
        def initialize(s="")
            super("Skipping patch #{s}")
        end
    end

    # Exception raised when git-fixes cannot be fetched
    class GitFixesFetchError < KernelWorkError
    end

    # Exception raised when no mainline tag is found for a SHA
    class NoSuchMainline < KernelWorkError
    end

    # Exception raised when the base kernel version cannot be determined
    class BaseKernelError < KernelWorkError
    end

    # Exception raised when no bug/CVE reference is provided
    class NoRefError < KernelWorkError
        # Initialize a new NoRefError
        def initialize()
            super("No bug/CVE ref provided nor default set")
        end
    end

    # Exception raised when checkpatch fails
    class CheckPatchError < KernelWorkError
        # Initialize a new CheckPatchError
        def initialize()
            super("Patchlist does not apply")
        end
    end

    # Exception raised when a commit is empty
    class EmptyCommitError < KernelWorkError
    end

    # Exception raised when blacklist.conf conflicts cannot be auto-resolved
    class BlacklistConflictError < KernelWorkError
        # Initialize a new BlacklistConflictError
        def initialize()
            super("Cannot auto-resolve blacklist.conf conflicts")
        end
    end

    # Exception raised when a SHA is provided instead of a Commit object
    class ShaNotCommitError < KernelWorkError
        # Initialize a new ShaNotCommitError
        def initialize()
            super("SHA provided instead of KernelWork::Commit objecty")
        end
    end

    # Exception raised when a SHA is not found in the repository
    class ShaNotFoundError < KernelWorkError
        # Initialize a new ShaNotFoundError
        # @param sha [String] The missing SHA
        def initialize(sha)
            super("SHA '#{sha}' was not found in the repository")
        end
    end

    # Exception raised when a required argument is missing
    class MissingArgumentError < KernelWorkError
        # Initialize a new MissingArgumentError
        # @param arg [String] The name of the missing argument
        def initialize(arg)
            super("Missing required argument: #{arg}")
        end
    end

    # Exception raised when a file is not found
    class FileNotFoundError < KernelWorkError
        # Initialize a new FileNotFoundError
        # @param path [String] The path to the missing file
        def initialize(path)
            super("File not found: #{path}")
        end
    end

    # Exception raised when a target file already exists
    class TargetFileExistsError < KernelWorkError
        # Initialize a new TargetFileExistsError
        # @param path [String] The path to the existing file
        def initialize(path)
            super("Target file already exists: #{path}")
        end
    end

    # Exception raised when patch information is invalid or missing
    class PatchInfoError < KernelWorkError
        # Initialize a new PatchInfoError
        # @param msg [String] Error message
        def initialize(msg="Invalid patch information")
            super(msg)
        end
    end

    # Exception raised when patch extraction fails
    class PatchExtractionError < KernelWorkError
        # Initialize a new PatchExtractionError
        # @param msg [String] Error message
        def initialize(msg="Failed to extract patch")
            super(msg)
        end
    end
end