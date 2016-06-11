# -*- encoding: utf-8 -*-
require File.expand_path '../lib/docbookrx/identity', __FILE__

Gem::Specification.new do |s|
  s.name = Docbookrx::Identity.name
  s.version = Docbookrx::Identity.version
  s.authors = ['Dan Allen']
  s.email = ['dan.j.allen@gmail.com']
  s.homepage = 'https://github.com/asciidoctor/docbookrx'
  s.summary = 'A DocBook to AsciiDoc converter'
  s.description = 'The prescription for all your DocBook pain. Converts DocBook XML to AsciiDoc.'
  s.license = 'MIT'

  files = begin
    IO.popen('git ls-files -z') {|io| io.read }.split "\0"
  rescue
    Dir['**/*']
  end
  s.files = files.grep(/^(?:(?:bin|lib|tasks|spec)\/.+|Rakefile|LICENSE|(?:README|WORKLOG)\.adoc)$/)
  s.executables = ['docbookrx']
  s.test_files = s.files.grep(/^spec\//)
  s.extra_rdoc_files = Dir['README.adoc', 'LICENSE']
  s.require_paths = ['lib']

  s.add_runtime_dependency 'nokogiri', '~> 1.6.7'
  s.add_development_dependency 'rake', '~> 10.4.0'
  s.add_development_dependency 'rspec', '~> 3.4.0'
end
