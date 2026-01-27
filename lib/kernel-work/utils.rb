module KernelWork
   # List of classes that implement various kernel work actions
   ACTION_CLASS = [ Common, Suse, Upstream, KEnv ]
    # @!visibility private
    @@load_class = []
    # @!visibility private
    @@verbose_log = false

    # Convert a string to an action symbol, validating it against available actions
    #
    # @param str [String] Action name
    # @return [Symbol] Action symbol
    # @raise [RuntimeError] If action is invalid
    def stringToAction(str)
        action = str.to_sym()
        raise("Invalid action '#{str}'") if KernelWork::getActionAttr("ACTION_LIST").index(action) == nil
        return action
    end
    module_function :stringToAction

    # Convert an action symbol to a string
    #
    # @param sym [Symbol] Action symbol
    # @return [String] Action name
    def actionToString(sym)
        return sym.to_s()
    end
    module_function :actionToString

    # Get attributes from all action classes
    #
    # @param attr [Symbol] Attribute name (e.g., "ACTION_LIST")
    # @return [Hash, Array] Aggregated attributes
    def getActionAttr(attr)
        if Common.const_get(attr).class == Hash
            return ACTION_CLASS.inject({}){|h, x| h.merge(x.const_get(attr))}
        else
            return ACTION_CLASS.map(){|x| x.const_get(attr)}.flatten()
        end
    end
    module_function :getActionAttr


    # Run a block on the class responsible for a specific action
    #
    # @param action [Symbol] The action
    # @param sym [Symbol, nil] Optional method to check for existence
    # @yield [Class] The class handling the action
    # @return [Object] Result of the block or error code
    def _runOnClass(action, sym, &block)
        ACTION_CLASS.each(){|x|
            next if x::ACTION_LIST.index(action) == nil
            if sym == nil || x.singleton_methods().index(sym) != nil then
                return yield(x)
            end
            return 0
        }
        return -1
    end
    module_function :_runOnClass

    # Set options for an action
    #
    # @param action [Symbol] The action
    # @param optsParser [OptionParser] The option parser
    # @param opts [Hash] The options hash
    def setOpts(action, optsParser, opts)
        KernelWork::_runOnClass(action, :set_opts) {|kClass|
            kClass.set_opts(action, optsParser, opts)
        }
    end
    module_function :setOpts

    # Check options for validity
    #
    # @param opts [Hash] The options hash
    def checkOpts(opts)
         KernelWork::_runOnClass(opts[:action], :check_opts) {|kClass|
             kClass.check_opts(opts)
        }
    end
    module_function :checkOpts

    # Execute an action
    #
    # @param opts [Hash] The options hash
    # @param action [Symbol] The action to execute
    # @return [Object] Result of the action (often an Integer exit code)
    def execAction(opts, action)
        KernelWork::_runOnClass(action, nil) {|kClass|
            obj = kClass.new()
            begin
                ret = obj.public_send(action, opts)
                return ret.is_a?(Integer) ? ret : 0
            rescue KernelWorkError => e
                puts("# " + "ERROR".red().to_s() + ": Action '#{action}' failed: #{e.message}")
                e.backtrace.each(){|l|
                    puts("# " + "ERROR".red().to_s() + ": \t" + l)
                } if KernelWork.verbose_log

                if e.is_a?(RunError)
                    return e.err_code
                else
                    return 1
                end
            end
        }
    end
    module_function :execAction

    # Set verbose logging
    #
    # @param val [Boolean] True to enable verbose logging
    def self.verbose_log=(val)
        @@verbose_log = val
    end
    # Get verbose logging status
    #
    # @return [Boolean] Verbose logging status
    def self.verbose_log()
        @@verbose_log
    end
end
