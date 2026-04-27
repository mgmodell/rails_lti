# RailsLti

A mountable Rails engine that provides full **LTI 1.3 Advantage** support to any Rails application.

## Features

- **OIDC Launch Flow** – Handles the two-step login-initiation → authentication-response flow
- **Dynamic Registration** – Automatically registers with LTI 1.3 platforms that support it
- **Deep Linking** – Build Deep Linking responses with `ltiResourceLink`, `link`, `html`, `image`, and `file` content items
- **Assignment and Grade Services (AGS)** – List/create line items and push scores
- **Names and Roles Provisioning Services (NRPS)** – Fetch course membership lists
- **JWKS endpoint** – Exposes the tool's public key for platform-side JWT verification
- **Test Helpers** – `RailsLti::TestHelpers::LtiHelpers` for writing LTI integration tests

## Requirements

- Ruby ≥ 3.0
- Rails ≥ 7.0

## Installation

Add the gem to your application's `Gemfile`:

```ruby
gem "rails_lti"
```

Run the install generator:

```sh
rails generate rails_lti:install
rails db:migrate
```

The generator:
1. Copies the migration to your `db/migrate/`
2. Creates `config/initializers/rails_lti.rb`
3. Mounts the engine at `/lti` in `config/routes.rb`

## Configuration

Edit `config/initializers/rails_lti.rb`:

```ruby
RailsLti.configure do |config|
  # Base URL of your tool (required)
  config.tool_url = "https://mytool.example.com"

  # RSA private key for signing JWTs.
  # Generate: OpenSSL::PKey::RSA.generate(2048).to_pem
  # Store in Rails credentials or an environment variable.
  config.private_key = Rails.application.credentials.lti_private_key

  # Called after a successful LTI launch.
  # Return a URL string to override the redirect, or nil to use target_link_uri.
  config.after_launch = ->(controller, claims) {
    controller.session[:lti_user_id] = claims["sub"]
    controller.session[:lti_context_id] = claims.dig(
      "https://purl.imsglobal.org/spec/lti/claim/context", "id"
    )
    nil  # redirect to target_link_uri from the launch
  }

  # Called after a successful dynamic registration.
  config.after_registration = ->(controller, platform) {
    Rails.logger.info "Registered with platform: #{platform.issuer}"
  }
end
```

## Usage

### Platform Setup (Manual)

Create a `RailsLti::Platform` and `RailsLti::Deployment` record for each LTI platform:

```ruby
platform = RailsLti::Platform.create!(
  issuer:        "https://canvas.instructure.com",
  client_id:     "10000000000001",       # from Canvas developer key
  oidc_auth_url: "https://canvas.instructure.com/api/lti/authorize_redirect",
  jwks_url:      "https://canvas.instructure.com/api/lti/security/jwks",
  token_url:     "https://canvas.instructure.com/login/oauth2/token"
)

RailsLti::Deployment.create!(
  platform:      platform,
  client_id:     "10000000000001",
  deployment_id: "1"                     # from Canvas deployment
)
```

### Dynamic Registration

Direct the platform administrator to:

```
GET https://mytool.example.com/lti/registration?openid_configuration=<PLATFORM_CONFIG_URL>&registration_token=<TOKEN>
```

The engine will automatically fetch the platform configuration, register the tool, and create the `Platform` record.

### Accessing Launch Claims

After a successful launch, claims are stored in the session:

```ruby
# In your controller:
claims = session[:lti_launch_claims]

user_id       = claims["sub"]
user_name     = claims["name"]
context_id    = claims.dig("https://purl.imsglobal.org/spec/lti/claim/context", "id")
roles         = claims["https://purl.imsglobal.org/spec/lti/claim/roles"]
resource_link = claims["https://purl.imsglobal.org/spec/lti/claim/resource_link"]
deployment_id = session[:lti_deployment_id]   # RailsLti::Deployment#id
```

### Deep Linking

In your deep linking controller action:

