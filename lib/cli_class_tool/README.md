# CLIClassTool

`CLIClassTool` is a lightweight, object-oriented framework for building class-based command-line interface (CLI) applications. It decouples the generic execution, logging, and action routing engine from project-specific business logic, making it extremely easy to synchronize across multiple projects or package as a shared gem.

---

## Directory Structure

To use `CLIClassTool` in your project, copy or subtree the `cli_class_tool/` directory under your library path (typically `lib/`):

```
lib/
└── cli_class_tool/
    ├── README.md
    ├── common.rb       # Generic common helper class (logging, shell exec, prompt)
    ├── string.rb       # Generic String class extension for ANSI colors
    └── utils.rb        # Generic action routing and runner engine
```

---

## How to Use inside a Project

### 1. Define Your Custom Action Classes
Define classes representing categories of your CLI commands. These classes should inherit from your project's subclassed `Common` (which inherits from `CLIClassTool::Common`):

```ruby
module MyProject
  # Inherit from CLIClassTool::Common
  class Common < CLIClassTool::Common
    # Add any project-specific helpers here
  end
end

module MyProject
  class Suse < Common
    # 1. Declare the list of available actions (methods)
    ACTION_LIST = [ :source_rebase, :checkpatch ]

    # 2. Define action method help/descriptions
    ACTION_HELP = {
      :source_rebase => "Rebase SUSE kernel sources to the latest tip",
      :checkpatch    => "Run checkpatch on pending patches"
    }

    # 3. Implement action methods
    def source_rebase(opts)
      log(:INFO, "Rebasing...")
      run("git pull --rebase")
      return 0 # Return 0 for success (or an Integer exit code)
    end

    def checkpatch(opts)
      # Uses inherited `run` and logging methods
      ret = run("git diff HEAD~1")
      log(:VERBOSE, ret)
      return 0
    end
  end
end
```

### 2. Initialize and Load CLIClassTool
In your library entrypoint (e.g. `lib/my-project.rb`), require the `cli_class_tool` components, set up your project-specific namespace, and extend `CLIClassTool::Utils`:

```ruby
# Add lib to load path if necessary
$LOAD_PATH.push(File.dirname(__FILE__))

require 'cli_class_tool'

module MyProject
  # Define project-specific base Common class
  class Common < CLIClassTool::Common
    # Project-specific methods can be defined here
  end
end

# Require all your custom action classes
require 'my_project/suse'
require 'my_project/other_actions'

module MyProject
  # List of classes that implement various CLI actions
  ACTION_CLASS = [ Suse, OtherActions ]

  # Extend CLIClassTool::Utils to map methods onto MyProject module
  extend CLIClassTool::Utils
end
```

### 3. Create the Executable Runner
In your executable bin (e.g. `bin/mytool`), parse options and call the `execAction` utility to invoke the target action class:

```ruby
#!/usr/bin/ruby
require 'optparse'
require 'my-project'

opts = { action: :source_rebase } # Typically parsed from command-line arguments

# 1. Optionally parse options
optsParser = OptionParser.new
MyProject.setOpts(opts[:action], optsParser, opts)
optsParser.parse!(ARGV)

# 2. Check options validity
MyProject.checkOpts(opts)

# 3. Execute action dynamically
# Uses the class `load` factory method if defined, falling back to `.new`.
# If an exception is thrown, it will be caught and logged cleanly, returning the correct exit status.
exit MyProject.execAction(opts, opts[:action])
```

---

## Logging Levels
By inheriting from `CLIClassTool::Common`, your action classes have access to a rich `log` helper supporting several standard output and color levels:

- `log(:DEBUG, "msg")`: Prints to STDOUT when `ENV["DEBUG"]` is active (Magenta).
- `log(:VERBOSE, "msg")`: Prints to STDOUT when `MyProject.verbose_log == true` (Blue).
- `log(:INFO, "msg")`: General informative logs (Green).
- `log(:PROGRESS, "msg")`: In-place update logs (Green with `\r` carriage return).
- `log(:WARNING, "msg")`: Warning logs (Brown).
- `log(:ERROR, "msg")`: Prints to STDERR (Red).

---

## Dynamic Class Overrides (Addons)

`CLIClassTool` natively supports dynamic class overrides (addons). This allows projects to load repository-specific or custom subclasses that extend or override base action behaviors without modifying the core codebase.

### 1. Set Up `getExtendedClass`

To enable class overrides, define a `getExtendedClass` class/module method on your parent module:

```ruby
module MyProject
  # Map of repository names to overridden classes
  @@custom_classes = {}

  def self.registerCustom(repo_name, classes)
    @@custom_classes[repo_name] = classes
  end

  # Resolve the customized/overridden subclass (addon) if registered
  def self.getExtendedClass(default_class, repo_name = File.basename(Dir.pwd))
    custom = @@custom_classes[repo_name]
    if custom != nil && custom[default_class] != nil
      return custom[default_class]
    else
      return default_class
    end
  end
end
```

If defined, `CLIClassTool` will automatically:
- Execute actions using the extended class instead of the base class.
- For options setup (`setOpts`) and validation checks (`checkOpts`), it will sequentially call BOTH the base class hooks and the extended class hooks to ensure clean options merging.

### 2. Dynamically Loading Addons

`CLIClassTool` provides a `loadAddons(path)` helper to dynamically scan a folder and load all custom Ruby classes/addons present in it. 

```ruby
module MyProject
  extend CLIClassTool::Utils

  # Load all core addons
  loadAddons(File.expand_path('addons', __dir__))

  # Load optional user addons from an environment variable path
  if ENV["MY_PROJECT_ADDON_DIR"]
    loadAddons(ENV["MY_PROJECT_ADDON_DIR"])
  end
end
```

### 3. Factory Class Loading & Validation

`CLIClassTool` provides helper methods to implement safe, validated factory class loading. This ensures that subclasses are only instantiated through the authorized factory methods rather than being directly instantiated:

- `loadClass(default_class, addon_key, *args)`: Safely loads and instantiates an overridden/extended class instance.
- `checkDirectConstructor(class)`: Raises an error if the class is directly instantiated instead of going through `loadClass`.

#### Example Setup:

```ruby
module MyProject
  class Suse < Common
    def initialize(path)
      # Validate that constructor was only called through loadClass factory
      MyProject.checkDirectConstructor(self.class)
      @path = path
    end

    # Factory loading method
    def self.load(path=".")
      # Safely instantiate via CLIClassTool loadClass
      return MyProject.loadClass(Suse, "suse-addon-key", path)
    end
  end
end
```
