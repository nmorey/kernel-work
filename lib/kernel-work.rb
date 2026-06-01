# Path to the library directory for Kernel Work
KERNELWORK_LIB_DIR = File.dirname(File.realdirpath(__FILE__)) + '/kernel-work/'
CLI_CLASS_TOOL_LIB_DIR = File.dirname(File.realdirpath(__FILE__)) + '/'
require 'readline'

$LOAD_PATH.push(CLI_CLASS_TOOL_LIB_DIR)
$LOAD_PATH.push(KERNELWORK_LIB_DIR)
require 'cli_class_tool'

require 'error'
require 'kv'
require 'config'


###
# Action Classes
###
require 'common'
require 'commit'
require 'upstream'
require 'suse'
require 'kenv'

module KernelWork
  ACTION_CLASS = [ Common, Suse, Upstream, KEnv ]
  extend CLIClassTool::Utils
end

$LOAD_PATH.pop()
$LOAD_PATH.pop()
