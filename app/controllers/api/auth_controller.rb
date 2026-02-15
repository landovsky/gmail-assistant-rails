module Api
  class AuthController < ApplicationController
    def init
      # Placeholder for OAuth bootstrap - returns mock response
      render json: {
        user_id: 1,
        email: "user@gmail.com",
        onboarded: true,
        migrated_v1: ActiveModel::Type::Boolean.new.cast(params[:migrate_v1]) != false
      }
    end
  end
end
