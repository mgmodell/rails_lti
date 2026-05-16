# frozen_string_literal: true

require "test_helper"

module RailsLti
  module Services
    class DynamicRegistrationTest < ActiveSupport::TestCase
      MOCK_OPENID_CONFIG = {
        "issuer" => "https://platform.example.com",
        "authorization_endpoint" => "https://platform.example.com/auth",
        "token_endpoint" => "https://platform.example.com/token",
        "jwks_uri" => "https://platform.example.com/jwks",
        "registration_endpoint" => "https://platform.example.com/register"
      }.freeze

      MOCK_CLIENT_DATA = {
        "client_id" => "dynamic_client_001",
        "registration_access_token" => "reg_token",
        "registration_client_uri" => "https://platform.example.com/register/dynamic_client_001"
      }.freeze

      def setup
        RailsLti.configure do |config|
          config.tool_url = "https://tool.example.com"
        end

        WebMock.stub_request(:get, "https://platform.example.com/.well-known/openid-configuration")
               .to_return(status: 200, body: MOCK_OPENID_CONFIG.to_json,
                          headers: { "Content-Type" => "application/json" })

        WebMock.stub_request(:post, "https://platform.example.com/register")
               .to_return(status: 201, body: MOCK_CLIENT_DATA.to_json,
                          headers: { "Content-Type" => "application/json" })
      end

      def teardown
        RailsLti.reset_configuration!
        WebMock.reset!
      end

      test "fetch_openid_configuration returns parsed JSON" do
        service = DynamicRegistration.new(
          openid_configuration_url: "https://platform.example.com/.well-known/openid-configuration",
          tool_url: "https://tool.example.com"
        )
        config = service.fetch_openid_configuration
        assert_equal "https://platform.example.com", config["issuer"]
      end

      test "register! creates a platform record" do
        service = DynamicRegistration.new(
          openid_configuration_url: "https://platform.example.com/.well-known/openid-configuration",
          tool_url: "https://tool.example.com"
        )
        assert_difference "Platform.count", 1 do
          service.register!(MOCK_OPENID_CONFIG)
        end
      end

      test "register! sets correct platform attributes" do
        service = DynamicRegistration.new(
          openid_configuration_url: "https://platform.example.com/.well-known/openid-configuration",
          tool_url: "https://tool.example.com"
        )
        platform = service.register!(MOCK_OPENID_CONFIG)

        assert_equal "https://platform.example.com", platform.issuer
        assert_equal "dynamic_client_001", platform.client_id
        assert_equal "https://platform.example.com/auth", platform.oidc_auth_url
        assert_equal "reg_token", platform.registration_access_token
      end

      test "raises Error for invalid openid_configuration_url scheme" do
        assert_raises(DynamicRegistration::Error) do
          DynamicRegistration.new(
            openid_configuration_url: "ftp://platform.example.com/config",
            tool_url: "https://tool.example.com"
          )
        end
      end

      test "raises Error for malformed openid_configuration_url" do
        assert_raises(DynamicRegistration::Error) do
          DynamicRegistration.new(
            openid_configuration_url: "not a url at all",
            tool_url: "https://tool.example.com"
          )
        end
      end

      test "raises Error when platform registration endpoint returns error" do
        WebMock.stub_request(:post, "https://platform.example.com/register")
               .to_return(status: 400, body: "Bad Request")

        service = DynamicRegistration.new(
          openid_configuration_url: "https://platform.example.com/.well-known/openid-configuration",
          tool_url: "https://tool.example.com"
        )
        assert_raises(DynamicRegistration::Error) do
          service.register!(MOCK_OPENID_CONFIG)
        end
      end

      test "raises Error when registration_endpoint is missing from openid_config" do
        config_without_endpoint = MOCK_OPENID_CONFIG.except("registration_endpoint")
        service = DynamicRegistration.new(
          openid_configuration_url: "https://platform.example.com/.well-known/openid-configuration",
          tool_url: "https://tool.example.com"
        )
        assert_raises(DynamicRegistration::Error) do
          service.register!(config_without_endpoint)
        end
      end
    end
  end
end
