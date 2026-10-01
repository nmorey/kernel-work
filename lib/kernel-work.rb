# Path to the library directory for Kernel Work
KERNELWORK_LIB_DIR = File.dirname(File.realdirpath(__FILE__)) + '/kernel-work/'
require 'readline'
require 'cli_class_tool'

require_relative 'kernel-work/error'
require_relative 'kernel-work/common'

###
# Models (domain classes)
###
require_relative 'kernel-work/models/kv'
require_relative 'kernel-work/models/config'
require_relative 'kernel-work/models/commit'
require_relative 'kernel-work/models/patch'
require_relative 'kernel-work/models/bugzilla'
require_relative 'kernel-work/models/cve_tracker'
require_relative 'kernel-work/models/cve'
require_relative 'kernel-work/models/commit_filter'
require_relative 'kernel-work/models/linux_build_opts'
require_relative 'kernel-work/models/linux'
require_relative 'kernel-work/models/kernel_source'
require_relative 'kernel-work/models/workflow'

###
# CLI Controllers
###
require_relative 'kernel-work/cli/build_opts'
require_relative 'kernel-work/cli/commit_filter'
require_relative 'kernel-work/cli/model_access'
require_relative 'kernel-work/cli/kernel'
require_relative 'kernel-work/cli/config'
require_relative 'kernel-work/cli/wenv'
require_relative 'kernel-work/cli/cve'

# Namespace for the Kernel Work tool suite.
#
# Provides utilities, configuration, action classes, and helper libraries
# to facilitate kernel backporting, CVE tracking, and upstream integration.
module KernelWork
  # The list of primary action classes included in the KernelWork module.
  # @return [Array<Class>] list of action classes
  ACTION_CLASS = [ CLI::Kernel ]

  # Subcommand actions registry for CLIClassTool routing
  # @return [Hash{String => Module}] mapping of subcommand names to CLI modules
  CLI_SUB_ACTIONS = {
    "cve"    => CLI::CVE,
    "config" => CLI::Config,
    "env"    => CLI::WEnv,
  }

  extend CLIClassTool::Utils
end
