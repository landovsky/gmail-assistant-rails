# frozen_string_literal: true

# Google OAuth2 configuration
# Supports both Rails credentials and environment variables
# Priority: ENV vars > Rails credentials

Rails.application.config.google_oauth = {
  client_id: ENV["GOOGLE_CLIENT_ID"] ||
    (Rails.application.credentials.google_oauth&.dig(:client_id) rescue nil),
  client_secret: ENV["GOOGLE_CLIENT_SECRET"] ||
    (Rails.application.credentials.google_oauth&.dig(:client_secret) rescue nil),
  redirect_uri: ENV["GOOGLE_REDIRECT_URI"] ||
    (Rails.application.credentials.google_oauth&.dig(:redirect_uri) rescue nil) ||
    "http://localhost:3000/auth/google/callback"
}

# Gmail API scope
Rails.application.config.gmail_scope = "https://www.googleapis.com/auth/gmail.modify"
