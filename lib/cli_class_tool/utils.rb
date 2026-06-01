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
            if common_class.const_get(attr).class == Hash
                return action_classes.inject({}){|h, x| h.merge(x.const_get(attr))}
            else
                return action_classes.map(){|x| x.const_get(attr)}.flatten()
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
                if sym == nil || x.singleton_methods().index(sym) != nil then
                    return yield(x)
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
                obj = kClass.new()
                begin
                    ret = obj.public_send(action, opts)
                    return ret.is_a?(Integer) ? ret : 0
                rescue error_class => e
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
    end
end
