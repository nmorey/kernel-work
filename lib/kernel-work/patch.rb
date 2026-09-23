require 'tempfile'
module KernelWork
    # Represents a kernel-source Patch commit
    class Patch < Common
        # Patch References
        attr_reader :ref
        # Generate a unique patch name, prompting the user if a conflict exists.
        #
        # @param suse [Suse] Suse repo
        # @param opts [Hash] Options including potential custom filename
        # @param commit [Commit] The commit to generate a name for
        # @return New Patch object
        # @raise [TargetFileExistsError] If target file exists and filename is provided via opts
        # @raise [SCPAbort] If user aborts conflict resolution
        def initialize(suse,
                       opts, commit)
            @suse = suse
            @commit = commit
            @pname= @commit.patchname().gsub(/^0001-/,"")
            # Default name might be overriden from CLI
            @pname = opts[:filename] if opts[:filename] != nil
            @name_checked = false
            @ref = opts[:ref]
            @cve_refs=nil
        end

        # Generate a patch from the Linux tree and fill in custom headers (Git-commit, Patch-mainline, etc.)
        # into kernel source
        #
        # @param opts [Hash] Options hash
        # @return [void]
        def generate(opts)
            name_check(opts)

            i = File.open(@commit.path + "/" + @commit.patchname,"r")
            o = File.open(fullpath() , "w+")
            p_split=0
            in_subj=false
            i.each(){|l|
                case l
                when /^Subject: \[PATCH/
                    in_subj=true
                    o.puts l
                when /^\n$/
                    if in_subj == true
                        o.puts "Git-commit: #{@commit.f_sha()}" if @commit.f_sha() != ""
                        o.puts "Patch-mainline: #{@commit.orig_tag()}" if @commit.orig_tag() != nil
                        o.puts "References: #{@ref}"
                        o.puts "Git-repo: #{@commit.git_repo()}" if @commit.git_repo() != nil
                        in_subj=false
                    end
                    o.puts l
                when /^---\n$/
                    if p_split == 0 then
                        name=@suse.runGit("config --get user.name")
                        email=@suse.runGit("config --get user.email")
                        o.puts "Acked-by: #{name} <#{email}>"
                        p_split = 1
                    end
                    o.puts l
                else
                    o.puts l
                end
            }
            i.close()
            o.close()
            File.delete(i)
        end

        # Get the full/absolute path to this patch
        #
        # @param pname [String] Optional argument to compute path for a given filename
        # @return [String] Absolute path
        def fullpath(pname=nil)
            return @suse.path + "/" + localpath(pname)
        end

        # Get the local path to this patch in kernel-source
        #
        # @param pname [String] Optional argument to compute path for a given filename
        # @return [String] Local path
        def localpath(pname=nil)
            pname = @pname if pname == nil
            return @suse.get_patch_dir() + "/" + pname
        end

        # Automatically extract CVE and BSC references for a patch using suse-add-cves
        #
        # @param opts [Hash] Options hash
        # @return [void]
        def update_ref_with_cve(opts)
            refs = cve_refs()
            if refs.to_s() == "" then
                log(:WARNING, "No CVE reference found")
                refs = @suse.default_patch_references(opts)
            end
            # Mark refs as the cve_refs or fallback refs and update the patchfile
            @ref = refs
            @suse.run("sed -i -e 's/^References: $/References: #{@ref}/' #{fullpath()}")

        end

        private
        # Check name availability to generate a patch
        # Looks into the patch dir of kernel source and make sure names will not clash.
        # In case of a clash, tries to find a solution or prompts user for a custom name
        #
        # Does not return anything but sets a new @pname that will not conflict
        # @param opts [Hash] Options hash
        def name_check(opts)
            return if @name_checked == true
            fpath=fullpath()

            if File.exist?(fpath)
                # If user specified a file name and it already exists, we cannot solve this
                # Raise an error
                raise TargetFileExistsError.new(@pname) if opts[:filename] != nil

                # Tries with a longer filename. Most of the time, it should solve the issue
                long_name = @commit.patchname(92)
                if !File.exist?(fullpath(long_name)) then
                    log(:WARNING, "File '#{@pname}' already exists in KERNEL_SOURCE_DIR")
                    log(:WARNING, "Auto-expanding name to '#{long_name}'")
                    @pname = long_name
                    fpath = fullpath()
                end
            end

            while File.exist?(fpath) do
                log(:ERROR, "File '#{@pname}' already exists in KERNEL_SOURCE_DIR")

                # If user has not specified a name, try to prompt him for one
                rep= confirm(opts, "set a custom filename",
                             ignore_default: true,
                             allowed_reps: ["y", "n"])
                if rep == "n" then
                    raise SCPAbort.new("User aborted filename selection")
                end

                rep="t"
                nName=nil
                while rep != "y"
                    nName = Readline.readline("Enter a filename (auto name was: #{@pname} ): ", true)
                    if nName == nil
                        raise SCPAbort.new("User aborted filename selection")
                    end
                    nName.strip!
                    rep = confirm(opts, "keep the filename '#{nName}'",
                                  ignore_default: true,
                                  allowed_reps: ["y", "n", "A" ])
                    if rep == "A" then
                        raise SCPAbort.new("User aborted filename selection")
                    end
                end
                @pname = nName
                fpath=fullpath()
            end
            @name_checked = true
        end

        # Fetch CVE/bugzilla references for a patch
        #
        # Does not need the patch to be actually generated
        def cve_refs()
            return @cve_refs if @cve_refs != nil
            Tempfile.create('kernel-work') do |file|
                file.puts "Git-commit: #{@commit.f_sha}"
                file.flush

                @suse.runSystem("suse-add-cves  -v $VULNS_GIT  #{file.path}")
                file.reopen(file.path, 'r')

                file.each() do |line|
                    if line =~ /References: (.*)$/
                        @cve_refs = $1
                        break
                    end
                end
            end
            return @cve_refs
        end
    end
end
