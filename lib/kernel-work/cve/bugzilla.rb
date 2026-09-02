require 'net/http'
require 'uri'
require 'json'

module KernelWork
    module CveCLI
        # A lightweight, reusable client for interacting with the Bugzilla REST API
        class BugzillaClient
            attr_reader :url, :api_key

            # @param config [Hash] Client configuration (bugzilla_url, bugzilla_api_key)
            def initialize(config = {})
                @url = config[:bugzilla_url] || "https://apibugzilla.suse.com"
                @api_key = config[:bugzilla_api_key]

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
            def request(path, params = {})
                url = URI.parse("#{@url.chomp('/')}/rest/#{path}")

                query_params = params.dup
                query_params[:api_key] = @api_key if @api_key && !@api_key.empty?
                url.query = URI.encode_www_form(query_params) unless query_params.empty?

                http = Net::HTTP.new(url.host, url.port)
                http.use_ssl = true if url.scheme == 'https'

                req = Net::HTTP::Get.new(url.request_uri)
                req['Accept'] = 'application/json'

                res = http.request(req)
                if res.code == "200"
                    JSON.parse(res.body)
                else
                    raise KernelWork::BugzillaError.new(res)
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
