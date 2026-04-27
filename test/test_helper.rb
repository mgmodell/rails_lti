# frozen_string_literal: true

# Load the dummy application
ENV["RAILS_ENV"] ||= "test"

require File.expand_path("dummy/config/environment", __dir__)

require "rails/test_help"
require "webmock/minitest"
require "mocha/minitest"

# Require our test helpers
require "rails_lti/test_helpers/lti_helpers"

# Load the schema (avoids needing to run migrations in CI)
ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)

class ActiveSupport::TestCase
  include RailsLti::TestHelpers::LtiHelpers

  # Setup transactional fixtures for each test
  self.use_transactional_tests = true
end
