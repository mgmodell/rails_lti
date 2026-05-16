# frozen_string_literal: true

require "test_helper"

module RailsLti
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    MOCK_OPENID_CONFIG = {
      "issuer" => "https://platform.example.com",
      "authorization_endpoint" => "https://platform.example.com/auth",
      "token_endpoint" => "https://platform.example.com/token",
      "jwks_uri" => "https://platform.example.com/jwks",
      "registration_endpoint" => "https://platform.example.com/register",
      "scopes_supported" => ["openid"],
      "response_types_supported" => ["id_token"],
      "subject_types_supported" => ["public"]
    }.freeze

    MOCK_CLIENT_DATA = {
      "client_id" => "dynamically_registered_client",
      "client_secret" => nil,
      "registration_access_token" => "reg_access_token",
      "registration_client_uri" => "https://platform.example.com/register/dynamically_registered_client"
    }.freeze

    def setup
      RailsLti.configure do |config|
        config.tool_url = "https://tool.example.com"
      end

      WebMock.stub_request(:get, "https://platform.example.com/.well-known/openid-configuration")
             .to_return(
               status: 200,
               body: MOCK_OPENID_CONFIG.to_json,
               headers: { "Content-Type" => "application/json" }
             )

      WebMock.stub_request(:post, "https://platform.example.com/register")
             .to_return(
               status: 201,
               body: MOCK_CLIENT_DATA.to_json,
               headers: { "Content-Type" => "application/json" }
             )

      stub_platform_jwks("https://platform.example.com/jwks")
    end

    def teardown
      RailsLti.reset_configuration!
      WebMock.reset!
    end

    test "GET /lti/registration creates a platform record" do
      assert_difference "RailsLti::Platform.count", 1 do
        get "/lti/registration", params: {
          openid_configuration: "https://platform.example.com/.well-known/openid-configuration",
          registration_token: "platform_reg_token"
        }
      end
      assert_response :success
    end

    test "GET /lti/registration stores client_id from platform response" do
      get "/lti/registration", params: {
        openid_configuration: "https://platform.example.com/.well-known/openid-configuration",
        registration_token: "platform_reg_token"
      }

      platform = RailsLti::Platform.find_by(issuer: "https://platform.example.com")
      assert platform
      assert_equal "dynamically_registered_client", platform.client_id
      assert_equal "reg_access_token", platform.registration_access_token
    end

    test "GET /lti/registration returns 400 without openid_configuration param" do
      get "/lti/registration"
      assert_response :bad_request
    end

    test "GET /lti/registration returns 400 when platform registration endpoint fails" do
      WebMock.stub_request(:post, "https://platform.example.com/register")
             .to_return(status: 500, body: "Server error")

      get "/lti/registration", params: {
        openid_configuration: "https://platform.example.com/.well-known/openid-configuration"
      }
      assert_response :bad_request
    end

    test "GET /lti/registration renders success view on completion" do
      get "/lti/registration", params: {
        openid_configuration: "https://platform.example.com/.well-known/openid-configuration"
      }
      assert_response :success
      assert_match /Registered Successfully/, response.body
    end

    test "GET /lti/registration calls after_registration callback if configured" do
      callback_called = false
      RailsLti.configuration.after_registration = ->(_controller, _platform) { callback_called = true }

      get "/lti/registration", params: {
        openid_configuration: "https://platform.example.com/.well-known/openid-configuration"
      }

      assert callback_called
    end
  end
end
