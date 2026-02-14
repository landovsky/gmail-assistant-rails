# frozen_string_literal: true

module Auth
  class GoogleController < ApplicationController
    # Initiates OAuth2 flow - redirects to Google consent screen
    def authorize
      client = google_oauth_client
      authorization_url = client.authorization_uri(
        scope: Rails.application.config.gmail_scope
      ).to_s

      redirect_to authorization_url, allow_other_host: true
    end

    # OAuth2 callback - exchanges code for tokens
    def callback
      code = params[:code]
      error = params[:error]

      if error.present?
        render plain: "OAuth error: #{error}", status: :bad_request
        return
      end

      unless code.present?
        render plain: "Missing authorization code", status: :bad_request
        return
      end

      begin
        client = google_oauth_client
        client.code = code
        client.fetch_access_token!

        # Find or create user by email
        user_info = fetch_user_email(client.access_token)
        user = User.find_or_create_by!(email: user_info[:email]) do |u|
          u.display_name = user_info[:name]
        end

        # Store tokens
        user.store_google_tokens(
          access_token: client.access_token,
          refresh_token: client.refresh_token,
          expires_at: Time.at(client.expires_at)
        )

        render plain: "Authentication successful! You can close this window."
      rescue StandardError => e
        Rails.logger.error "OAuth callback error: #{e.message}"
        render plain: "Authentication failed: #{e.message}", status: :internal_server_error
      end
    end

    private

    def google_oauth_client
      Signet::OAuth2::Client.new(
        client_id: Rails.application.config.google_oauth[:client_id],
        client_secret: Rails.application.config.google_oauth[:client_secret],
        authorization_uri: "https://accounts.google.com/o/oauth2/auth",
        token_credential_uri: "https://oauth2.googleapis.com/token",
        redirect_uri: Rails.application.config.google_oauth[:redirect_uri],
        scope: Rails.application.config.gmail_scope
      )
    end

    def fetch_user_email(access_token)
      uri = URI("https://www.googleapis.com/gmail/v1/users/me/profile")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{access_token}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        { email: data["emailAddress"], name: data["emailAddress"].split("@").first }
      else
        raise "Failed to fetch user profile: #{response.code} #{response.body}"
      end
    end
  end
end
