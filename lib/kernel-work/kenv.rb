module KernelWork
    # Interface to the kenv command line tool
    class KEnv < Common
        `which kenv`
        if $?.success? then
            # List of base actions available from kenv command
            BASE_ACTION_LIST = `kenv -l 2>/dev/null || echo ""`.chomp().split("\n").map(){|x| x.to_sym()}
            # Shortcut aliases for actions
            SHORTCUT_ACTION_LIST = {
                :s => :switch,
                :sw => :switch,
                :l => :list,
                :cr => :create,
            }
            # Full list of available actions
            ACTION_LIST = BASE_ACTION_LIST + SHORTCUT_ACTION_LIST.map(){|k, h| k}
            # Help text for actions
            ACTION_HELP = {
                :"*** kEnv commands *** *" => ""
            }.merge(BASE_ACTION_LIST.inject({}){|h, x|
                        h[x] = "kenv #{x.to_s()}"
                        h
                    })

            # Set options for KEnv actions
            #
            # @param action [Symbol] The action
            # @param optsParser [OptionParser] The option parser
            # @param opts [Hash] The options hash
            def self.set_opts(action, optsParser, opts)
                opts[:ignore_opts] = true
            end


            # @!method switch(opts)
            #   Switch kenv environment
            #   @param opts [Hash] Options hash with :extra_args
            # @!method list(opts)
            #   List kenv environments
            #   @param opts [Hash] Options hash with :extra_args
            # @!method create(opts)
            #   Create kenv environment
            #   @param opts [Hash] Options hash with :extra_args
            # @!method s(opts)
            #   Alias for switch
            # @!method sw(opts)
            #   Alias for switch
            # @!method l(opts)
            #   Alias for list
            # @!method cr(opts)
            #   Alias for create

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
            # Initialize a new KEnv object
            def initialize()
            end
        end
    end
end
