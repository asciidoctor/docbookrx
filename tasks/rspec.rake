begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.rspec_opts = ['-w', '-c']
  end
rescue LoadError => e
  warn e.message
end
