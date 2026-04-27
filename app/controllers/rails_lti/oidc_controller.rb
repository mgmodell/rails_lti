# frozen_string_literal: true

module RailsLti
  # Handles the LTI 1.3 OIDC login initiation and launch (authentication response).
  #
  # Mount the engine and these endpoints become available:
  #   GET/POST /lti/login  – Step 1: OIDC login initiation from the platform
  #   POST     /lti/launch – Step 2: Platform posts the id_token after authentication
  #   GET      /lti/jwks   – Tool's public JWKS endpoint
  class OidcController < ApplicationController
    # Step 1 – OIDC Login Initiation
    # The platform sends the user here. We validate the request, generate
    # state/nonce, and redirect to the platform's OIDC authorization endpoint.
    def login
      iss           = params[:iss]
      login_hint    = params[:login_hint]
      target_link_uri = params[:target_link_uri]
      client_id     = params[:client_id]
      deployment_id = params[:lti_deployment_id] || params[:deployment_id]

      return render_error("Missing required parameter: iss")           if iss.blank?
      return render_error("Missing required parameter: login_hint")    if login_hint.blank?
      return render_error("Missing required parameter: target_link_uri") if target_link_uri.blank?

      platform = find_platform(iss, client_id)
      return render_error("Unknown platform: #{iss}") unless platform

      state = SecureRandom.hex(32)
      nonce_value = SecureRandom.hex(32)

      RailsLti::Nonce.create!(
        value: nonce_value,
        expires_at: Time.now + RailsLti.configuration.nonce_ttl
      )

      session[:lti_state]            = state
      session[:lti_nonce]            = nonce_value
      session[:lti_target_link_uri]  = target_link_uri
      session[:lti_platform_id]      = platform.id
      session[:lti_client_id]        = platform.client_id
      session[:lti_deployment_id]    = deployment_id

      config = RailsLti.configuration
      redirect_uri = "#{config.tool_url}#{config.mount_path}/launch"

      auth_params = {
        response_type: "id_token",
        response_mode: "form_post",
        scope: "openid",
        client_id: platform.client_id,
        redirect_uri: redirect_uri,
        login_hint: login_hint,
        state: state,
        nonce: nonce_value,
        prompt: "none"
      }

      auth_params[:lti_message_hint] = params[:lti_message_hint] if params[:lti_message_hint].present?

      redirect_to "#{platform.oidc_auth_url}?#{auth_params.to_query}", allow_other_host: true
    end

    # Step 2 – Authentication Response (Launch)
    # The platform POSTs the signed id_token back here.
    def launch
      id_token = params[:id_token]
      state    = params[:state]

      return render_error("Missing id_token") if id_token.blank?
      return render_error("Missing state")    if state.blank?

      unless secure_compare(state, session[:lti_state])
        return render_error("State mismatch – possible CSRF attack")
      end

      deployment = find_deployment_for_launch
      return render_error("Deployment not found") unless deployment

      nonce = session[:lti_nonce]
      return render_error("No nonce in session") if nonce.blank?

      begin
        claims = RailsLti::JwtValidator.new(deployment, id_token, nonce).validate!
      rescue RailsLti::JwtValidator::ValidationError => e
        return render_error("JWT validation failed: #{e.message}")
      end

      session.delete(:lti_state)
      session.delete(:lti_nonce)

      session[:lti_launch_claims]    = claims
      session[:lti_deployment_id]    = deployment.id
      session[:lti_authenticated]    = true

      after_launch = RailsLti.configuration.after_launch
      if after_launch
        redirect_url = after_launch.call(self, claims)
        redirect_to redirect_url, allow_other_host: true if redirect_url
      else
        redirect_to session.delete(:lti_target_link_uri) || main_app.root_path,
                    allow_other_host: true
      end
    end

    # Public JWKS endpoint – returns the tool's public key(s) for platforms to verify
    # deep link response JWTs and client_credentials assertions.
    def jwks
      render json: RailsLti.configuration.public_jwks
    end

    private

    def find_platform(iss, client_id)
      if client_id.present?
        Platform.find_by(issuer: iss, client_id: client_id) ||
          Platform.find_by(issuer: iss)
      else
        Platform.find_by(issuer: iss)
      end
    end

    def find_deployment_for_launch
      platform_id   = session[:lti_platform_id]
      deployment_id = session[:lti_deployment_id]

      Deployment.joins(:platform)
                .find_by(
                  platform_id: platform_id,
                  deployment_id: deployment_id
                )
    end

    def render_error(message)
      render plain: message, status: :bad_request
    end

    # Constant-time string comparison to avoid timing attacks
    def secure_compare(a, b)
      ActiveSupport::SecurityUtils.secure_compare(a.to_s, b.to_s)
    end
  end
end
