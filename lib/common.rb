$LOAD_PATH.push(BACKPORT_LIB_DIR)

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
    class Common
        ACTION_LIST = [ :list_actions ]
        ACTION_HELP = {}
        def self.execAction(opts, action)
            puts KernelWork::getActionAttr("ACTION_LIST").join("\n")
            return 0
        end
    end

    ACTION_CLASS = [ Common, Suse, Upstream ]
#    ACTION_CLASS = [ Upstream, Suse ]
    @@load_class = []
    @@verbose_log = false

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

            # Try to add repo specific opts
            y = getClass(x)
            if x != y && y.singleton_methods().index(:check_opts) != nil then
                y.check_opts(opts)
            end
        }
    end
    module_function :checkOpts

    def execAction(opts, action)
        ACTION_CLASS.each(){|x|
            next if x::ACTION_LIST.index(action) == nil
            return x.execAction(opts, action)
        }
    end
    module_function :execAction

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
    module_function :confirm

    def checkLog(opts, br1, br2, action_msg)
        puts "Diff between #{br1} and #{br2}"
        puts `git log --format=oneline #{br1} ^#{br2}`
        return "n" if action_msg.to_s() == ""
        rep = confirm(opts, "#{action_msg} this branch")
        return rep
    end
    module_function :checkLog

    def showLog(opts, br1, br2)
        log(:INFO, "Diff between #{br1} and #{br2}")
        puts `git log --format=oneline #{br1} ^#{br2}`
        return "n"
    end
    module_function :showLog

    def _log(lvl, str, out=STDOUT)
        puts("# " + lvl.to_s() + ": " + str)
    end
    module_function :_log

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
    module_function :log

    def setVerbose(val)
        @@verbose_log = val
    end
    module_function :setVerbose
end
$LOAD_PATH.pop()


