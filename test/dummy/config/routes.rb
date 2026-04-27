# frozen_string_literal: true

Rails.application.routes.draw do
  mount RailsLti::Engine => "/lti"
  root to: proc { [200, { "Content-Type" => "text/plain" }, ["OK"]] }
end
