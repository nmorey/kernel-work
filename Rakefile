require 'yard'

YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb']
  t.options = ['--title', 'Kernel Work Documentation', '--protected', '--private']
end

task :check_whitespace do
  puts "Checking for trailing whitespace..."
  files = Dir.glob('lib/**/*.rb') + Dir.glob('bin/*') + ['Rakefile']
  errors = []
  files.each do |file|
    next if File.directory?(file)
    lines = File.readlines(file)
    lines.each_with_index do |line, index|
      if line =~ /[ \t]+$/
        errors << "#{file}:#{index + 1}: trailing whitespace found"
      end
    end
  end

  if errors.any?
    puts errors.join("\n")
    exit 1
  else
    puts "No trailing whitespace found."
  end
end

task :test do
  puts "Running tests..."
  sh "ruby test/test_gen_backport_list.rb"
  sh "ruby test/test_cve.rb"
end

task :test_docker do
  puts "Testing Docker containerization..."
  temp_dir = "/tmp/cve-docker-test-data"
  container_name = "cve-api-test-run"
  port = 4567

  begin
    # 1. Clean up any previous test remnants
    sh "docker rm -f #{container_name} >/dev/null 2>&1 || true"
    sh "rm -rf #{temp_dir}"
    sh "mkdir -p #{temp_dir}"

    # 2. Build image
    puts "Building Docker image..."
    sh "docker build -q -t cve-api-server-test ."

    # 3. Start container
    puts "Running Docker container..."
    sh "docker run -d -p #{port}:4567 -v #{temp_dir}:/data --name #{container_name} cve-api-server-test"

    # Give the container a brief moment to boot up
    puts "Waiting for server to start..."
    sleep 2

    # 4. Perform live request test using curl
    puts "Sending PUT request to create a CVE..."
    sh "curl -s -f -X PUT -H 'Content-Type: application/json' -d '{\"bug_id\":\"999\",\"cve\":\"CVE-2026-999\",\"branches\":{\"SLE15\":\"ToDo\"}}' http://127.0.0.1:#{port}/cves/999"

    puts "Sending GET request to verify written CVE..."
    res = `curl -s -f http://127.0.0.1:#{port}/cves`
    unless res.include?("CVE-2026-999")
      raise "Docker verification failed: Written CVE was not found in GET response! Response: #{res}"
    end

    # 5. Verify file written to host volume mount
    host_file = File.join(temp_dir, "cves", "999.json")
    unless File.exist?(host_file)
      raise "Docker verification failed: File was not created in volume mount on the host: #{host_file}"
    end

    puts "Docker integration verification PASSED!"

  ensure
    # 6. Clean up
    puts "Cleaning up Docker container..."
    # Clear files from within the container first to avoid root-ownership permission errors on host
    `docker exec #{container_name} rm -rf /data/cves` rescue nil
    sh "docker rm -f #{container_name} >/dev/null 2>&1 || true"
    sh "rm -rf #{temp_dir}"
  end
end
task :default => [:check_whitespace, :test, :yard]
