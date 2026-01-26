# Main module for Kernel Work tools and utilities
module KernelWork

    # Common utility class providing logging, configuration, and shell execution methods
    class Common
        # List of available actions for this class
        ACTION_LIST = [ :list_actions ]
        # Help text for actions
        ACTION_HELP = {}

        private
        # Internal log method
        # @param lvl [String] Log level string (colored)
        # @param str [String] Message
        # @param out [IO] Output stream (default STDOUT)
        def _log(lvl, str, out=STDOUT)
            puts("# " + lvl.to_s() + ": " + str)
        end

        # Internal relog method (update current line)
        # @param lvl [String] Log level string (colored)
        # @param str [String] Message
        # @param out [IO] Output stream (default STDOUT)
        def _relog(lvl, str, out=STDOUT)
            print("# " + lvl.to_s() + ": " + str + "\r")
        end

        # Raise error if system command failed
        # @param check_err [Boolean] Whether to check for errors
        # @param sysret [Process::Status] System return status
        # @param ret [String, nil] Optional return message
        # @raise [RunError] If command failed
        def abort_if_err(check_err, sysret, ret = nil)
            raise(RunError.new(sysret.exitstatus, ret)) if sysret.exitstatus != 0 && check_err == true
        end

        # Debug command execution
        # @param cmd_type [String] Type of command (e.g., 'git')
        # @param cmd [String] The command string
        def cmd_debug(cmd_type, cmd)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running #{cmd_type} command '#{cmd}'")
        end
        protected
        # Log a message with a specific level
        #
        # @param lvl [Symbol] Log level (:DEBUG, :INFO, :WARNING, :ERROR, etc.)
        # @param str [String] Message to log
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

        # Detect and set the current git branch
        #
        # @raise [UnknownBranch] If branch cannot be detected
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

        # Prompt the user for confirmation
        #
        # @param opts [Hash] Options hash
        # @param msg [String] Confirmation message
        # @param ignore_default [Boolean] Ignore default yes/no options
        # @param allowed_reps [Array<String>] Allowed responses
        # @return [String] User response
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
        # Run a shell command
        #
        # @param cmd [String] Command to run
        # @param check_err [Boolean] Raise error on failure
        # @return [String] Command output
        # @raise [RunError] If command fails and check_err is true
        def run(cmd, check_err = true)
            cmd_debug('', cmd)
            ret = `cd #{@path} && #{cmd}`.chomp()
            abort_if_err(check_err, $?, ret)
            return ret
        end

        # Run a shell command using system() (interactive)
        #
        # @param cmd [String] Command to run
        # @param check_err [Boolean] Raise error on failure
        # @return [Boolean] Command success status
        # @raise [RunError] If command fails and check_err is true
        def runSystem(cmd, check_err = true)
            cmd_debug('interactive', cmd)
            ret = system("cd #{@path} && #{cmd}")
            abort_if_err(check_err, $?)
            return ret
        end

        # Run a git command
        #
        # @param cmd [String] Git command arguments
        # @param opts [Hash] Options (e.g., :env)
        # @param check_err [Boolean] Raise error on failure
        # @return [String] Command output
        # @raise [RunError] If command fails and check_err is true
        def runGit(cmd, opts={}, check_err = true)
            cmd_debug('git', cmd)
            ret = `cd #{@path} && #{opts[:env]} git #{cmd}`.chomp()
            abort_if_err(check_err, $?, ret)
            return ret
        end

        # Run a git command interactively
        #
        # @param cmd [String] Git command arguments
        # @param opts [Hash] Options (e.g., :env)
        # @param check_err [Boolean] Raise error on failure
        # @return [Boolean] Command success status
        # @raise [RunError] If command fails and check_err is true
        def runGitInteractive(cmd, opts={}, check_err = true)
            cmd_debug('git interactive', cmd)
            ret = system("cd #{@path} && #{opts[:env]} git #{cmd}")
            abort_if_err(check_err, $?)
            return ret
        end

        # List available actions
        #
        # @param opts [Hash] Options hash
        # @return [Integer] 0
        def list_actions(opts)
            puts KernelWork::getActionAttr("ACTION_LIST").map(){|x| KernelWork::actionToString(x)}.join("\n")
            return 0
        end
    end
end


