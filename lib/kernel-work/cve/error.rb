module KernelWork
    module CveCLI
        # Base class for all KernelWork exceptions
        class CveCLIError < KernelWorkError
        end

        # Exception raised when bugzill request fails
        class BugzillaError < CveCLIError
            # Initialize a new BugzillaError
            # @param res [Net::HTTPResponse] Bugzilla request error
            def initialize(res)
                super("Bugzilla request failed with code #{res.code}: #{res.body}")
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
    end
end
