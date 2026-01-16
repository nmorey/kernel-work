module KernelWork
    class KV
        include Comparable
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
        attr_reader :major, :minor
        def to_s()
            return @major.to_s() + "." + @minor.to_s()
        end
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
