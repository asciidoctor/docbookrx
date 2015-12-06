# -*- encoding: utf-8 -*-
require File.expand_path '../lib/docbookrx/identity', __FILE__

Gem::Specification.new do |s|
  s.name = Docbookrx::Identity.name
  s.version = Docbookrx::Identity.version
  s.authors = ['Dan Allen']
  s.email = ['dan.j.allen@gmail.com']
  s.homepage = 'https://github.com/opendevise/docbookrx'
  s.summary = 'A DocBook to AsciiDoc converter'
  s.description = 'The prescription you need to get rid of your DocBook problem. Converts DocBook XML to AsciiDoc.'
  s.license = 'MIT'

  s.add_runtime_dependency 'nokogiri', '~> 1.6.7'
  s.add_development_dependency 'rake', '~> 10.4.0'
  s.add_development_dependency 'rspec', '~> 3.4.0'

  s.files = Dir['lib/*', 'lib/*/**']
  s.executables = ['docbookrx']
  s.extra_rdoc_files = Dir['README.doc', 'LICENSE']
  s.require_paths = ['lib']
end
