# frozen_string_literal: true

module RailsLti
  # Short-lived nonce records used to prevent JWT replay attacks.
  # Each nonce is stored when the OIDC login is initiated and consumed on launch.
  class Nonce < ApplicationRecord
    self.table_name = "rails_lti_nonces"

    validates :value,      presence: true, uniqueness: true
    validates :expires_at, presence: true

    scope :expired, -> { where("expires_at < ?", Time.now) }

    # @return [Boolean] true if the nonce has passed its expiry time
    def expired?
      expires_at < Time.now
    end

    # Remove all expired nonces from the database.
    def self.cleanup_expired!
      expired.delete_all
    end
  end
end
