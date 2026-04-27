# frozen_string_literal: true

require "jwt"
require "openssl"

module RailsLti
  module TestHelpers
    # Provides helpers for testing LTI 1.3 integrations in host Rails applications.
    #
    # Include in your test class:
    #   include RailsLti::TestHelpers::LtiHelpers
    #
    # Example:
    #   class MyLtiTest < ActionDispatch::IntegrationTest
    #     include RailsLti::TestHelpers::LtiHelpers
    #
    #     test "LTI launch" do
    #       platform, deployment = create_test_platform_and_deployment
    #       id_token = build_id_token(deployment, claims: { sub: "user123" })
    #       # ... use id_token in your test
    #     end
    #   end
    module LtiHelpers
      # -----------------------------------------------------------------------
      # Key helpers
      # -----------------------------------------------------------------------

      # Generates a fresh RSA key pair for use in tests.
      # @return [OpenSSL::PKey::RSA]
      def generate_rsa_key
        OpenSSL::PKey::RSA.generate(2048)
      end

      # Returns the test RSA private key (memoised per test instance).
      # The corresponding public key is registered with the test platform.
      # @return [OpenSSL::PKey::RSA]
      def lti_private_key
        @lti_private_key ||= generate_rsa_key
      end

      # -----------------------------------------------------------------------
      # Database helpers
      # -----------------------------------------------------------------------

      # Create a Platform + Deployment pair suitable for testing.
      # Configures a stub JWKS endpoint via WebMock if WebMock is available.
      #
      # @param issuer [String]
      # @param client_id [String]
      # @param deployment_id [String]
      # @param extra_platform_attrs [Hash]
      # @return [[RailsLti::Platform, RailsLti::Deployment]]
      def create_test_platform_and_deployment(
        issuer: "https://platform.example.com",
        client_id: "test_client_id",
        deployment_id: "1",
        **extra_platform_attrs
      )
        jwks_url = "#{issuer}/.well-known/jwks.json"

        platform = RailsLti::Platform.find_or_create_by!(issuer: issuer, client_id: client_id) do |p|
          p.oidc_auth_url = "#{issuer}/auth"
          p.token_url     = "#{issuer}/token"
          p.jwks_url      = jwks_url
          extra_platform_attrs.each { |k, v| p.public_send(:"#{k}=", v) }
        end

        deployment = RailsLti::Deployment.find_or_create_by!(
          platform: platform,
          client_id: client_id,
          deployment_id: deployment_id
        )

        stub_platform_jwks(jwks_url) if defined?(WebMock)

        [platform, deployment]
      end

      # -----------------------------------------------------------------------
      # JWT / token helpers
      # -----------------------------------------------------------------------

      # Build a signed LTI 1.3 ID token JWT.
      #
      # @param deployment [RailsLti::Deployment]
      # @param message_type [String] "LtiResourceLinkRequest" | "LtiDeepLinkingRequest"
      # @param claims [Hash] additional or override claims
      # @param key [OpenSSL::PKey::RSA, nil] signing key (defaults to lti_private_key)
      # @return [String] signed JWT
      def build_id_token(deployment,
                         message_type: "LtiResourceLinkRequest",
                         claims: {},
                         key: nil)
        now        = Time.now.to_i
        signing_key = key || lti_private_key

        base_claims = {
          "iss" => deployment.platform.issuer,
          "aud" => deployment.client_id,
          "sub" => claims.delete(:sub) || claims.delete("sub") || "test_user_#{SecureRandom.hex(4)}",
          "iat" => now,
          "exp" => now + 3600,
          "nonce" => claims.delete(:nonce) || claims.delete("nonce") || store_test_nonce,
          "https://purl.imsglobal.org/spec/lti/claim/version" => "1.3.0",
          "https://purl.imsglobal.org/spec/lti/claim/message_type" => message_type,
          "https://purl.imsglobal.org/spec/lti/claim/deployment_id" => deployment.deployment_id,
          "https://purl.imsglobal.org/spec/lti/claim/target_link_uri" =>
            "#{RailsLti.configuration.tool_url || 'https://tool.example.com'}/lti/launch",
          "https://purl.imsglobal.org/spec/lti/claim/roles" => [
            "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
          ],
          "https://purl.imsglobal.org/spec/lti/claim/context" => {
            "id" => "course_1",
            "type" => ["http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering"],
            "label" => "TEST101",
            "title" => "Test Course"
          },
          "https://purl.imsglobal.org/spec/lti/claim/resource_link" => {
            "id" => "resource_link_1",
            "title" => "Test Resource"
          }
        }

        if message_type == "LtiDeepLinkingRequest"
          base_claims["https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"] = {
            "deep_link_return_url" => "#{deployment.platform.issuer}/deep_link_return",
            "accept_types" => ["ltiResourceLink", "link", "html", "image", "file"],
            "accept_presentation_document_targets" => ["iframe", "window", "embed"],
            "accept_multiple" => true,
            "auto_create" => false
          }
        end

        # Add AGS claims for resource link requests
        if message_type == "LtiResourceLinkRequest"
          base_claims["https://purl.imsglobal.org/spec/lti-ags/claim/endpoint"] = {
            "lineitems" => "#{deployment.platform.issuer}/lineitems",
            "lineitem" => "#{deployment.platform.issuer}/lineitems/1",
            "scope" => [
              Services::Ags::AGS_SCORE_SCOPE,
              Services::Ags::AGS_LINEITEM_SCOPE,
              Services::Ags::AGS_LINEITEM_RO_SCOPE,
              Services::Ags::AGS_RESULT_RO_SCOPE
            ]
          }
          base_claims["https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice"] = {
            "context_memberships_url" => "#{deployment.platform.issuer}/memberships",
            "service_versions" => ["2.0"]
          }
        end

        # Merge in caller-provided overrides (string keys)
        merged = base_claims.merge(stringify_keys(claims))

        kid = JWT::JWK.new(signing_key).export[:kid] rescue nil
        headers = { typ: "JWT" }
        headers[:kid] = kid if kid

        JWT.encode(merged, signing_key, "RS256", headers)
      end

      # Build an OIDC login request params hash (as if sent by the platform).
      # @param deployment [RailsLti::Deployment]
      # @param target_link_uri [String, nil]
      # @return [Hash]
      def build_oidc_login_params(deployment, target_link_uri: nil)
        {
          iss: deployment.platform.issuer,
          login_hint: "login_hint_#{SecureRandom.hex(4)}",
          target_link_uri: target_link_uri || "#{RailsLti.configuration.tool_url}/lti/launch",
          lti_message_hint: "hint_#{SecureRandom.hex(4)}",
          client_id: deployment.client_id,
          deployment_id: deployment.deployment_id
        }
      end

      # Store a nonce in the database and return its value.
      # @return [String] nonce value
      def store_test_nonce
        value = SecureRandom.hex(16)
        RailsLti::Nonce.create!(
          value: value,
          expires_at: Time.now + RailsLti.configuration.nonce_ttl
        )
        value
      end

      # -----------------------------------------------------------------------
      # WebMock stub helpers
      # -----------------------------------------------------------------------

      # Stub the platform JWKS endpoint to return the test public key.
      # Requires WebMock to be available.
      # @param jwks_url [String]
      # @param key [OpenSSL::PKey::RSA, nil] defaults to lti_private_key
      def stub_platform_jwks(jwks_url, key: nil)
        return unless defined?(WebMock)

        signing_key = key || lti_private_key
        jwk = JWT::JWK.new(signing_key.public_key).export
        jwk[:use] = "sig"
        jwk[:alg] = "RS256"

        WebMock.stub_request(:get, jwks_url)
               .to_return(
                 status: 200,
                 body: { keys: [jwk] }.to_json,
                 headers: { "Content-Type" => "application/json" }
               )
      end

      # Stub an OAuth 2 token endpoint to return a mock access token.
      # @param token_url [String]
      # @param access_token [String]
      # @param expires_in [Integer]
      def stub_platform_token_endpoint(token_url, access_token: "test_access_token", expires_in: 3600)
        return unless defined?(WebMock)

        WebMock.stub_request(:post, token_url)
               .to_return(
                 status: 200,
                 body: {
                   access_token: access_token,
                   token_type: "Bearer",
                   expires_in: expires_in,
                   scope: ""
                 }.to_json,
                 headers: { "Content-Type" => "application/json" }
               )
      end

      private

      def stringify_keys(hash)
        hash.transform_keys(&:to_s)
      end
    end
  end
end
