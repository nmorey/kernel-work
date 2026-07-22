module KernelWork
    # Common utility class providing logging, configuration, and shell execution methods
    # Inherits generic capabilities from CLIClassTool::Common and implements project-specific branch handling
    class Common < CLIClassTool::Common

        # Extract shared commit filtering option parsing
        # @param optsParser [OptionParser] The option parser
        # @param opts [Hash] The options hash
        def self.set_filter_opts(optsParser, opts)
            opts[:filter] ||= {}
            optsParser.on("-p", "--path <path>", String,
                          "Path to subtree to monitor for non-backported patches.") {
                |val| opts[:filter][:paths] ||= []; opts[:filter][:paths] << val}
            optsParser.on("-F", "--fixes",
                          "Only look at commits containing 'Fixes:' tag.") {
                |val| opts[:filter][:fixes] = true}
            optsParser.on("-g", "--grep <pattern>", String,
                          "Filter commits with a specific keyword/pattern in commit message.") {
                |val| opts[:filter][:grep] = val}
            optsParser.on("--author <author>", String,
                          "Filter commits with a specific author.") {
                |val| opts[:filter][:author] = val}
            optsParser.on("--filter <name>", String,
                  "Use a saved filter from configuration.") {
                |val| opts[:filter][:saved_filter_name] = val}
        end

        # Generic filter merging logic
        # @param target [Hash] Merged output hash
        # @param source [Hash] Incoming source hash
        # @return [Hash] Merged target
        def self.merge_filter(target, source)
            source.each do |k, v|
                next if k == :saved_filter_name
                if v.is_a?(Array)
                    target[k] = (target[k] || []) + v
                else
                    target[k] = v
                end
            end
            target
        end

        # Generic filter loading and override layering
        # @param opts [Hash] The options hash
        def self.check_filter_opts(opts)
            if opts[:filter]
                # 1. Start with the base defaults
                base_filter = {
                    :paths => [],
                    :fixes => false,
                    :grep => nil,
                    :author => nil,
                    :skip_treewide => false
                }

                # 2. If a saved filter is specified, load it and merge it over the defaults
                if opts[:filter][:saved_filter_name]
                    name = opts[:filter][:saved_filter_name]
                    saved_filters = KernelWork.config.settings[:filters] || {}
                    saved = saved_filters[name.to_sym]
                    raise SavedFilterNotFoundError.new(name) if saved.nil?

                    merge_filter(base_filter, saved)
                end

                # 3. Overlay the explicitly set CLI values on top
                merge_filter(base_filter, opts[:filter])

                # Replace opts[:filter] with the resolved merged hash
                opts[:filter] = base_filter
            end
        end

        # Detect and set the current git branch
        #
        # @raise [UnknownBranch] If branch cannot be detected
        def set_branches()
            begin
                @local_branch = runGit("branch --show current").chomp()
                @branch = @local_branch.split('/')[2..-2].join('/')
            rescue
                begin
                    # Check if we are in the middle of a rebase
                    gitDir = runGit("rev-parse --git-dir HEAD").split("\n")[0]
                    raise "No luck" if ! File.directory?("#{gitDir}/rebase-merge")
                    @local_branch = run("head -n1 #{gitDir}/rebase-merge/head-name").chomp().
                                        split('/')[2..-1].join('/')

                    @branch = @local_branch.split('/')[2..-2].join('/')
                rescue
                    raise UnknownBranch.new(@path)
                end
            end
        end
    end
end
