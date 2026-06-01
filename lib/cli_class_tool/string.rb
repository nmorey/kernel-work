# Extension to the core String class to add colorization support
class String
    # colorization
    @@is_a_tty = nil

    # Colorize the string using ANSI escape codes
    #
    # @param color_code [Integer] ANSI color code
    # @return [String] Colorized string if TTY, else original string
    def colorize(color_code)
        @@is_a_tty = STDOUT.isatty() if @@is_a_tty == nil
        if @@is_a_tty then
            return "\e[#{color_code}m#{self}\e[0m"
        else
            return self
        end
    end

    # Make the string red
    # @return [String] Red string
    def red
        colorize(31)
    end

    # Make the string green
    # @return [String] Green string
    def green
        colorize(32)
    end

    # Make the string brown (yellow)
    # @return [String] Brown string
    def brown
        colorize(33)
    end

    # Make the string blue
    # @return [String] Blue string
    def blue
        colorize(34)
    end

    # Make the string magenta
    # @return [String] Magenta string
    def magenta
        colorize(35)
    end
end
