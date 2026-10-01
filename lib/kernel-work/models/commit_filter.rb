module KernelWork
    # Domain model representing commit filtering criteria for git logs and rev-lists
    class CommitFilter
        # @!attribute [rw] paths
        #   @return [Array<String>] List of subtree paths to monitor
        attr_accessor :paths

        # @!attribute [rw] exclude_paths
        #   @return [Array<String>] List of paths to exclude from monitoring
        attr_accessor :exclude_paths

        # @!attribute [rw] fixes
        #   @return [Boolean] If true, only include commits with Fixes: tags
        attr_accessor :fixes

        # @!attribute [rw] grep
        #   @return [String, nil] Keyword pattern to search in commit messages
        attr_accessor :grep

        # @!attribute [rw] author
        #   @return [String, nil] Author filter string
        attr_accessor :author

        # @!attribute [rw] skip_treewide
        #   @return [Boolean] If true, skip tree-wide commits
        attr_accessor :skip_treewide

        # Initialize a new CommitFilter instance
        # @param paths [Array<String>] Subtree paths to include
        # @param exclude_paths [Array<String>] Paths to exclude
        # @param fixes [Boolean] Only include commits with Fixes: tag
        # @param grep [String, nil] Message search pattern
        # @param author [String, nil] Commit author search string
        # @param skip_treewide [Boolean] Ignore tree-wide commits
        def initialize(paths: [], exclude_paths: [], fixes: false, grep: nil, author: nil, skip_treewide: false)
            @paths = paths ? paths.dup : []
            @exclude_paths = exclude_paths ? exclude_paths.dup : []
            @fixes = fixes || false
            @grep = grep
            @author = author
            @skip_treewide = skip_treewide || false
        end

        # Convert filter criteria to a Hash representation
        # @return [Hash{Symbol => Object}] Hash representation of filter settings
        def to_h
            {
                paths: @paths,
                exclude_paths: @exclude_paths,
                fixes: @fixes,
                grep: @grep,
                author: @author,
                skip_treewide: @skip_treewide
            }
        end

        # Create a CommitFilter instance from a Hash
        # @param hash [Hash, nil] Hash containing filter settings
        # @return [CommitFilter] New CommitFilter instance
        def self.from_h(hash)
            return new if hash.nil? || !hash.is_a?(Hash)

            new(
                paths: hash[:paths] || hash['paths'] || [],
                exclude_paths: hash[:exclude_paths] || hash['exclude_paths'] || [],
                fixes: hash[:fixes] || hash['fixes'] || false,
                grep: hash[:grep] || hash['grep'],
                author: hash[:author] || hash['author'],
                skip_treewide: hash[:skip_treewide] || hash['skip_treewide'] || false
            )
        end

        # Access filter attribute by symbol or string key
        # @param key [Symbol, String] Attribute key
        # @return [Object] Value of attribute
        def [](key)
            to_h[key.to_sym]
        end

        # Set filter attribute by symbol or string key
        # @param key [Symbol, String] Attribute key
        # @param val [Object] Value to set
        # @return [Object] Value set
        def []=(key, val)
            case key.to_sym
            when :paths then @paths = val
            when :exclude_paths then @exclude_paths = val
            when :fixes then @fixes = val
            when :grep then @grep = val
            when :author then @author = val
            when :skip_treewide then @skip_treewide = val
            end
        end

        # Dig into filter attributes like a Hash
        # @param keys [Array<Symbol, String>] Sequence of keys
        # @return [Object, nil]
        def dig(*keys)
            to_h.dig(*keys)
        end

        # Overlay another filter or hash onto this filter, returning a new merged CommitFilter
        # @param other [CommitFilter, Hash] Other filter or hash to overlay
        # @return [CommitFilter] Merged CommitFilter instance
        def overlay(other)
            other_filter = other.is_a?(CommitFilter) ? other : CommitFilter.from_h(other)
            CommitFilter.new(
                paths: (@paths + other_filter.paths).uniq,
                exclude_paths: (@exclude_paths + other_filter.exclude_paths).uniq,
                fixes: other_filter.fixes || @fixes,
                grep: other_filter.grep || @grep,
                author: other_filter.author || @author,
                skip_treewide: other_filter.skip_treewide || @skip_treewide
            )
        end
    end
end
