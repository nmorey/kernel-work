module KernelWork
    # Kernel Version class for handling major.minor version strings
    class KV
        include Comparable

        # Initialize a new KV object
        #
        # @param t [Float, String, Integer] Major version or full version string/float
        # @param min [Integer, nil] Minor version (optional if t is string/float)
        # @raise [RuntimeError] If version format is invalid
        def initialize(t, min=nil)
            if min == nil then
                if t.is_a?(Float) || t.is_a?(String)
                    (@major, @minor) = t.to_s().split('.').map(){|x| x.to_i}
                else
                    raise("Invalid Kernel version #{t}")
                end
            else
                @major = t.to_i
                @minor = min.to_i
            end
        end
        # @!attribute [r] major
        #   @return [Integer] Major version number
        # @!attribute [r] minor
        #   @return [Integer] Minor version number
        attr_reader :major, :minor

        # String representation of the kernel version
        #
        # @return [String] "major.minor"
        def to_s()
            return @major.to_s() + "." + @minor.to_s()
        end

        # Compare two KV objects
        #
        # @param other [KV, String] Object to compare with
        # @return [Integer, nil] -1, 0, 1 for comparison, or nil if not comparable
        def <=>(other)
            begin
                other = KV.new(other) if other.class != KV
            rescue
                return nil
            end

            comp = @major <=> other.major
            if comp == 0
                return @minor <=> other.minor
            else
                return comp
            end
        end
    end
end
