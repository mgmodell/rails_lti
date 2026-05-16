# frozen_string_literal: true

module RailsLti
  module Services
    # Names and Roles Provisioning Services (NRPS) – LTI Advantage
    # Fetches the membership list for a context (course/group).
    # @see https://www.imsglobal.org/spec/lti-nrps/v2p0
    class Nrps
      NRPS_SCOPE = "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"

      class Error < StandardError; end

      # @param deployment [RailsLti::Deployment]
      # @param nrps_claims [Hash] the NRPS claim from the launch JWT
      #   Expected key: "context_memberships_url"
      def initialize(deployment, nrps_claims)
        @deployment        = deployment
        @memberships_url   = nrps_claims["context_memberships_url"]
        raise Error, "No context_memberships_url in NRPS claims" unless @memberships_url
      end

      # Fetch all members of the context.
      # Handles pagination automatically.
      # @param role [String, nil] optional IMS role URI to filter by
      # @return [Array<Hash>] list of membership objects
      def members(role: nil)
        params = {}
        params[:role] = role if role

        all_members = []
        url = @memberships_url

        loop do
          response = fetch_page(url, params)
          body = parse_response(response)
          all_members.concat(Array(body["members"]))

          next_url = extract_next_link(response.headers["link"])
          break unless next_url

          url    = next_url
          params = {}
        end

        all_members
      end

      private

      def fetch_page(url, params)
        conn.get(url, params,
          "Authorization" => "Bearer #{token}",
          "Accept" => "application/vnd.ims.lti-nrps.v2.membershipcontainer+json"
        )
      end

      def token
        AccessTokenService.new(@deployment).fetch(NRPS_SCOPE)
      end

      def conn
        @conn ||= Faraday.new do |f|
          f.adapter Faraday.default_adapter
        end
      end

      def parse_response(response)
        raise Error, "NRPS request failed (#{response.status}): #{response.body}" unless response.success?

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON from NRPS endpoint: #{e.message}"
      end

      # Parse RFC 5988 Link header for rel="next"
      def extract_next_link(link_header)
        return nil if link_header.blank?

        link_header.split(",").each do |part|
          url, rel = part.strip.split(";").map(&:strip)
          return url.delete("<>").strip if rel&.include?('rel="next"')
        end

        nil
      end
    end
  end
end
