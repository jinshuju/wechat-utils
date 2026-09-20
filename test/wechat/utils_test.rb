require 'test_helper'
require 'benchmark'
require 'support/local_http_server'

class Wechat::UtilsTest < Minitest::Test
  def setup
    Wechat::Utils.reset_connections!
  end

  def teardown
    Wechat::Utils.reset_connections!
    @server.stop if @server
  end

  def test_that_it_has_a_version_number
    assert_equal '0.3.1', ::Wechat::Utils::VERSION
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

  # --- request option mapping (no real network, WebMock intercepts the socket) ---

  def test_it_should_send_request_and_parse_to_json
    stub_request(:get, 'https://api.weixin.qq.com/sns/oauth2/access_token?appid=a&secret=b')
      .to_return(body: '{"access_token":"token","openid":"weixin_openid"}')
    assert_equal({'access_token' => 'token', 'openid' => 'weixin_openid'},
                 Wechat::Utils.get_request('https://api.weixin.qq.com/sns/oauth2/access_token?appid=a&secret=b', {}))
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
    expected_url = 'https://api.weixin.qq.com/sns/userinfo?access_token=your_token&openid=your_openid&lang=zh_CN'
    stub_request(:get, expected_url).to_return(body: '{"openid":"openid","nickname":"warmwind"}')
    assert_equal({'openid' => 'openid', 'nickname' => 'warmwind'}, Wechat::Utils.fetch_oauth_user_info('your_token', 'your_openid'))
  end

  def test_it_should_fetch_user_info
    expected_url = 'https://api.weixin.qq.com/cgi-bin/user/info?access_token=your_token&openid=your_openid&lang=zh_CN'
    stub_request(:get, expected_url).to_return(body: '{"openid":"openid","nickname":"warmwind"}')
    assert_equal({'openid' => 'openid', 'nickname' => 'warmwind'}, Wechat::Utils.fetch_user_info('your_token', 'your_openid'))
  end

  def test_a_nil_timeout_should_disable_the_timeouts_like_rest_client_did
    expected_url = 'https://api.weixin.qq.com/cgi-bin/user/info?access_token=t&openid=o&lang=zh_CN'
    stub_request(:get, expected_url).to_return(body: '{}')
    Wechat::Utils.fetch_user_info 't', 'o', request_opts: {timeout: nil}
  end

  def test_it_should_map_specific_timeouts
    expected_url = 'https://api.weixin.qq.com/cgi-bin/user/info?access_token=t&openid=o&lang=zh_CN'
    stub_request(:get, expected_url).to_return(body: '{}')
    Wechat::Utils.fetch_user_info 't', 'o', request_opts: {open_timeout: 2, read_timeout: 3}
  end

  def test_it_should_pass_extra_headers_and_string_keys
    expected_url = 'https://api.weixin.qq.com/cgi-bin/user/info?access_token=t&openid=o&lang=zh_CN'
    stub_request(:get, expected_url).with(headers: {'X-Trace' => 'abc'}).to_return(body: '{}')
    Wechat::Utils.fetch_user_info 't', 'o', request_opts: {'headers' => {'X-Trace' => 'abc'}}
  end

  def test_it_should_accept_a_proxy_option_without_raising
    expected_url = 'https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=a&secret=s'
    stub_request(:get, expected_url).to_return(body: '{}')
    Wechat::Utils.fetch_global_access_token 'a', 's', request_opts: {proxy: false}
  end

  def test_it_should_reject_unknown_request_options
    error = assert_raises(ArgumentError) { Wechat::Utils.get_request('https://api.weixin.qq.com/x', method: 'POST') }
    assert_match(/unsupported request options: :method/, error.message)
  end

  def test_it_should_raise_on_an_unfollowed_redirect_status
    start_server { |_req| [304, ''] }
    assert_raises(Faraday::ClientError) { Wechat::Utils.get_request(@server.url('/x')) }
  end

  def test_it_should_raise_on_any_status_other_than_200
    start_server { |_req| [201, '{}'] }
    assert_raises(Faraday::ClientError) { Wechat::Utils.get_request(@server.url('/x')) }
  end

  def test_post_request_should_send_a_json_body_and_parse_the_response
    stub_request(:post, 'https://api.weixin.qq.com/cgi-bin/qrcode/create')
      .with(body: '{"action_name":"QR_STR_SCENE","action_info":{"scene":{"scene_str":"1"}}}',
            headers: {'Content-Type' => 'application/json'})
      .to_return(body: '{"ticket":"abc"}')
    result = Wechat::Utils.post_request(
      'https://api.weixin.qq.com/cgi-bin/qrcode/create',
      action_name: 'QR_STR_SCENE', action_info: {scene: {scene_str: '1'}}
    )
    assert_equal({'ticket' => 'abc'}, result)
  end

  def test_post_request_should_send_a_string_payload_as_is
    stub_request(:post, 'https://api.weixin.qq.com/x').with(body: 'raw-body').to_return(body: '{}')
    Wechat::Utils.post_request('https://api.weixin.qq.com/x', 'raw-body')
  end

  def test_post_request_should_send_literal_false_and_null_json_payloads
    stub_request(:post, 'https://api.weixin.qq.com/f').with(body: 'false').to_return(body: '{}')
    Wechat::Utils.post_request('https://api.weixin.qq.com/f', false)

    stub_request(:post, 'https://api.weixin.qq.com/n').with(body: 'null').to_return(body: '{}')
    Wechat::Utils.post_request('https://api.weixin.qq.com/n', nil)
  end

  def test_post_request_should_let_an_explicit_header_override_the_default_content_type
    stub_request(:post, 'https://api.weixin.qq.com/x').with(headers: {'Content-Type' => 'text/plain'}).to_return(body: '{}')
    Wechat::Utils.post_request('https://api.weixin.qq.com/x', {a: 1}, headers: {'Content-Type' => 'text/plain'})
  end

  def test_post_request_should_reject_unknown_request_options
    error = assert_raises(ArgumentError) { Wechat::Utils.post_request('https://api.weixin.qq.com/x', {}, method: 'PUT') }
    assert_match(/unsupported request options: :method/, error.message)
  end

  def test_post_request_should_reuse_the_same_connection_as_get_request
    start_server
    Wechat::Utils.get_request(@server.url('/g'))
    Wechat::Utils.post_request(@server.url('/p'), {})
    assert_equal 1, @server.accepted_connections
  end

  def test_it_should_return_jsapi_ticket_and_resposne
    expected_url = 'https://api.weixin.qq.com/cgi-bin/ticket/getticket?access_token=your_token&type=jsapi'
    stub_request(:get, expected_url).to_return(body: '{"ticket":"your_ticket"}')
    assert_equal(['your_ticket', {'ticket' => 'your_ticket'}], Wechat::Utils.fetch_jsapi_ticket('your_token'))
  end

  def test_it_should_return_global_access_token
    expected_url = 'https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=your_appid&secret=your_secret'
    stub_request(:get, expected_url).to_return(body: '{"access_token":"your_token"}')
    assert_equal(['your_token', {'access_token' => 'your_token'}], Wechat::Utils.fetch_global_access_token('your_appid', 'your_secret'))
  end

  def test_it_should_return_jsapi_params
    res = Wechat::Utils.jsapi_params 'your_appid', 'http://test.com', 'your_ticket'
    assert_equal 'your_appid',  res[:appid]
    assert_equal 'http://test.com',  res[:url]
    assert_equal %i(appid timestamp noncestr signature url), res.keys
  end

  # --- persistent connection behaviour against a real local server ---

  def test_it_should_raise_the_default_idle_timeout
    start_server
    Wechat::Utils.get_request(@server.url('/x'))
    adapter = adapter_for(Wechat::Utils.send(:ssl_options, {}), nil)
    persistent = adapter.instance_variable_get(:@cached_connection)
    assert_equal Wechat::Utils::IdleTimeoutAdapter::IDLE_TIMEOUT, persistent.idle_timeout
    refute_equal 5, persistent.idle_timeout
  end

  def test_it_should_reuse_one_tcp_connection_for_sequential_requests
    start_server
    5.times do |i|
      body = Wechat::Utils.get_request(@server.url("/cgi-bin/token?grant_type=client_credential&appid=#{i}"))
      assert_equal({'path' => '/cgi-bin/token', 'query' => "grant_type=client_credential&appid=#{i}"}, body)
    end
    assert_equal 5, @server.requests.size
    assert_equal 1, @server.accepted_connections
  end

  def test_it_should_reuse_one_tls_session_for_sequential_https_requests
    start_server(tls: true)
    3.times do |i|
      assert_equal "appid=#{i}", Wechat::Utils.get_request(@server.url("/cgi-bin/token?appid=#{i}"))['query']
    end
    assert_equal 3, @server.requests.size
    assert_equal 1, @server.accepted_connections
  end

  def test_it_should_verify_certificates_when_asked_to
    start_server(tls: true)
    assert_raises(Faraday::SSLError) do
      Wechat::Utils.get_request(@server.url('/cgi-bin/token'), verify_ssl: true)
    end
  end

  def test_it_should_enforce_read_timeout_over_https
    start_server(tls: true) { |_req| sleep 5; [200, '{}'] }
    elapsed = Benchmark.realtime do
      assert_raises(Faraday::TimeoutError) { Wechat::Utils.get_request(@server.url('/slow'), timeout: 0.5) }
    end
    assert_operator elapsed, :<, 3
    # IdleTimeoutAdapter restores Net::HTTP's built-in max_retries = 1, so a
    # read-timed-out GET (idempotent) is transparently retried once on a
    # fresh connection before raising: two requests reach the server and
    # the call takes ~2x the timeout, not just one timeout's worth.
    assert_operator elapsed, :>, 0.9
    assert_equal 2, @server.requests.size
  end

  def test_it_should_not_retry_a_timed_out_post
    start_server(tls: true) { |_req| sleep 5; [200, '{}'] }
    elapsed = Benchmark.realtime do
      assert_raises(Faraday::TimeoutError) { Wechat::Utils.post_request(@server.url('/slow'), {}, timeout: 0.5) }
    end
    # POST is not in Net::HTTP's idempotent method list, so unlike GET it
    # is never silently retried after a read timeout.
    assert_operator elapsed, :<, 0.9
    assert_equal 1, @server.requests.size
  end

  def test_each_thread_should_get_its_own_connection_and_correct_responses
    start_server
    results = Array.new(4) do |t|
      Thread.new do
        Array.new(3) { |i| Wechat::Utils.get_request(@server.url("/t?thread=#{t}&i=#{i}"))['query'] }
      end
    end.map(&:value)

    assert_equal 12, @server.requests.size
    assert_equal 4, @server.accepted_connections
    results.each_with_index do |queries, t|
      assert_equal (0..2).map { |i| "thread=#{t}&i=#{i}" }, queries
    end
  end

  def test_it_should_recover_when_the_server_drops_an_idle_keep_alive_connection
    start_server(drop_after_response: true)
    assert_equal 'n=1', Wechat::Utils.get_request(@server.url('/x?n=1'))['query']
    assert_equal 'n=2', Wechat::Utils.get_request(@server.url('/x?n=2'))['query']
  end

  def test_it_should_follow_redirects_like_rest_client_did
    start_server do |req|
      if req.path == '/old'
        [302, "http://127.0.0.1:#{@server.port}/new?#{req.query}"]
      else
        [200, JSON.generate('path' => req.path, 'query' => req.query)]
      end
    end
    assert_equal({'path' => '/new', 'query' => 'a=1'}, Wechat::Utils.get_request(@server.url('/old?a=1')))
    assert_equal %w[/old /new], @server.requests.map(&:path)
  end

  def test_it_should_not_follow_a_308_redirect_like_rest_client_did
    start_server { |_req| [308, 'http://127.0.0.1:1/new'] }
    assert_raises(Faraday::ClientError) { Wechat::Utils.get_request(@server.url('/old')) }
    assert_equal 1, @server.requests.size
  end

  def test_it_should_not_follow_a_redirected_post_like_rest_client_did
    start_server { |_req| [307, 'http://127.0.0.1:1/new'] }
    assert_raises(Faraday::ClientError) { Wechat::Utils.post_request(@server.url('/old'), {}) }
    assert_equal 1, @server.requests.size
  end

  def test_it_should_follow_more_than_faradays_default_of_three_redirects
    hops = 5
    start_server do |req|
      n = req.path.delete_prefix('/hop').to_i
      n < hops ? [302, "http://127.0.0.1:#{@server.port}/hop#{n + 1}"] : [200, '{"ok":true}']
    end
    assert_equal({'ok' => true}, Wechat::Utils.get_request(@server.url('/hop0')))
    assert_equal hops + 1, @server.requests.size
  end

  def test_it_should_raise_once_on_a_redirect_missing_a_location_instead_of_repeating_it
    start_server { |_req| [302, ''] }
    assert_raises(Faraday::ClientError) { Wechat::Utils.get_request(@server.url('/x')) }
    assert_equal 1, @server.requests.size
  end

  def test_it_should_not_leak_a_disabled_timeout_into_a_later_reused_connection
    start_server(tls: true) { |_req| sleep 1; [200, '{}'] }
    assert_raises(Faraday::TimeoutError) { Wechat::Utils.get_request(@server.url('/slow'), timeout: 0.2) }
    # Same cached connection as above; a stale 0.2s timeout would make this raise too.
    Wechat::Utils.get_request(@server.url('/slow'), timeout: nil)
  end

  def test_concurrent_requests_with_different_timeouts_should_not_clobber_each_other
    start_server { |_req| sleep 0.3; [200, '{}'] }
    short_timeout_failures = 0
    long_timeout_failures = 0

    5.times do
      threads = [
        Thread.new do
          Wechat::Utils.get_request(@server.url('/x'), timeout: 0.05)
        rescue Faraday::TimeoutError
          short_timeout_failures += 1
        end,
        Thread.new do
          Wechat::Utils.get_request(@server.url('/x'), timeout: 5)
        rescue Faraday::TimeoutError
          long_timeout_failures += 1
        end
      ]
      threads.each(&:join)
    end

    assert_equal 5, short_timeout_failures
    assert_equal 0, long_timeout_failures
  end

  def test_requests_with_different_proxies_should_use_different_connections
    ssl = Wechat::Utils.send(:ssl_options, {})
    default_connection = Wechat::Utils.send(:connection, ssl, nil)
    proxied_connection = Wechat::Utils.send(:connection, ssl, 'http://proxy.example:3128')
    refute_same default_connection, proxied_connection
  end

  def test_it_should_raise_on_http_error_status
    start_server { |_req| [500, '{"errcode":-1}'] }
    assert_raises(Faraday::ServerError) { Wechat::Utils.get_request(@server.url('/x')) }
  end

  def test_reset_connections_should_allow_a_fresh_connection_to_be_built
    start_server
    Wechat::Utils.get_request(@server.url('/x?n=1'))
    ssl = Wechat::Utils.send(:ssl_options, {})
    before = Wechat::Utils.send(:connection, ssl, nil)
    Wechat::Utils.reset_connections!
    after = Wechat::Utils.send(:connection, ssl, nil)
    refute_same before, after
  end

  private

  def start_server(**options, &handler)
    @server = LocalHttpServer.new(**options, &handler).start
  end

  def adapter_for(ssl, proxy)
    conn = Wechat::Utils.send(:connection, ssl, proxy)
    conn.app.instance_variable_get(:@app).instance_variable_get(:@app)
  end
end
