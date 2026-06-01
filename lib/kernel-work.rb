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
require_relative 'kernel-work/kenv'

module KernelWork
  ACTION_CLASS = [ Common, Suse, Upstream, KEnv ]
  extend CLIClassTool::Utils
end
