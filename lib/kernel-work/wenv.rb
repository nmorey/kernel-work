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
rescue LoadError => e
    # WorkEnvs is not available on this system
    p e
end

module KernelWork
    # Register WorkEnvs as a subcommand under 'env' if available
    if defined?(WorkEnvs)
        Env = WorkEnvs

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

