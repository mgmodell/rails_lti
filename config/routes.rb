# frozen_string_literal: true

RailsLti::Engine.routes.draw do
  # OIDC login initiation (GET or POST from platform)
  match "login",        to: "oidc#login",    via: [:get, :post]

  # OIDC authentication response (POST from platform with id_token)
  post  "launch",       to: "oidc#launch"

  # Tool's public JWKS endpoint
  get   "jwks",         to: "oidc#jwks"

  # Dynamic registration
  get   "registration", to: "registrations#new"
end
