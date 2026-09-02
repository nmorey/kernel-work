# Path to the library directory for Kernel Work
KERNELWORK_LIB_DIR = File.dirname(File.realdirpath(__FILE__)) + '/kernel-work/'
require 'readline'
require 'cli_class_tool'

require_relative 'kernel-work/error'
require_relative 'kernel-work/kv'
require_relative 'kernel-work/config'


###
# Action Classes
###
require_relative 'kernel-work/common'
require_relative 'kernel-work/commit'
require_relative 'kernel-work/upstream'
require_relative 'kernel-work/suse'
require_relative 'kernel-work/wenv'
require_relative 'kernel-work/config_cli'
require_relative 'kernel-work/cve'

# Namespace for the Kernel Work tool suite.
#
# Provides utilities, configuration, action classes, and helper libraries
# to facilitate kernel backporting, CVE tracking, and upstream integration.
module KernelWork
  # The list of primary action classes included in the KernelWork module.
  # @return [Array<Class>] list of action classes
  ACTION_CLASS = [ Suse, Upstream ]
  extend CLIClassTool::Utils
end
