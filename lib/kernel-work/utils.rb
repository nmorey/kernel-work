module KernelWork
   ACTION_CLASS = [ Common, Suse, Upstream, KEnv ]
    @@load_class = []
    @@verbose_log = false

    def stringToAction(str)
        action = str.to_sym()
        raise("Invalid action '#{str}'") if KernelWork::getActionAttr("ACTION_LIST").index(action) == nil
        return action
    end
    module_function :stringToAction

    def actionToString(sym)
        return sym.to_s()
    end
    module_function :actionToString

    def getActionAttr(attr)
        if Common.const_get(attr).class == Hash
            return ACTION_CLASS.inject({}){|h, x| h.merge(x.const_get(attr))}
        else
            return ACTION_CLASS.map(){|x| x.const_get(attr)}.flatten()
        end
    end
    module_function :getActionAttr


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

    def setOpts(action, optsParser, opts)
        KernelWork::_runOnClass(action, :set_opts) {|kClass|
            kClass.set_opts(action, optsParser, opts)
        }
    end
    module_function :setOpts

    def checkOpts(opts)
         KernelWork::_runOnClass(opts[:action], :check_opts) {|kClass|
             kClass.check_opts(opts)
        }
    end
    module_function :checkOpts

    def execAction(opts, action)
        KernelWork::_runOnClass(action, nil) {|kClass|
            obj = kClass.new()
            begin
                return obj.public_send(action, opts)
            rescue RunError => e
                puts("# " + "ERROR".red().to_s() + ": Action '#{action}' failed with err '#{e.err_code()}'")
                e.backtrace.each(){|l|
                    puts("# " + "ERROR".red().to_s() + ": \t" + l)
                }
                return e.err_code()
            end
        }
    end
    module_function :execAction

    def self.verbose_log=(val)
        @@verbose_log = val
    end
    def self.verbose_log()
        @@verbose_log
    end
end
