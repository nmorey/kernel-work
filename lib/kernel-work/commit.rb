module KernelWork
    class Commit < Common
        attr_reader :sha, :orig_tag, :git_repo

        @@Q_BRANCHES = [ "linux-rdma/for-rc", "linux-rdma/for-next" ]

        def initialize(sha, subject = nil, patch_id = nil)
            @path=ENV["LINUX_GIT"].chomp()
            @sha = sha
            @subject = subject
            @patch_id = patch_id
        end

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

        def patch_id()
            return @patch_id if @patch_id != nil

            begin
                @patch_id = runGit("format-patch -n1 #{@sha} --stdout | git patch-id | awk '{ print $1}'").chomp()
            rescue
                raise ShaNotFoundError.new(@sha)
            end
            return @patch_id
        end

        def f_sha()
            return @f_sha if @f_sha != nil
            begin
                @f_sha = runGit("rev-parse #{@sha}")
                return @f_sha
            rescue
                raise ShaNotFoundError.new(@sha)
            end
        end

        def desc()
            "#{@sha[0..11]} (\"#{subject()}\")"
        end

        def check_patch_info(opts)
            f_sha()
            get_mainline()

            if @orig_tag == "" then
                if opts[:ignore_tag] != true then
                    log(:ERROR, "Commit is not contained in any tag nor maintainer repo")
                    return false
                else
                    @f_sha = ""
                    @orig_tag="Never, in-house patch"

                end
            end
            return true
        end

        def gen_patch()
            @patchname = runGit("format-patch -n1 #{sha}")
        end

        def patchname()
            return @patchname if @patchname != nil

            @patchname = runGit("format-patch -n1 #{sha}")
            return @patchname
        end

        def to_s
            if @subject
                "#{@sha} ##{@subject}"
            else
                @sha
            end
        end

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
        def get_mainline()
            begin
                @orig_tag = runGit("describe --contains --match 'v*' #{@sha}").gsub(/~.*/, '')
            rescue
                 log(:INFO, "Commit not in any tag. Trying to find a maintainer branch")

                 remote_branches=runGit("branch -a --contains #{@sha}").split("\n").
                                     each().grep(/remotes\//).map(){|x|
                     x.lstrip.split(/[ \t]/)[0].gsub(/remotes\//,'')}.
                                     each(){|r|
                     idx = @@Q_BRANCHES.index(r)
                     next if idx ==nil

                     log(:INFO, "Found it in #{@@Q_BRANCHES[idx]}")
                     @orig_tag = "Queued in subsystem maintainer repository"
                     remote=@@Q_BRANCHES[idx].gsub(/\/.*/,'')
                     @git_repo=@upstream.runGit("config remote.#{remote}.url")
                     return
                 }
            end
        end
    end
end
