# frozen_string_literal: true

module RailsLti
  # Represents an LTI 1.3 platform (tool consumer).
  # One platform record stores the OIDC configuration for a given issuer/client_id pair.
  #
  # In Canvas, for example, the issuer is "https://canvas.instructure.com"
  # and the client_id is assigned when the developer key is created.
  class Platform < ApplicationRecord
    self.table_name = "rails_lti_platforms"

    has_many :deployments, class_name: "RailsLti::Deployment", foreign_key: :platform_id,
                           dependent: :destroy, inverse_of: :platform

    validates :issuer,        presence: true
    validates :client_id,     presence: true
    validates :oidc_auth_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
    validates :jwks_url,      presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
    validates :token_url,     presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
    validates :issuer, uniqueness: { scope: :client_id }
  end
end
