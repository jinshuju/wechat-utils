require 'test_helper'

class Wechat::UtilsTest < Minitest::Test
  def test_that_it_has_a_version_number
    assert_equal '0.2.0', ::Wechat::Utils::VERSION
  end

  def test_it_should_return_snsapi_base_oauth_url_for_code
    actual = Wechat::Utils.create_oauth_url_for_code 'your_appid', 'http://yourhost.com', false, 'custom_state'
    expected = 'https://open.weixin.qq.com/connect/oauth2/authorize?appid=your_appid&redirect_uri=http%3A%2F%2Fyourhost.com&response_type=code&scope=snsapi_base&state=custom_state#wechat_redirect'
    assert_equal expected, actual
  end

  def test_it_should_return_snsapi_info_oauth_url_for_code
    actual = Wechat::Utils.create_oauth_url_for_code 'your_appid', 'http://yourhost.com', true, 'custom_state'
    expected = 'https://open.weixin.qq.com/connect/oauth2/authorize?appid=your_appid&redirect_uri=http%3A%2F%2Fyourhost.com&response_type=code&scope=snsapi_userinfo&state=custom_state#wechat_redirect'
    assert_equal expected, actual
  end

  def test_it_should_return_url_for_fetching_openid
    actual = Wechat::Utils.create_oauth_url_for_openid 'your_appid', 'app_secret', 'callback_code'
    expected = 'https://api.weixin.qq.com/sns/oauth2/access_token?appid=your_appid&secret=app_secret&code=callback_code&grant_type=authorization_code'
    assert_equal expected, actual
  end

  def test_it_should_send_request_and_parse_to_json
    response_body = "{\"access_token\":\"token\",\"openid\":\"weixin_openid\"}"
    response = mock('response')
    ::RestClient::Request.expects(:execute).with(common_request_opts 'url').returns response
    response.stubs(:body).returns response_body
    assert_equal({'access_token' => 'token', 'openid' => 'weixin_openid'}, Wechat::Utils.get_request('url', {}))
  end

  def test_it_should_return_openid_and_nil_error
    Wechat::Utils.expects(:create_oauth_url_for_openid).with('your_appid', 'app_secret', 'callback_code').returns 'url'
    Wechat::Utils.expects(:get_request).with('url', {}).returns({'access_token' => 'token', 'openid' => 'weixin_openid'})
    assert_equal(['weixin_openid', 'token', {'access_token' => 'token', 'openid' => 'weixin_openid'}], Wechat::Utils.fetch_openid_and_access_token('your_appid', 'app_secret', 'callback_code'))
  end

  def test_it_should_return_nil_openid_and_all_the_reponse_when_openid_is_nil
    Wechat::Utils.expects(:create_oauth_url_for_openid).with('your_appid', 'app_secret', 'callback_code').returns 'url'
    Wechat::Utils.expects(:get_request).with('url', {}).returns({error: 'some error'})
    assert_equal([nil, nil, {error: 'some error'}], Wechat::Utils.fetch_openid_and_access_token('your_appid', 'app_secret', 'callback_code'))
  end

  def test_it_should_fetch_oauth_user_info
    response_body = "{\"openid\":\"openid\",\"nickname\":\"warmwind\"}"
    response = mock('response')
    expected_url = 'https://api.weixin.qq.com/sns/userinfo?access_token=your_token&openid=your_openid&lang=zh_CN'
    ::RestClient::Request.expects(:execute).with(common_request_opts expected_url).returns response
    response.stubs(:body).returns response_body
    Wechat::Utils.fetch_oauth_user_info 'your_token', 'your_openid'
  end

  def test_it_should_fetch_user_info
    response_body = "{\"openid\":\"openid\",\"nickname\":\"warmwind\"}"
    response = mock('response')
    expected_url = 'https://api.weixin.qq.com/cgi-bin/user/info?access_token=your_token&openid=your_openid&lang=zh_CN'
    ::RestClient::Request.expects(:execute).with(common_request_opts expected_url).returns response
    response.stubs(:body).returns response_body
    Wechat::Utils.fetch_user_info 'your_token', 'your_openid'
  end

  def test_it_should_fetch_user_info_with_timeout
    response_body = "{\"openid\":\"openid\",\"nickname\":\"warmwind\"}"
    response = mock('response')
    expected_url = 'https://api.weixin.qq.com/cgi-bin/user/info?access_token=your_token&openid=your_openid&lang=zh_CN'
    ::RestClient::Request.expects(:execute).with(common_request_opts expected_url, {timeout: 1}).returns response
    response.stubs(:body).returns response_body
    Wechat::Utils.fetch_user_info 'your_token', 'your_openid', request_opts: {timeout: 1}
  end

  def test_it_should_return_jsapi_ticket_and_resposne
    response_body = "{\"ticket\":\"your_ticket\"}"
    response = mock('response')
    expected_url = 'https://api.weixin.qq.com/cgi-bin/ticket/getticket?access_token=your_token&type=jsapi'
    ::RestClient::Request.expects(:execute).with(common_request_opts expected_url).returns response
    response.stubs(:body).returns response_body
    assert_equal(['your_ticket', {'ticket' => 'your_ticket'}], Wechat::Utils.fetch_jsapi_ticket('your_token'))
  end

  def test_it_should_return_global_access_token
    response_body = "{\"access_token\":\"your_token\"}"
    response = mock('response')
    expected_url = 'https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=your_appid&secret=your_secret'
    ::RestClient::Request.expects(:execute).with(common_request_opts expected_url).returns response
    response.stubs(:body).returns response_body
    assert_equal(['your_token', {'access_token' => 'your_token'}], Wechat::Utils.fetch_global_access_token('your_appid', 'your_secret'))
  end

  def test_it_should_return_jsapi_params
      res = Wechat::Utils.jsapi_params 'your_appid', 'http://test.com', 'your_ticket'
      assert_equal 'your_appid',  res[:appid]
      assert_equal 'http://test.com',  res[:url]
      assert_equal %i(appid timestamp noncestr signature url), res.keys
  end

  private
  def common_request_opts url, extra_opts = {}
    {
      :url => url,
      :verify_ssl => false,
      :ssl_version => 'TLSv1',
      :method => 'GET',
      :headers => false,
      :timeout => 30
    }.merge extra_opts
  end
end