```ruby
def create
  deployment = RailsLti::Deployment.find(session[:lti_deployment_id])
  dl_settings = session[:lti_launch_claims]
                  .dig("https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings")

  items = [
    RailsLti::Services::DeepLink::ContentItem.lti_resource_link(
      url:   "https://mytool.example.com/activities/#{@activity.id}",
      title: @activity.name
    )
  ]

  service = RailsLti::Services::DeepLink.new(deployment, dl_settings, items)
  @jwt     = service.build_response_jwt
  @return_url = service.return_url
  # Render a form that auto-posts the JWT back to return_url
end
```

### Pushing Grades (AGS)

```ruby
deployment = RailsLti::Deployment.find(session[:lti_deployment_id])
ags_claims  = session[:lti_launch_claims]
                .dig("https://purl.imsglobal.org/spec/lti-ags/claim/endpoint")

ags = RailsLti::Services::Ags.new(deployment, ags_claims)

# Submit a score
ags.submit_score(
  user_id:           session[:lti_launch_claims]["sub"],
  score:             85.0,
  score_maximum:     100.0,
  activity_progress: RailsLti::Services::Ags::ACTIVITY_PROGRESS_COMPLETED,
  grading_progress:  RailsLti::Services::Ags::GRADING_PROGRESS_FULLY_GRADED
)
```

### Fetching Membership (NRPS)

```ruby
deployment  = RailsLti::Deployment.find(session[:lti_deployment_id])
nrps_claims = session[:lti_launch_claims]
                .dig("https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice")

nrps    = RailsLti::Services::Nrps.new(deployment, nrps_claims)
members = nrps.members
# => [{ "userId" => "...", "roles" => [...], "name" => "..." }, ...]

# Filter by role
instructors = nrps.members(role: "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor")
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET/POST | `/lti/login` | OIDC login initiation |
| POST | `/lti/launch` | OIDC authentication response (receives `id_token`) |
| GET | `/lti/jwks` | Tool's public JWKS for platform signature verification |
| GET | `/lti/registration` | Dynamic registration endpoint |

## Test Helpers

Include `RailsLti::TestHelpers::LtiHelpers` in your test cases:

```ruby
class LtiIntegrationTest < ActionDispatch::IntegrationTest
  include RailsLti::TestHelpers::LtiHelpers

  def setup
    @platform, @deployment = create_test_platform_and_deployment(
      issuer:    "https://canvas.example.com",
      client_id: "test_client"
    )
  end

  test "LTI resource link launch" do
    # 1. Simulate login initiation
    get "/lti/login", params: build_oidc_login_params(@deployment)
    assert_response :redirect

    # 2. Build a signed id_token using the test key
    nonce = session[:lti_nonce]
    state = session[:lti_state]
    token = build_id_token(@deployment, claims: { "nonce" => nonce })

    # 3. Simulate launch
    post "/lti/launch", params: { id_token: token, state: state }
    assert_response :redirect
    assert session[:lti_authenticated]
  end

  test "LTI deep linking launch" do
    get "/lti/login", params: build_oidc_login_params(@deployment)
    nonce = session[:lti_nonce]
    state = session[:lti_state]

    token = build_id_token(@deployment,
                           message_type: "LtiDeepLinkingRequest",
                           claims: { "nonce" => nonce })

    post "/lti/launch", params: { id_token: token, state: state }
    assert_response :redirect
  end
end
```

### Available Helper Methods

| Method | Description |
|--------|-------------|
| `create_test_platform_and_deployment(...)` | Create a Platform + Deployment and stub JWKS |
| `build_id_token(deployment, ...)` | Build a signed LTI JWT |
| `build_oidc_login_params(deployment, ...)` | Build login initiation params hash |
| `store_test_nonce` | Create a nonce record and return its value |
| `stub_platform_jwks(url, ...)` | Stub the JWKS endpoint (WebMock) |
| `stub_platform_token_endpoint(url, ...)` | Stub the OAuth2 token endpoint (WebMock) |
| `lti_private_key` | Per-test RSA key (memoised) |
| `generate_rsa_key` | Generate a fresh RSA key |

## Maintenance

### Nonce Cleanup

Expired nonces should be cleaned up periodically. Run from a scheduled job or rake task:

```ruby
RailsLti::Nonce.cleanup_expired!
```

## License

MIT – see [LICENSE](LICENSE).

