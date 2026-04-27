# frozen_string_literal: true

require "test_helper"

module RailsLti
  class DeploymentTest < ActiveSupport::TestCase
    def setup
      @platform = Platform.create!(
        issuer: "https://platform.example.com",
        client_id: "client_001",
        oidc_auth_url: "https://platform.example.com/auth",
        jwks_url: "https://platform.example.com/jwks",
        token_url: "https://platform.example.com/token"
      )
    end

    test "is valid with all required attributes" do
      deployment = Deployment.new(
        platform: @platform,
        client_id: "client_001",
        deployment_id: "deploy_1"
      )
      assert deployment.valid?
    end

    test "requires client_id" do
      deployment = Deployment.new(platform: @platform, deployment_id: "deploy_1")
      refute deployment.valid?
      assert_includes deployment.errors[:client_id], "can't be blank"
    end

    test "requires deployment_id" do
      deployment = Deployment.new(platform: @platform, client_id: "client_001")
      refute deployment.valid?
      assert_includes deployment.errors[:deployment_id], "can't be blank"
    end

    test "requires platform" do
      deployment = Deployment.new(client_id: "client_001", deployment_id: "deploy_1")
      refute deployment.valid?
    end

    test "enforces unique deployment_id per platform" do
      Deployment.create!(platform: @platform, client_id: "client_001", deployment_id: "deploy_1")
      dup = Deployment.new(platform: @platform, client_id: "client_001", deployment_id: "deploy_1")
      refute dup.valid?
      assert_includes dup.errors[:deployment_id], "has already been taken"
    end

    test "allows same deployment_id on different platforms" do
      other = Platform.create!(
        issuer: "https://other.example.com",
        client_id: "client_002",
        oidc_auth_url: "https://other.example.com/auth",
        jwks_url: "https://other.example.com/jwks",
        token_url: "https://other.example.com/token"
      )
      Deployment.create!(platform: @platform, client_id: "client_001", deployment_id: "deploy_1")
      other_deploy = Deployment.new(platform: other, client_id: "client_002", deployment_id: "deploy_1")
      assert other_deploy.valid?
    end

    test "belongs to a platform" do
      deployment = Deployment.create!(platform: @platform, client_id: "client_001", deployment_id: "d1")
      assert_equal @platform, deployment.platform
    end
  end
end
