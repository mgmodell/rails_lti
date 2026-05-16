# frozen_string_literal: true

RailsLti.configure do |config|
  # The base URL of your tool (no trailing slash).
  # Used to build redirect URIs, JWKS URLs, etc.
  # config.tool_url = "https://mytool.example.com"

  # The path where the engine is mounted (must match your routes.rb).
  # config.mount_path = "/lti"

  # Path (relative to mount_path) for the public JWKS endpoint.
  # config.jwks_path = "/jwks"

  # Nonce TTL in seconds (default: 300 – 5 minutes).
  # config.nonce_ttl = 300

  # RSA private key for signing JWTs (deep links, client_credentials assertions).
  # Generate with: OpenSSL::PKey::RSA.generate(2048).to_pem
  # Store securely (e.g. credentials, environment variable).
  # config.private_key = Rails.application.credentials.lti_private_key

  # Called after a successful LTI launch. Receives (controller, claims).
  # Return a String URL to redirect to, or nil to use the target_link_uri.
  # config.after_launch = ->(controller, claims) {
  #   controller.session[:current_lti_user] = claims["sub"]
  #   nil  # redirect to target_link_uri
  # }

  # Called after a successful deep link selection.
  # Receives (controller, content_items).
  # config.after_deep_link = ->(controller, items) {}

  # Called after a successful dynamic registration.
  # Receives (controller, platform).
  # config.after_registration = ->(controller, platform) {}
end
