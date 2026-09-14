# Wechat::Utils

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/wechat/utils`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'wechat-utils'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install wechat-utils

## Usage

```ruby
# get snsapi_base code url
Wechat::Utils.create_oauth_url_for_code 'your_appid', 'http://yourhost.com', false, 'custom_state'

# get snsapi_info code url
Wechat::Utils.create_oauth_url_for_code 'your_appid', 'http://yourhost.com', true, 'custom_state'

# get openid id url
Wechat::Utils.create_oauth_url_for_openid 'your_appid', 'app_secret', 'code'

# fetch openid
Wechat::Utils.fetch_openid 'your_appid', 'app_secret', 'callback_code'

# fetch_user_info
Wechat::Utils.fetch_user_info 'your_access_token', 'your_openid'

# fetch_jsapi_ticket
Wechat::Utils.fetch_jsapi_ticket 'your_access_token'

# jsapi_params
Wechat::Utils.jsapi_params 'your_appid', 'url', 'jsapi_ticket'

# get_request / post_request - used internally by the helpers above, and
# available directly for any other WeChat endpoint. Requests reuse a
# pooled keep-alive connection per (thread, SSL config, proxy).
Wechat::Utils.get_request 'https://api.weixin.qq.com/cgi-bin/...'
Wechat::Utils.post_request 'https://api.weixin.qq.com/cgi-bin/...', {action_name: 'QR_STR_SCENE'}

# Supported extra_opts keys for both:
#   :timeout, :open_timeout, :read_timeout, :write_timeout - seconds; nil disables the timeout
#   :headers      - Hash of extra request headers (string values)
#   :proxy        - proxy URL; false disables proxies, including the http_proxy / https_proxy env vars
#   :verify_ssl   - false (default) / true / OpenSSL::SSL::VERIFY_*
#   :ssl_version, :ssl_min_version, :ssl_max_version - OpenSSL names
#   :ssl_ca_file
# Any other key raises ArgumentError.
```

## Breaking changes from 0.2.x

0.3.0 replaces `rest-client` with Faraday + `faraday-net_http_persistent`
(pooled, keep-alive connections). This changes behavior visible to callers:

- **Error classes.** Failures now raise `Faraday::*` (`Faraday::ClientError`,
  `Faraday::ServerError`, `Faraday::TimeoutError`, `Faraday::SSLError`,
  `Faraday::ConnectionFailed`), not `RestClient::*`. Update any `rescue`
  clauses.
- **Semian.** [Semian's `semian/net_http`](https://github.com/Shopify/semian)
  patch still instruments the underlying `Net::HTTP`, so a circuit breaker
  wrapped around these calls keeps working - but `Net::CircuitOpenError`
  (a `Net::ProtocolError` subclass) is now rescued and re-raised wrapped as
  `Faraday::ConnectionFailed` by Faraday's adapter. Code that used to
  `rescue Net::CircuitOpenError` directly should instead do:
  ```ruby
  rescue Faraday::ConnectionFailed => e
    raise unless e.wrapped_exception.is_a?(Net::CircuitOpenError)
    # circuit is open
  end
  ```
- **Unknown request options now raise.** Passing an unsupported key in
  `request_opts` (e.g. `:method`) raises `ArgumentError` instead of being
  silently ignored or misused.
- **Ruby >= 3.2 required** (was >= 2.6).
- `rest-client` is no longer a dependency.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/warmwind/wechat-utils. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

