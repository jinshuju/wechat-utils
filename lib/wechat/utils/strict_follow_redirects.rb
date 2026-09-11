require 'faraday/follow_redirects'

module Wechat
  module Utils
    # faraday-follow_redirects treats a missing Location header as an empty
    # one, which resolves back to the same URL, so it silently repeats the
    # request (the same JSON body, for a POST) up to the redirect limit
    # instead of failing on the first response. rest-client raised
    # immediately when a redirect response had no Location; match that by
    # not following a redirect that doesn't carry one, leaving it to
    # Wechat::Utils#perform_request's own status check to raise.
    #
    # rest-client also never followed 308 (Permanent Redirect) - it only
    # handled 301/302/307 (GET/HEAD only) and 303, raising for everything
    # else, 308 included. faraday-follow_redirects follows 308 like 307
    # (method and body preserved); reject it here too.
    #
    # It also only followed 301/302/307 for GET/HEAD, raising for any
    # other method - a POST hitting one of those would otherwise be
    # silently turned into a GET (301/302, non-standards-compliant
    # default) or replayed as the same POST (307), duplicating a
    # state-changing call. 303 is unrestricted since it always converts
    # to GET regardless of the original method.
    class StrictFollowRedirects < Faraday::FollowRedirects::Middleware
      GET_HEAD_ONLY_STATUSES = [301, 302, 307].freeze

      def follow_redirect?(env, response)
        return false unless super
        return false if response.status == 308
        return false if response['location'].to_s.strip.empty?
        return false if GET_HEAD_ONLY_STATUSES.include?(response.status) && !%i[get head].include?(env[:method])

        true
      end
    end
  end
end
