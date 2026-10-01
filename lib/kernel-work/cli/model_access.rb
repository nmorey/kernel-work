module KernelWork
    module CLI
        # Shared model access mixin module for CLI controllers and action handlers.
        #
        # Provides lazy accessors for domain models ({Linux}, {KernelSource})
        # and workflow orchestration ({Workflow}), as well as attribute writers
        # to support dependency injection and testing.
        module ModelAccess
            # Set the Linux domain model instance
            # @param value [Linux] Linux instance
            # @return [Linux] Assigned instance
            attr_writer :linux

            # Set the KernelSource domain model instance
            # @param value [KernelSource] KernelSource instance
            # @return [KernelSource] Assigned instance
            attr_writer :kernel_source

            # Set the Workflow orchestrator instance
            # @param value [Workflow] Workflow instance
            # @return [Workflow] Assigned instance
            attr_writer :workflow

            # Set the CVE tracker domain model instance
            # @param value [CveTracker] CveTracker instance
            # @return [CveTracker] Assigned instance
            attr_writer :cve_tracker

            # Set the Bugzilla client instance
            # @param value [BugzillaClient] BugzillaClient instance
            # @return [BugzillaClient] Assigned instance
            attr_writer :bugzilla

            # Access the Linux domain model lazily
            # @return [Linux] Linux instance
            def linux
                @linux ||= Linux.new
            end

            # Access the KernelSource domain model lazily
            # @return [KernelSource] KernelSource instance
            def kernel_source
                @kernel_source ||= KernelSource.new
            end

            # Access the Workflow orchestration service lazily
            # @return [Workflow] Workflow instance
            def workflow
                @workflow ||= Workflow.new(linux: linux, kernel_source: kernel_source)
            end

            # Access the CVE tracker domain model lazily
            # @return [CveTracker] CveTracker instance
            def cve_tracker
                @cve_tracker ||= CveTracker.create(KernelWork.config.cve.to_h, self)
            end

            # Access the Bugzilla client lazily
            # @return [BugzillaClient] BugzillaClient instance
            def bugzilla
                @bugzilla ||= BugzillaClient.new(KernelWork.config.cve.to_h)
            end
        end
    end
end
