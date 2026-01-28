module KernelWork
    # Represents a git commit with utility methods to retrieve metadata
    class Commit < Common
        # @!attribute [r] sha
        #   @return [String] The commit SHA
        # @!attribute [r] orig_tag
        #   @return [String] The original tag that introduced the commit
        # @!attribute [r] git_repo
        #   @return [String] The git repository URL where the commit was introduced (ie maintainer tree)
        attr_reader :sha, :orig_tag, :git_repo

        # Initialize a new Commit object
        #
        # @param sha [String] The commit SHA
        # @param subject [String, nil] The commit subject (optional)
        # @param patch_id [String, nil] The patch ID (optional)
        def initialize(sha, subject = nil, patch_id = nil)
            @path=KernelWork.config.linux_git
            @sha = sha
            @subject = subject
            @patch_id = patch_id
        end

        # Retrieve the subject of the commit
        #
        # @return [String] The commit subject
        # @raise [ShaNotFoundError] If the SHA is not found
        def subject()
            return @subject if @subject != nil

            begin
                desc=runGit("log -n1  --format=oneline --no-decorate #{@sha}")
                desc =~ /^[0-9a-f]+\s+(.*)$/
                @subject = $1
            rescue
                raise ShaNotFoundError.new(@sha)
            end
            return @subject
        end

        # Retrieve the patch ID of the commit
        #
        # @return [String] The patch ID
        # @raise [ShaNotFoundError] If the SHA is not found
        def patch_id()
            return @patch_id if @patch_id != nil

            begin
                @patch_id = runGit("format-patch -n1 #{@sha} --stdout | git patch-id | awk '{ print $1}'").chomp()
            rescue
                raise ShaNotFoundError.new(@sha)
            end
            return @patch_id
        end

        # Retrieve the full SHA of the commit
        #
        # @return [String] The full SHA
        # @raise [ShaNotFoundError] If the SHA is not found
        def f_sha()
            return @f_sha if @f_sha != nil
            begin
                @f_sha = runGit("rev-parse #{@sha}")
                return @f_sha
            rescue
                raise ShaNotFoundError.new(@sha)
            end
        end

        # Return a description of the commit (short SHA + subject)
        #
        # @return [String] Description string
        def desc()
            "#{@sha[0..11]} (\"#{subject()}\")"
        end

        # Check if the commit info is valid and present in tags or maintainer branches
        #
        # @param opts [Hash] Options hash
        # @option opts [Boolean] :ignore_tag Whether to ignore missing tags
        # @return [void]
        # @raise [PatchInfoError] If commit is not in any tag/repo and ignore_tag is false
        def check_patch_info(opts)
            f_sha()
            get_mainline()

            if @orig_tag == nil then
                if opts[:ignore_tag] != true then
                    raise PatchInfoError.new("Commit is not contained in any tag nor maintainer repo")
                else
                    @f_sha = ""
                    @orig_tag="Never, in-house patch"

                end
            end
        end

        # Generate a patch file for the commit
        #
        # @return [String] The filename of the generated patch
        def gen_patch()
            @patchname = runGit("format-patch -n1 #{sha}")
        end

        # Retrieve the patch filename, generating it if necessary
        #
        # @return [String] The patch filename
        def patchname()
            return @patchname if @patchname != nil

            @patchname = runGit("format-patch -n1 #{sha}")
            return @patchname
        end

        # String representation of the commit
        #
        # @return [String] SHA and subject
        def to_s
            if @subject
                "#{@sha} ##{@subject}"
            else
                @sha
            end
        end

        # Equality check
        #
        # @param other [Commit, String] Another commit object or SHA string
        # @return [Boolean] True if SHAs match
        def ==(other)
            if other.is_a?(Commit)
                @sha == other.sha
            elsif other.is_a?(String)
                @sha == other
            else
                false
            end
        end

        private
        # Attempt to find the mainline tag or maintainer branch containing the commit
        def get_mainline()
            begin
                @orig_tag = runGit("describe --contains --match 'v*' #{@sha}").gsub(/~.*/, '')
            rescue
                 log(:INFO, "Commit not in any tag. Trying to find a maintainer branch")

                 remote_branches=runGit("branch -a --contains #{@sha}").split("\n").
                                     each().grep(/remotes\//).map(){|x|
                     x.lstrip.split(/[ \t]/)[0].gsub(/remotes\//,'')}.
                                     each(){|r|
                     idx = KernelWork.config.upstream.maintainer_branches.index(r)
                     next if idx ==nil

                     log(:INFO, "Found it in #{KernelWork.config.upstream.maintainer_branches[idx]}")
                     @orig_tag = "Queued in subsystem maintainer repository"
                     remote=KernelWork.config.upstream.maintainer_branches[idx].gsub(/\/.*/,'')
                     @git_repo=@upstream.runGit("config remote.#{remote}.url")
                     return
                 }
            end
        end
    end
end
