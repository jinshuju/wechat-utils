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
```


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/warmwind/wechat-utils. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

