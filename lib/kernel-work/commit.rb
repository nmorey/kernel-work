require 'cgi'
require 'open3'

module KernelWork
    # Represents a git commit with utility methods to retrieve metadata
    class Commit < Common
        # @!attribute [r] sha
        #   @return [String] The commit SHA
        # @!attribute [r] orig_tag
        #   @return [String] The original tag that introduced the commit
        # @!attribute [r] git_repo
        #   @return [String] The git repository URL where the commit was introduced (ie maintainer tree)
        # @!attribute [r] path
        #   @return [String] The git repository path
        attr_reader :sha, :orig_tag, :git_repo, :path
        attr_accessor :data
        attr_accessor :extra_desc
        # @!attribute [rw] series
        #   @return [Array<Commit>, nil] Cached patch series commits or nil if uncomputed
        attr_accessor :series

        # Initialize a new Commit object
        #
        # @param sha [String] The commit SHA
        # @param opts [Hash] Options hash
        # @option opts [String, nil] :subject The commit subject (optional)
        # @option opts [String, nil] :patch_id The patch ID (optional)
        # @option opts [String, nil] :path The git repository path (defaults to KernelWork.config.linux_git)
        # @option opts [String, nil] :extra_desc Additional description text (optional)
        # @option opts [Object, nil] :data Associated arbitrary data or CVE object (optional)
        # @option opts [Array<Commit>, nil] :series Cached patch series commits (optional)
        def initialize(sha, opts = {})
            opts ||= {}
            @path = opts[:path] || KernelWork.config.linux_git
            @sha = sha
            @subject = opts[:subject]
            @patch_id = opts[:patch_id]
            @extra_desc = opts[:extra_desc]
            @data = opts[:data]
            @series = opts[:series]
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
            "#{@sha[0..11]} (\"#{subject()}\")" + (@extra_desc != nil ? " #{extra_desc}" : "")
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

        # Extract SHAs of commits fixed by this commit from the "Fixes:" tags in the commit message
        #
        # @return [Array<String>] List of fixed commit SHAs
        def fixes_shas()
            return @fixes_shas if @fixes_shas != nil
            @fixes_shas = []
            begin
                msg = runGit("log -n1 --format=%B #{@sha}")
                msg.each_line do |line|
                    if line =~ /Fixes:\s*([0-9a-f]{12,40})/i
                        @fixes_shas << $1
                    end
                end
            rescue
                # Ignore errors and return empty list
            end
            @fixes_shas
        end

        # Extract Link: URLs matching patch.msgid.link or lore.kernel.org from the commit message
        #
        # @return [Array<String>] List of matching Link URLs
        def lore_links()
            return @lore_links if @lore_links != nil
            @lore_links = []
            begin
                msg = runGit("log -n1 --format=%B #{@sha}")
                msg.each_line do |line|
                    if line =~ /^\s*Link:\s*<?(https?:\/\/(?:patch\.msgid\.link|lore\.kernel\.org)[^\s>]+)>?/i
                        @lore_links << $1
                    end
                end
            rescue
                # Ignore errors and return empty list
            end
            @lore_links
        end

        # Parse patch series commit metadata from public-inbox HTML
        #
        # @param html [String, nil] The HTML content
        # @return [Array<Hash>] List of patch metadata hashes in the patch series (ordered by index)
        def self.parse_series_html(html)
            return [] if html.nil? || html.empty?

            current_subject = nil
            if html =~ /Subject:\s*<a[^>]*id=t[^>]*>(.*?)<\/a>/m
                current_subject = CGI.unescapeHTML($1.strip)
            elsif html =~ /<title>(.*?)<\/title>/m
                title = CGI.unescapeHTML($1.strip)
                current_subject = title.sub(/\s+-\s+[^-]+$/, "")
            end

            current_msgid = nil
            if html =~ /Message-ID:\s*&lt;([^&>]+)&gt;/m
                current_msgid = $1.strip
            elsif html =~ /Message-ID:\s*<([^>]+)>/m
                current_msgid = $1.strip
            end

            idx, total, subj = nil, nil, nil
            if current_subject && current_subject =~ /\[[^\]]*?\b(\d+)\/(\d+)\b[^\]]*\]\s*(.*)$/
                idx = $1.to_i
                total = $2.to_i
                subj = $3.strip
            end

            return [] if total.nil? || total <= 1

            patches = {}
            if idx && idx > 0
                patches[idx] = { :idx => idx, :total => total, :subject => subj, :msgid => current_msgid }
            end

            html.scan(/<a\s+[^>]*href="([^"]+)"[^>]*>([^<]+)<\/a>/m) do |href, text|
                text = CGI.unescapeHTML(text.strip)
                if text =~ /\[[^\]]*?\b(\d+)\/(\d+)\b[^\]]*\]\s*(.*)$/
                    p_idx = $1.to_i
                    p_total = $2.to_i
                    p_subj = $3.strip
                    if p_total == total && p_idx > 0
                        p_msgid = href.sub(/^\.\.\//, "").sub(/\/$/, "").strip
                        p_msgid = nil if p_msgid.start_with?("#") || p_msgid.include?("?") || p_msgid.empty?
                        patches[p_idx] ||= { :idx => p_idx, :total => p_total, :subject => p_subj, :msgid => p_msgid }
                    end
                end
            end

            patches.keys.sort.map { |k| patches[k] }
        end

        # Retrieve patch series commits if commit is part of a patch series on lore / patch.msgid.link
        #
        # @return [Array<Commit>] List of resolved commit objects in the patch series
        def patch_series()
            return @series if @series != nil
            @series = []

            target_ref = determine_target_ref()
            ct = runGit("log -n 1 --format=%ct #{@sha}", {}, false).strip.to_i rescue 0
            time_filter = ct > 0 ? "--since=\"@#{ct - 30 * 86400}\" --until=\"@#{ct + 30 * 86400}\"" : ""

            lore_links().each do |url|
                html = nil
                begin
                    stdout, stderr, status = Open3.capture3("curl", "-sL", "-A", "kernel-work/1.0", url)
                    next unless status.success?
                    html = stdout
                rescue
                    next
                end

                parsed_entries = self.class.parse_series_html(html)
                next if parsed_entries.empty?

                resolved_commits = []
                parsed_entries.each do |entry|
                    if (entry[:msgid] && lore_links().any? { |l| l.include?(entry[:msgid]) }) ||
                       (@subject && entry[:subject] == @subject)
                        resolved_commits << self
                        next
                    end

                    commit = resolve_series_patch(entry, target_ref, time_filter)
                    if commit != nil
                        resolved_commits << commit
                    else
                        log(:DEBUG, "Could not find commit in #{@path} for series patch #{entry[:idx]}/#{entry[:total]}: '#{entry[:subject]}'")
                    end
                end

                @series = resolved_commits
                break unless @series.empty?
            end

            # Cross-attach cached series array to all sibling commits in the series
            @series.each do |c|
                c.series = @series if c.is_a?(Commit)
            end

            @series
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

        # Equality check for Hash and Array#uniq
        #
        # @param other [Object] Another object
        # @return [Boolean] True if equal
        def eql?(other)
            self == other
        end

        # Hash code based on commit SHA
        #
        # @return [Integer] Hash code
        def hash
            @sha.hash
        end

        private

        # Determine the git target ref (e.g. origin/master, master, maintainer branch) containing this commit
        #
        # @return [String] The ref name
        def determine_target_ref()
            return "HEAD" if @sha.nil?

            # 1. Check if self is ancestor of origin/master
            begin
                runGit("merge-base --is-ancestor #{@sha} origin/master", {}, true)
                return "origin/master"
            rescue
            end

            # 2. Check if self is ancestor of master
            begin
                runGit("merge-base --is-ancestor #{@sha} master", {}, true)
                return "master"
            rescue
            end

            # 3. Check maintainer branches from config
            if KernelWork.config.upstream && KernelWork.config.upstream.maintainer_branches
                KernelWork.config.upstream.maintainer_branches.each do |br|
                    begin
                        runGit("merge-base --is-ancestor #{@sha} #{br}", {}, true)
                        return br
                    rescue
                    end
                end
            end

            # 4. Check remote branches containing @sha
            begin
                branches = runGit("branch -a --contains #{@sha}", {}, false).split("\n").map(&:strip)
                remote_br = branches.find { |b| b.start_with?("remotes/") && !b.include?("HEAD") }
                return remote_br.sub(%r{^remotes/}, '') if remote_br
                local_br = branches.find { |b| !b.start_with?("*") && !b.include?("detached") }
                return local_br if local_br
            rescue
            end

            "HEAD"
        end

        # Resolve a series patch entry to a Commit in the repository
        #
        # @param entry [Hash] Patch metadata hash containing :idx, :total, :subject, :msgid
        # @param target_ref [String] The git target ref to search (e.g. origin/master, master, HEAD)
        # @param time_filter [String] Optional git date-bounded argument
        # @return [Commit, nil] Resolved commit or nil if not found
        def resolve_series_patch(entry, target_ref = "HEAD", time_filter = "")
            # 1. Message-ID / Link: trailer search
            if entry[:msgid]
                begin
                    sha = runGit("log #{target_ref} #{time_filter} -n 1 --format=%H --grep=\"#{entry[:msgid]}\"", {}, false).strip
                    return Commit.new(sha, :subject => entry[:subject], :path => @path) unless sha.empty?
                rescue
                end
            end

            # 2. Exact Subject search
            if entry[:subject]
                begin
                    clean_subj = entry[:subject].to_s.sub(/\A\[.*?\]\s*/, '').gsub('"', '').strip
                    output = runGit("log #{target_ref} #{time_filter} -n 5 --format=%H -F --grep=\"#{clean_subj}\"", {}, false)
                    shas = output.split("\n").map(&:strip).reject(&:empty?)
                    if shas.length == 1
                        return Commit.new(shas.first, :subject => entry[:subject], :path => @path)
                    elsif shas.length > 1
                        matched_sha = disambiguate_shas(shas)
                        return Commit.new(matched_sha, :subject => entry[:subject], :path => @path) if matched_sha
                    end
                rescue
                end
            end

            # 3. Neighborhood scan around self.sha using author and date window
            begin
                neighbor_sha = find_in_neighborhood(entry, target_ref, time_filter)
                return Commit.new(neighbor_sha, :subject => entry[:subject], :path => @path) if neighbor_sha
            rescue
            end

            nil
        end

        # Disambiguate multiple candidate SHAs using author match with self
        #
        # @param shas [Array<String>] Candidate commit SHAs
        # @return [String, nil] Best matching SHA or first candidate
        def disambiguate_shas(shas)
            return nil if shas.nil? || shas.empty?
            begin
                self_author = runGit("log -n 1 --format=%ae #{@sha}", {}, false).strip
                shas.each do |cand|
                    cand_author = runGit("log -n 1 --format=%ae #{cand}", {}, false).strip
                    return cand if !self_author.empty? && cand_author == self_author
                end
            rescue
            end
            shas.first
        end

        # Search for a series commit around self.sha using author and date window
        #
        # @param entry [Hash] Patch metadata entry
        # @param target_ref [String] The git target ref to search
        # @param time_filter [String] Optional git date-bounded argument
        # @return [String, nil] Commit SHA if found, nil otherwise
        def find_in_neighborhood(entry, target_ref = "HEAD", time_filter = "")
            return nil if @sha.nil?
            clean_subj = entry[:subject].to_s.sub(/\A\[.*?\]\s*/, '').gsub('"', '').strip.downcase
            return nil if clean_subj.empty?

            author = runGit("log -n 1 --format=%ae #{@sha}", {}, false).strip rescue ""
            author_arg = author.empty? ? "" : "--author=\"#{author}\""

            begin
                window = runGit("log #{target_ref} #{time_filter} #{author_arg} --format=\"%H %s\" -n 50", {}, false)
                window.split("\n").each do |line|
                    line = line.strip
                    next if line.empty?
                    parts = line.split(" ", 2)
                    next if parts.length < 2
                    cand_sha = parts[0]
                    cand_subj = parts[1].downcase.strip
                    if cand_subj == clean_subj || cand_subj.include?(clean_subj) || clean_subj.include?(cand_subj)
                        return cand_sha
                    end
                end
            rescue
            end
            nil
        end

        # Attempt to find the mainline tag or maintainer branch containing the commit
        #
        # @return [void]
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
                     @git_repo=runGit("config remote.#{remote}.url")
                     return
                 }
            end
        end
    end
end
