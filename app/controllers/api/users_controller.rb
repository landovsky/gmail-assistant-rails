module Api
  class UsersController < ApplicationController
    def index
      users = User.active.order(id: :desc)
      render json: users.map { |u|
        {
          id: u.id,
          email: u.email,
          display_name: u.display_name,
          onboarded_at: u.onboarded_at
        }
      }
    end

    def create
      if User.exists?(email: params[:email])
        return render json: { detail: "User with this email already exists" }, status: :conflict
      end

      user = User.create!(
        email: params[:email],
        display_name: params[:display_name]
      )

      render json: { id: user.id, email: user.email }
    end

    def settings
      user = User.find(params[:user_id])
      settings = user.user_settings.each_with_object({}) do |s, hash|
        hash[s.setting_key] = s.parsed_value
      end
      render json: settings
    rescue ActiveRecord::RecordNotFound
      render json: { detail: "User not found" }, status: :not_found
    end

    def update_settings
      user = User.find(params[:user_id])
      key = params[:key]
      value = params[:value]
      encoded_value = value.is_a?(String) ? value : value.to_json

      existing = user.user_settings.find_by(setting_key: key)
      if existing
        UserSetting.where(user_id: user.id, setting_key: key)
                   .update_all(setting_value: encoded_value)
      else
        UserSetting.create!(user: user, setting_key: key, setting_value: encoded_value)
      end

      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { detail: "User not found" }, status: :not_found
    end

    def labels
      user = User.find(params[:user_id])
      labels = user.user_labels.each_with_object({}) do |l, hash|
        hash[l.label_key] = l.gmail_label_id
      end
      render json: labels
    rescue ActiveRecord::RecordNotFound
      render json: { detail: "User not found" }, status: :not_found
    end

    def emails
      user = User.find(params[:user_id])
      scope = user.emails

      if params[:status].present? || params[:classification].present?
        scope = scope.by_status(params[:status]) if params[:status].present?
        scope = scope.by_classification(params[:classification]) if params[:classification].present?
      else
        scope = scope.by_status("pending")
      end

      render json: scope.order(id: :desc)
    rescue ActiveRecord::RecordNotFound
      render json: { detail: "User not found" }, status: :not_found
    end
  end
end
