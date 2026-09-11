$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'wechat/utils'

require 'minitest/autorun'
require 'mocha/minitest'
require 'webmock/minitest'

WebMock.disable_net_connect!(allow_localhost: true)
