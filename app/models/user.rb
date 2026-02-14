class User < ApplicationRecord
  # Associations
  has_many :user_labels, dependent: :destroy
  has_many :user_settings, dependent: :destroy
  has_one :sync_state, dependent: :destroy
  has_many :emails, dependent: :destroy
  has_many :email_events, dependent: :destroy
  has_many :jobs, dependent: :destroy
  has_many :llm_calls, dependent: :destroy
  has_many :agent_runs, dependent: :destroy

  # Encrypted attributes for OAuth tokens
  encrypts :google_access_token
  encrypts :google_refresh_token

  # Validations
  validates :email, presence: true, uniqueness: true

  # Check if OAuth tokens are present
  def google_authenticated?
    google_refresh_token.present?
  end

  # Check if access token needs refresh
  def google_token_expired?
    google_token_expires_at.nil? || google_token_expires_at < Time.current
  end

  # Store OAuth tokens from Google response
  def store_google_tokens(access_token:, refresh_token: nil, expires_at:)
    update!(
      google_access_token: access_token,
      google_refresh_token: refresh_token || google_refresh_token,
      google_token_expires_at: expires_at
    )
  end
end
