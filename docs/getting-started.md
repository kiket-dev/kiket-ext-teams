# Getting Started with Microsoft Teams

Send notifications and messages via Microsoft Teams channels and chats.

## Prerequisites

- Microsoft 365 account with Teams access
- Azure AD app registration permissions

## Step 1: Register an Azure AD App

1. Go to [Azure Portal](https://portal.azure.com) → **Azure Active Directory** → **App registrations**
2. Click **New registration**
3. Configure:
   - **Name**: "Kiket Integration"
   - **Supported account types**: Accounts in this organizational directory
   - **Redirect URI**: Web → Your Kiket callback URL
4. Note the **Application (client) ID** and **Directory (tenant) ID**

## Step 2: Configure API Permissions

1. Go to **API permissions** → **Add a permission**
2. Select **Microsoft Graph** → **Application permissions**
3. Add: `ChannelMessage.Send`, `Chat.ReadWrite.All`, `Team.ReadBasic.All`, `User.Read.All`
4. Click **Grant admin consent**

## Step 3: Create Client Secret

1. Go to **Certificates & secrets** → **New client secret**
2. Copy the secret value immediately

## Step 4: Configure in Kiket

1. Go to **Organization Settings → Extensions → Microsoft Teams**
2. Enter Tenant ID, Client ID, and Client Secret
3. Click **Authorize** to complete OAuth flow

## Step 5: Add to Workflows

```yaml
automations:
  - name: notify_teams_on_issue
    trigger:
      event: issue.created
    actions:
      - extension: dev.kiket.ext.teams
        command: teams.sendMessage
        params:
          channel: "Project Updates"
          template: issue_created_message
```
