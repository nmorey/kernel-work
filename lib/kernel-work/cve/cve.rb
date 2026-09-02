module KernelWork

    # Represents a CVE bug being tracked in the system
    class CVE < Common
        # The ToDo workflow state for a CVE bug.
        STATE_TODO       = "ToDo"
        # The Applied workflow state for a CVE bug.
        STATE_APPLIED    = "Applied"
        # The Pushed workflow state for a CVE bug.
        STATE_PUSHED     = "Pushed"
        # The Merged workflow state for a CVE bug.
        STATE_MERGED     = "Merged"
        # The Reassigned workflow state for a CVE bug.
        STATE_REASSIGNED = "Reassigned"

        # List of all valid workflow states dynamically retrieved from STATE_* constants.
        VALID_STATES = constants.grep(/^STATE_/).map { |c| const_get(c) }.freeze

        # Maximum string length among all valid workflow states.
        MAX_STATE_LEN = VALID_STATES.map(&:length).max

        attr_reader :bug_id, :cve, :summary, :fix_sha, :distros, :branches, :tracker

        # Validate that a state is a recognized workflow state and return its canonical form
        # @param state [String, Symbol, nil] The state value to validate
        # @return [String] The normalized state string
        # @raise [CveCLI::InvalidCveStateError] If the state is unknown
        def self.validate_state!(state)
            state_str = state.to_s.strip
            return "" if state_str.empty?

            canonical = VALID_STATES.find { |s| s.casecmp?(state_str) }
            return canonical if canonical

            raise CveCLI::InvalidCveStateError.new(state)
        end

        # Validate that a state is a recognized workflow state and return its canonical form
        # @param state [String, Symbol, nil] The state value to validate
        # @return [String] The normalized state string
        # @raise [CveCLI::InvalidCveStateError] If the state is unknown
        def validate_state!(state)
            self.class.validate_state!(state)
        end

        # Colour a string (or state string) based on the CVE workflow state
        # @param state [String, Symbol] The workflow state value
        # @param text [String, nil] Optional text to colour (defaults to state)
        # @return [String] The coloured string
        def self.colour(state, text = nil)
            text = (text || state).to_s
            norm_state = begin
                validate_state!(state)
            rescue CveCLI::InvalidCveStateError
                state.to_s
            end

            case norm_state
            when STATE_TODO
                text.red
            when STATE_MERGED
                text.green
            when STATE_APPLIED
                text.brown
            when STATE_PUSHED
                text.blue
            else
                text
            end
        end

        class << self
            alias_method :color, :colour
        end

        # Colour a string (or state string) based on the CVE workflow state
        # @param state [String, Symbol] The workflow state value
        # @param text [String, nil] Optional text to colour (defaults to state)
        # @return [String] The coloured string
        def colour(state, text = nil)
            self.class.colour(state, text)
        end
        alias_method :color, :colour

        # Initialize a new CVE instance
        # @param attributes [Hash] The attributes hash (symbolized keys)
        # @raise [CveCLI::InvalidCveStateError] If any branch state is unknown
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
                    @branches[k.to_sym] = self.class.validate_state!(v)
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
        # @param status [String, Symbol] The new status value
        # @raise [CveCLI::InvalidCveStateError] If the state is unknown
        # @return [String]
        def set_status(branch, status)
            norm_status = self.class.validate_state!(status)
            @branches[branch.to_sym] = norm_status
            @tracker.write_bug(@bug_id, self) if @tracker
            log(:INFO, "Successfully updated status of Bug ##{@bug_id} to '#{norm_status}'.")
            norm_status
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
