# frozen_string_literal: true

require "test_helper"

module RailsLti
  class PlatformTest < ActiveSupport::TestCase
    def setup
      @platform = Platform.new(
        issuer: "https://platform.example.com",
        client_id: "client_001",
        oidc_auth_url: "https://platform.example.com/auth",
        jwks_url: "https://platform.example.com/jwks",
        token_url: "https://platform.example.com/token"
      )
    end

    test "is valid with all required attributes" do
      assert @platform.valid?
    end

    test "requires issuer" do
      @platform.issuer = nil
      refute @platform.valid?
      assert_includes @platform.errors[:issuer], "can't be blank"
    end

    test "requires client_id" do
      @platform.client_id = nil
      refute @platform.valid?
      assert_includes @platform.errors[:client_id], "can't be blank"
    end

    test "requires oidc_auth_url" do
      @platform.oidc_auth_url = nil
      refute @platform.valid?
      assert_includes @platform.errors[:oidc_auth_url], "can't be blank"
    end

    test "requires jwks_url" do
      @platform.jwks_url = nil
      refute @platform.valid?
      assert_includes @platform.errors[:jwks_url], "can't be blank"
    end

    test "requires token_url" do
      @platform.token_url = nil
      refute @platform.valid?
      assert_includes @platform.errors[:token_url], "can't be blank"
    end

    test "validates URL format for oidc_auth_url" do
      @platform.oidc_auth_url = "not-a-url"
      refute @platform.valid?
      assert_includes @platform.errors[:oidc_auth_url], "is invalid"
    end

    test "validates URL format for jwks_url" do
      @platform.jwks_url = "not-a-url"
      refute @platform.valid?
      assert_includes @platform.errors[:jwks_url], "is invalid"
    end

    test "validates URL format for token_url" do
      @platform.token_url = "not-a-url"
      refute @platform.valid?
      assert_includes @platform.errors[:token_url], "is invalid"
    end

    test "enforces unique issuer+client_id" do
      @platform.save!
      duplicate = Platform.new(
        issuer: @platform.issuer,
        client_id: @platform.client_id,
        oidc_auth_url: @platform.oidc_auth_url,
        jwks_url: @platform.jwks_url,
        token_url: @platform.token_url
      )
      refute duplicate.valid?
      assert_includes duplicate.errors[:issuer], "has already been taken"
    end

    test "has many deployments" do
      @platform.save!
      deployment = Deployment.create!(
        platform: @platform,
        client_id: @platform.client_id,
        deployment_id: "deploy_1"
      )
      assert_includes @platform.deployments, deployment
    end

    test "destroys associated deployments when deleted" do
      @platform.save!
      Deployment.create!(platform: @platform, client_id: @platform.client_id, deployment_id: "d1")
      assert_difference "Deployment.count", -1 do
        @platform.destroy
      end
    end
  end
end
