# frozen_string_literal: true

require "kiket_sdk"
require "json"
require "net/http"
require "uri"
require "logger"
require "cgi"

# Microsoft Teams Notification Extension
# Handles sending notifications via Microsoft Graph API
class TeamsNotificationExtension
  REQUIRED_NOTIFY_SCOPES = %w[notifications:send].freeze
  REQUIRED_VALIDATE_SCOPES = %w[notifications:read].freeze

  GRAPH_BASE_URL = "https://graph.microsoft.com/v1.0".freeze

  class TeamsAPIError < StandardError
    attr_reader :retry_after, :status

    def initialize(message, status: nil, retry_after: nil)
      super(message)
      @status = status
      @retry_after = retry_after
    end
  end

  def initialize
    @sdk = KiketSDK.new
    @logger = Logger.new($stdout)
    setup_handlers
  end

  def app
    @sdk
  end

  private

  def setup_handlers
    # Send notification
    @sdk.register("teams.notify", version: "v1", required_scopes: REQUIRED_NOTIFY_SCOPES) do |payload, context|
      handle_notify(payload, context)
    end

    # Validate channel/chat configuration
    @sdk.register("teams.validate", version: "v1", required_scopes: REQUIRED_VALIDATE_SCOPES) do |payload, context|
      handle_validate(payload, context)
    end
  end

  def handle_notify(payload, context)
    validate_notification_request!(payload)

    token = acquire_access_token(context)
    result = case payload["channel_type"]
    when "channel"
      send_channel_message(token, payload, context)
    when "chat"
      send_chat_message(token, payload)
    else
      raise ArgumentError, "Unsupported channel_type: #{payload['channel_type']}"
    end

    context[:endpoints].log_event("teams.message.sent", {
      channel_type: payload["channel_type"],
      org_id: context[:auth][:org_id]
    })

    {
      success: true,
      message_id: result[:message_id],
      delivered_at: Time.now.utc.iso8601
    }
  rescue ArgumentError => e
    @logger.error "Validation error: #{e.message}"
    { success: false, error: e.message }
  rescue TeamsAPIError => e
    @logger.error "Teams API error: #{e.message}"
    { success: false, error: "Teams API error: #{e.message}", retry_after: e.retry_after }
  rescue StandardError => e
    @logger.error "Unexpected error: #{e.message}\n#{e.backtrace.join("\n")}"
    { success: false, error: "Internal server error" }
  end

  def handle_validate(payload, context)
    token = acquire_access_token(context)

    case payload["channel_type"]
    when "channel"
      validate_channel_exists(token, payload, context)
    when "chat"
      validate_chat_exists(token, payload)
    else
      raise ArgumentError, "Unsupported channel_type: #{payload['channel_type']}"
    end

    { valid: true, message: "Configuration is valid" }
  rescue ArgumentError => e
    { valid: false, error: e.message }
  rescue TeamsAPIError => e
    { valid: false, error: e.message }
  rescue StandardError => e
    @logger.error "Unexpected error: #{e.message}"
    { valid: false, error: "Internal server error" }
  end

  # Validation helpers

  def validate_notification_request!(payload)
    message = payload["message"]
    raise ArgumentError, "message is required" if message.nil? || message.to_s.strip.empty?

    channel_type = payload["channel_type"]
    raise ArgumentError, "channel_type is required" if channel_type.nil?

    case channel_type
    when "channel"
      team_id = payload["team_id"]
      raise ArgumentError, "team_id is required for channel notifications" if team_id.to_s.strip.empty?
      raise ArgumentError, "channel_id is required for channel notifications" if payload["channel_id"].to_s.strip.empty?
    when "chat"
      raise ArgumentError, "chat_id is required for chat notifications" if payload["chat_id"].to_s.strip.empty?
    else
      raise ArgumentError, "Unsupported channel_type: #{channel_type}"
    end
  end

  # OAuth and API methods

  def acquire_access_token(context)
    tenant_id = context[:secret].call("TEAMS_TENANT_ID")
    client_id = context[:secret].call("TEAMS_CLIENT_ID")
    client_secret = context[:secret].call("TEAMS_CLIENT_SECRET")

    if [tenant_id, client_id, client_secret].any? { |value| value.to_s.strip.empty? }
      raise ArgumentError, "Missing Teams OAuth credentials"
    end

    uri = URI("https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token")
    request = Net::HTTP::Post.new(uri)
    request.set_form_data(
      client_id: client_id,
      client_secret: client_secret,
      scope: "https://graph.microsoft.com/.default",
      grant_type: "client_credentials"
    )

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise TeamsAPIError.new("Failed to obtain access token", status: response.code.to_i)
    end

    data = JSON.parse(response.body)
    data["access_token"] || raise(TeamsAPIError, "Missing access_token in response")
  end

  def send_channel_message(token, payload, context)
    team_id = payload["team_id"] || context[:secret].call("TEAMS_DEFAULT_TEAM_ID")
    channel_id = payload["channel_id"]
    uri = URI("#{GRAPH_BASE_URL}/teams/#{team_id}/channels/#{channel_id}/messages")

    response = post_graph_json(uri, token, build_message_payload(payload, context))
    { message_id: response["id"] }
  end

  def send_chat_message(token, payload)
    chat_id = payload["chat_id"]
    uri = URI("#{GRAPH_BASE_URL}/chats/#{chat_id}/messages")

    response = post_graph_json(uri, token, build_message_payload(payload, nil))
    { message_id: response["id"] }
  end

  def validate_channel_exists(token, payload, context)
    team_id = payload["team_id"] || context[:secret].call("TEAMS_DEFAULT_TEAM_ID")
    channel_id = payload["channel_id"]
    raise ArgumentError, "team_id and channel_id are required" if team_id.to_s.empty? || channel_id.to_s.empty?

    uri = URI("#{GRAPH_BASE_URL}/teams/#{team_id}/channels/#{channel_id}")
    get_graph_json(uri, token)
  end

  def validate_chat_exists(token, payload)
    chat_id = payload["chat_id"]
    raise ArgumentError, "chat_id is required" if chat_id.to_s.empty?

    uri = URI("#{GRAPH_BASE_URL}/chats/#{chat_id}")
    get_graph_json(uri, token)
  end

  def build_message_payload(payload, context)
    format = payload["format"] || "text"
    {
      subject: payload["subject"],
      body: {
        contentType: content_type(format),
        content: format_message(payload["message"], format)
      }
    }.compact
  end

  def content_type(format)
    format == "html" ? "html" : "text"
  end

  def format_message(message, format)
    case format
    when "html"
      message
    when "markdown"
      markdown_to_html(message)
    else
      CGI.escapeHTML(message.to_s)
    end
  end

  def markdown_to_html(text)
    html = CGI.escapeHTML(text.to_s)
    html.gsub(/\*\*(.*?)\*\*/) { "<strong>#{::Regexp.last_match(1)}</strong>" }
        .gsub(/\*(.*?)\*/) { "<em>#{::Regexp.last_match(1)}</em>" }
        .gsub(/`(.*?)`/) { "<code>#{::Regexp.last_match(1)}</code>" }
        .gsub(/\n/, "<br />")
  end

  def post_graph_json(uri, access_token, payload)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.dump(payload)

    perform_graph_request(uri, request)
  end

  def get_graph_json(uri, access_token)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{access_token}"

    perform_graph_request(uri, request)
  end

  def perform_graph_request(uri, request)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    parse_graph_response(response)
  end

  def parse_graph_response(response)
    body = response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
  rescue JSON::ParserError
    body = {}
  ensure
    return body if response.is_a?(Net::HTTPSuccess)

    retry_after = response["Retry-After"]&.to_i
    message = if body.is_a?(Hash)
                body.dig("error", "message") || body["message"]
    end
    message ||= response.message

    raise TeamsAPIError.new(message, status: response.code.to_i, retry_after: retry_after)
  end
end

# Run the extension
if __FILE__ == $PROGRAM_NAME
  extension = TeamsNotificationExtension.new

  Rack::Handler::Puma.run(
    extension.app,
    Host: ENV.fetch("HOST", "0.0.0.0"),
    Port: ENV.fetch("PORT", 8080).to_i,
    Threads: "0:16"
  )
end
