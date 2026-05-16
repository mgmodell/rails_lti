# frozen_string_literal: true

require "test_helper"

module RailsLti
  module Services
    class AgsTest < ActiveSupport::TestCase
      def setup
        RailsLti.configure do |config|
          config.tool_url = "https://tool.example.com"
          config.private_key = generate_rsa_key
        end

        @platform, @deployment = create_test_platform_and_deployment
        stub_platform_token_endpoint(@platform.token_url)

        @ags_claims = {
          "lineitems" => "https://platform.example.com/lineitems",
          "lineitem" => "https://platform.example.com/lineitems/1",
          "scope" => [
            Ags::AGS_SCORE_SCOPE,
            Ags::AGS_LINEITEM_SCOPE,
            Ags::AGS_LINEITEM_RO_SCOPE,
            Ags::AGS_RESULT_RO_SCOPE
          ]
        }
      end

      def teardown
        RailsLti.reset_configuration!
        WebMock.reset!
      end

      # -----------------------------------------------------------------------
      # list_line_items
      # -----------------------------------------------------------------------

      test "list_line_items fetches from lineitems URL" do
        items = [{ "id" => "1", "label" => "Homework", "scoreMaximum" => 100.0 }]
        WebMock.stub_request(:get, "https://platform.example.com/lineitems")
               .to_return(status: 200, body: items.to_json,
                          headers: { "Content-Type" => "application/vnd.ims.lis.v2.lineitemcontainer+json" })

        result = Ags.new(@deployment, @ags_claims).list_line_items
        assert_equal items, result
      end

      test "list_line_items raises Error when no lineitems URL" do
        ags = Ags.new(@deployment, @ags_claims.merge("lineitems" => nil))
        assert_raises(Ags::Error) { ags.list_line_items }
      end

      test "list_line_items raises Error on HTTP failure" do
        WebMock.stub_request(:get, "https://platform.example.com/lineitems")
               .to_return(status: 500, body: "error")

        assert_raises(Ags::Error) { Ags.new(@deployment, @ags_claims).list_line_items }
      end

      # -----------------------------------------------------------------------
      # create_line_item
      # -----------------------------------------------------------------------

      test "create_line_item POSTs to lineitems URL" do
        new_item = { "id" => "2", "label" => "Quiz", "scoreMaximum" => 50.0 }
        WebMock.stub_request(:post, "https://platform.example.com/lineitems")
               .to_return(status: 200, body: new_item.to_json,
                          headers: { "Content-Type" => "application/vnd.ims.lis.v2.lineitem+json" })

        result = Ags.new(@deployment, @ags_claims)
                    .create_line_item(label: "Quiz", score_maximum: 50.0)
        assert_equal new_item, result
      end

      # -----------------------------------------------------------------------
      # submit_score
      # -----------------------------------------------------------------------

      test "submit_score POSTs to scores endpoint" do
        WebMock.stub_request(:post, "https://platform.example.com/lineitems/1/scores")
               .to_return(status: 200, body: "")

        result = Ags.new(@deployment, @ags_claims).submit_score(
          user_id: "user_123",
          score: 85.0,
          score_maximum: 100.0
        )
        assert_not_nil result
      end

      test "submit_score raises Error when no lineitem URL" do
        ags = Ags.new(@deployment, @ags_claims.merge("lineitem" => nil))
        assert_raises(Ags::Error) do
          ags.submit_score(user_id: "u", score: 50.0, score_maximum: 100.0)
        end
      end

      test "submit_score uses custom lineitem_url when provided" do
        custom_url = "https://platform.example.com/lineitems/99"
        WebMock.stub_request(:post, "#{custom_url}/scores")
               .to_return(status: 200, body: "")

        result = Ags.new(@deployment, @ags_claims).submit_score(
          user_id: "u", score: 10.0, score_maximum: 20.0,
          lineitem_url: custom_url
        )
        assert_not_nil result
      end

      # -----------------------------------------------------------------------
      # get_results
      # -----------------------------------------------------------------------

      test "get_results fetches from results endpoint" do
        results = [{ "userId" => "user_123", "resultScore" => 85.0 }]
        WebMock.stub_request(:get, "https://platform.example.com/lineitems/1/results")
               .to_return(status: 200, body: results.to_json,
                          headers: { "Content-Type" => "application/vnd.ims.lis.v2.resultcontainer+json" })

        result = Ags.new(@deployment, @ags_claims).get_results
        assert_equal results, result
      end
    end
  end
end
