require 'rest-client'
require 'wechat/utils/version'

module Wechat
  module Utils
    def self.create_oauth_url_for_code app_id, redirect_url, more_info = false, state=nil
      common_parts = {
        appid: app_id,
        response_type: 'code',
        scope: more_info ? 'snsapi_userinfo' : 'snsapi_base',
        state: state
      }
      "https://open.weixin.qq.com/connect/oauth2/authorize?#{hash_to_query common_parts }&#{CGI::escape redirect_url}#wechat_redirect"
    end

    def self.create_oauth_url_for_openid(app_id, app_secret, code)
      query_parts = {
        appid: app_id,
        secret: app_secret,
        code: code,
        grant_type: 'authorization_code'
      }
      "https://api.weixin.qq.com/sns/oauth2/access_token?#{hash_to_query query_parts}"
    end

    def self.get_request(url)
      request_opts = {
        :url => url,
        :verify_ssl => false,
        :ssl_version => 'TLSv1',
        :method => 'GET',
        :headers => false,
        :open_timeout => 30,
        :timeout => 30
      }
      JSON.parse RestClient::Request.execute(request_opts).body
    end

    private

    def self.hash_to_query hash
      hash.map { |k, v| "#{k}=#{v}" }.join('&')
    end
  end
end
