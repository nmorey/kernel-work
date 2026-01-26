module KernelWork

    class RunError < RuntimeError
        def initialize(err_code, msg = nil)
            super("Command failed with error code '#{err_code}'")
            @err_code = err_code
            @msg = msg
        end
        attr_reader :err_code, :msg
    end

    class UnknownBranch < RuntimeError
        def initialize(path)
            super("Failed to detect branch name in #{path}")
        end
    end

    class BranchMismatch < RuntimeError
        def initialize(upstream_br, suse_br)
            super("Branch mismatch. Linux tree has '#{upstream_br}'. kernel-source has '#{suse_br}'")
        end
    end

    # SCP Abort by user input
    class SCPAbort < RuntimeError
    end

    # SCP of this patch skipped by user
    class SCPSkip < RuntimeError
        def initialize(s="")
            super("Skipping patch #{s}")
        end
    end

    # Failed to retrieve GitFixes
    class GitFixesFetchError < RuntimeError
    end

    # Failed to find a mainline tag containing a sha
    class NoSuchMainline < RuntimeError
    end

    # Failed to find which kernel version we are based on
    class BaseKernelError < RuntimeError
    end

    class NoRefError < RuntimeError
        def initialize()
            super("No bug/CVE ref provided nor default set")
        end
    end

    class CheckPatchError < RuntimeError
        def initialize()
            super("Patchlist does not apply")
        end
    end

    class EmptyCommitError < RuntimeError
    end

    class BlacklistConflictError < RuntimeError
        def initialize()
            super("Cannot auto-resolve blacklist.conf conflicts")
        end
    end

    class ShaNotCommitError < RuntimeError
        def initialize()
            super("SHA provided instead of KernelWork::Commit objecty")
        end
    end

    class ShaNotFoundError < RuntimeError
        def initialize(sha)
            super("SHA '#{sha}' was not found in the repository")
        end
    end
end
