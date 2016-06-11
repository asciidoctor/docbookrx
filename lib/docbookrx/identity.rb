module Docbookrx
  module Identity
    def self.name
      'docbookrx'
    end

    def self.label
      'DocBook Rx'
    end

    def self.version
      '1.0.0.dev'
    end

    def self.version_label
      %(#{label} #{version})
    end
  end
end
