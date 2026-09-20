require 'faraday/net_http_persistent'

module Wechat
  module Utils
    # faraday-net_http_persistent leaves Net::HTTP::Persistent at its default
    # 5 second idle_timeout. Real WeChat API calls (a user scanning a QR code,
    # a form submission) are typically tens of seconds to minutes apart, so
    # without this the pooled connection is closed and re-established on
    # almost every call anyway. Raised once, right after the connection is
    # built; if the server closes it first, net-http-persistent already
    # retries on a fresh connection.
    class IdleTimeoutAdapter < Faraday::Adapter::NetHttpPersistent
      IDLE_TIMEOUT = 60

      # Known gap: Faraday::Adapter::NetHttp#call configures this
      # adapter's single shared Net::HTTP::Persistent manager (SSL,
      # open/read/write timeout, proxy) and only afterwards dispatches
      # through it, as two separate steps. Wechat::Utils caches one
      # adapter per real OS thread, so two threads never share one here -
      # but on a Fiber-scheduler-based server (e.g. Falcon/Async), many
      # fibers run on that one thread and would share this same manager,
      # so a fiber switch landing between "configure" and "dispatch"
      # could let one fiber's request go out with settings a second
      # fiber configured in between.
      #
      # A Mutex around the whole call was tried and reverted: under a
      # real Fiber scheduler, a second fiber locking a Mutex already held
      # by another fiber on the same thread raises `ThreadError: deadlock
      # ; lock already owned by another fiber belonging to the same
      # thread` instead of waiting - a hard failure, worse than the race
      # it was meant to prevent. Properly fixing this needs fiber-scoped
      # adapters sharing one underlying socket pool, which is real
      # redesign work; accepted as a gap since nothing indicates this
      # gem is used under a Fiber-scheduler server today.
      def net_http_connection(env)
        first_use = @cached_connection.nil?
        connection = super
        connection.idle_timeout = IDLE_TIMEOUT if first_use
        connection
      end

      # Faraday::Adapter::NetHttp#configure_request unconditionally zeroes
      # max_retries on every call, on the assumption a freshly opened
      # connection is unlikely to already be dead. That assumption doesn't
      # hold for a pooled, reused connection - the whole point of this
      # adapter - so a server closing a keep-alive socket right as it's
      # reused would surface as a hard failure instead of the transparent
      # reopen-and-retry-once Net::HTTP (since Ruby 2.5) already provides
      # for idempotent requests. Restore net-http-persistent's own default.
      def configure_request(http, req)
        super
        http.max_retries = 1
      end
    end
  end
end
