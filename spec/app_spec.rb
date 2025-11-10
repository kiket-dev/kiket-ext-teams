# frozen_string_literal: true

require "spec_helper"

RSpec.describe TeamsNotificationExtension do
  include Rack::Test::Methods

  before do
    allow_any_instance_of(described_class).to receive(:acquire_access_token).and_return("token")
  end

  describe "GET /health" do
    it "returns healthy response" do
      get "/health"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("healthy")
    end
  end

  describe "POST /notify" do
    it "delivers channel notifications" do
      allow_any_instance_of(described_class).to receive(:send_channel_message)
        .and_return(message_id: "abc123")

      post "/notify", {
        channel_type: "channel",
        team_id: "team",
        channel_id: "channel",
        message: "hello"
      }.to_json, "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["success"]).to be(true)
      expect(body["message_id"]).to eq("abc123")
    end

    it "rejects missing message" do
      post "/notify", {
        channel_type: "channel",
        team_id: "team",
        channel_id: "channel"
      }.to_json, "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(400)
    end
  end
end
