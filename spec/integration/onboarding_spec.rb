require "rails_helper"

RSpec.describe "Onboarding", type: :request do
  describe "TC-1.1: First-time user onboarding" do
    xit "creates user, provisions labels, imports settings, seeds sync state" do
      # Preconditions: No users in the database. OAuth credentials available.
      # Actions: Call POST /api/auth/init
      # Expected:
      # - User record created in users table with email from Gmail profile
      # - onboarded_at is set
      # - 9 labels created in Gmail (or existing ones found)
      # - All 9 label mappings stored in user_labels
      # - Communication styles and contacts imported to user_settings
      # - Sync state created with current historyId from Gmail profile
      # - Response contains user_id and email
    end
  end

  describe "TC-1.2: Duplicate onboarding is idempotent" do
    xit "returns existing user without creating duplicates" do
      # Preconditions: User already exists and is onboarded.
      # Actions: Call POST /api/auth/init again
      # Expected:
      # - No duplicate user created
      # - Existing user_id returned
      # - Labels re-provisioned (idempotent)
      # - No errors
    end
  end
end
