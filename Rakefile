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
end

task :default => [:check_whitespace, :test, :yard]
