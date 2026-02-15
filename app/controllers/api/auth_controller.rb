module Api
  class AuthController < ApplicationController
    def init
      migrate_v1 = ActiveModel::Type::Boolean.new.cast(params[:migrate_v1]) != false

      # Build Gmail client (triggers OAuth consent if no cached token)
      begin
        client = Gmail::Client.new
      rescue StandardError => e
        return render json: { detail: "OAuth credentials error: #{e.message}" }, status: :bad_request
      end

      # Get user profile from Gmail
      profile = client.get_profile
      email = profile.email_address
      unless email.present?
        return render json: { detail: "Cannot retrieve email from Gmail profile" }, status: :internal_server_error
      end

      # Find or create user
      user = User.find_or_initialize_by(email: email)
      user.display_name = params[:display_name] if params[:display_name].present?
      user.is_active = true
      user.save!

      # Provision Gmail labels
      provision_labels(client, user)

      # Import settings from YAML config files
      import_settings(user)

      # Migrate v1 label IDs if requested
      migrated = false
      if migrate_v1
        migrated = migrate_v1_labels(user)
      end

      # Seed sync state with current history ID
      seed_sync_state(client, user)

      # Mark user as onboarded
      user.update!(onboarded_at: Time.current)

      render json: {
        user_id: user.id,
        email: user.email,
        onboarded: true,
        migrated_v1: migrated
      }
    end

    private

    def provision_labels(client, user)
      # Get existing labels from Gmail
      existing_labels = client.list_labels.labels || []
      existing_by_name = existing_labels.each_with_object({}) do |label, hash|
        hash[label.name] = label
      end

      UserLabel::STANDARD_NAMES.each do |key, name|
        # Skip if already provisioned locally
        next if user.user_labels.exists?(label_key: key)

        if existing_by_name[name]
          # Label already exists in Gmail
          gmail_label = existing_by_name[name]
        else
          # Create label in Gmail
          gmail_label = client.create_label(name)
        end

        user.user_labels.create!(
          label_key: key,
          gmail_label_id: gmail_label.id,
          gmail_label_name: gmail_label.name
        )
      end
    end

    def import_settings(user)
      # Import communication_styles from YAML
      styles_file = Rails.root.join("config", "communication_styles.yml")
      if File.exist?(styles_file)
        styles = YAML.load_file(styles_file)
        upsert_setting(user, "communication_styles", styles)
      end

      # Import contacts from YAML
      contacts_file = Rails.root.join("config", "contacts.yml")
      if File.exist?(contacts_file)
        contacts = YAML.load_file(contacts_file)
        upsert_setting(user, "contacts", contacts)
      end
    end

    def upsert_setting(user, key, value)
      encoded = value.is_a?(String) ? value : value.to_json
      existing = user.user_settings.find_by(setting_key: key)
      if existing
        existing.update!(setting_value: encoded)
      else
        user.user_settings.create!(setting_key: key, setting_value: encoded)
      end
    end

    def migrate_v1_labels(user)
      label_ids_file = Rails.root.join("config", "label_ids.yml")
      return false unless File.exist?(label_ids_file)

      label_ids = YAML.load_file(label_ids_file)
      return false unless label_ids.is_a?(Hash)

      label_ids.each do |key, gmail_id|
        next unless gmail_id.present?

        UserLabel.where(user_id: user.id, label_key: key)
                 .update_all(gmail_label_id: gmail_id)
      end

      true
    end

    def seed_sync_state(client, user)
      profile = client.get_profile
      history_id = profile.history_id&.to_s || "0"

      sync_state = user.sync_state || user.build_sync_state
      sync_state.last_history_id = history_id
      sync_state.last_sync_at = Time.current
      sync_state.save!
    end
  end
end
