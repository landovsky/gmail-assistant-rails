# Google OAuth and Gmail API Setup

This document explains how to configure Google OAuth2 authentication and Gmail API access for the application.

## Prerequisites

1. A Google Cloud Project
2. Gmail API enabled
3. OAuth 2.0 credentials configured

## Google Cloud Console Setup

### 1. Create or Select a Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one

### 2. Enable Gmail API

1. Navigate to **APIs & Services** > **Library**
2. Search for "Gmail API"
3. Click **Enable**

### 3. Create OAuth 2.0 Credentials

1. Navigate to **APIs & Services** > **Credentials**
2. Click **Create Credentials** > **OAuth client ID**
3. Select **Web application** as the application type
4. Configure:
   - **Name**: Gmail Assistant Rails App (or your preferred name)
   - **Authorized redirect URIs**:
     - For development: `http://localhost:3000/auth/google/callback`
     - For production: `https://yourdomain.com/auth/google/callback`
5. Click **Create**
6. Copy the **Client ID** and **Client Secret**

### 4. Configure OAuth Consent Screen

1. Navigate to **APIs & Services** > **OAuth consent screen**
2. Select **External** user type (or Internal if using Google Workspace)
3. Fill in the required fields:
   - **App name**: Gmail Assistant
   - **User support email**: Your email
   - **Developer contact information**: Your email
4. Add scopes:
   - Click **Add or Remove Scopes**
   - Search for and add: `https://www.googleapis.com/auth/gmail.modify`
5. Add test users (for External apps during testing)
6. Click **Save and Continue**

## Application Configuration

### Environment Variables

Copy `.env.example` to `.env` and fill in your credentials:

```bash
cp .env.example .env
```

Edit `.env`:

```env
GOOGLE_CLIENT_ID=your_client_id_here.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your_client_secret_here
GOOGLE_REDIRECT_URI=http://localhost:3000/auth/google/callback
```

### Rails Credentials (Alternative)

Instead of environment variables, you can use Rails encrypted credentials:

```bash
bin/rails credentials:edit --environment development
```

Add:

```yaml
google_oauth:
  client_id: your_client_id_here
  client_secret: your_client_secret_here
  redirect_uri: http://localhost:3000/auth/google/callback
```

## Usage

### OAuth Flow

1. **Start the authorization flow**:
   ```
   Visit: http://localhost:3000/auth/google/authorize
   ```

2. **Grant permissions**:
   - You'll be redirected to Google's consent screen
   - Sign in with your Google account
   - Click **Allow** to grant Gmail access

3. **Callback handling**:
   - After authorization, Google redirects back to `/auth/google/callback`
   - The app exchanges the authorization code for access and refresh tokens
   - Tokens are encrypted and stored in the database
   - User record is created or updated

### Using the Gmail Client

```ruby
# Initialize the client with a user
user = User.find_by(email: "your@email.com")
client = Gmail::Client.new(user)

# List messages
messages = client.list_messages(query: "is:inbox", max_results: 10)

# Get a specific message
message = client.get_message(message_id)

# Parse message details
parser = Gmail::MessageParser.new(message)
from = parser.from  # { email: "sender@example.com", name: "Sender Name" }
subject = parser.subject
body = parser.body

# Create a draft reply
builder = Gmail::DraftBuilder.new(
  user_email: user.email,
  to: from[:email],
  subject: subject,
  body: "Your reply here",
  thread_id: message.thread_id,
  in_reply_to: parser.message_id
)
draft_message = builder.build

# Create the draft
draft = client.create_draft(draft_message)
```

## Token Management

### Automatic Token Refresh

The `Gmail::Client` automatically refreshes access tokens when they expire using the stored refresh token.

### Token Expiration

- Access tokens expire after ~1 hour
- Refresh tokens are long-lived (valid for 6 months of inactivity)
- Tokens are automatically refreshed before API calls if expired

### Token Storage

Tokens are encrypted in the database using Rails' built-in encryption:
- `google_access_token` - Encrypted access token
- `google_refresh_token` - Encrypted refresh token
- `google_token_expires_at` - Token expiration timestamp

## Scopes

The application requests the following OAuth scope:

- `https://www.googleapis.com/auth/gmail.modify` - Read, compose, send, and manage Gmail messages

This scope provides:
- ✅ Read messages and threads
- ✅ Create and manage drafts
- ✅ Modify labels
- ✅ Access history API
- ❌ Does NOT allow: Permanent deletion or sending on behalf of user

## Error Handling

The Gmail client includes automatic retry logic for:

- **Network errors**: Connection resets, timeouts, SSL errors
- **Rate limits**: 429 responses with exponential backoff
- **Server errors**: 500, 502, 503, 504 responses

Non-retryable errors (4xx except 429) fail immediately.

## Security Notes

1. **Never commit** `.env` or credentials files to version control
2. Tokens are **encrypted** at rest in the database
3. Use **HTTPS** in production for the redirect URI
4. Regularly **rotate** OAuth client secrets
5. Monitor **OAuth consent screen** for suspicious activity

## Troubleshooting

### "Error 400: redirect_uri_mismatch"

- Ensure the redirect URI in your `.env` matches exactly what's configured in Google Cloud Console
- Include the protocol (`http://` or `https://`)
- Match the port number if using localhost

### "Access blocked: This app's request is invalid"

- Verify the Gmail API is enabled in Google Cloud Console
- Check that the OAuth consent screen is properly configured
- Ensure you've added test users if the app is in testing mode

### "Invalid grant" errors

- The refresh token may have expired or been revoked
- User needs to re-authorize the application
- Visit `/auth/google/authorize` to reauthorize

### Token refresh fails

- Check that `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are correct
- Verify the user has a valid `google_refresh_token` in the database
- Check Rails logs for detailed error messages

## Production Deployment

1. Update `GOOGLE_REDIRECT_URI` to your production domain
2. Add the production redirect URI to Google Cloud Console
3. Set all environment variables in your production environment
4. Ensure database encryption keys are configured in production credentials
5. Use HTTPS for all OAuth redirects
6. Consider implementing token rotation and monitoring
