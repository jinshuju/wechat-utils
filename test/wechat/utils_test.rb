require 'test_helper'

class Wechat::UtilsTest < Minitest::Test
  def test_that_it_has_a_version_number
    assert_equal '0.1.0', ::Wechat::Utils::VERSION
  end

  def test_it_should_return_snsapi_base_oauth_url_for_code
    actual = Wechat::Utils.create_oauth_url_for_code 'your_appid', 'http://yourhost.com', false, 'custom_state'
    expected =  'https://open.weixin.qq.com/connect/oauth2/authorize?appid=your_appid&response_type=code&scope=snsapi_base&state=custom_state&http%3A%2F%2Fyourhost.com#wechat_redirect'
    assert_equal expected, actual
  end

  def test_it_should_return_snsapi_info_oauth_url_for_code
    actual = Wechat::Utils.create_oauth_url_for_code 'your_appid', 'http://yourhost.com', true, 'custom_state'
    expected =  'https://open.weixin.qq.com/connect/oauth2/authorize?appid=your_appid&response_type=code&scope=snsapi_userinfo&state=custom_state&http%3A%2F%2Fyourhost.com#wechat_redirect'
    assert_equal expected, actual
  end

  def test_it_should_return_url_for_fetching_openid
    actual = Wechat::Utils.create_oauth_url_for_openid 'your_appid', 'app_secret', 'callback_code'
    expected = 'https://api.weixin.qq.com/sns/oauth2/access_token?appid=your_appid&secret=app_secret&code=callback_code&grant_type=authorization_code'
    assert_equal expected, actual
  end

  def test_it_should_send_request_and_parse_to_json
    request_opts = {
      :url => 'url',
      :verify_ssl => false,
      :ssl_version => 'TLSv1',
      :method => 'GET',
      :headers => false,
      :open_timeout => 30,
      :timeout => 30
    }
    response_body = "{\"access_token\":\"token\",\"openid\":\"weixin_openid\"}"
    response = mock('response')
    ::RestClient::Request.expects(:execute).with(request_opts).returns response
    response.stubs(:body).returns response_body
    assert_equal({'access_token' => 'token', 'openid' => 'weixin_openid'}, Wechat::Utils.get_request('url'))
  end

  def test_it_should_return_openid_and_nil_error
    Wechat::Utils.expects(:create_oauth_url_for_openid).with('your_appid', 'app_secret', 'callback_code').returns 'url'
    Wechat::Utils.expects(:get_request).with('url').returns({'access_token' => 'token', 'openid' => 'weixin_openid'})
    assert_equal(['weixin_openid', nil], Wechat::Utils.fetch_openid('your_appid', 'app_secret', 'callback_code'))
  end

  def test_it_should_return_nil_openid_and_all_the_reponse_when_openid_is_nil
    Wechat::Utils.expects(:create_oauth_url_for_openid).with('your_appid', 'app_secret', 'callback_code').returns 'url'
    Wechat::Utils.expects(:get_request).with('url').returns({error: 'some error'})
    assert_equal([nil, {error: 'some error'}], Wechat::Utils.fetch_openid('your_appid', 'app_secret', 'callback_code'))
  end
end
