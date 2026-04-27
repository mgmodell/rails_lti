# frozen_string_literal: true

module RailsLti
  # Represents a specific LTI tool deployment within a platform.
  # A deployment maps to a combination of platform + client_id + deployment_id.
  class Deployment < ApplicationRecord
    self.table_name = "rails_lti_deployments"

    belongs_to :platform, class_name: "RailsLti::Platform", inverse_of: :deployments

    validates :client_id,     presence: true
    validates :deployment_id, presence: true
    validates :deployment_id, uniqueness: { scope: :platform_id }
  end
end
