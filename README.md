# Microsoft Teams Notification Extension

Send notifications to Microsoft Teams channels and chats using the Microsoft Graph API.

## Features
- Direct messages to 1:1 chats
- Channel notifications with HTML/Markdown formatting
- Subject support for channel posts
- Validation endpoint to verify channel or chat configuration before enabling automations

## Prerequisites
1. **Microsoft Entra ID (Azure AD) tenant** with Teams enabled
2. **App registration** with the following Graph application permissions:
   - `ChatMessage.Send`
   - `ChannelMessage.Send`
   - `Chat.ReadWrite`
   - `Channel.ReadBasic.All`
3. A generated **client secret** for the registration
4. Team, channel, or chat IDs (see below)

## Environment Variables
Create a `.env` file or configure secrets in Kiket:

```
TEAMS_TENANT_ID=<azure-tenant-id>
TEAMS_CLIENT_ID=<app-client-id>
TEAMS_CLIENT_SECRET=<client-secret>
TEAMS_DEFAULT_TEAM_ID=<optional default team id>
TEAMS_DEFAULT_CHANNEL_ID=<optional default channel id>
TEAMS_DEFAULT_FORMAT=html   # html | markdown | text
```

## Running Locally
```
bundle install
bundle exec ruby app.rb -p 4567
```

Health check: `GET /health`

## Sending a Notification
```
curl -X POST http://localhost:4567/notify \
  -H "Content-Type: application/json" \
  -d '{
    "channel_type": "channel",
    "team_id": "<team-id>",
    "channel_id": "<channel-id>",
    "subject": "Deploy Complete",
    "format": "markdown",
    "message": "**Green build** deployed to production"
  }'
```

For direct chats:
```
{
  "channel_type": "chat",
  "chat_id": "19:abc123@thread.v2",
  "message": "Hello from Kiket"
}
```

## Validation Endpoint
```
curl -X POST http://localhost:4567/validate \
  -H "Content-Type: application/json" \
  -d '{
    "channel_type": "channel",
    "team_id": "<team-id>",
    "channel_id": "<channel-id>"
  }'
```
Returns `{ "valid": true }` when Teams accepts the IDs.

## Finding IDs
- **Team/Channel:** In Teams, open the channel menu → **Get link to channel** and extract `team`/`channel` IDs.
- **Chat:** Call `GET https://graph.microsoft.com/v1.0/users/{user-id}/chats` or use the Teams developer tools to copy the chat thread ID.

## Deployment
Use the provided Dockerfile:
```
docker build -t teams-notifications .
docker run --env-file .env -p 8080:8080 teams-notifications
```

## Error Handling
Errors from Microsoft Graph are surfaced with HTTP 502 status codes and Relay retry hints. Common failures:
- 401/403: invalid credentials or insufficient Graph permissions
- 404: incorrect team/channel/chat IDs
- 429: rate limits (the response includes `retry_after` seconds)
