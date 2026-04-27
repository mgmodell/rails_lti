# frozen_string_literal: true

require "test_helper"

module RailsLti
  module Services
    class NrpsTest < ActiveSupport::TestCase
      def setup
        RailsLti.configure do |config|
          config.tool_url = "https://tool.example.com"
          config.private_key = generate_rsa_key
        end

        @platform, @deployment = create_test_platform_and_deployment
        stub_platform_token_endpoint(@platform.token_url)

        @nrps_claims = {
          "context_memberships_url" => "https://platform.example.com/memberships",
          "service_versions" => ["2.0"]
        }
      end

      def teardown
        RailsLti.reset_configuration!
        WebMock.reset!
      end

      test "members returns list of members" do
        members = [
          { "userId" => "u1", "roles" => ["Learner"] },
          { "userId" => "u2", "roles" => ["Instructor"] }
        ]
        WebMock.stub_request(:get, "https://platform.example.com/memberships")
               .to_return(
                 status: 200,
                 body: { "id" => "ctx1", "members" => members }.to_json,
                 headers: { "Content-Type" => "application/vnd.ims.lti-nrps.v2.membershipcontainer+json" }
               )

        result = Nrps.new(@deployment, @nrps_claims).members
        assert_equal members, result
      end

      test "members handles paginated responses" do
        page1_members = [{ "userId" => "u1" }]
        page2_members = [{ "userId" => "u2" }]
        page2_url = "https://platform.example.com/memberships?page=2"

        WebMock.stub_request(:get, "https://platform.example.com/memberships")
               .to_return(
                 status: 200,
                 body: { "members" => page1_members }.to_json,
                 headers: {
                   "Content-Type" => "application/vnd.ims.lti-nrps.v2.membershipcontainer+json",
                   "Link" => %(<#{page2_url}>; rel="next")
                 }
               )

        WebMock.stub_request(:get, page2_url)
               .to_return(
                 status: 200,
                 body: { "members" => page2_members }.to_json,
                 headers: { "Content-Type" => "application/vnd.ims.lti-nrps.v2.membershipcontainer+json" }
               )

        result = Nrps.new(@deployment, @nrps_claims).members
        assert_equal page1_members + page2_members, result
      end

      test "members passes role filter as query param" do
        WebMock.stub_request(:get, "https://platform.example.com/memberships")
               .with(query: { "role" => "Instructor" })
               .to_return(
                 status: 200,
                 body: { "members" => [] }.to_json,
                 headers: { "Content-Type" => "application/vnd.ims.lti-nrps.v2.membershipcontainer+json" }
               )

        result = Nrps.new(@deployment, @nrps_claims).members(role: "Instructor")
        assert_equal [], result
      end

      test "raises Error when no memberships URL" do
        assert_raises(Nrps::Error) do
          Nrps.new(@deployment, {})
        end
      end

      test "raises Error on HTTP failure" do
        WebMock.stub_request(:get, "https://platform.example.com/memberships")
               .to_return(status: 500, body: "error")

        assert_raises(Nrps::Error) do
          Nrps.new(@deployment, @nrps_claims).members
        end
      end
    end
  end
end
