module KernelWork
module CveCLI
    class CveAction
        public
        # Status action
        def status(opts)
            config = KernelWork.config.cve.to_h
            cve_files = @tracker.read_all

            if cve_files.empty?
                log(:INFO, "No CVE tracking data found.")
                return 0
            end

            active_distros = Set.new
            matching_cves = cve_files.select do |cve|
                active = cve.active_branches
                unless active.empty?
                    active_distros.merge(active.keys.map(&:to_s))
                    true
                else
                    false
                end
            end

            if matching_cves.empty?
                log(:INFO, "No active CVEs found.")
                return 0
            end

            distros_list = active_distros.to_a.sort

            # Determine the maximum width for the first column "CVE (Bug ID)"
            cve_col_header = "CVE BugID (#{matching_cves.length})"
            max_cve_width = [cve_col_header.length, matching_cves.map { |cve|
                                 cve.to_s.visible_length }.max || 0].max + 3

            # Determine width for each distro column
            distro_widths = {}
            distros_list.each do |distro|
                distro_widths[distro] = [distro.length, CVE::MAX_STATE_LEN].max + 3
            end

            # Print header
            print sprintf("%-#{max_cve_width}s", cve_col_header)
            distros_list.each do |distro|
                header_state = distro_column_state(distro, matching_cves)
                padding = " " * (distro_widths[distro] - distro.length)
                print "#{KernelWork::CVE.colour(header_state, distro)}#{padding}"
            end
            puts ""

            # Print separator
            separator_len = max_cve_width + distros_list.map { |d| distro_widths[d] }.sum
            puts "-" * separator_len

            # Print each CVE row
            matching_cves.each do |cve|
                col_str = cve.to_s(opts)
                padding = " " * [0, max_cve_width - col_str.visible_length].max
                cve_bug_str = "#{col_str}#{padding}"
                statuses_str = ""

                statuses = []
                distros_list.each do |distro|
                    status = cve.get_status(distro) || ""
                    statuses << status
                    status_str = sprintf("%-#{distro_widths[distro]}s", status)
                    statuses_str += KernelWork::CVE.colour(status, status_str)
                end
                statuses.reject! { |s| s.nil? || s.empty? || s == CVE::STATE_REASSIGNED }
                cve_bug_str = KernelWork::CVE.colour(status_global_state(statuses), cve_bug_str)
                puts "#{cve_bug_str}#{statuses_str}"
            end

            return 0
        end
        alias_method :ls, :status

        private
        # Determine the aggregate workflow state for a distro column header based on CVE statuses.
        #
        # @param distro [String, Symbol] The distro branch name.
        # @param cves [Array<CVE>] The list of matching CVE bugs.
        # @return [String] The workflow state constant representing the column status.
        def distro_column_state(distro, cves)
            statuses = cves.map { |cve|
                cve.get_status(distro)
            }.reject { |s| s.nil? || s.empty? || s == CVE::STATE_REASSIGNED }

            return status_global_state(statuses)
        end
    end
end
end
