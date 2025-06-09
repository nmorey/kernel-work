$LOAD_PATH.push(BACKPORT_LIB_DIR)

module KernelWork
    class RunError < RuntimeError
        def initialize(err_code, msg = nil)
            @err_code = err_code
            @msg = msg
        end
        attr_reader :err_code, :msg
    end
    class UnknownBranch < RuntimeError
        def initialize(path)
            super("Failed to detect branch name in #{path}")
        end
    end
    class BranchMismatch < RuntimeError
        def initialize(upstream_br, suse_br)
            super("Branch mismatch. Linux tree has '#{upstream_br}'. kernel-source has '#{suse_br}'")
        end
    end
    class Common
        ACTION_LIST = [ :list_actions ]
        ACTION_HELP = {}

        private
        def _log(lvl, str, out=STDOUT)
            puts("# " + lvl.to_s() + ": " + str)
        end
        def _relog(lvl, str, out=STDOUT)
            print("# " + lvl.to_s() + ": " + str + "\r")
        end
        def abort_if_err(check_err, sysret, ret = nil)
            raise(RunError.new(sysret.exitstatus, ret)) if sysret.exitstatus != 0 && check_err == true
        end

        protected
        def log(lvl, str)
            case lvl
            when :DEBUG
                _log("DEBUG".magenta(), str) if ENV["DEBUG"].to_s() != ""
            when :DEBUG_CI
                _log("DEBUG_CI".magenta(), str) if ENV["DEBUG_CI"].to_s() != ""
            when :VERBOSE
                _log("INFO".blue(), str) if KernelWork::verbose_log == true
            when :INFO
                _log("INFO".green(), str)
            when :PROGRESS
                _relog("INFO".green(), str)
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
                    raise UnknownBranch.new(@path)
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
        def run(cmd, check_err = true)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running command '#{cmd}'")
            ret = `cd #{@path} && #{cmd}`.chomp()
            abort_if_err(check_err, $?, ret)
            return ret
        end

        def runSystem(cmd, check_err = true)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running interactive command '#{cmd}'")
            ret = system("cd #{@path} && #{cmd}")
            abort_if_err(check_err, $?)
            return ret
        end

        def runGit(cmd, opts={}, check_err = true)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running git command '#{cmd}'")
            ret = `cd #{@path} && #{opts[:env]} git #{cmd}`.chomp()
            abort_if_err(check_err, $?, ret)
            return ret
        end

        def runGitInteractive(cmd, opts={}, check_err = true)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running interactive git command '#{cmd}'")
            ret = system("cd #{@path} && #{opts[:env]} git #{cmd}")
            abort_if_err(check_err, $?)
            return ret
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
require 'kenv'

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
            return obj.send(action, opts)
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
$LOAD_PATH.pop()


