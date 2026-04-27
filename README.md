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

---

## Table of Contents

1. [How LTI 1.3 Works](#how-lti-13-works)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Generating and Storing Your RSA Key](#generating-and-storing-your-rsa-key)
5. [Platform Setup](#platform-setup)
   - [Automatic – Dynamic Registration](#automatic--dynamic-registration)
   - [Manual – Canvas](#manual--canvas)
   - [Manual – Moodle](#manual--moodle)
   - [Manual – Blackboard / Anthology](#manual--blackboard--anthology)
6. [Handling the Post-Launch Landing Page](#handling-the-post-launch-landing-page)
7. [Session Reference](#session-reference)
8. [Deep Linking](#deep-linking)
9. [Pushing Grades (AGS)](#pushing-grades-ags)
10. [Fetching Membership (NRPS)](#fetching-membership-nrps)
11. [Endpoints Reference](#endpoints-reference)
12. [Test Helpers](#test-helpers)
13. [Maintenance](#maintenance)
14. [Migrating from Another LTI Library](#migrating-from-another-lti-library)

---

## How LTI 1.3 Works

LTI 1.3 uses the **OpenID Connect (OIDC) implicit flow** to launch tools from a platform (Canvas, Moodle, etc.). The engine handles this automatically, but understanding the flow helps when debugging.

```
Platform (Canvas, Moodle…)          Your Tool (Rails app)
────────────────────────────        ──────────────────────────────────────
1. User clicks tool link
   POST/GET →  /lti/login           2. Validate request, generate state+nonce,
               (iss, login_hint,       store in session, redirect to platform's
                target_link_uri)       OIDC auth endpoint

                                    ← redirect to platform OIDC auth URL

3. Platform authenticates user,
   signs id_token JWT, and
   POST → /lti/launch               4. Validate state (anti-CSRF), validate JWT
          (id_token, state)            (signature, nonce, claims), store claims
                                       in session, redirect to target_link_uri

                                    ← redirect to your app's landing page
```

**Key security properties:**
- The `state` parameter prevents CSRF attacks during the launch.
- The `nonce` inside the JWT is stored in the database and consumed on first use, preventing replay attacks.
- The JWT signature is verified against the platform's public JWKS.

---

## Installation

Add the gem to your application's `Gemfile`:

```ruby
gem "rails_lti"
```

Run the install generator:

```sh
bundle install
rails generate rails_lti:install
rails db:migrate
```

The generator does three things:
1. Copies the migration (creates `rails_lti_platforms`, `rails_lti_deployments`, `rails_lti_nonces` tables)
2. Creates `config/initializers/rails_lti.rb` with commented-out options
3. Adds `mount RailsLti::Engine => "/lti"` to `config/routes.rb`

---

## Configuration

Edit `config/initializers/rails_lti.rb`. The minimum required settings are `tool_url` and `private_key`:

```ruby
RailsLti.configure do |config|
  # Required: base URL of your tool (no trailing slash)
  config.tool_url = "https://mytool.example.com"

  # Required in production: RSA private key for signing JWTs
  # See "Generating and Storing Your RSA Key" below
  config.private_key = Rails.application.credentials.lti_private_key

  # Optional: path where the engine is mounted (default: "/lti")
  # Must match config/routes.rb
  # config.mount_path = "/lti"

  # Optional: nonce expiry in seconds (default: 300)
  # config.nonce_ttl = 300

  # Optional: called after a successful LTI launch.
  # Return a URL string to redirect to, or nil to follow target_link_uri.
  config.after_launch = ->(controller, claims) {
    # Map the LTI user to your app's user model
    lti_user_id = claims["sub"]
    user = User.find_or_create_by!(lti_user_id: lti_user_id) do |u|
      u.name  = claims["name"]
      u.email = claims["email"]
    end
    controller.session[:user_id] = user.id
    nil  # redirect to target_link_uri
  }

  # Optional: called after successful dynamic registration
  config.after_registration = ->(controller, platform) {
    Rails.logger.info "Registered with #{platform.issuer} (client_id: #{platform.client_id})"
  }
end
```

### All Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `tool_url` | `nil` | Base URL of your tool. **Required.** |
| `private_key` | auto-generated | RSA private key for signing JWTs. Auto-generated key is not safe for multi-process production. **Set explicitly.** |
| `mount_path` | `"/lti"` | Path prefix for all engine routes. Must match `routes.rb`. |
| `jwks_path` | `"/jwks"` | Path for the JWKS endpoint, relative to `mount_path`. |
| `nonce_ttl` | `300` | Nonce expiry in seconds. |
| `state_ttl` | `300` | State expiry in seconds (informational; enforced by session). |
| `after_launch` | `nil` | Proc called after a successful launch. Receives `(controller, claims)`. Return a redirect URL or `nil`. |
| `after_deep_link` | `nil` | Proc called after deep link content selection (reserved for future use). |
| `after_registration` | `nil` | Proc called after dynamic registration. Receives `(controller, platform)`. |

---

## Generating and Storing Your RSA Key

The engine uses an RSA-2048 key pair to:
- Sign deep linking response JWTs
- Sign `client_credentials` assertions when fetching AGS/NRPS access tokens

The tool's **public key** is exposed at `GET /lti/jwks` so platforms can verify signatures.

### Step 1 — Generate a key

In a Rails console or a one-off script:

```ruby
require "openssl"
key = OpenSSL::PKey::RSA.generate(2048)
puts key.to_pem          # private key – keep secret
puts key.public_key.to_pem  # public key – shared via JWKS
```

### Step 2 — Store it securely

**Option A: Rails credentials (recommended)**

```sh
rails credentials:edit
```

Add:

```yaml
lti_private_key: |
  -----BEGIN RSA PRIVATE KEY-----
  MIIEowIBAAKCAQEA...
  -----END RSA PRIVATE KEY-----
```

Then in `config/initializers/rails_lti.rb`:

```ruby
config.private_key = Rails.application.credentials.lti_private_key
```

**Option B: Environment variable**

```sh
export LTI_PRIVATE_KEY="$(cat /path/to/lti_private_key.pem)"
```

```ruby
config.private_key = ENV["LTI_PRIVATE_KEY"]
```

> **Important:** Use the same key across all application processes and deployments. Rotating the key invalidates existing deep link JWTs and `client_credentials` registrations.

---

## Platform Setup

### Automatic – Dynamic Registration

Platforms that support [LTI Advantage Dynamic Registration](https://www.imsglobal.org/spec/lti-dr/v1p0) (Canvas, Open edX, etc.) can register your tool automatically.

Direct the platform administrator to:

```
GET https://mytool.example.com/lti/registration
    ?openid_configuration=<PLATFORM_OPENID_CONFIG_URL>
    &registration_token=<OPTIONAL_BEARER_TOKEN>
```

The engine will:
1. Fetch the platform's OpenID configuration
2. POST a registration payload to the platform's `registration_endpoint`
3. Create a `RailsLti::Platform` record with the returned `client_id`
4. Display a "registered successfully" page (or call `after_registration`)

You still need to create at least one `RailsLti::Deployment` record for the deployment ID the platform assigns:

```ruby
platform = RailsLti::Platform.find_by(issuer: "https://canvas.instructure.com")

RailsLti::Deployment.create!(
  platform:      platform,
  client_id:     platform.client_id,
  deployment_id: "1"   # from the platform's tool configuration UI
)
```

---

### Manual – Canvas

In Canvas: **Admin → Developer Keys → + LTI Key**, then **Settings**:

| Canvas field | Value |
|---|---|
| Target Link URI | `https://mytool.example.com/lti/launch` |
| OpenID Connect Initiation URL | `https://mytool.example.com/lti/login` |
| JWK Method | Public JWK URL → `https://mytool.example.com/lti/jwks` |
| Redirect URIs | `https://mytool.example.com/lti/launch` |

After saving, Canvas shows the **Client ID**. Enable the developer key and add it to a course via **External Apps → + App → By Client ID**.

Create the records in a Rails console or seed:

```ruby
platform = RailsLti::Platform.find_or_create_by!(
  issuer:    "https://canvas.instructure.com",
  client_id: "10000000000001"   # your Canvas Client ID
) do |p|
  p.oidc_auth_url = "https://canvas.instructure.com/api/lti/authorize_redirect"
  p.jwks_url      = "https://canvas.instructure.com/api/lti/security/jwks"
  p.token_url     = "https://canvas.instructure.com/login/oauth2/token"
end

RailsLti::Deployment.create!(
  platform:      platform,
  client_id:     platform.client_id,
  deployment_id: "1"   # shown in Canvas → Course → External Apps → tool details
)
```

---

### Manual – Moodle

In Moodle: **Site administration → Plugins → External tool → Manage tools → + Add LTI Advantage tool**:

| Moodle field | Value |
|---|---|
| Tool URL | `https://mytool.example.com/lti/launch` |
| LTI version | LTI 1.3 |
| Client ID | (auto-generated; copy it after saving) |
| Initiate login URL | `https://mytool.example.com/lti/login` |
| Redirection URI(s) | `https://mytool.example.com/lti/launch` |
| Public keyset URL | `https://mytool.example.com/lti/jwks` |

```ruby
platform = RailsLti::Platform.find_or_create_by!(
  issuer:    "https://moodle.example.com",
  client_id: "moodle_client_id"   # from Moodle tool config
) do |p|
  p.oidc_auth_url = "https://moodle.example.com/mod/lti/auth.php"
  p.jwks_url      = "https://moodle.example.com/mod/lti/certs.php"
  p.token_url     = "https://moodle.example.com/mod/lti/token.php"
end

RailsLti::Deployment.create!(
  platform:      platform,
  client_id:     platform.client_id,
  deployment_id: "1"
)
```

---

### Manual – Blackboard / Anthology

In Blackboard: **Admin Panel → LTI Tool Providers → Register LTI 1.3 Tool**:

| Blackboard field | Value |
|---|---|
| Client ID | (provided by Blackboard after initial registration; see docs) |
| Target Link URI | `https://mytool.example.com/lti/launch` |
| OIDC Login Init URL | `https://mytool.example.com/lti/login` |
| Tool Public Key URL | `https://mytool.example.com/lti/jwks` |

```ruby
platform = RailsLti::Platform.find_or_create_by!(
  issuer:    "https://blackboard.example.com",
  client_id: "blackboard_client_id"
) do |p|
  p.oidc_auth_url = "https://blackboard.example.com/api/v1/gateway/oauth2/jwttoken"
  p.jwks_url      = "https://blackboard.example.com/api/v1/gateway/oauth2/jwks.json"
  p.token_url     = "https://blackboard.example.com/api/v1/gateway/oauth2/token"
end

RailsLti::Deployment.create!(
  platform:      platform,
  client_id:     platform.client_id,
  deployment_id: "1"
)
```

---

## Handling the Post-Launch Landing Page

After a successful launch the engine redirects to the `target_link_uri` (or the URL returned by `after_launch`). You need a controller action at that URL to present your tool's content.

### Example: a shared `LtiConcern`

```ruby
# app/controllers/concerns/lti_concern.rb
module LtiConcern
  extend ActiveSupport::Concern

  included do
    before_action :require_lti_launch, only: [:show, :index]
  end

  private

  def require_lti_launch
    redirect_to root_path, alert: "Please launch this tool from your LMS." \
      unless session[:lti_authenticated]
  end

  def lti_claims
    session[:lti_launch_claims] || {}
  end

  def lti_user_id
    lti_claims["sub"]
  end

  def lti_context_id
    lti_claims.dig("https://purl.imsglobal.org/spec/lti/claim/context", "id")
  end

  def lti_roles
    lti_claims["https://purl.imsglobal.org/spec/lti/claim/roles"] || []
  end

  def lti_instructor?
    lti_roles.any? { |r| r.include?("Instructor") || r.include?("Teacher") }
  end

  def lti_deployment
    @lti_deployment ||= RailsLti::Deployment.find(session[:lti_deployment_id])
  end
end
```

```ruby
# app/controllers/activities_controller.rb
class ActivitiesController < ApplicationController
  include LtiConcern

  def show
    @activity = Activity.find(params[:id])
    @user     = current_user  # set by after_launch callback
  end
end
```

### Using `after_launch` to integrate with your user model

The `after_launch` callback fires before the redirect, giving you a chance to log the user in:

```ruby
# config/initializers/rails_lti.rb
RailsLti.configure do |config|
  config.tool_url   = "https://mytool.example.com"
  config.private_key = Rails.application.credentials.lti_private_key

  config.after_launch = ->(controller, claims) {
    user = User.find_or_create_by!(lti_user_id: claims["sub"]) do |u|
      u.name  = claims["name"]
      u.email = claims["email"]
    end

    # Store the user in the session the same way your app normally does
    controller.session[:user_id] = user.id

    # Return nil to follow target_link_uri, or return a URL string to override
    nil
  }
end
```

---

## Session Reference

The engine writes the following keys to the Rails session during the launch flow:

| Key | Type | Description |
|-----|------|-------------|
| `session[:lti_authenticated]` | `true` | Set after a successful launch. Use this as a gate in `before_action`. |
| `session[:lti_launch_claims]` | `Hash` | Full decoded JWT payload from the platform. |
| `session[:lti_deployment_id]` | `Integer` | Database ID of the `RailsLti::Deployment` record. |

The following keys are present **during the login/launch handshake only** and are deleted after a successful launch:

| Key | Description |
|-----|-------------|
| `session[:lti_state]` | CSRF state token. Compared on launch. |
| `session[:lti_nonce]` | Nonce value. Compared against JWT and DB. |
| `session[:lti_target_link_uri]` | Redirect destination after launch. |
| `session[:lti_platform_id]` | Database ID of the `RailsLti::Platform`. |

### Commonly Used Claims

```ruby
claims = session[:lti_launch_claims]

# User identity
claims["sub"]           # LTI user ID (stable, opaque)
claims["name"]          # Full name
claims["given_name"]    # First name
claims["family_name"]   # Last name
claims["email"]         # Email (if granted)

# Context (course/group)
context = claims["https://purl.imsglobal.org/spec/lti/claim/context"]
context["id"]           # Course ID
context["title"]        # Course name
context["label"]        # Short course code

# Roles (IMS Global role URIs)
claims["https://purl.imsglobal.org/spec/lti/claim/roles"]
# e.g. ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"]

# Resource link (the specific tool placement)
link = claims["https://purl.imsglobal.org/spec/lti/claim/resource_link"]
link["id"]              # Stable ID of this placement
link["title"]           # Title set by instructor
link["description"]     # Optional description

# Message type
claims["https://purl.imsglobal.org/spec/lti/claim/message_type"]
# "LtiResourceLinkRequest" or "LtiDeepLinkingRequest"

# AGS endpoint (for grade pushing)
ags = claims["https://purl.imsglobal.org/spec/lti-ags/claim/endpoint"]

# NRPS endpoint (for roster)
nrps = claims["https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice"]

# Deep linking settings (present on LtiDeepLinkingRequest only)
dl = claims["https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"]
```

---

## Deep Linking

Deep Linking lets an instructor select content from your tool that is then embedded in the course. The flow is:

1. Instructor opens the tool from a "content selection" placement (sends `LtiDeepLinkingRequest`)
2. Your tool presents a content picker UI
3. The instructor selects content; your tool builds a signed JWT and POSTs it back to the platform

### Detecting a Deep Linking launch

```ruby
# In your controller or concern:
def deep_linking_launch?
  session[:lti_launch_claims]
    &.dig("https://purl.imsglobal.org/spec/lti/claim/message_type") == "LtiDeepLinkingRequest"
end
```

### Building the response

```ruby
# app/controllers/content_picker_controller.rb
class ContentPickerController < ApplicationController
  include LtiConcern

  # GET /content_picker — show the picker UI
  def index
    @activities = Activity.all
  end

  # POST /content_picker — instructor has selected; return items to platform
  def create
    deployment  = lti_deployment
    dl_settings = lti_claims["https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"]

    items = params[:activity_ids].map do |id|
      activity = Activity.find(id)
      RailsLti::Services::DeepLink::ContentItem.lti_resource_link(
        url:   activity_url(activity),
        title: activity.name,
        text:  activity.description,
        # Optionally create a grade column at the same time:
        line_item: {
          scoreMaximum: 100,
          label:        activity.name,
          resourceId:   activity.id.to_s
        }
      )
    end

    service = RailsLti::Services::DeepLink.new(deployment, dl_settings, items)
    @jwt        = service.build_response_jwt
    @return_url = service.return_url
    render :return_to_platform
  end
end
```

### Auto-post view template

The platform expects an HTML form that auto-submits the JWT. Create `app/views/content_picker/return_to_platform.html.erb`:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Returning to platform…</title>
  </head>
  <body>
    <p>Sending your selection back to the course…</p>
    <%= form_tag @return_url, id: "lti_form", method: :post do %>
      <%= hidden_field_tag "JWT", @jwt %>
    <% end %>
    <script>document.getElementById("lti_form").submit();</script>
  </body>
</html>
```

### Available content item types

```ruby
# LTI Resource Link — embeds a tool launch in the course
RailsLti::Services::DeepLink::ContentItem.lti_resource_link(
  url:          "https://mytool.example.com/activities/1",
  title:        "Week 1 Quiz",
  text:         "Optional description shown to students",
  custom_params: { "activity_id" => "1" },   # passed back on launch
  line_item:    { scoreMaximum: 100, label: "Week 1 Quiz" }  # creates grade column
)

# External link
RailsLti::Services::DeepLink::ContentItem.link(
  url:   "https://example.com/resource",
  title: "Reading Material"
)

# Embedded HTML
RailsLti::Services::DeepLink::ContentItem.html_fragment(
  html:   "<p>Hello from the tool!</p>",
  width:  800,
  height: 400
)

# Image
RailsLti::Services::DeepLink::ContentItem.image(
  url:    "https://mytool.example.com/images/diagram.png",
  title:  "Diagram",
  width:  600,
  height: 400
)

# File download
RailsLti::Services::DeepLink::ContentItem.file(
  url:        "https://mytool.example.com/exports/data.csv",
  media_type: "text/csv",
  title:      "Export Data"
)
```

---

## Pushing Grades (AGS)

Assignment and Grade Services let your tool push scores back to the platform's gradebook.

### Prerequisites

The `LtiResourceLinkRequest` JWT must include an AGS endpoint claim (platforms grant this when you configure the required scopes on the developer key). Check its presence before using AGS:

```ruby
ags_claims = session[:lti_launch_claims]
               &.dig("https://purl.imsglobal.org/spec/lti-ags/claim/endpoint")

unless ags_claims
  # Platform did not grant AGS for this launch
end
```

### Submit a score

```ruby
deployment = RailsLti::Deployment.find(session[:lti_deployment_id])
ags        = RailsLti::Services::Ags.new(deployment, ags_claims)

ags.submit_score(
  user_id:           session[:lti_launch_claims]["sub"],
  score:             85.0,
  score_maximum:     100.0,
  activity_progress: RailsLti::Services::Ags::ACTIVITY_PROGRESS_COMPLETED,
  grading_progress:  RailsLti::Services::Ags::GRADING_PROGRESS_FULLY_GRADED,
  comment:           "Well done!"          # optional
)
```

### Activity and grading progress constants

```ruby
# Activity progress — what the student has done
RailsLti::Services::Ags::ACTIVITY_PROGRESS_INITIALIZED   # "Initialized"
RailsLti::Services::Ags::ACTIVITY_PROGRESS_STARTED       # "Started"
RailsLti::Services::Ags::ACTIVITY_PROGRESS_IN_PROGRESS   # "InProgress"
RailsLti::Services::Ags::ACTIVITY_PROGRESS_SUBMITTED     # "Submitted"
RailsLti::Services::Ags::ACTIVITY_PROGRESS_COMPLETED     # "Completed"

# Grading progress — whether the grade is final
RailsLti::Services::Ags::GRADING_PROGRESS_NOT_READY      # "NotReady"
RailsLti::Services::Ags::GRADING_PROGRESS_FAILED         # "Failed"
RailsLti::Services::Ags::GRADING_PROGRESS_PENDING        # "Pending"
RailsLti::Services::Ags::GRADING_PROGRESS_PENDING_MANUAL # "PendingManual"
RailsLti::Services::Ags::GRADING_PROGRESS_FULLY_GRADED   # "FullyGraded"
```

### Managing line items

```ruby
# List all grade columns for this placement
line_items = ags.list_line_items

# Create a new grade column
line_item = ags.create_line_item(
  label:         "Final Exam",
  score_maximum: 100.0,
  resource_id:   "exam_42",   # optional; your internal ID
  tag:           "final"       # optional; filter tag
)

# Submit to a specific line item by URL
ags.submit_score(
  user_id:           "user_sub",
  score:             90.0,
  score_maximum:     100.0,
  lineitem_url:      line_item["id"],
  activity_progress: RailsLti::Services::Ags::ACTIVITY_PROGRESS_COMPLETED,
  grading_progress:  RailsLti::Services::Ags::GRADING_PROGRESS_FULLY_GRADED
)

# Retrieve results
results = ags.get_results
results = ags.get_results(lineitem_url: line_item["id"])
```

---

## Fetching Membership (NRPS)

Names and Roles Provisioning Services give you the full roster for the current course context.

```ruby
deployment  = RailsLti::Deployment.find(session[:lti_deployment_id])
nrps_claims = session[:lti_launch_claims]
                &.dig("https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice")

unless nrps_claims
  # Platform did not grant NRPS for this launch
end

nrps = RailsLti::Services::Nrps.new(deployment, nrps_claims)

# All members (handles pagination automatically)
members = nrps.members
# => [{ "userId" => "abc", "roles" => [...], "name" => "Alice" }, ...]

# Filter by IMS role URI
instructors = nrps.members(
  role: "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
)
learners = nrps.members(
  role: "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
)
```

### Common role URIs

| Role | URI |
|------|-----|
| Instructor | `http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor` |
| Learner / Student | `http://purl.imsglobal.org/vocab/lis/v2/membership#Learner` |
| Teaching Assistant | `http://purl.imsglobal.org/vocab/lis/v2/membership#TeachingAssistant` |
| Content Developer | `http://purl.imsglobal.org/vocab/lis/v2/membership#ContentDeveloper` |
| Administrator | `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Administrator` |

---

## Endpoints Reference

The engine mounts these routes under `mount_path` (default `/lti`):

| Method | Path | Description |
|--------|------|-------------|
| `GET` / `POST` | `/lti/login` | Step 1 of OIDC launch. Platform sends `iss`, `login_hint`, `target_link_uri`. |
| `POST` | `/lti/launch` | Step 2 of OIDC launch. Platform posts the signed `id_token` and `state`. |
| `GET` | `/lti/jwks` | Tool's public JWKS. Platforms use this to verify deep link JWTs. |
| `GET` | `/lti/registration` | Dynamic Registration. Requires `openid_configuration` query param. |

Configure these URLs in your platform's developer key / LTI tool settings.

---

## Test Helpers

Add `rails_lti` as a development/test dependency if you don't want it in production, then include the helpers:

```ruby
# test/test_helper.rb (or spec/rails_helper.rb for RSpec)
require "rails_lti/test_helpers/lti_helpers"

class ActiveSupport::TestCase
  include RailsLti::TestHelpers::LtiHelpers
end
```

Configure a stable private key so JWTs are verifiable across all tests:

```ruby
# test/test_helper.rb
RailsLti.configure do |config|
  config.tool_url    = "https://tool.example.com"
  config.private_key = File.read(Rails.root.join("test/fixtures/lti_private_key.pem"))
end
```

Generate a fixture key once:
```sh
ruby -e "require 'openssl'; puts OpenSSL::PKey::RSA.generate(2048).to_pem" \
  > test/fixtures/lti_private_key.pem
```

### Complete integration test example

```ruby
class LtiLaunchTest < ActionDispatch::IntegrationTest
  include RailsLti::TestHelpers::LtiHelpers

  def setup
    # Creates Platform + Deployment records and stubs the JWKS endpoint
    @platform, @deployment = create_test_platform_and_deployment(
      issuer:    "https://canvas.example.com",
      client_id: "test_client_001"
    )
  end

  # ── Resource Link Launch ──────────────────────────────────────────────────

  test "resource link launch redirects to target_link_uri" do
    # Step 1: simulate login initiation from platform
    get "/lti/login", params: build_oidc_login_params(@deployment,
      target_link_uri: "https://tool.example.com/activities/42"
    )
    assert_response :redirect
    assert_includes response.location, @platform.oidc_auth_url

    # Step 2: simulate authentication response from platform
    token = build_id_token(@deployment, claims: { "nonce" => session[:lti_nonce] })
    post "/lti/launch", params: { id_token: token, state: session[:lti_state] }

    assert_response :redirect
    assert session[:lti_authenticated]
    assert_not_nil session[:lti_launch_claims]
    assert_equal @deployment.id, session[:lti_deployment_id]
  end

  test "launch stores user sub in claims" do
    get "/lti/login", params: build_oidc_login_params(@deployment)
    token = build_id_token(@deployment,
      claims: { "nonce" => session[:lti_nonce], "sub" => "student_99" }
    )
    post "/lti/launch", params: { id_token: token, state: session[:lti_state] }

    assert_equal "student_99", session[:lti_launch_claims]["sub"]
  end

  # ── Deep Linking Launch ───────────────────────────────────────────────────

  test "deep linking launch sets message_type in claims" do
    get "/lti/login", params: build_oidc_login_params(@deployment)
    token = build_id_token(@deployment,
      message_type: "LtiDeepLinkingRequest",
      claims: { "nonce" => session[:lti_nonce] }
    )
    post "/lti/launch", params: { id_token: token, state: session[:lti_state] }

    assert_equal "LtiDeepLinkingRequest",
      session[:lti_launch_claims]["https://purl.imsglobal.org/spec/lti/claim/message_type"]
  end

  # ── Error cases ───────────────────────────────────────────────────────────

  test "launch rejects state mismatch" do
    get "/lti/login", params: build_oidc_login_params(@deployment)
    token = build_id_token(@deployment, claims: { "nonce" => session[:lti_nonce] })
    post "/lti/launch", params: { id_token: token, state: "wrong_state" }
    assert_response :bad_request
  end
end
```

### Stubbing AGS and NRPS in tests

```ruby
test "pushes a score" do
  stub_platform_token_endpoint(@platform.token_url, access_token: "tok123")

  WebMock.stub_request(:post, "https://platform.example.com/lineitems/1/scores")
         .to_return(status: 200, body: "")

  ags_claims = {
    "lineitem" => "https://platform.example.com/lineitems/1",
    "scope"    => [RailsLti::Services::Ags::AGS_SCORE_SCOPE]
  }

  ags = RailsLti::Services::Ags.new(@deployment, ags_claims)
  ags.submit_score(user_id: "u1", score: 90.0, score_maximum: 100.0)
  # assert WebMock request was made, or use assert_requested
end
```

### Available Helper Methods

| Method | Description |
|--------|-------------|
| `create_test_platform_and_deployment(**opts)` | Creates `Platform` + `Deployment` records and stubs the platform JWKS endpoint. Returns `[platform, deployment]`. |
| `build_id_token(deployment, message_type:, claims:, key:)` | Returns a signed LTI 1.3 JWT string. Defaults to `LtiResourceLinkRequest`. Includes AGS, NRPS, and context claims automatically. |
| `build_oidc_login_params(deployment, target_link_uri:)` | Returns a params hash for `GET /lti/login`, as a platform would send. |
| `store_test_nonce` | Creates a `RailsLti::Nonce` record and returns its string value. |
| `stub_platform_jwks(url, key:)` | Stubs `GET url` to return a JWKS containing the test key's public component (requires WebMock). |
| `stub_platform_token_endpoint(url, access_token:, expires_in:)` | Stubs `POST url` to return an OAuth 2 token response (requires WebMock). |
| `lti_private_key` | Per-test-instance RSA private key (memoised). Used by `build_id_token` by default. |
| `generate_rsa_key` | Generates and returns a fresh 2048-bit RSA key. |

---

## Maintenance

### Nonce Cleanup

Each LTI launch creates a `RailsLti::Nonce` database record that is consumed on first use. Expired records are harmless but accumulate over time. Clean them up with:

```ruby
RailsLti::Nonce.cleanup_expired!
```

Schedule this in a background job or cron task. Example with `whenever` gem:

```ruby
# config/schedule.rb
every 1.day, at: "3:00 am" do
  runner "RailsLti::Nonce.cleanup_expired!"
end
```

Example with Sidekiq + a scheduled worker:

```ruby
class LtiNonceCleanupJob < ApplicationJob
  queue_as :default

  def perform
    RailsLti::Nonce.cleanup_expired!
  end
end
```

---

## Migrating from Another LTI Library

If you're replacing an existing LTI 1.0/1.1 or IMS-LTI gem (e.g. `ims-lti`, `lti_provider`):

1. **Remove the old gem and routes** — delete any `lti_provider` routes or custom LTI controllers.

2. **Add `rails_lti` and run the installer** — follow the [Installation](#installation) steps.

3. **Port platform records** — if your existing app stores platform/consumer information, create corresponding `RailsLti::Platform` and `RailsLti::Deployment` records. You'll also need to reconfigure the platforms to use LTI 1.3 (LTI 1.0/1.1 records are not compatible).

4. **Update your launch handler** — in LTI 1.0/1.1, the tool posted directly to a page. In LTI 1.3, the engine handles the two-step OIDC flow and then redirects to your `target_link_uri`. Migrate your old landing page to use the session keys documented in [Session Reference](#session-reference) instead of the old `params[:*]` values.

5. **Update platform configurations** — in each platform (Canvas, Moodle, etc.), replace the old LTI 1.0/1.1 external tool with a new LTI 1.3 Developer Key pointing to the new endpoints.

6. **Grade passback** — LTI 1.0 used `lis_outcome_service_url`/`lis_result_sourcedid` for grade passback. LTI 1.3 uses AGS. Replace any `IMS::LTI::OutcomeService` calls with `RailsLti::Services::Ags#submit_score`.

---

## License

MIT – see [LICENSE](LICENSE).

