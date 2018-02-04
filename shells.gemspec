# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'shells/version'

Gem::Specification.new do |spec|
  spec.name          = 'shells'
  spec.version       = Shells::VERSION
  spec.authors       = ['Beau Barker']
  spec.email         = ['beau@barkerest.com']

  spec.summary       = 'A set of simple shells for interacting with other devices.'
  spec.homepage      = 'https://github.com/barkerest/shells'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency             'net-ssh',      '~> 4.1.0'
  spec.add_dependency             'rubyserial',   '~> 0.4.0'

  spec.add_development_dependency 'bundler',      '~> 1.14'
  spec.add_development_dependency 'rake',         '~> 10.0'
  spec.add_development_dependency 'minitest',     '~> 5.0'
  spec.add_development_dependency 'minitest-reporters'
  spec.add_development_dependency 'rb-readline'
  spec.add_development_dependency 'pry'
end

