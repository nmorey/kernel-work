if ENV["WORK_ENV_SCRIPTS_DIR"].to_s != ""
    $LOAD_PATH.push(ENV["WORK_ENV_SCRIPTS_DIR"] + "/lib")
end

begin
    require 'WorkEnvs'

    # Reopen WorkEnvs to define subcommand names/descriptions for parent auto-discovery
    module WorkEnvs
        CLI_COMMAND_NAME = "env"
        CLI_DESCRIPTION = "Manage work environments"
        CLI_HELP_EXPAND = "*** WENV commands ***"
    end
rescue LoadError => _e
    # WorkEnvs is not available on this system
end

module KernelWork
    module CLI
        if defined?(WorkEnvs)
            WEnv = WorkEnvs
        else
            # Stub module when WorkEnvs is not available
            module WEnv
                # Command name registered with CLIClassTool.
                CLI_COMMAND_NAME = "env"
                # Short description of the command.
                CLI_DESCRIPTION = "Manage work environments"
            end
        end
    end

    # Register WorkEnvs as a subcommand under 'env' if available
    if defined?(WorkEnvs)
        # Reference to the WorkEnvs module representing the work environment.
        # @return [Module] the WorkEnvs module alias
        Env = WorkEnvs
        # Reference to WEnv in CLI namespace.
        WEnv = CLI::WEnv

        # Define top-level command aliases dynamically expanded by CLIClassTool
        CLI_COMMAND_ALIASES = {
            :s      => "env switch",
            :sw     => "env switch",
            :switch => "env switch",
            :l      => "env list",
            :list   => "env list",
            :cr     => "env create",
            :create => "env create"
        }
    end
end
