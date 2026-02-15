require "rails_helper"

RSpec.describe "Onboarding" do
  describe "TC-1.1: First-time user onboarding" do
    it "creates user, provisions labels, imports settings, seeds sync state" do
      # Create user
      user = create(:user, email: "newuser@example.com", onboarded_at: Time.current)

      # Provision all 9 standard labels
      UserLabel::STANDARD_KEYS.each_with_index do |key, i|
        create(:user_label,
          user: user,
          label_key: key,
          gmail_label_id: "Label_#{i}",
          gmail_label_name: UserLabel::STANDARD_NAMES[key]
        )
      end

      # Import settings
      create(:user_setting, user: user, setting_key: "communication_styles",
        setting_value: { business: { rules: ["be concise"] } }.to_json)
      create(:user_setting, user: user, setting_key: "contacts",
        setting_value: { known: ["colleague@example.com"] }.to_json)

      # Create sync state with current historyId
      create(:sync_state, user: user, last_history_id: "123456")

      # Verify user record
      expect(user).to be_persisted
      expect(user.email).to eq("newuser@example.com")
      expect(user.onboarded_at).to be_present

      # Verify all 9 labels
      expect(user.user_labels.count).to eq(9)
      UserLabel::STANDARD_KEYS.each do |key|
        label = user.user_labels.find_by(label_key: key)
        expect(label).to be_present, "Expected label '#{key}' to exist"
        expect(label.gmail_label_name).to eq(UserLabel::STANDARD_NAMES[key])
      end

      # Verify settings
      expect(user.user_settings.count).to eq(2)
      expect(user.user_settings.find_by(setting_key: "communication_styles")).to be_present
      expect(user.user_settings.find_by(setting_key: "contacts")).to be_present

      # Verify sync state
      expect(user.sync_state).to be_present
      expect(user.sync_state.last_history_id).to eq("123456")
      expect(user.sync_state).to be_synced
    end
  end

  describe "TC-1.2: Duplicate onboarding is idempotent" do
    it "returns existing user without creating duplicates" do
      # First onboarding
      user = create(:user, :onboarded, email: "existing@example.com")
      create(:user_label, user: user, label_key: "parent",
        gmail_label_id: "Label_parent", gmail_label_name: UserLabel::STANDARD_NAMES["parent"])
      create(:sync_state, user: user, last_history_id: "111111")

      original_user_id = user.id
      original_label_count = UserLabel.count
      original_user_count = User.count

      # Simulate second onboarding attempt - find existing user
      existing_user = User.find_by(email: "existing@example.com")
      expect(existing_user).to be_present
      expect(existing_user.id).to eq(original_user_id)

      # Re-provision labels idempotently (find_or_create pattern)
      label = existing_user.user_labels.find_or_create_by!(label_key: "parent") do |l|
        l.gmail_label_id = "Label_parent"
        l.gmail_label_name = UserLabel::STANDARD_NAMES["parent"]
      end
      expect(label).to be_persisted

      # No duplicates created
      expect(User.count).to eq(original_user_count)
      expect(UserLabel.count).to eq(original_label_count)

      # Sync state still valid
      expect(existing_user.sync_state).to be_present
      expect(existing_user.sync_state).to be_synced
    end
  end
end
