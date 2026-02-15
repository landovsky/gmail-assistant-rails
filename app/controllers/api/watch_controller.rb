module Api
  class WatchController < ApplicationController
    def create
      topic = AppConfig.sync["pubsub_topic"]
      if topic.blank?
        return render json: { detail: "No Pub/Sub topic configured" }, status: :bad_request
      end

      if params[:user_id].present?
        user = User.find(params[:user_id])
        register_watch_for(user)
        render json: {
          user_id: user.id,
          email: user.email,
          watch_registered: true
        }
      else
        users = User.active
        results = users.map do |user|
          register_watch_for(user)
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

    private

    def register_watch_for(user)
      client = Gmail::Client.new(user_email: user.email)
      manager = Gmail::WatchManager.new(client)
      manager.register_watch(user)
    end
  end
end
