# Changelog

## [0.1.0] – 2026-04-27

### Added
- LTI 1.3 OIDC launch flow (login initiation + authentication response)
- Dynamic Registration (LTI Advantage DR)
- Deep Linking (content items: ltiResourceLink, link, html, image, file)
- Assignment and Grade Services (AGS) – list/create line items, submit scores, get results
- Names and Roles Provisioning Services (NRPS) – membership list with pagination
- JWKS endpoint for tool public key distribution
- `RailsLti::Platform` and `RailsLti::Deployment` ActiveRecord models
- Nonce management for JWT replay protection (`RailsLti::Nonce`)
- `RailsLti::JwtValidator` for LTI 1.3 ID token validation
- `RailsLti::Services::AccessTokenService` for OAuth 2.0 client_credentials token fetching
- `RailsLti::TestHelpers::LtiHelpers` – test helper module for host app developers
- Install generator (`rails generate rails_lti:install`)
- Configurable callbacks: `after_launch`, `after_deep_link`, `after_registration`
