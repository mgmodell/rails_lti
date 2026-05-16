# frozen_string_literal: true

require "rails/all"
require_relative "../../../lib/rails_lti"

Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.1

    config.eager_load = false
    config.secret_key_base = "test_secret_key_base_for_dummy_app_do_not_use_in_production"

    config.active_record.maintain_test_schema = false

    config.cache_store = :memory_store
  end
end
