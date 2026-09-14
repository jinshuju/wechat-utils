require 'json'
require 'cgi'
require 'digest/sha1'
require 'securerandom'
require 'faraday'
require 'faraday/follow_redirects'
require 'faraday/net_http_persistent'
require 'wechat/utils/version'
require 'wechat/utils/idle_timeout_adapter'
require 'wechat/utils/strict_follow_redirects'


module Wechat
  module Utils
    # Defaults applied to every request. They mirror the behaviour of the
    # previous rest-client based implementation.
    DEFAULT_REQUEST_OPTS = {
      verify_ssl: false,
      timeout: 30
    }.freeze
    # rest-client followed up to 10 redirects by default; match it.
    REDIRECT_LIMIT = 10
    # get_request has no body; a distinct sentinel (rather than plain nil)
    # so post_request can still send a literal JSON null or false payload.
    NO_PAYLOAD = Object.new.freeze
    # A persistent connection is reused across calls, and Faraday only ever
    # assigns a timeout onto it when the resolved value is truthy, so a bare
    # nil would silently leave whatever timeout the previous call set. Stand
    # in a timeout long enough that it never fires in practice, so every call
    # always assigns a concrete value and none can leak into the next one.
    # Kept to one day: some layers convert this to milliseconds internally,
    # and a much larger value (e.g. 1_000_000_000) overflows there.
    NO_TIMEOUT = 86_400
    # Used unless the caller supplies any of :ssl_version / :ssl_min_version /
    # :ssl_max_version (a fixed version plus explicit bounds would conflict).
    DEFAULT_SSL_VERSION = 'TLSv1_2'.freeze
    SSL_VERSION_KEYS = %i[ssl_version ssl_min_version ssl_max_version].freeze

    # Options that only affect the request, not which connection is reused.
    REQUEST_OPTION_KEYS = %i[timeout open_timeout read_timeout write_timeout headers proxy].freeze
    # Options that decide which underlying persistent connection is used.
    SSL_OPTION_KEYS = %i[verify_ssl ssl_version ssl_min_version ssl_max_version ssl_ca_file].freeze

    # Faraday normally decodes the query string into a params hash and
    # re-encodes it (sorted) before sending. WeChat URLs are built by hand in
    # this module, so pass the query through untouched instead.
    module RawQueryEncoder
      KEY = '__raw_query__'.freeze

      def self.decode(query)
        { KEY => query }
      end

      def self.encode(params)
        params[KEY].to_s
      end
    end

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

      # Performs a GET request over a persistent (keep-alive) connection and
      # parses the JSON body. See #post_request for the supported
      # +extra_opts+ keys.
      def get_request url, extra_opts = {}
        perform_request :get, url, NO_PAYLOAD, extra_opts
      end

      # Performs a POST request with a JSON body over a persistent
      # (keep-alive) connection and parses the JSON response body.
      #
      # +payload+ is JSON-encoded unless it is already a String.
      #
      # Supported +extra_opts+ keys:
      #   :timeout, :open_timeout, :read_timeout, :write_timeout - seconds;
      #                     nil disables the timeout, as it did with rest-client
      #   :headers        - Hash of extra request headers
      #   :proxy          - proxy URL; false disables proxies, including the
      #                     http_proxy / https_proxy environment variables
      #   :verify_ssl     - false (default) / true / OpenSSL::SSL::VERIFY_*
      #   :ssl_version, :ssl_min_version, :ssl_max_version - OpenSSL names
      #   :ssl_ca_file
      def post_request url, payload, extra_opts = {}
        perform_request :post, url, payload, extra_opts
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

      # Forgets the current thread's cached connections, so its next request
      # builds fresh ones. Useful in tests; net-http-persistent itself
      # already avoids reusing a parent process's sockets after a fork.
      def reset_connections!
        connections.each_value { |conn| shutdown_persistent_manager(conn) }
        connections.clear
      end

      private

      # Faraday::Adapter#close is a no-op by default and
      # faraday-net_http_persistent doesn't override it, so closing the
      # Faraday::Connection wouldn't actually close the pooled sockets;
      # shut down the underlying Net::HTTP::Persistent manager directly
      # instead, or repeated resets (as the test suite does, once per
      # test) would leak sockets until an eventual GC.
      def shutdown_persistent_manager(conn)
        adapter = conn.app
        adapter = adapter.instance_variable_get(:@app) while adapter && !adapter.is_a?(Faraday::Adapter)
        adapter&.instance_variable_get(:@cached_connection)&.shutdown
      end

      def perform_request method, url, payload, extra_opts
        opts = DEFAULT_REQUEST_OPTS.merge(symbolize_keys(extra_opts || {}))
        unknown = opts.keys - REQUEST_OPTION_KEYS - SSL_OPTION_KEYS
        raise ArgumentError, "unsupported request options: #{unknown.map(&:inspect).join(', ')}" unless unknown.empty?

        response = connection(ssl_options(opts), opts[:proxy]).public_send(method, url) do |req|
          # A sentinel, not payload's truthiness: false/nil are valid JSON
          # bodies a caller may deliberately pass to post_request.
          unless payload.equal?(NO_PAYLOAD)
            req.headers['Content-Type'] = 'application/json'
            req.body = payload.is_a?(String) ? payload : payload.to_json
          end
          # Resolve the phase-specific timeouts here (explicit value, else
          # :timeout) so an explicit nil disables that timeout instead of
          # falling back to Faraday's `read_timeout || timeout`.
          %i[open_timeout read_timeout write_timeout].each do |key|
            value = opts.key?(key) ? opts[key] : opts[:timeout]
            req.options.send("#{key}=", value.nil? ? NO_TIMEOUT : value)
          end
          # []= normalises a URL string into Faraday::ProxyOptions; nil/false
          # overrides the proxy Faraday would otherwise pick up from the
          # http_proxy / https_proxy environment variables
          req.options[:proxy] = opts[:proxy] if opts.key?(:proxy)
          # after Content-Type, so an explicit header can still override
          # it. Values must already be strings - Net::HTTP calls #strip on
          # them - since none of this gem's fixed WeChat endpoints need a
          # Symbol/number shorthand.
          req.headers.update(opts[:headers]) if opts[:headers].is_a?(Hash)
        end
        # WeChat's JSON API always responds 200, even for a logical
        # (errcode-carrying) failure; Faraday's raise_error middleware
        # already raises on 4xx/5xx, and StrictFollowRedirects handles the
        # redirect statuses it will follow, so anything else reaching here
        # (an unfollowed redirect, or any other unexpected status) is an
        # error.
        unless response.status == 200
          raise Faraday::ClientError, status: response.status, headers: response.headers, body: response.body
        end
        JSON.parse response.body
      end

      # Thread-local: faraday-net_http_persistent caches a single
      # Net::HTTP::Persistent instance per adapter and mutates its timeouts
      # and proxy in place for every request. Two threads sharing one
      # adapter could each clobber the other's setting between "configure"
      # and "dispatch"; a connection (and its adapter) private to the
      # current thread makes that impossible, without giving up the actual
      # socket reuse, which net-http-persistent itself already pools by
      # host:port across threads.
      #
      # Thread.current[]/[]= is fiber-local, not thread-local, so it would
      # hand a fresh (unpooled) cache to every request on a fiber-based
      # server; thread_variable_get/set are the ones that stay shared
      # across fibers within the same thread.
      def connections
        Thread.current.thread_variable_get(:wechat_utils_connections) ||
          Thread.current.thread_variable_set(:wechat_utils_connections, {})
      end

      # One Faraday connection per distinct (SSL configuration, proxy) pair.
      #
      # Known gap vs. rest-client: it carried Set-Cookie values from a
      # redirect response into the redirected request via a cookie jar;
      # this doesn't. Accepted deliberately - api.weixin.qq.com is a
      # stateless JSON API that has no occasion to set a cookie a
      # redirect target would need, and matching that behavior exactly
      # would mean adding faraday-cookie_jar/http-cookie as new runtime
      # dependencies for it.
      def connection ssl, proxy
        connections[[ssl, proxy]] ||= Faraday.new(ssl: ssl, request: { params_encoder: RawQueryEncoder }) do |f|
          # rest-client used to follow GET redirects as well
          f.use StrictFollowRedirects, limit: REDIRECT_LIMIT
          f.response :raise_error
          f.adapter IdleTimeoutAdapter
        end
      end

      def ssl_options opts
        ssl = { verify: verify_ssl?(opts[:verify_ssl]) }
        ssl[:version] = DEFAULT_SSL_VERSION if (opts.keys & SSL_VERSION_KEYS).empty?
        ssl[:version] = opts[:ssl_version] if opts[:ssl_version]
        ssl[:min_version] = opts[:ssl_min_version] if opts[:ssl_min_version]
        ssl[:max_version] = opts[:ssl_max_version] if opts[:ssl_max_version]
        # net-http-persistent forces verify_mode back to VERIFY_PEER
        # whenever ca_file is set, regardless of :verify, so only pass it
        # through when the caller actually wants verification.
        ssl[:ca_file] = opts[:ssl_ca_file] if opts[:ssl_ca_file] && ssl[:verify]
        ssl
      end

      # Accepts the boolean form as well as rest-client's OpenSSL constants.
      def verify_ssl? value
        return false if value == false || value.nil?
        return value != OpenSSL::SSL::VERIFY_NONE if value.is_a?(Integer)
        true
      end

      def symbolize_keys hash
        hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end

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
