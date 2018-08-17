require 'json'
require 'rest-client'
require 'wechat/utils/version'
require 'securerandom'


module Wechat
  module Utils
    class << self
      def create_oauth_url_for_code app_id, redirect_url, more_info = false, state=nil
        common_parts = {
          appid: app_id,
          redirect_uri: CGI::escape(redirect_url),
          response_type: 'code',
          scope: more_info ? 'snsapi_userinfo' : 'snsapi_base',
          state: state
        }
        "https://open.weixin.qq.com/connect/oauth2/authorize?#{hash_to_query common_parts}#wechat_redirect"
      end

      def create_oauth_url_for_openid app_id, app_secret, code
        query_parts = {
          appid: app_id,
          secret: app_secret,
          code: code,
          grant_type: 'authorization_code'
        }
        "https://api.weixin.qq.com/sns/oauth2/access_token?#{hash_to_query query_parts}"
      end

      def fetch_openid_and_access_token app_id, app_secret, code, request_opts: {}
        url = create_oauth_url_for_openid app_id, app_secret, code
        response = get_request url, request_opts
        return response['openid'], response['access_token'], response
      end

      # access_token is get from oauth
      def fetch_oauth_user_info access_token, openid, request_opts: {}
        get_request "https://api.weixin.qq.com/sns/userinfo?access_token=#{access_token}&openid=#{openid}&lang=zh_CN", request_opts
      end

      # access_token is the global token
      def fetch_user_info access_token, openid, request_opts: {}
        get_request "https://api.weixin.qq.com/cgi-bin/user/info?access_token=#{access_token}&openid=#{openid}&lang=zh_CN", request_opts
      end

      def get_request url, extra_opts
        request_opts = {
          :url => url,
          :verify_ssl => false,
          :ssl_version => 'TLSv1',
          :method => 'GET',
          :headers => false,
          :timeout => 30
        }.merge(extra_opts)
        JSON.parse RestClient::Request.execute(request_opts).body
      end

      def fetch_jsapi_ticket access_token, request_opts: {}
        response = get_request "https://api.weixin.qq.com/cgi-bin/ticket/getticket?access_token=#{access_token}&type=jsapi", request_opts
        return response['ticket'], response
      end

      def fetch_global_access_token appid, secret, request_opts: {}
        response = get_request "https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=#{appid}&secret=#{secret}", request_opts
        return response['access_token'], response
      end

      def jsapi_params appid, url, jsapi_ticket
        timestamp = Time.now.to_i
        noncestr = SecureRandom.urlsafe_base64(12)
        signature = sign_params timestamp: timestamp, noncestr: noncestr, jsapi_ticket: jsapi_ticket, url: url
        {
          appid: appid,
          timestamp: timestamp,
          noncestr: noncestr,
          signature: signature,
          url: url
        }
      end

      private

      def hash_to_query hash
        hash.map { |k, v| "#{k}=#{v}" }.join('&')
      end

      def sign_params options
        to_be_singed_string = options.sort.map { |key, value| "#{key}=#{value}" }.join("&")
        Digest::SHA1.hexdigest to_be_singed_string
      end
    end
  end
end
