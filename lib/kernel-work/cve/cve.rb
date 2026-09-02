module KernelWork

    # Represents a CVE bug being tracked in the system
    class CVE < Common
        # Define CVE workflow state constants
        STATE_TODO       = "ToDo"
        STATE_APPLIED    = "Applied"
        STATE_PUSHED     = "Pushed"
        STATE_MERGED     = "Merged"
        STATE_REASSIGNED = "Reassigned"

        attr_reader :bug_id, :cve, :summary, :fix_sha, :distros, :branches, :tracker

        # Initialize a new CVE instance
        # @param attributes [Hash] The attributes hash (symbolized keys)
        def initialize(attributes = {})
            @bug_id = attributes[:bug_id].to_s
            @cve = attributes[:cve]
            @summary = attributes[:summary]
            @fix_sha = attributes[:fix_sha]
            @distros = attributes[:distros] || []
            @tracker = attributes[:tracker] || nil

            @branches = {}
            if attributes[:branches]
                attributes[:branches].each do |k, v|
                    @branches[k.to_sym] = v
                end
            end
        end

        # Create a CVE instance from a hash, or return the CVE instance if already one
        # @param tracker [CveTracker] Tracker used to load the data
        # @param data [Hash, CVE] The source data
        # @return [CVE, nil]
        def self.from_h(tracker, data)
            return nil if data.nil?
            return data if data.is_a?(CVE)
            data[:tracker] = tracker
            new(data)
        end

        # Convert the CVE instance to a symbolized hash
        # @return [Hash]
        def to_h
            {
                bug_id: @bug_id,
                cve: @cve,
                summary: @summary,
                fix_sha: @fix_sha,
                distros: @distros,
                branches: @branches
            }
        end

        # Custom JSON serialization support (e.g. for WEBrick pretty_generate)
        # @return [String]
        def to_json(*args)
            to_h.to_json(*args)
        end

        # Retrieve the status of a specific branch
        # @param branch [String, Symbol] The branch name
        # @return [String, nil]
        def get_status(branch)
            @branches[branch.to_sym]
        end

        # Update the status of a specific branch
        # @param branch [String, Symbol] The branch name
        # @param status [String] The new status value
        # @return [String]
        def set_status(branch, status)
            @branches[branch.to_sym] = status
            @tracker.write_bug(@bug_id, self)
            log(:INFO, "Successfully updated status of Bug ##{@bug_id} to '#{status}'.")
        end

        # Hash-like reader compatibility method
        # @param key [Symbol, String] The attribute name
        # @return [Object]
        def [](key)
            case key.to_sym
            when :bug_id then @bug_id
            when :cve then @cve
            when :summary then @summary
            when :fix_sha then @fix_sha
            when :distros then @distros
            when :branches then @branches
            when :tracker then @tracker
            else
                nil
            end
        end

        # Get list of active branch/status pairs, filtering out empty or reassigned ones
        # @return [Hash]
        def active_branches
            @branches.select do |_, status_val|
                status_str = status_val.to_s.strip
                !status_str.empty? && status_str != STATE_REASSIGNED
            end
        end

        # Check if all active branches are merged (or fully resolved)
        # @return [Boolean]
        def all_ok?
            active = active_branches
            return false if active.empty?
            active.values.all? { |status| status == STATE_MERGED }
        end
    end
end
