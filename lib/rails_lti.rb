# frozen_string_literal: true

require "jwt"
require "faraday"
require "openssl"

require "rails_lti/version"
require "rails_lti/configuration"
require "rails_lti/engine"

# Services (loaded after engine so Rails is available for AccessTokenService)
require "rails_lti/jwt_validator"
require "rails_lti/services/access_token_service"
require "rails_lti/services/ags"
require "rails_lti/services/nrps"
require "rails_lti/services/deep_link"
require "rails_lti/services/dynamic_registration"

module RailsLti
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
