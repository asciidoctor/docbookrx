require 'stringio'

module RSpec::Support::Helpers
  def capture_stdio
    old_stdout, $stdout = $stdout, StringIO.new
    old_stderr, $stderr = $stderr, StringIO.new
    yield $stdout, $stderr
  ensure
    $stdout, $stderr = old_stdout, old_stderr
  end
end

RSpec.configure do |config|
  config.include RSpec::Support::Helpers
end
