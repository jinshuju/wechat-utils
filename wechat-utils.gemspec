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
  spec.required_ruby_version = '>= 3.3.1'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '>= 2.0'
  spec.add_development_dependency 'rake', '>= 12.3.3'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'mocha', ['>= 2.1']
  spec.add_development_dependency 'webmock'

  spec.add_runtime_dependency 'faraday', ['~> 1.10']
  spec.add_runtime_dependency 'faraday-follow_redirects', ['~> 0.3']
  spec.add_runtime_dependency 'faraday-net_http_persistent', ['~> 1.2']
  spec.add_runtime_dependency 'net-http-persistent', ['~> 4.0']
  # net-http-persistent only requires connection_pool >= 2.2.4, which
  # predates connection_pool's own automatic post-fork connection
  # invalidation (confirmed present in 2.5.5, absent in 2.5.0 and
  # earlier). Without it, a preloading app that forks workers after an
  # initial request could have a child reuse the parent's inherited
  # socket.
  spec.add_runtime_dependency 'connection_pool', ['>= 2.5.5']
  # Faraday::Request::BasicAuthentication (used for URL-embedded
  # credentials) requires 'base64'. It's a default gem bundled with the
  # interpreter through Ruby 3.3 but not from 3.4 on, and neither this
  # gem nor faraday 1.10 declares it, so an authenticated URL could raise
  # LoadError on 3.4+ unless the app happens to have base64 in its own
  # bundle already.
  spec.add_runtime_dependency 'base64'
end
