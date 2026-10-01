module KernelWork
    module CLI
        # CLI-specific handler and option parser for CommitFilter
        class CommitFilter < KernelWork::CommitFilter
            # Initialize a new CLI CommitFilter from options hash, existing CommitFilter, or defaults
            # @param opts [Hash, KernelWork::CommitFilter, nil] Options hash or existing filter
            def initialize(opts = nil)
                if opts.is_a?(Hash)
                    cli_paths = opts[:paths] || opts[:filter_paths] || (opts[:filter] && opts[:filter][:paths]) || []
                    cli_exclude = opts[:exclude_paths] || opts[:filter_exclude_paths] || (opts[:filter] && opts[:filter][:exclude_paths]) || []
                    cli_fixes = opts[:fixes] || opts[:filter_fixes] || (opts[:filter] && opts[:filter][:fixes]) || false
                    cli_grep = opts[:grep] || opts[:filter_grep] || (opts[:filter] && opts[:filter][:grep])
                    cli_author = opts[:author] || opts[:filter_author] || (opts[:filter] && opts[:filter][:author])
                    cli_skip_treewide = opts[:skip_treewide] || opts[:filter_skip_treewide] || (opts[:filter] && opts[:filter][:skip_treewide]) || false

                    super(
                        paths: cli_paths,
                        exclude_paths: cli_exclude,
                        fixes: cli_fixes,
                        grep: cli_grep,
                        author: cli_author,
                        skip_treewide: cli_skip_treewide
                    )
                elsif opts.is_a?(KernelWork::CommitFilter)
                    super(
                        paths: opts.paths,
                        exclude_paths: opts.exclude_paths,
                        fixes: opts.fixes,
                        grep: opts.grep,
                        author: opts.author,
                        skip_treewide: opts.skip_treewide
                    )
                else
                    super()
                end
            end

            # Add filter command-line options to OptionParser
            # @param opts_parser [OptionParser] Command-line option parser instance
            # @param opts [Hash] Options hash where parsed arguments are stored
            # @return [void]
            def self.add_options(opts_parser, opts)
                opts[:filter] ||= new
                filter = opts[:filter]

                opts[:filter_name] = nil
                opts[:filter_paths] = []
                opts[:filter_exclude_paths] = []
                opts[:filter_fixes] = false
                opts[:filter_grep] = nil
                opts[:filter_author] = nil
                opts[:filter_skip_treewide] = false

                opts_parser.on("--filter <name>", String, "Filter name in configuration.") do |val|
                    opts[:filter_name] = val
                end
                opts_parser.on("-p", "--path <path>", String,
                              "Path to subtree to monitor for non-backported patches.") do |val|
                    opts[:filter_paths] << val
                    filter.paths << val
                end
                opts_parser.on("-e", "--exclude-path <path>", String,
                              "Path to exclude from the monitor.") do |val|
                    opts[:filter_exclude_paths] << val
                    filter.exclude_paths << val
                end
                opts_parser.on("-F", "--fixes",
                              "Only look at commits containing 'Fixes:' tag.") do |_val|
                    opts[:filter_fixes] = true
                    filter.fixes = true
                end
                opts_parser.on("-g", "--grep <pattern>", String,
                              "Filter commits with a specific keyword/pattern in commit message.") do |val|
                    opts[:filter_grep] = val
                    filter.grep = val
                end
                opts_parser.on("--author <author>", String,
                              "Filter commits with a specific author.") do |val|
                    opts[:filter_author] = val
                    filter.author = val
                end
                opts_parser.on("-T", "--skip-treewide", "Automatically skip tree wide patches.") do |_val|
                    opts[:filter_skip_treewide] = true
                    filter.skip_treewide = true
                end
            end

            # Resolve a CommitFilter from CLI options hash and configuration settings
            # @param opts [Hash] Parsed CLI options hash
            # @param may_be_missing [Boolean] Whether a missing saved filter is allowed without error
            # @return [CommitFilter] Resolved CommitFilter instance
            # @raise [SavedFilterNotFoundError] If named filter is not found in configuration and not may_be_missing
            def self.from_opts(opts, may_be_missing: false)
                base = new

                if opts[:filter_name]
                    name = opts[:filter_name]
                    saved_filters = KernelWork.config.settings[:filters] || {}
                    saved = saved_filters[name.to_sym]
                    if saved.nil?
                        raise SavedFilterNotFoundError.new(name) unless may_be_missing
                    else
                        base = new(KernelWork::CommitFilter.from_h(saved))
                    end
                end

                f = opts[:filter]
                cli_paths = opts[:filter_paths] || (f.respond_to?(:paths) ? f.paths : (f.is_a?(Hash) && f[:paths])) || []
                cli_exclude = opts[:filter_exclude_paths] || (f.respond_to?(:exclude_paths) ? f.exclude_paths : (f.is_a?(Hash) && f[:exclude_paths])) || []
                cli_fixes = opts[:filter_fixes] || (f.respond_to?(:fixes) ? f.fixes : (f.is_a?(Hash) && f[:fixes])) || false
                cli_grep = opts[:filter_grep] || (f.respond_to?(:grep) ? f.grep : (f.is_a?(Hash) && f[:grep]))
                cli_author = opts[:filter_author] || (f.respond_to?(:author) ? f.author : (f.is_a?(Hash) && f[:author]))
                cli_skip_treewide = opts[:filter_skip_treewide] || (f.respond_to?(:skip_treewide) ? f.skip_treewide : (f.is_a?(Hash) && f[:skip_treewide])) || false

                base.paths = (base.paths + cli_paths).uniq
                base.exclude_paths = (base.exclude_paths + cli_exclude).uniq
                base.fixes = true if cli_fixes
                base.grep = cli_grep if cli_grep
                base.author = cli_author if cli_author
                base.skip_treewide = true if cli_skip_treewide

                opts[:filter] = base if opts.is_a?(Hash)
                base
            end
        end
    end
end
