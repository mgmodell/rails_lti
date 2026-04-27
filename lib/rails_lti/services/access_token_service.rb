# frozen_string_literal: true

module RailsLti
  module Services
    # Fetches OAuth 2.0 access tokens from the platform using client_credentials grant
    # with private_key_jwt client authentication (as required by LTI Advantage).
    class AccessTokenService
      GRANT_TYPE = "client_credentials"
      CLIENT_ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

      class Error < StandardError; end

      # @param deployment [RailsLti::Deployment]
      def initialize(deployment)
        @deployment = deployment
      end

      # Fetch an access token for the given scope.
      # Tokens are cached for the duration of their expiry minus 30 seconds.
      # @param scope [String] the LTI Advantage scope URI
      # @return [String] the access token
      def fetch(scope)
        cache_key = "rails_lti:access_token:#{@deployment.id}:#{Digest::SHA256.hexdigest(scope)}"

        cached = Rails.cache.read(cache_key)
        return cached if cached

        token_data = request_token(scope)
        expires_in = token_data["expires_in"].to_i
        ttl = expires_in > 30 ? expires_in - 30 : expires_in

        Rails.cache.write(cache_key, token_data["access_token"], expires_in: ttl) if ttl > 0

        token_data["access_token"]
      end

      private

      def request_token(scope)
        platform   = @deployment.platform
        now        = Time.now.to_i
        private_key = RailsLti.configuration.private_key

        client_assertion = JWT.encode(
          {
            iss: @deployment.client_id,
            sub: @deployment.client_id,
            aud: platform.token_url,
            iat: now,
            exp: now + 300,
            jti: SecureRandom.hex(16)
          },
          private_key,
          "RS256"
        )

        response = conn.post(platform.token_url) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(
            grant_type: GRANT_TYPE,
            client_assertion_type: CLIENT_ASSERTION_TYPE,
            client_assertion: client_assertion,
            scope: scope
          )
        end

        raise Error, "Token request failed (#{response.status}): #{response.body}" unless response.success?

        JSON.parse(response.body)
      rescue JSON::ParserError, Faraday::Error => e
        raise Error, "Token request error: #{e.message}"
      end

      def conn
        @conn ||= Faraday.new do |f|
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
