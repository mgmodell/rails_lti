# frozen_string_literal: true

module RailsLti
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :null_session
  end
end
