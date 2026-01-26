require 'yard'

YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb']
  t.options = ['--title', 'Kernel Work Documentation', '--protected', '--private']
end

task :default => :yard
