# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'wechat/utils/version'

Gem::Specification.new do |spec|
  spec.name          = 'wechat-utils'
  spec.version       = Wechat::Utils::VERSION
  spec.authors       = ['Oscar Jiang']
  spec.email         = ['pengj0520@gmail.com']

  spec.summary       = %q{wechat api for remote calls}
  spec.description   = %q{wechat api for remote calls}
  spec.homepage      = 'https://github.com/warmwind/wechat-utils'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '>= 2.0'
  spec.add_development_dependency 'rake', '>= 12.3.3'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'mocha', ['~> 1.1']

  spec.add_runtime_dependency 'rest-client', ['> 1.8']
end
