require 'net/http'
require 'uri'
require 'json'

module KernelWork
    module CveCLI
        # A lightweight, reusable client for interacting with the Bugzilla REST API
        class BugzillaClient
            # Default timeout for Bugzilla requests in seconds.
            DEFAULT_TIMEOUT = 15

            attr_reader :url, :api_key
            attr_accessor :timeout

            # @param config [Hash] Client configuration (bugzilla_url, bugzilla_api_key, bugzilla_timeout)
            def initialize(config = {})
                @url = config[:bugzilla_url] || "https://apibugzilla.suse.com"
                @api_key = config[:bugzilla_api_key]
                @timeout = (config[:bugzilla_timeout] || config[:timeout] || DEFAULT_TIMEOUT).to_i

                # Fallback to .bugzillarc credentials if API key is not explicitly provided
                if @api_key.nil? || @api_key.empty?
                    bz_config = self.class.read_bugzillarc["apibugzilla.suse.com"] || {}
                    @api_key = bz_config["api_key"]
                end
            end

            # Request wrapper to execute GET requests to the Bugzilla REST API
            # @param path [String] Request sub-path (e.g., "bug" or "bug/12345/comment")
            # @param params [Hash] Additional query parameters
            # @return [Hash] Parsed JSON response body
            # @raise [BugzillaTimeoutError] If the request times out
            # @raise [BugzillaError] If the request or connection fails
            def request(path, params = {})
                url = URI.parse("#{@url.chomp('/')}/rest/#{path}")

                query_params = params.dup
                query_params[:api_key] = @api_key if @api_key && !@api_key.empty?
                url.query = URI.encode_www_form(query_params) unless query_params.empty?

                http = Net::HTTP.new(url.host, url.port)
                http.use_ssl = true if url.scheme == 'https'
                http.open_timeout = @timeout
                http.read_timeout = @timeout

                req = Net::HTTP::Get.new(url.request_uri)
                req['Accept'] = 'application/json'

                begin
                    res = http.request(req)
                rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
                    raise BugzillaTimeoutError.new(@timeout)
                rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
                    raise BugzillaError.new("Bugzilla connection failed: #{e.message}")
                end

                if res.code == "200"
                    JSON.parse(res.body)
                else
                    raise BugzillaError.new(res)
                end
            end

            # Parse ~/.bugzillarc to find Bugzilla credentials
            # @return [Hash] Config options hash
            def self.read_bugzillarc
                path = File.expand_path("~/.bugzillarc")
                return {} unless File.exist?(path)

                config = {}
                current_section = nil

                File.foreach(path) do |line|
                    line = line.strip
                    next if line.empty? || line.start_with?("#", ";")

                    if line =~ /^\[(.*)\]$/
                        current_section = $1
                        config[current_section] = {}
                    elsif line =~ /^([^=]+)=(.*)$/ && current_section
                        key = $1.strip
                        val = $2.strip
                        val = val[1..-2] if val.start_with?('"') && val.end_with?('"')
                        val = val[1..-2] if val.start_with?("'") && val.end_with?("'")
                        config[current_section][key] = val
                    end
                end
                config
            end
        end
    end
end
