# frozen_string_literal: true

require_relative "lib/rails_lti/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_lti"
  spec.version     = RailsLti::VERSION
  spec.authors     = ["Micah Gideon Modell"]
  spec.email       = ["mgmodell@example.com"]
  spec.homepage    = "https://github.com/mgmodell/rails_lti"
  spec.summary     = "A Rails engine providing LTI 1.3 Advantage capabilities"
  spec.description = <<~DESC
    A mountable Rails engine that adds LTI 1.3 Advantage support to any Rails
    application, including OIDC launch, dynamic registration, deep linking,
    Assignment & Grade Services (AGS), and Names & Roles Provisioning Services (NRPS).
  DESC
  spec.license = "MIT"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = ">= 3.0"

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "jwt", ">= 2.7"
  spec.add_dependency "faraday", ">= 1.9"

  spec.add_development_dependency "sqlite3", "~> 1.4"
  spec.add_development_dependency "minitest-reporters", "~> 1.5"
  spec.add_development_dependency "mocha", "~> 2.0"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "rubocop-rails-omakase", "~> 1.0"
end
