require 'json'
require 'yaml'
require 'fileutils'
require 'net/http'
require 'uri'

module KernelWork
    # Module exposing CVE commands nested under 'cve'
    module CveCLI
        # Base CVE Tracker interface
        class CveTracker
            # Factory method to create a CVE tracker based on config.
            # @param config [Hash] Configuration options including :tracker_type.
            # @param logger [Object, nil] Optional logger instance.
            # @return [CveTracker] Instance of a tracker subclass.
            # @raise [RuntimeError] If tracker type is unknown.
            def self.create(config, logger = nil)
                type = config[:tracker_type] || "local"
                case type.to_s.downcase
                when "local"
                    CveLocalTracker.new(config, logger)
                when "rest"
                    CveRestTracker.new(config, logger)
                else
                    raise "Unknown CVE tracker type: #{type}"
                end
            end

            def read_all
                raise NotImplementedError
            end

            def read_bug(bug_id)
                raise NotImplementedError
            end

            def write_bug(bug_id, data)
                raise NotImplementedError
            end

            def delete_all
                raise NotImplementedError
            end

            def delete_bug(bug_id)
                raise NotImplementedError
            end
        end

        # Local CVE Tracker that stores bug info in JSON files.
        class CveLocalTracker < CveTracker
            attr_reader :repo_path, :cves_path

            def initialize(config, logger = nil)
                @repo_path = config[:data_repo]
                if @repo_path.nil? || @repo_path.empty?
                    @repo_path = "~/workspace/cve-data"
                end
                @repo_path = File.expand_path(@repo_path)
                @cves_path = File.join(@repo_path, "cves")
                @logger = logger
            end

            # Ensure the directory for storing CVE JSON files exists.
            # @return [void]
            def ensure_dir
                FileUtils.mkdir_p(@cves_path) unless File.directory?(@cves_path)
            end

            # Read all CVE bugs stored in the local repository.
            # @return [Array<CVE>] All CVE instances.
            # @raise [CorruptedJSONError] If any file contains corrupted JSON.
            def read_all
                ensure_dir
                cves = []
                Dir.glob(File.join(@cves_path, "*.json")).each do |file_path|
                    begin
                        content = File.read(file_path)
                        data = JSON.parse(content, symbolize_names: true)
                        cves << CVE.from_h(self, data)
                    rescue => e
                        raise CorruptedJSONError.new()
                    end
                end
                cves
            end

            def read_bug(bug_id)
                ensure_dir
                file_path = File.join(@cves_path, "#{bug_id}.json")
                raise BugNotFoundError.new() if ! File.exist?(file_path)
                begin
                    data = JSON.parse(File.read(file_path), symbolize_names: true)
                    CVE.from_h(self, data)
                rescue => e
                    raise CorruptedJSONError.new()
                end
            end

            # Write bug tracking data to local repository file.
            # @param bug_id [String] The Bugzilla bug ID.
            # @param data [CVE, Hash] The CVE instance or raw data hash.
            # @return [void]
            def write_bug(bug_id, data)
                ensure_dir
                file_path = File.join(@cves_path, "#{bug_id}.json")
                cve_hash = data.is_a?(CVE) ? data.to_h : data
                File.write(file_path, JSON.pretty_generate(cve_hash))
            end

            # Delete all CVE files and directory from local repository.
            # @return [void]
            def delete_all
                if File.directory?(@cves_path)
                    FileUtils.rm_rf(@cves_path)
                end
                ensure_dir
            end

            # Delete a specific bug's local file.
            # @param bug_id [String] The Bugzilla bug ID.
            # @return [void]
            def delete_bug(bug_id)
                ensure_dir
                file_path = File.join(@cves_path, "#{bug_id}.json")
                if File.exist?(file_path)
                    File.delete(file_path)
                end
            end
        end

        # REST CVE Tracker that synchronizes CVE bugs with a remote HTTP API server.
        class CveRestTracker < CveTracker
            def initialize(config, logger = nil)
                @url = config[:tracker_url]
                @logger = logger
                if @url.nil? || @url.empty?
                    raise RestURLNotSetError.new()
                end

                @url = @url.chomp('/')
            end

            # Read all CVE bugs from the REST API.
            # @return [Array<CVE>] All CVE instances.
            # @raise [RestError] If the HTTP request fails.
            def read_all
                begin
                    uri = URI("#{@url}/cves")
                    response = Net::HTTP.get_response(uri)
                    if response.is_a?(Net::HTTPSuccess)
                        data = JSON.parse(response.body, symbolize_names: true)
                        data.is_a?(Array) ? data.map { |h| CVE.from_h(self, h) } : []
                    else
                        raise RestError.new("read_all", response)
                    end
                rescue => e
                    raise RestError.new("read_all", response)
                end
            end

            # Read a specific CVE bug from the REST API.
            # @param bug_id [String] The Bugzilla bug ID.
            # @return [CVE] The parsed CVE object.
            # @raise [BugNotFoundError] If the API server returns a 404.
            # @raise [RestError] If any other HTTP error occurs.
            def read_bug(bug_id)
                begin
                    uri = URI("#{@url}/cves/#{bug_id}")
                    response = Net::HTTP.get_response(uri)
                    if response.is_a?(Net::HTTPSuccess)
                        data = JSON.parse(response.body, symbolize_names: true)
                        CVE.from_h(self, data)
                    elsif response.code == "404"
                        raise BugNotFoundError.new()
                    else
                        raise RestError.new("read_bug(#{bug_id})", response)
                    end
                rescue BugNotFoundError => e
                    raise e
                rescue => e
                    raise RestError.new("read_bug(#{bug_id})", response)
                end
            end

            # Write or update CVE bug tracking data via the REST API.
            # @param bug_id [String] The Bugzilla bug ID.
            # @param data [CVE, Hash] The CVE instance or raw data hash.
            # @return [void]
            # @raise [RestError] If the REST write request fails.
            def write_bug(bug_id, data)
                begin
                    uri = URI("#{@url}/cves/#{bug_id}")
                    http = Net::HTTP.new(uri.host, uri.port)
                    if uri.scheme == 'https'
                        http.use_ssl = true
                    end
                    request = Net::HTTP::Put.new(uri.path, { 'Content-Type' => 'application/json' })
                    cve_hash = data.is_a?(CVE) ? data.to_h : data
                    request.body = JSON.pretty_generate(cve_hash)
                    response = http.request(request)
                    unless response.is_a?(Net::HTTPSuccess)
                        raise RestError.new("write_bug(#{bug_id})", response)
                    end
                rescue => e
                    raise RestError.new("write_bug(#{bug_id})", response)
                end
            end

            # Delete all CVE data from the REST server database.
            # @return [void]
            # @raise [RestError] If the delete request fails.
            def delete_all
                begin
                    uri = URI("#{@url}/cves")
                    http = Net::HTTP.new(uri.host, uri.port)
                    if uri.scheme == 'https'
                        http.use_ssl = true
                    end
                    request = Net::HTTP::Delete.new(uri.path)
                    response = http.request(request)
                    unless response.is_a?(Net::HTTPSuccess)
                        raise RestError.new("delete_all})", response)
                    end
                rescue => e
                    raise RestError.new("delete_all})", response)
                end
            end

            # Delete a specific CVE bug from the REST server database.
            # @param bug_id [String] The Bugzilla bug ID.
            # @return [void]
            # @raise [RestError] If the delete request fails.
            def delete_bug(bug_id)
                begin
                    uri = URI("#{@url}/cves/#{bug_id}")
                    http = Net::HTTP.new(uri.host, uri.port)
                    if uri.scheme == 'https'
                        http.use_ssl = true
                    end
                    request = Net::HTTP::Delete.new(uri.path)
                    response = http.request(request)
                    unless response.is_a?(Net::HTTPSuccess)
                        raise RestError.new("delete_bug(#{bug_id})", response)
                    end
                rescue => e
                    raise RestError.new("delete_bug(#{bug_id})", response)
                end
            end
        end
    end
end
