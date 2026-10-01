require 'tempfile'

module KernelWork
    # Represents a kernel-source Patch commit
    class Patch < Common
        # Patch References
        # @return [String, nil] The patch reference string
        attr_reader :ref

        # Patch filename
        # @return [String] The patch filename
        attr_reader :pname
        alias_method :name, :pname

        # Initialize a new Patch object
        # @param kernel_source [KernelSource] KernelSource repository model
        # @param commit [Commit] The commit to generate a patch for
        # @param filename [String, nil] Custom patch filename override
        # @return [Patch] New Patch object
        def initialize(kernel_source, commit, filename: nil)
            @kernel_source = kernel_source
            @commit = commit
            @pname = filename || @commit.patchname.gsub(/^0001-/, "")
            @name_checked = false
            @ref = nil
            @cve_refs = nil
        end

        # Generate a patch from the Linux tree and fill in custom headers (Git-commit, Patch-mainline, etc.)
        # into kernel source
        #
        # @param filename [String, nil] Custom patch filename
        # @param ref [String, nil] Reference string override
        # @param yn_default [Symbol, nil] Default auto-reply (:yes or :no)
        # @return [void]
        def generate(filename: nil, ref: nil, yn_default: nil)
            name_check(filename: filename, yn_default: yn_default)
            compute_ref(ref: ref)

            i = File.open(@commit.path + "/" + @commit.patchname, "r")
            o = File.open(fullpath, "w+")
            p_split = 0
            in_subj = false
            i.each do |l|
                case l
                when /^Subject: \[PATCH/
                    in_subj = true
                    o.puts l
                when /^\n$/
                    if in_subj == true
                        o.puts "Git-commit: #{@commit.f_sha}" if @commit.f_sha != ""
                        o.puts "Patch-mainline: #{@commit.orig_tag}" if @commit.orig_tag != nil
                        raise NoRefError.new if @ref.to_s == ""

                        o.puts "References: #{@ref}"
                        o.puts "Git-repo: #{@commit.git_repo}" if @commit.git_repo != nil
                        in_subj = false
                    end
                    o.puts l
                when /^---\n$/
                    if p_split == 0
                        name = @kernel_source.runGit("config --get user.name")
                        email = @kernel_source.runGit("config --get user.email")
                        o.puts "Acked-by: #{name} <#{email}>"
                        p_split = 1
                    end
                    o.puts l
                else
                    o.puts l
                end
            end
            i.close
            o.close
            File.delete(i)
        end

        # Get the full/absolute path to this patch
        #
        # @param pname [String, nil] Optional argument to compute path for a given filename
        # @return [String] Absolute path
        def fullpath(pname = nil)
            @kernel_source.path + "/" + localpath(pname)
        end

        # Get the local path to this patch in kernel-source
        #
        # @param pname [String, nil] Optional argument to compute path for a given filename
        # @return [String] Local path
        def localpath(pname = nil)
            pname = @pname if pname.nil?
            @kernel_source.patch_dir + "/" + pname
        end

        # Automatically extract CVE and BSC references for a patch using suse-add-cves
        # Fallback to default ref
        #
        # @param ref [String, nil] Explicit reference string override
        # @return [void]
        def compute_ref(ref: nil)
            return @ref if ref.nil? && !@ref.to_s.empty?

            refs = cve_refs
            if refs.to_s == ""
                @ref = @kernel_source.default_patch_references(ref)
                raise NoRefError.new if @ref.to_s == ""
            else
                @ref = refs
            end
        end

        private

        # Check name availability to generate a patch
        # Looks into the patch dir of kernel source and make sure names will not clash.
        # In case of a clash, tries to find a solution or prompts user for a custom name
        #
        # @param filename [String, nil] Custom filename override
        # @param yn_default [Symbol, nil] Default auto-reply
        # @return [void]
        # @raise [TargetFileExistsError] If target file exists and custom filename was provided
        # @raise [SCPAbort] If user aborts interactive selection
        def name_check(filename: nil, yn_default: nil)
            return if @name_checked == true

            fpath = fullpath

            if File.exist?(fpath)
                raise TargetFileExistsError.new(@pname) if filename != nil

                long_name = @commit.patchname(92)
                if !File.exist?(fullpath(long_name))
                    log(:WARNING, "File '#{@pname}' already exists in KERNEL_SOURCE_DIR")
                    log(:WARNING, "Auto-expanding name to '#{long_name}'")
                    @pname = long_name
                    fpath = fullpath
                end
            end

            confirm_opts = { yn_default: yn_default }
            while File.exist?(fpath)
                log(:ERROR, "File '#{@pname}' already exists in KERNEL_SOURCE_DIR")

                rep = confirm(confirm_opts, "set a custom filename",
                              ignore_default: true,
                              allowed_reps: ["y", "n"])
                if rep == "n"
                    raise SCPAbort.new("User aborted filename selection")
                end

                rep = "t"
                n_name = nil
                while rep != "y"
                    n_name = Readline.readline("Enter a filename (auto name was: #{@pname} ): ", true)
                    if n_name == nil
                        raise SCPAbort.new("User aborted filename selection")
                    end
                    n_name.strip!
                    rep = confirm(confirm_opts, "keep the filename '#{n_name}'",
                                  ignore_default: true,
                                  allowed_reps: ["y", "n", "A"])
                    if rep == "A"
                        raise SCPAbort.new("User aborted filename selection")
                    end
                end
                @pname = n_name
                fpath = fullpath
            end
            @name_checked = true
        end

        # Fetch CVE/bugzilla references for a patch
        #
        # @return [String, nil] The CVE and BSC references
        def cve_refs
            return @cve_refs if @cve_refs != nil

            Tempfile.create('kernel-work') do |file|
                file.puts "Git-commit: #{@commit.f_sha}"
                file.flush

                @kernel_source.run_suse_add_cves(file.path)
                file.reopen(file.path, 'r')

                file.each do |line|
                    if line =~ /References: (.*)$/
                        @cve_refs = $1
                        break
                    end
                end
            end
            @cve_refs
        end
    end
end
