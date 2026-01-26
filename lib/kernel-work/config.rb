require 'yaml'
require 'fileutils'

module KernelWork
  # Configuration management for Kernel Work
  class Config
    # Default configuration values
    DEFAULTS = {
      linux_git_env_var: "LINUX_GIT",
      kernel_source_dir_env_var: "KERNEL_SOURCE_DIR",
      upstream: {
        default_j_opt: "$(nproc --all --ignore=4)",
        remote: "SUSE",
        git_fixes_url: "http://fixes.prg2.suse.org/current/",
        git_fixes_subtree: "infiniband",
        maintainer_branches: [ "linux-rdma/for-rc", "linux-rdma/for-next" ],
        # Default compiler rules
        compiler_rules: [
          { :range => "0.0...4.0", :gcc => "gcc-4.8" },
          { :range => "4.0..5.3",  :gcc => "gcc-7"   },
          {                        :gcc => "gcc -std=gnu11" }
        ],
        # Default archs
        # Note: Arch keys are strings in usage, but symbols in this hash definition.
        # We will ensure they are accessible as needed.
        archs: {
            "x86_64" => {
                :CC => "CC=\"ccache gcc\"",
            },
            "arm64" => {
                :CC => "CC=\"ccache gcc\"",
                :CROSS_COMPILE => "aarch64-suse-linux-",
                :ARCH => "ARCH=arm64",
            },
            "s390x" => {
                :CC => "CC=\"ccache gcc\"",
                :CROSS_COMPILE => "s390x-suse-linux-",
                :ARCH => "ARCH=s390",
            }
        }
      },
      suse: {
        remote: "origin",
        # Default branches
        branches: [
            {  :name => "SLE15-SP6-LTSS",
               :ref => "git-fixes",
            },
            {  :name => "SLE15-SP7",
               :ref => "git-fixes",
            },
            {  :name => "SL-16.0",
               :ref => "git-fixes",
            },
            {  :name => "SL-16.1",
               :ref => "git-fixes",
            },
            {  :name => "cve/linux-5.14-LTSS",
               :ref => nil
            },
            {  :name => "cve/linux-5.3-LTSS",
               :ref => nil
            }
        ]
      }
    }

    # Initialize a new Config object with defaults and load from file
    def initialize
      @settings = deep_copy(DEFAULTS)
      load_config
    end

    # Access the raw settings hash
    # @return [Hash]
    def settings
        @settings
    end

    # Get the environment variable name for LINUX_GIT
    # @return [String]
    def linux_git_env_var
        @settings[:linux_git_env_var]
    end

    # Get the environment variable name for KERNEL_SOURCE_DIR
    # @return [String]
    def kernel_source_dir_env_var
        @settings[:kernel_source_dir_env_var]
    end

    # Get the path to LINUX_GIT from environment
    # @return [String, nil]
    def linux_git
        ENV[linux_git_env_var].chomp if ENV[linux_git_env_var]
    end

    # Get the path to KERNEL_SOURCE_DIR from environment
    # @return [String, nil]
    def kernel_source_dir
        ENV[kernel_source_dir_env_var].chomp if ENV[kernel_source_dir_env_var]
    end

    # Access upstream specific configuration
    # @return [RecursiveConfig]
    def upstream
        RecursiveConfig.new(@settings[:upstream])
    end

    # Access SUSE specific configuration
    # @return [RecursiveConfig]
    def suse
        RecursiveConfig.new(@settings[:suse])
    end

    # Load configuration from YAML file and merge with defaults
    def load_config
        file = config_file
        if File.exist?(file)
            loaded = YAML.load_file(file, symbolize_names: true) || {}
            deep_merge!(@settings, loaded)
        else
            save_config # Save defaults if no config exists
        end
    end

    # Save current configuration to YAML file
    def save_config
        file = config_file
        dir = File.dirname(file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.write(file, @settings.to_yaml)
    end

    # Get the path to the configuration file
    # @return [String]
    def config_file
        config_home = ENV['XDG_CONFIG_HOME']
        if config_home.nil? || config_home.empty?
            config_home = File.join(Dir.home, '.config')
        end
        File.join(config_home, 'kernel-work', 'config.yml')
    end

    private

    # Deep copy a hash
    # @param hash [Hash]
    # @return [Hash]
    def deep_copy(hash)
      Marshal.load(Marshal.dump(hash))
    end

    # Deep merge source hash into target hash
    # @param target [Hash]
    # @param source [Hash]
    # @return [Hash]
    def deep_merge!(target, source)
      source.each do |key, value|
        if target[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge!(target[key], value)
        else
          target[key] = value
        end
      end
      target
    end

    # Wrapper class for recursive configuration access via method calls or brackets
    class RecursiveConfig
        # Initialize with a hash or array
        # @param obj [Hash, Array]
        def initialize(obj)
            @obj = obj
        end

        # Access value by key
        # @param key [Symbol, String]
        # @return [Object, RecursiveConfig]
        def []=(key, val)
            @obj[key] = val
        end

        # Access value by key
        # @param key [Symbol, String]
        # @return [Object, RecursiveConfig]
        def [](key)
            val = get_value(key)
            wrap(val)
        end

        # Handle dynamic method calls for configuration keys
        def method_missing(name, *args, &block)
            if @obj.is_a?(Hash)
                val = get_value(name)
                # If val is nil, try string version of name
                if val.nil? && !@obj.key?(name)
                     val = get_value(name.to_s)
                end

                # If we found something, wrap it
                if !val.nil? || @obj.key?(name) || @obj.key?(name.to_s)
                     return wrap(val)
                end
            end

            if @obj.respond_to?(name)
                return @obj.public_send(name, *args, &block)
            end

            super
        end

        # Convert to raw hash
        # @return [Hash]
        def to_h
            @obj
        end

        # Convert to raw array
        # @return [Array]
        def to_a
            return @obj if @obj.is_a?(Array)
            super
        end

        # Check if it responds to a method
        def respond_to_missing?(name, include_private = false)
            @obj.respond_to?(name, include_private) || super
        end

        private

        # Get value from the underlying object
        def get_value(key)
             @obj[key]
        end

        # Wrap value in RecursiveConfig if it's a hash or array containing hashes
        def wrap(val)
            if val.is_a?(Hash)
                RecursiveConfig.new(val)
            elsif val.is_a?(Array)
                val.map { |v| wrap(v) }
            else
                val
            end
        end
    end
  end

  # Get the global configuration instance
  # @return [Config]
  def self.config
    @config ||= Config.new
  end

  # Configure KernelWork
  # @yield [config]
  def self.configure
    yield config
  end
end
