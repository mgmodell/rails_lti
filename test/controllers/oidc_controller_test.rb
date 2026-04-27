# frozen_string_literal: true

require "test_helper"

module RailsLti
  class OidcControllerTest < ActionDispatch::IntegrationTest
    def setup
      RailsLti.configure do |config|
        config.tool_url = "https://tool.example.com"
        config.private_key = generate_rsa_key
      end

      @platform, @deployment = create_test_platform_and_deployment(
        issuer: "https://platform.example.com",
        client_id: "client_001"
      )
    end

    def teardown
      RailsLti.reset_configuration!
    end

    # -------------------------------------------------------------------------
    # JWKS endpoint
    # -------------------------------------------------------------------------

    test "GET /lti/jwks returns public JWKS" do
      get "/lti/jwks"
      assert_response :success
      json = JSON.parse(response.body)
      assert json.key?("keys")
      assert_equal 1, json["keys"].length
      assert_equal "RS256", json["keys"].first["alg"]
    end

    # -------------------------------------------------------------------------
    # OIDC Login
    # -------------------------------------------------------------------------

    test "GET /lti/login redirects to platform auth endpoint" do
      get "/lti/login", params: {
        iss: @platform.issuer,
        login_hint: "user123",
        target_link_uri: "https://tool.example.com/lti/launch",
        client_id: @platform.client_id
      }
      assert_response :redirect
      assert_includes response.location, @platform.oidc_auth_url
      assert_includes response.location, "response_type=id_token"
      assert_includes response.location, "nonce="
      assert_includes response.location, "state="
    end

    test "POST /lti/login also redirects to platform auth endpoint" do
      post "/lti/login", params: {
        iss: @platform.issuer,
        login_hint: "user123",
        target_link_uri: "https://tool.example.com/lti/launch",
        client_id: @platform.client_id
      }
      assert_response :redirect
    end

    test "GET /lti/login returns 400 if iss is missing" do
      get "/lti/login", params: {
        login_hint: "user123",
        target_link_uri: "https://tool.example.com/lti/launch"
      }
      assert_response :bad_request
    end

    test "GET /lti/login returns 400 if login_hint is missing" do
      get "/lti/login", params: {
        iss: @platform.issuer,
        target_link_uri: "https://tool.example.com/lti/launch"
      }
      assert_response :bad_request
    end

    test "GET /lti/login returns 400 if target_link_uri is missing" do
      get "/lti/login", params: {
        iss: @platform.issuer,
        login_hint: "user123"
      }
      assert_response :bad_request
    end

    test "GET /lti/login returns 400 for unknown platform" do
      get "/lti/login", params: {
        iss: "https://unknown.example.com",
        login_hint: "user123",
        target_link_uri: "https://tool.example.com/lti/launch"
      }
      assert_response :bad_request
    end

    test "login stores state and nonce in session" do
      get "/lti/login", params: {
        iss: @platform.issuer,
        login_hint: "user123",
        target_link_uri: "https://tool.example.com/lti/launch",
        client_id: @platform.client_id
      }
      assert session[:lti_state].present?
      assert session[:lti_nonce].present?
    end

    test "login creates a Nonce record in the database" do
      assert_difference "RailsLti::Nonce.count", 1 do
        get "/lti/login", params: {
          iss: @platform.issuer,
          login_hint: "user123",
          target_link_uri: "https://tool.example.com/lti/launch",
          client_id: @platform.client_id
        }
      end
    end

    # -------------------------------------------------------------------------
    # Launch (authentication response)
    # -------------------------------------------------------------------------

    test "POST /lti/launch with valid id_token redirects to target_link_uri" do
      nonce = store_test_nonce
      state = "test_state_#{SecureRandom.hex(8)}"

      id_token = build_id_token(
        @deployment,
        claims: { "nonce" => nonce }
      )

      # Simulate a prior login request having set session values
      post "/lti/login", params: {
        iss: @platform.issuer,
        login_hint: "user123",
        target_link_uri: "https://tool.example.com/launch_destination",
        client_id: @platform.client_id,
        lti_deployment_id: @deployment.deployment_id
      }

      # Now extract state and nonce from session to create a valid token
      nonce_from_session = session[:lti_nonce]
      state_from_session = session[:lti_state]

      # Create a token using the nonce from the session
      id_token = build_id_token(
        @deployment,
        claims: { "nonce" => nonce_from_session }
      )

      post "/lti/launch", params: {
        id_token: id_token,
        state: state_from_session
      }

      assert_response :redirect
      assert session[:lti_authenticated]
      assert session[:lti_launch_claims].present?
    end

    test "POST /lti/launch returns 400 with state mismatch" do
      post "/lti/login", params: {
        iss: @platform.issuer,
        login_hint: "user123",
        target_link_uri: "https://tool.example.com/launch",
        client_id: @platform.client_id,
        lti_deployment_id: @deployment.deployment_id
      }

      nonce = session[:lti_nonce]
      id_token = build_id_token(@deployment, claims: { "nonce" => nonce })

      post "/lti/launch", params: {
        id_token: id_token,
        state: "wrong_state"
      }

      assert_response :bad_request
    end

    test "POST /lti/launch returns 400 if id_token is missing" do
      post "/lti/launch", params: { state: "some_state" }
      assert_response :bad_request
    end

    test "POST /lti/launch returns 400 if state is missing" do
      post "/lti/launch", params: { id_token: "some_token" }
      assert_response :bad_request
    end

    test "POST /lti/launch rejects replayed nonces" do
      # Do the full login flow
      post "/lti/login", params: {
        iss: @platform.issuer,
        login_hint: "user123",
        target_link_uri: "https://tool.example.com/launch",
        client_id: @platform.client_id,
        lti_deployment_id: @deployment.deployment_id
      }

      nonce_value = session[:lti_nonce]
      state_value = session[:lti_state]

      id_token = build_id_token(@deployment, claims: { "nonce" => nonce_value })

      # First launch – should succeed
      post "/lti/launch", params: { id_token: id_token, state: state_value }
      assert_response :redirect

      # Second launch with same token – nonce already consumed, should fail
      # Start a new session
      post "/lti/login", params: {
        iss: @platform.issuer,
        login_hint: "user456",
        target_link_uri: "https://tool.example.com/launch",
        client_id: @platform.client_id,
        lti_deployment_id: @deployment.deployment_id
      }
      second_state = session[:lti_state]

      # Inject the old nonce into session to simulate a replay
      session[:lti_nonce] = nonce_value

      post "/lti/launch", params: { id_token: id_token, state: second_state }
      assert_response :bad_request
    end
  end
end
