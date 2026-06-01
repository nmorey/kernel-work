module CLIClassTool
    # Generic utilities for CLI class-based actions
    module Utils

        # Convert a string to an action symbol, validating it against available actions
        #
        # @param str [String] Action name
        # @return [Symbol] Action symbol
        # @raise [RuntimeError] If action is invalid
        def stringToAction(str)
            action = str.to_sym()
            raise("Invalid action '#{str}'") if self.getActionAttr("ACTION_LIST").index(action) == nil
            return action
        end

        # Convert an action symbol to a string
        #
        # @param sym [Symbol] Action symbol
        # @return [String] Action name
        def actionToString(sym)
            return sym.to_s()
        end

        # Get attributes from all action classes
        #
        # @param attr [Symbol] Attribute name (e.g., "ACTION_LIST")
        # @return [Hash, Array] Aggregated attributes
        def getActionAttr(attr)
            action_classes = self::ACTION_CLASS
            common_class = self::Common

            # Resolve overridden/extended class (addon) if getExtendedClass is defined
            resolved_classes = action_classes.map do |x|
                self.respond_to?(:getExtendedClass) ? self.getExtendedClass(x) : x
            end

            if common_class.const_get(attr).class == Hash
                return resolved_classes.inject({}){|h, x| h.merge(x.const_get(attr))}
            else
                return resolved_classes.map(){|x| x.const_get(attr)}.flatten()
            end
        end

        # Run a block on the class responsible for a specific action
        #
        # @param action [Symbol] The action
        # @param sym [Symbol, nil] Optional method to check for existence
        # @yield [Class] The class handling the action
        # @return [Object] Result of the block or error code
        def _runOnClass(action, sym, &block)
            self::ACTION_CLASS.each(){|x|
                next if x::ACTION_LIST.index(action) == nil
                
                # Resolve overridden/extended class (addon)
                class_to_use = self.respond_to?(:getExtendedClass) ? self.getExtendedClass(x) : x

                if sym != nil
                    has_base = x.singleton_methods().index(sym) != nil
                    has_addon = class_to_use != x && class_to_use.singleton_methods().index(sym) != nil

                    if has_base || has_addon
                        yield(x) if has_base
                        yield(class_to_use) if has_addon
                        return 0
                    end
                else
                    return yield(class_to_use)
                end
                return 0
            }
            return -1
        end

        # Set options for an action
        #
        # @param action [Symbol] The action
        # @param optsParser [OptionParser] The option parser
        # @param opts [Hash] The options hash
        def setOpts(action, optsParser, opts)
            self._runOnClass(action, :set_opts) {|kClass|
                kClass.set_opts(action, optsParser, opts)
            }
        end

        # Check options for validity
        #
        # @param opts [Hash] The options hash
        def checkOpts(opts)
             self._runOnClass(opts[:action], :check_opts) {|kClass|
                 kClass.check_opts(opts)
            }
        end

        # Execute an action
        #
        # @param opts [Hash] The options hash
        # @param action [Symbol] The action to execute
        # @param error_class [Class, nil] Optional base error class to rescue
        # @return [Object] Result of the action (often an Integer exit code)
        def execAction(opts, action, error_class = nil)
            caught_error_class = error_class || StandardError

            self._runOnClass(action, nil) {|kClass|
                begin
                    # Some class have their own execAction, because object creation might be tricky.
                    if kClass.respond_to?(:execAction)
                        ret = kClass.execAction(opts, action)
                    else
                        # Use load factory method if defined, else fall back to .new
                        obj = kClass.respond_to?(:load) ? kClass.load() : kClass.new()
                        ret = obj.public_send(action, opts)
                    end
                    return ret.is_a?(Integer) ? ret : 0
                rescue caught_error_class => e
                    puts("# " + "ERROR".red().to_s() + ": Action '#{action}' failed: #{e.message}")
                    e.backtrace.each(){|l|
                        puts("# " + "ERROR".red().to_s() + ": \t" + l)
                    } if self.verbose_log

                    begin
                        return e.err_code
                    rescue
                        return 1
                    end
                end
            }
        end

        # Set verbose logging
        #
        # @param val [Boolean] True to enable verbose logging
        def verbose_log=(val)
            @verbose_log = val
        end

        # Get verbose logging status
        #
        # @return [Boolean] Verbose logging status
        def verbose_log()
            @verbose_log
        end

        # Load all custom addon classes/files from a directory
        #
        # @param path [String] Absolute or relative directory path containing .rb files
        def loadAddons(path)
            return unless Dir.exist?(path)

            $LOAD_PATH.push(path)
            Dir.entries(path).each() do |entry|
                next if !File.file?(File.join(path, entry)) || entry !~ /\.rb$/
                require entry.sub(/\.rb$/, "")
            end
            $LOAD_PATH.pop()
        end

        # Safely load an overridden/extended class instance using a generic addon_key
        def loadClass(default_class, addon_key, *more)
            @load_class ||= []
            @load_class.push(default_class)

            # Resolve overridden class using getExtendedClass if available
            extended_class = self.respond_to?(:getExtendedClass) ? self.getExtendedClass(default_class, addon_key) : default_class
            obj = extended_class.new(*more)
            @load_class.pop()
            return obj
        end

        # Validate that the constructor was only called through loadClass
        def checkDirectConstructor(theClass)
            @load_class ||= []
            curLoad = @load_class.last()
            cl = theClass
            while cl != Object
                return if cl == curLoad
                cl = cl.superclass
            end
            raise("Use #{self.name}::loadClass to construct a #{theClass} class")
        end

        # Generic CLI runner and argument parser for class-based applications.
        #
        # @param opts [Hash] Initial options hash
        # @param argv [Array<String>] Command line arguments (defaults to ARGV)
        # @yield [parser, phase, action_opts] Custom options setup callback block
        def run_cli(opts = {}, argv = ARGV)
            # Fetch actions and action helps
            action_helps = self.getActionAttr("ACTION_HELP")
            action_list = self.getActionAttr("ACTION_LIST")

            # 1. Action Parser Setup
            action_parser = OptionParser.new(nil, 60)
            action_parser.banner = "Usage: #{$0} <action> [action options]"
            action_parser.separator ""
            action_parser.separator "Options:"
            action_parser.on("-h", "--help", "Display usage.") { puts action_parser.to_s; exit 0 }
            action_parser.on("--verbose", "Displays more informations.") { self.verbose_log = true }

            # Yield parser to allow caller to customize the global options
            yield(action_parser, :global, opts) if block_given?

            action_parser.separator "Possible actions:"
            
            # Format actions nicely with padding
            max_len = action_helps.keys.map { |k| self.actionToString(k).length }.max || 0
            col_width = max_len + 4
            action_helps.each do |k, x|
                indent = col_width - self.actionToString(k).length
                action_parser.separator "\t * " + self.actionToString(k) + (" " * indent) + x
            end

            # Include any registered custom addon class listings if defined
            if self.respond_to?(:getCustomClasses) && self.getCustomClasses.length > 0
                action_parser.separator "Custom repo addons available:"
                self.getCustomClasses.each do |k, x|
                    action_parser.separator "\t * #{k}"
                end
            end

            rest = action_parser.order!(argv)
            if rest.length <= 0
                STDERR.puts("Error: No action provided")
                puts action_parser.to_s
                exit 1
            end

            action_s = argv[0]
            action = opts[:action] = self.stringToAction(action_s)
            argv.shift()

            # 2. Options Parser Setup
            opts_parser = OptionParser.new(nil, 60)
            opts_parser.banner = "Usage: #{$0} #{action_s} "
            opts_parser.separator "# " + action_helps[action].to_s()
            opts_parser.separator ""
            opts_parser.separator "Options:"
            opts_parser.on("-h", "--help", "Display usage.") { puts opts_parser.to_s; exit 0 }
            opts_parser.on("-n", "--no", "Assume no to all questions.") { opts[:yn_default] = :no }
            opts_parser.on("-y", "--yes", "Assume yes to all questions.") { opts[:yn_default] = :yes }
            opts_parser.on("--verbose", "Displays more informations.") { self.verbose_log = true }

            # Provide custom block hook for option parser customization
            yield(opts_parser, :action, opts) if block_given?

            # Set options on classes
            self.setOpts(action, opts_parser, opts)

            # Order remaining arguments
            if opts[:ignore_opts] != true
                rest = opts_parser.order!(argv)
                raise("Extra Unexpected extra arguments provided: " + rest.map(){|x|"'" + x + "'"}.join(", ")) if rest.length != 0
            else
                opts[:extra_args] = argv
            end

            # Validate options and execute action
            self.checkOpts(opts)
            exit self.execAction(opts, action)
        end
    end
end
