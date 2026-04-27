# frozen_string_literal: true

module RailsLti
  module Services
    # Handles LTI Advantage Dynamic Registration
    # @see https://www.imsglobal.org/spec/lti-dr/v1p0
    class DynamicRegistration
      REGISTRATION_MEDIA_TYPE = "application/json"

      class Error < StandardError; end

      # @param openid_configuration_url [String] Platform's OpenID configuration URL
      # @param registration_token [String, nil] Optional bearer token for the registration request
      # @param tool_url [String] Base URL of the tool
      def initialize(openid_configuration_url:, registration_token: nil, tool_url:)
        validate_https_url!(openid_configuration_url, "openid_configuration_url")
        @openid_configuration_url = openid_configuration_url
        @registration_token       = registration_token
        @tool_url                 = tool_url
      end

      # Fetch platform's OpenID configuration.
      # @return [Hash] OpenID configuration JSON
      def fetch_openid_configuration
        response = conn.get(@openid_configuration_url)
        raise Error, "Failed to fetch OpenID configuration: #{response.status}" unless response.success?

        JSON.parse(response.body)
      rescue JSON::ParserError, Faraday::Error => e
        raise Error, "OpenID configuration error: #{e.message}"
      end

      # Register the tool with the platform.
      # @param openid_config [Hash] Platform's OpenID configuration
      # @return [RailsLti::Platform] the newly created or updated platform record
      def register!(openid_config)
        registration_endpoint = openid_config["registration_endpoint"]
        raise Error, "No registration_endpoint in OpenID configuration" unless registration_endpoint

        validate_https_url!(registration_endpoint, "registration_endpoint")

        body    = build_registration_payload(openid_config)
        headers = { "Content-Type" => REGISTRATION_MEDIA_TYPE }
        headers["Authorization"] = "Bearer #{@registration_token}" if @registration_token

        response = conn.post(registration_endpoint, body.to_json, headers)
        raise Error, "Registration failed (#{response.status}): #{response.body}" unless response.success?

        client_data = JSON.parse(response.body)
        create_platform(openid_config, client_data)
      rescue JSON::ParserError, Faraday::Error => e
        raise Error, "Registration error: #{e.message}"
      end

      private

      def build_registration_payload(openid_config)
        config = RailsLti.configuration

        {
          "application_type" => "web",
          "response_types" => ["id_token"],
          "grant_types" => ["implicit", "client_credentials"],
          "initiate_login_uri" => "#{@tool_url}#{config.mount_path}/login",
          "redirect_uris" => ["#{@tool_url}#{config.mount_path}/launch"],
          "client_name" => openid_config["tool_name"] || "Rails LTI Tool",
          "jwks_uri" => "#{@tool_url}#{config.mount_path}#{config.jwks_path}",
          "token_endpoint_auth_method" => "private_key_jwt",
          "scope" => all_scopes.join(" "),
          "https://purl.imsglobal.org/spec/lti-tool-configuration" => {
            "domain" => URI.parse(@tool_url).host,
            "target_link_uri" => "#{@tool_url}#{config.mount_path}/launch",
            "oidc_initiation_url" => "#{@tool_url}#{config.mount_path}/login",
            "messages" => [
              {
                "type" => "LtiResourceLinkRequest",
                "target_link_uri" => "#{@tool_url}#{config.mount_path}/launch"
              },
              {
                "type" => "LtiDeepLinkingRequest",
                "target_link_uri" => "#{@tool_url}#{config.mount_path}/launch"
              }
            ],
            "claims" => ["iss", "sub", "name", "given_name", "family_name", "email"],
            "deployment" => []
          }
        }
      end

      def all_scopes
        [
          Services::Ags::AGS_SCORE_SCOPE,
          Services::Ags::AGS_LINEITEM_SCOPE,
          Services::Ags::AGS_LINEITEM_RO_SCOPE,
          Services::Ags::AGS_RESULT_RO_SCOPE,
          Services::Nrps::NRPS_SCOPE
        ]
      end

      def create_platform(openid_config, client_data)
        issuer     = openid_config["issuer"]
        client_id  = client_data["client_id"]

        platform = Platform.find_or_initialize_by(issuer: issuer, client_id: client_id)
        platform.assign_attributes(
          oidc_auth_url: openid_config["authorization_endpoint"],
          jwks_url: openid_config["jwks_uri"],
          token_url: openid_config["token_endpoint"],
          registration_access_token: client_data["registration_access_token"],
          registration_client_uri: client_data["registration_client_uri"]
        )
        platform.save!
        platform
      end

      def conn
        @conn ||= Faraday.new do |f|
          f.adapter Faraday.default_adapter
        end
      end

      # Validate that a URL uses HTTPS (or HTTP for localhost in development).
      # Raises Error if the URL is invalid or uses a disallowed scheme.
      def validate_https_url!(url, param_name)
        parsed = URI.parse(url)
        unless parsed.is_a?(URI::HTTP) && %w[http https].include?(parsed.scheme)
          raise Error, "#{param_name} must be a valid HTTP/HTTPS URL"
        end
      rescue URI::InvalidURIError
        raise Error, "#{param_name} is not a valid URL"
      end
    end
  end
end
