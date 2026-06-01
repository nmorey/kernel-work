require 'cli_class_tool/common'

module KernelWork
    # Common utility class providing logging, configuration, and shell execution methods
    # Inherits generic capabilities from CLIClassTool::Common and implements project-specific branch handling
    class Common < CLIClassTool::Common

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
    end
end
