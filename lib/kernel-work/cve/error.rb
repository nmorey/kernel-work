module KernelWork
    module CveCLI
        # Base class for all KernelWork exceptions
        class CveCLIError < KernelWorkError
        end

        # Exception raised when bugzilla request fails
        class BugzillaError < CveCLIError
            # Initialize a new BugzillaError
            # @param res_or_msg [Net::HTTPResponse, String] Bugzilla request error or message
            def initialize(res_or_msg)
                if res_or_msg.is_a?(Net::HTTPResponse)
                    super("Bugzilla request failed with code #{res_or_msg.code}: #{res_or_msg.body}")
                else
                    super(res_or_msg.to_s)
                end
            end
        end

        # Exception raised when Bugzilla request times out
        class BugzillaTimeoutError < BugzillaError
            # Initialize a new BugzillaTimeoutError
            # @param timeout [Integer, Float] The timeout duration in seconds
            def initialize(timeout)
                super("Bugzilla request timed out after #{timeout} seconds")
            end
        end

        # Exception raised when no fix sha is found in a bugzilla report
        class FixShaNotFoundError < CveCLIError
            # Initialize a new FixShaNotFound
            # @param bug_id [String] Bugzilla bug id
            def initialize(bug_id)
                super("Unable to find Fix SHA for Bug ##{bug_id}")
            end
        end

        # Exception when bug was not found
        class BugNotFoundError < CveCLIError
        end

        # Exception when bug JSON was not parsable
        class CorruptedJSONError < CveCLIError
        end

        # Exception raised when REST request fails
        class RestError < CveCLIError
            # Initialize a new RestError
            # @param query [String] Query type
            # @param res [Net::HTTPResponse] REST request error
            def initialize(query, res)
                super("REST request #{query} failed with code #{res.code}: #{res.body}")
            end
        end

        # Exception when REST query are triggered but URL is not configured
        class RestURLNotSetError < CveCLIError
        end

        # Exception raised when a CVE branch state is invalid
        class InvalidCveStateError < CveCLIError
            # Initialize a new InvalidCveStateError
            # @param state [String] The invalid state value
            def initialize(state)
                super("Invalid CVE state '#{state}'")
            end
        end
    end
end
