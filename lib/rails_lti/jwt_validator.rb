# frozen_string_literal: true

module RailsLti
  # Validates LTI 1.3 ID tokens (JWTs) from a platform.
  class JwtValidator
    REQUIRED_CLAIMS = %w[iss aud sub iat exp nonce].freeze
    LTI_VERSION_CLAIM = "https://purl.imsglobal.org/spec/lti/claim/version"
    MESSAGE_TYPE_CLAIM = "https://purl.imsglobal.org/spec/lti/claim/message_type"
    LTI_VERSION = "1.3.0"

    class ValidationError < StandardError; end

    # @param deployment [RailsLti::Deployment] the deployment record
    # @param id_token [String] raw JWT string from the platform
    # @param nonce [String] expected nonce (from session)
    # @param state [String] expected state (from session)
    def initialize(deployment, id_token, nonce)
      @deployment = deployment
      @id_token   = id_token
      @nonce      = nonce
    end

    # Decode and validate the JWT, returning the claims hash.
    # Raises ValidationError on any failure.
    # @return [Hash] decoded JWT claims
    def validate!
      header  = decode_header
      payload = decode_and_verify(header["kid"])

      validate_claims(payload)
      validate_nonce(payload["nonce"])

      payload
    end

    private

    def decode_header
      parts = @id_token.split(".")
      raise ValidationError, "Malformed JWT" unless parts.length == 3

      JSON.parse(Base64.urlsafe_decode64(parts[0] + "=="))
    rescue JSON::ParserError
      raise ValidationError, "Malformed JWT header"
    end

    def decode_and_verify(kid)
      jwks    = fetch_jwks
      key     = find_key(jwks, kid)
      public_key = JWT::JWK.new(key).keypair

      options = {
        algorithms: ["RS256"],
        verify_iat: true,
        verify_expiration: true
      }

      payload, = JWT.decode(@id_token, public_key, true, options)
      payload
    rescue JWT::DecodeError => e
      raise ValidationError, "JWT decode error: #{e.message}"
    end

    def fetch_jwks
      platform = @deployment.platform
      conn = Faraday.new do |f|
        f.adapter Faraday.default_adapter
      end
      response = conn.get(platform.jwks_url)
      raise ValidationError, "Failed to fetch JWKS from platform" unless response.success?

      JSON.parse(response.body)
    rescue Faraday::Error, JSON::ParserError => e
      raise ValidationError, "JWKS fetch error: #{e.message}"
    end

    def find_key(jwks, kid)
      keys = jwks["keys"] || []
      key  = kid ? keys.find { |k| k["kid"] == kid } : keys.first
      raise ValidationError, "No matching key found in platform JWKS (kid=#{kid})" unless key

      key
    end

    def validate_claims(payload)
      REQUIRED_CLAIMS.each do |claim|
        raise ValidationError, "Missing required claim: #{claim}" if payload[claim].nil?
      end

      unless iss_matches?(payload["iss"])
        raise ValidationError, "iss mismatch: expected #{@deployment.platform.issuer}, got #{payload['iss']}"
      end

      unless aud_matches?(payload["aud"])
        raise ValidationError, "aud mismatch: expected #{@deployment.client_id}"
      end

      unless deployment_id_matches?(payload)
        raise ValidationError, "deployment_id mismatch"
      end

      if payload[LTI_VERSION_CLAIM] != LTI_VERSION
        raise ValidationError, "Unsupported LTI version: #{payload[LTI_VERSION_CLAIM]}"
      end
    end

    def iss_matches?(iss)
      iss == @deployment.platform.issuer
    end

    def aud_matches?(aud)
      Array(aud).include?(@deployment.client_id)
    end

    def deployment_id_matches?(payload)
      claimed_deployment_id = payload["https://purl.imsglobal.org/spec/lti/claim/deployment_id"]
      claimed_deployment_id == @deployment.deployment_id
    end

    def validate_nonce(nonce_value)
      raise ValidationError, "Nonce mismatch" if nonce_value != @nonce

      nonce_record = RailsLti::Nonce.find_by(value: nonce_value)
      raise ValidationError, "Nonce not found or already used" unless nonce_record
      raise ValidationError, "Nonce expired" if nonce_record.expired?

      nonce_record.destroy
    end
  end
end
