module KernelWork
    class KEnv < Common
        BASE_ACTION_LIST = `kenv -l 2>/dev/null || echo ""`.chomp().split("\n").map(){|x| x.to_sym()}
        SHORTCUT_ACTION_LIST = {
            :s => :switch,
            :sw => :switch,
            :l => :list,
            :cr => :create,
        }
        ACTION_LIST = BASE_ACTION_LIST + SHORTCUT_ACTION_LIST.map(){|k, h| k}
        ACTION_HELP = {
            :"*** kEnv commands *** *" => ""
        }.merge(BASE_ACTION_LIST.inject({}){|h, x|
                    h[x] = "kenv #{x.to_s()}"
                    h
                })

        def self.set_opts(action, optsParser, opts)
            opts[:ignore_opts] = true
        end


        BASE_ACTION_LIST.each(){|action|
            define_method action do |opts|
                return exec("kenv", action.to_s(), *opts[:extra_args])
            end
        }
        SHORTCUT_ACTION_LIST.each(){|short, action|
            next if BASE_ACTION_LIST.index(action) == nil
            define_method short do |opts|
                return exec("kenv", action.to_s(), *opts[:extra_args])
            end
        }
        public
        def initialize()
        end
    end
end
