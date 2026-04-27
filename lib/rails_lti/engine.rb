# frozen_string_literal: true

module RailsLti
  class Engine < ::Rails::Engine
    isolate_namespace RailsLti

    config.generators do |g|
      g.test_framework :minitest
      g.assets false
      g.helper false
    end

    # Run migrations for the engine automatically when inside a host app
    initializer "rails_lti.migrations" do |app|
      unless app.root.to_s == root.to_s
        config.paths["db/migrate"].expanded.each do |path|
          app.config.paths["db/migrate"] << path
        end
      end
    end

    # Clean up expired nonces periodically
    config.after_initialize do
      # Nonce cleanup can be triggered via a background job or the provided rake task
    end
  end
end
