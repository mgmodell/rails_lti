# frozen_string_literal: true

module RailsLti
  # Handles LTI Advantage Dynamic Registration.
  # @see https://www.imsglobal.org/spec/lti-dr/v1p0
  #
  # Flow:
  #   1. Platform opens GET /lti/registration?openid_configuration=<url>&registration_token=<token>
  #   2. Tool fetches the platform's OpenID configuration
  #   3. Tool POSTs a client registration to the platform's registration endpoint
  #   4. Tool stores the resulting platform record
  class RegistrationsController < ApplicationController
    # GET /lti/registration
    # Called by the platform to initiate dynamic registration.
    def new
      @openid_configuration_url = params[:openid_configuration]
      @registration_token       = params[:registration_token]

      return render_error("Missing openid_configuration parameter") if @openid_configuration_url.blank?

      config = RailsLti.configuration

      service = Services::DynamicRegistration.new(
        openid_configuration_url: @openid_configuration_url,
        registration_token: @registration_token,
        tool_url: config.tool_url
      )

      begin
        @openid_config = service.fetch_openid_configuration
        @platform = service.register!(@openid_config)
      rescue Services::DynamicRegistration::Error => e
        return render_error("Dynamic registration failed: #{e.message}")
      end

      after_registration = config.after_registration
      if after_registration
        after_registration.call(self, @platform)
      else
        render :new
      end
    end

    private

    def render_error(message)
      render plain: message, status: :bad_request
    end
  end
end
