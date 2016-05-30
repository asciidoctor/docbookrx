ENV['NOKOGIRI_USE_SYSTEM_LIBRARIES'] = "1"
Dir.glob('tasks/*.rake').each { |file| load file }

task default: %w(spec)
