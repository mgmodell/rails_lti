# frozen_string_literal: true

module RailsLti
  module Services
    # Assignment and Grade Services (AGS) – LTI Advantage
    # Provides helpers to:
    #   - list, create, and update line items
    #   - submit scores
    # @see https://www.imsglobal.org/spec/lti-ags/v2p0
    class Ags
      AGS_SCORE_SCOPE  = "https://purl.imsglobal.org/spec/lti-ags/scope/score"
      AGS_LINEITEM_SCOPE  = "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
      AGS_LINEITEM_RO_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"
      AGS_RESULT_RO_SCOPE = "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"

      ACTIVITY_PROGRESS_INITIALIZED  = "Initialized"
      ACTIVITY_PROGRESS_STARTED      = "Started"
      ACTIVITY_PROGRESS_IN_PROGRESS  = "InProgress"
      ACTIVITY_PROGRESS_SUBMITTED    = "Submitted"
      ACTIVITY_PROGRESS_COMPLETED    = "Completed"

      GRADING_PROGRESS_NOT_READY     = "NotReady"
      GRADING_PROGRESS_FAILED        = "Failed"
      GRADING_PROGRESS_PENDING       = "Pending"
      GRADING_PROGRESS_PENDING_MANUAL = "PendingManual"
      GRADING_PROGRESS_FULLY_GRADED  = "FullyGraded"

      class Error < StandardError; end

      # @param deployment [RailsLti::Deployment]
      # @param ags_claims [Hash] the AGS claims from the launch JWT
      #   Expected keys: "lineitems" (container URL), "lineitem" (single line item URL), "scope"
      def initialize(deployment, ags_claims)
        @deployment  = deployment
        @ags_claims  = ags_claims
        @lineitems   = ags_claims["lineitems"]
        @lineitem    = ags_claims["lineitem"]
        @scopes      = Array(ags_claims["scope"])
      end

      # @return [Array<Hash>] list of line items
      def list_line_items
        raise Error, "No lineitems URL available" unless @lineitems

        response = conn.get(@lineitems, {},
          "Authorization" => "Bearer #{token_for(AGS_LINEITEM_RO_SCOPE)}",
          "Accept" => "application/vnd.ims.lis.v2.lineitemcontainer+json"
        )
        parse_response(response)
      end

      # @param label [String] display label for the line item
      # @param score_maximum [Float] maximum possible score
      # @param resource_id [String, nil] optional resource link ID
      # @param tag [String, nil] optional tag
      # @return [Hash] created line item
      def create_line_item(label:, score_maximum:, resource_id: nil, tag: nil)
        raise Error, "No lineitems URL available" unless @lineitems

        body = { label: label, scoreMaximum: score_maximum }
        body[:resourceId] = resource_id if resource_id
        body[:tag] = tag if tag

        response = conn.post(@lineitems, body.to_json,
          "Authorization" => "Bearer #{token_for(AGS_LINEITEM_SCOPE)}",
          "Content-Type" => "application/vnd.ims.lis.v2.lineitem+json",
          "Accept" => "application/vnd.ims.lis.v2.lineitem+json"
        )
        parse_response(response)
      end

      # Submit a score for a user on the launch line item (or a specified one).
      # @param user_id [String] the LTI user_id (sub claim)
      # @param score [Float] the raw score achieved
      # @param score_maximum [Float] the maximum possible score
      # @param activity_progress [String] one of the ACTIVITY_PROGRESS_* constants
      # @param grading_progress [String] one of the GRADING_PROGRESS_* constants
      # @param comment [String, nil] optional grader comment
      # @param lineitem_url [String, nil] override the line item URL (uses launch lineitem by default)
      # @return [Hash] the score submission response
      def submit_score(user_id:, score:, score_maximum:,
                       activity_progress: ACTIVITY_PROGRESS_COMPLETED,
                       grading_progress: GRADING_PROGRESS_FULLY_GRADED,
                       comment: nil, lineitem_url: nil)
        url = lineitem_url || @lineitem
        raise Error, "No lineitem URL available" unless url

        score_url = "#{url.chomp("/")}/scores"
        body = {
          userId: user_id,
          scoreGiven: score,
          scoreMaximum: score_maximum,
          activityProgress: activity_progress,
          gradingProgress: grading_progress,
          timestamp: Time.now.utc.iso8601
        }
        body[:comment] = comment if comment

        response = conn.post(score_url, body.to_json,
          "Authorization" => "Bearer #{token_for(AGS_SCORE_SCOPE)}",
          "Content-Type" => "application/vnd.ims.lis.v1.score+json"
        )
        parse_response(response)
      end

      # Retrieve results for the current line item.
      # @param lineitem_url [String, nil] override the line item URL
      # @return [Array<Hash>] list of result objects
      def get_results(lineitem_url: nil)
        url = lineitem_url || @lineitem
        raise Error, "No lineitem URL available" unless url

        results_url = "#{url.chomp("/")}/results"
        response = conn.get(results_url, {},
          "Authorization" => "Bearer #{token_for(AGS_RESULT_RO_SCOPE)}",
          "Accept" => "application/vnd.ims.lis.v2.resultcontainer+json"
        )
        parse_response(response)
      end

      private

      def token_for(scope)
        AccessTokenService.new(@deployment).fetch(scope)
      end

      def conn
        @conn ||= Faraday.new do |f|
          f.adapter Faraday.default_adapter
        end
      end

      def parse_response(response)
        raise Error, "AGS request failed (#{response.status}): #{response.body}" unless response.success?

        JSON.parse(response.body)
      rescue JSON::ParserError
        response.body
      end
    end
  end
end
