module Api
  class SyncController < ApplicationController
    def create
      user_id = (params[:user_id] || 1).to_i
      full = ActiveModel::Type::Boolean.new.cast(params[:full]) || false

      user = User.find(user_id)

      if full
        SyncState.where(user_id: user.id).delete_all
      end

      Job.create!(
        user: user,
        job_type: "sync",
        payload: { full: full }.to_json
      )

      render json: { queued: true, user_id: user.id, full: full }
    rescue ActiveRecord::RecordNotFound
      render json: { detail: "User not found" }, status: :not_found
    end
  end
end
