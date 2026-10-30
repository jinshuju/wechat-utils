module Wechat
  module Utils
    module Instrumentable
      def subscribe(name = rand, &block)
        subscribers[name] = block
        name
      end

      # Called once per request with a Hash:
      #   method, url, status, errcode, errmsg, error, duration_ms
      def notify(event)
        subscribers.each_value { |subscriber| subscriber.call(event) }
      end

      private

      def subscribers
        @subscribers ||= {}
      end
    end
  end
end
