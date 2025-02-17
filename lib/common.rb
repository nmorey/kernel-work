$LOAD_PATH.push(BACKPORT_LIB_DIR)

module KernelWork
    class Common
        ACTION_LIST = [ :list_actions ]
        ACTION_HELP = {}

        def self.execAction(opts, action)
            up   = Common.new()
            return up.send(action, opts)
        end

        private
        def _log(lvl, str, out=STDOUT)
            puts("# " + lvl.to_s() + ": " + str)
        end

        protected
        def log(lvl, str)
            case lvl
            when :DEBUG
                _log("DEBUG".magenta(), str) if ENV["DEBUG"].to_s() != ""
            when :DEBUG_CI
                _log("DEBUG_CI".magenta(), str) if ENV["DEBUG_CI"].to_s() != ""
            when :VERBOSE
                _log("INFO".blue(), str) if @@verbose_log == true
            when :INFO
                _log("INFO".green(), str)
            when :WARNING
                _log("WARNING".brown(), str)
            when :ERROR
                _log("ERROR".red(), str, STDERR)
            else
                _log(lvl, str)
            end
        end

        def set_branches()
            begin
                @local_branch = runGit("branch --show current").chomp()
                @branch = @local_branch.split('/')[2..-2].join('/')
            rescue
                begin
                    # Check if we are in the middle of a rebase
                    gitDir = runGit("rev-parse --git-dir HEAD").split("\n")[0]
                    raise "No luck" if ! File.directory?("#{gitDir}/rebase-merge")
                    @local_branch = run("head -n1 #{gitDir}/rebase-merge/head-name").chomp().
                                        split('/')[2..-1].join('/')

                    @branch = @local_branch.split('/')[2..-2].join('/')
                rescue
                    raise "Failed to detect branch name"
                end
            end
        end

        def confirm(opts, msg, ignore_default=false, allowed_reps=[ "y", "n" ])
            rep = 't'
            while allowed_reps.index(rep) == nil && rep != '' do
                puts "Do you wish to #{msg} ? (#{allowed_reps.join("/")}): "
                case (ignore_default == true ? nil : opts[:yn_default])
                when :no
                    puts "Auto-replying no due to --no option"
                    rep = 'n'
                when :yes
                    puts "Auto-replying yes due to --yes option"
                    rep = 'y'
                else
                    rep = STDIN.gets.chomp()
                end
            end
            return rep
        end

        public
        def run(cmd)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running command '#{cmd}'")
            return `cd #{@path} && #{cmd}`.chomp()
        end

        def runSystem(cmd)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running interactive command '#{cmd}'")
            return system("cd #{@path} && #{cmd}")
        end

        def runGit(cmd, opts={})
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running git command '#{cmd}'")
            return `cd #{@path} && #{opts[:env]} git #{cmd}`.chomp()
        end

        def runGitInteractive(cmd, opts={})
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running interactive git command '#{cmd}'")
            return system("cd #{@path} && #{opts[:env]} git #{cmd}")
        end

        def list_actions(opts)
            puts KernelWork::getActionAttr("ACTION_LIST").map(){|x| KernelWork::actionToString(x)}.join("\n")
            return 0
        end
    end
end

# require here
require 'upstream'
require 'suse'

$LOAD_PATH.pop()

class String
    # colorization
    @@is_a_tty = nil
    def colorize(color_code)
        @@is_a_tty = STDOUT.isatty() if @@is_a_tty == nil
        if @@is_a_tty then
            return "\e[#{color_code}m#{self}\e[0m"
        else
            return self
        end
    end

    def red
        colorize(31)
    end

    def green
        colorize(32)
    end

    def brown
        colorize(33)
    end

    def blue
        colorize(34)
    end

    def magenta
        colorize(35)
    end
end

module KernelWork
   ACTION_CLASS = [ Common, Suse, Upstream ]
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

    def setOpts(action, optsParser, opts)
         ACTION_CLASS.each(){|x|
             next if x::ACTION_LIST.index(action) == nil
             if x.singleton_methods().index(:set_opts) != nil then
                 x.set_opts(action, optsParser, opts)
             end
             break
        }
    end
    module_function :setOpts

    def checkOpts(opts)
        ACTION_CLASS.each(){|x|
            next if x::ACTION_LIST.index(opts[:action]) == nil
            next if x.singleton_methods().index(:check_opts) == nil
            x.check_opts(opts)
        }
    end
    module_function :checkOpts

    def execAction(opts, action)
        ACTION_CLASS.each(){|kClass|
            next if kClass::ACTION_LIST.index(action) == nil
            obj = kClass.new()
            return obj.send(action, opts)
        }
    end
    module_function :execAction

    def setVerbose(val)
        @@verbose_log = val
    end
    module_function :setVerbose
end
$LOAD_PATH.pop()


