# Extension to the core String class to add terminal hyperlink support.
class String
    # Wrap the string in an OSC 8 terminal hyperlink if stdout is a TTY.
    #
    # @param url [String, nil] Target URL for the hyperlink.
    # @return [String] The formatted terminal hyperlink, or original string if not a TTY or URL is nil/empty.
    def hyperlink(url)
        @@is_a_tty = $stdout.isatty() if @@is_a_tty == nil
        if @@is_a_tty && url && !url.empty?
            "\e]8;;#{url}\e\\#{self}\e]8;;\e\\"
        else
            self
        end
    end
end
