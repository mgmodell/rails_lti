# frozen_string_literal: true

module RailsLti
  class Configuration
    # The host application's tool URL base (used for redirect URIs, JWKS, etc.)
    # e.g. "https://mytool.example.com"
    attr_accessor :tool_url

    # The path prefix where the engine is mounted (default: "/lti")
    attr_accessor :mount_path

    # Private key (RSA) used to sign deep link responses and dynamic registration JWTs.
    # Provide an OpenSSL::PKey::RSA instance or PEM string.
    # If nil, a new key is generated at startup (not suitable for production multi-process).
    attr_writer :private_key

    # Public JWKS endpoint path (relative to mount path)
    attr_accessor :jwks_path

    # Nonce expiry in seconds (default: 300 – 5 minutes)
    attr_accessor :nonce_ttl

    # State expiry in seconds (default: 300 – 5 minutes)
    attr_accessor :state_ttl

    # Proc/lambda called after a successful LTI launch.
    # Receives (controller, launch_params) where launch_params is a Hash.
    # The proc should return a redirect URL string, or nil to use the default.
    attr_accessor :after_launch

    # Proc/lambda called after a successful deep link selection.
    # Receives (controller, content_items) where content_items is an Array of Hashes.
    attr_accessor :after_deep_link

    # Proc/lambda called after a successful dynamic registration.
    # Receives (controller, platform) where platform is a RailsLti::Platform instance.
    attr_accessor :after_registration

    def initialize
      @mount_path  = "/lti"
      @jwks_path   = "/jwks"
      @nonce_ttl   = 300
      @state_ttl   = 300
      @after_launch      = nil
      @after_deep_link   = nil
      @after_registration = nil
    end

    def private_key
      @private_key ||= OpenSSL::PKey::RSA.generate(2048)
    end

    def private_key=(value)
      @private_key = value.is_a?(String) ? OpenSSL::PKey::RSA.new(value) : value
    end

    def public_jwks
      key = private_key
      jwk = JWT::JWK.new(key.public_key).export
      jwk[:use] = "sig"
      jwk[:alg] = "RS256"
      { keys: [jwk] }
    end
  end
end
