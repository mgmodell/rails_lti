# frozen_string_literal: true

require "test_helper"

module RailsLti
  module Services
    class DeepLinkTest < ActiveSupport::TestCase
      def setup
        RailsLti.configure do |config|
          config.tool_url = "https://tool.example.com"
          config.private_key = generate_rsa_key
        end

        @platform, @deployment = create_test_platform_and_deployment

        @deep_link_settings = {
          "deep_link_return_url" => "https://platform.example.com/deep_link_return",
          "accept_types" => ["ltiResourceLink", "link", "html"],
          "accept_presentation_document_targets" => ["iframe", "window"],
          "accept_multiple" => true,
          "auto_create" => false
        }
      end

      def teardown
        RailsLti.reset_configuration!
      end

      test "build_response_jwt returns a signed JWT" do
        item = DeepLink::ContentItem.lti_resource_link(
          url: "https://tool.example.com/resource/1",
          title: "My Resource"
        )

        service = DeepLink.new(@deployment, @deep_link_settings, [item])
        jwt = service.build_response_jwt

        assert jwt.is_a?(String)
        parts = jwt.split(".")
        assert_equal 3, parts.length
      end

      test "build_response_jwt payload contains correct claims" do
        item = DeepLink::ContentItem.link(url: "https://example.com", title: "Link")
        service = DeepLink.new(@deployment, @deep_link_settings, [item])
        jwt = service.build_response_jwt

        # Decode without verification for inspection
        payload, = JWT.decode(jwt, nil, false)

        assert_equal @deployment.client_id, payload["iss"]
        assert_equal @deployment.platform.issuer, payload["aud"]
        assert_equal "LtiDeepLinkingResponse", payload["https://purl.imsglobal.org/spec/lti/claim/message_type"]
        assert_equal "1.3.0", payload["https://purl.imsglobal.org/spec/lti/claim/version"]
        assert_equal @deployment.deployment_id, payload["https://purl.imsglobal.org/spec/lti/claim/deployment_id"]
        assert_equal [item.transform_keys(&:to_s)],
                     payload["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]
      end

      test "build_response_jwt includes optional message/log fields when provided" do
        service = DeepLink.new(@deployment, @deep_link_settings, [],
                               message: "Success", log: "Submitted", error_message: nil)
        payload, = JWT.decode(service.build_response_jwt, nil, false)

        assert_equal "Success", payload["https://purl.imsglobal.org/spec/lti-dl/claim/msg"]
        assert_equal "Submitted", payload["https://purl.imsglobal.org/spec/lti-dl/claim/log"]
        assert_nil payload["https://purl.imsglobal.org/spec/lti-dl/claim/errormsg"]
      end

      test "return_url returns the deep_link_return_url from settings" do
        service = DeepLink.new(@deployment, @deep_link_settings, [])
        assert_equal "https://platform.example.com/deep_link_return", service.return_url
      end

      # ContentItem builders

      test "ContentItem.lti_resource_link builds correct hash" do
        item = DeepLink::ContentItem.lti_resource_link(
          url: "https://tool.example.com/res",
          title: "Resource",
          custom_params: { "foo" => "bar" }
        )
        assert_equal "ltiResourceLink", item[:type]
        assert_equal "https://tool.example.com/res", item[:url]
        assert_equal "Resource", item[:title]
        assert_equal({ "foo" => "bar" }, item[:custom])
      end

      test "ContentItem.link builds correct hash" do
        item = DeepLink::ContentItem.link(url: "https://example.com", title: "A Link")
        assert_equal "link", item[:type]
        assert_equal "https://example.com", item[:url]
      end

      test "ContentItem.html_fragment builds correct hash" do
        item = DeepLink::ContentItem.html_fragment(html: "<b>hello</b>", width: 800, height: 600)
        assert_equal "html", item[:type]
        assert_equal "<b>hello</b>", item[:html]
        assert_equal 800, item[:width]
      end

      test "ContentItem.image builds correct hash" do
        item = DeepLink::ContentItem.image(url: "https://img.example.com/pic.png", title: "Pic")
        assert_equal "image", item[:type]
        assert_equal "https://img.example.com/pic.png", item[:url]
      end

      test "ContentItem.file builds correct hash" do
        item = DeepLink::ContentItem.file(url: "https://files.example.com/doc.pdf", media_type: "application/pdf")
        assert_equal "file", item[:type]
        assert_equal "application/pdf", item[:mediaType]
      end
    end
  end
end
