# frozen_string_literal: true

module RailsLti
  module Services
    # Builds LTI Deep Linking response JWTs.
    # The tool presents content selection UI, then calls this service to
    # create the signed JWT to POST back to the platform.
    # @see https://www.imsglobal.org/spec/lti-dl/v2p0
    class DeepLink
      MESSAGE_TYPE = "LtiDeepLinkingResponse"

      # Content item type builders
      module ContentItem
        # @param url [String] URL of the LTI resource
        # @param title [String]
        # @param text [String, nil]
        # @param custom_params [Hash] custom parameters
        def self.lti_resource_link(url:, title: nil, text: nil, custom_params: {}, line_item: nil)
          item = { type: "ltiResourceLink", url: url }
          item[:title]  = title if title
          item[:text]   = text  if text
          item[:custom] = custom_params unless custom_params.empty?
          if line_item
            item[:lineItem] = line_item
          end
          item
        end

        # @param url [String] URL of the content link
        # @param title [String]
        # @param text [String, nil]
        # @param icon [Hash, nil] { url:, width:, height: }
        # @param thumbnail [Hash, nil] { url:, width:, height: }
        def self.link(url:, title: nil, text: nil, icon: nil, thumbnail: nil)
          item = { type: "link", url: url }
          item[:title]     = title     if title
          item[:text]      = text      if text
          item[:icon]      = icon      if icon
          item[:thumbnail] = thumbnail if thumbnail
          item
        end

        # @param url [String] URL to the file
        # @param media_type [String] MIME type
        # @param title [String, nil]
        def self.file(url:, media_type:, title: nil)
          item = { type: "file", url: url, mediaType: media_type }
          item[:title] = title if title
          item
        end

        # @param html [String] HTML string to embed
        # @param title [String, nil]
        # @param width [Integer, nil]
        # @param height [Integer, nil]
        def self.html_fragment(html:, title: nil, width: nil, height: nil)
          item = { type: "html", html: html }
          item[:title]  = title  if title
          item[:width]  = width  if width
          item[:height] = height if height
          item
        end

        # @param url [String] Image URL
        # @param title [String, nil]
        # @param width [Integer, nil]
        # @param height [Integer, nil]
        def self.image(url:, title: nil, width: nil, height: nil)
          item = { type: "image", url: url }
          item[:title]  = title  if title
          item[:width]  = width  if width
          item[:height] = height if height
          item
        end
      end

      # @param deployment [RailsLti::Deployment]
      # @param deep_link_settings [Hash] the deep_linking_settings claim from the launch JWT
      # @param content_items [Array<Hash>] items to include in the response
      # @param message [String, nil] optional message to display to the user
      # @param log [String, nil] optional log message
      # @param error_message [String, nil] optional error message
      # @param error_log [String, nil] optional error log
      def initialize(deployment, deep_link_settings, content_items,
                     message: nil, log: nil, error_message: nil, error_log: nil)
        @deployment          = deployment
        @deep_link_settings  = deep_link_settings
        @content_items       = content_items
        @message             = message
        @log                 = log
        @error_message       = error_message
        @error_log           = error_log
      end

      # Build and sign the deep linking response JWT.
      # @return [String] signed JWT
      def build_response_jwt
        now     = Time.now.to_i
        payload = {
          iss: @deployment.client_id,
          aud: @deployment.platform.issuer,
          iat: now,
          exp: now + 600,
          nonce: SecureRandom.hex(16),
          "https://purl.imsglobal.org/spec/lti/claim/message_type" => MESSAGE_TYPE,
          "https://purl.imsglobal.org/spec/lti/claim/version" => "1.3.0",
          "https://purl.imsglobal.org/spec/lti/claim/deployment_id" => @deployment.deployment_id,
          "https://purl.imsglobal.org/spec/lti-dl/claim/content_items" => @content_items,
          "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" => @deep_link_settings
        }

        payload["https://purl.imsglobal.org/spec/lti-dl/claim/msg"] = @message if @message
        payload["https://purl.imsglobal.org/spec/lti-dl/claim/log"] = @log if @log
        payload["https://purl.imsglobal.org/spec/lti-dl/claim/errormsg"] = @error_message if @error_message
        payload["https://purl.imsglobal.org/spec/lti-dl/claim/errorlog"] = @error_log if @error_log

        private_key = RailsLti.configuration.private_key
        kid = private_key.public_key.to_jwk[:kid] rescue nil

        headers = { typ: "JWT" }
        headers[:kid] = kid if kid

        JWT.encode(payload, private_key, "RS256", headers)
      end

      # Returns the return_url from the deep link settings where the JWT should be POSTed.
      # @return [String]
      def return_url
        @deep_link_settings["deep_link_return_url"]
      end
    end
  end
end
