# frozen_string_literal: true

module RailsLti
  class ApplicationController < ActionController::Base
    # LTI platforms POST to the launch and registration endpoints without
    # CSRF tokens. The LTI 1.3 spec uses the `state` parameter and nonce to
    # provide equivalent protection. We therefore use :null_session here
    # so that CSRF protection does not block these legitimate platform requests.
    protect_from_forgery with: :null_session
  end
end
