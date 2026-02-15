module Api
  class WatchController < ApplicationController
    def create
      # Placeholder for watch registration
      if params[:user_id].present?
        user = User.find(params[:user_id])
        render json: {
          user_id: user.id,
          email: user.email,
          watch_registered: true
        }
      else
        users = User.active
        results = users.map do |user|
          {
            user_id: user.id,
            email: user.email,
            watch_registered: true
          }
        end
        render json: { results: results }
      end
    rescue ActiveRecord::RecordNotFound
      render json: { detail: "User not found" }, status: :not_found
    end

    def status
      states = SyncState.includes(:user).map do |state|
        {
          user_id: state.user_id,
          email: state.user.email,
          last_history_id: state.last_history_id,
          last_sync_at: state.last_sync_at,
          watch_expiration: state.watch_expiration,
          watch_resource_id: state.watch_resource_id
        }
      end
      render json: states
    end
  end
end
