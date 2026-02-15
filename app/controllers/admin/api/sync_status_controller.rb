# frozen_string_literal: true

module Admin
  module Api
    # Admin API for viewing sync status
    class SyncStatusController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /admin/api/sync_status
      # Show sync state for all users
      def index
        sync_states = SyncState.all.includes(:user)

        render json: sync_states.map { |state| serialize_sync_state(state) }, status: :ok
      rescue => e
        Rails.logger.error "Admin sync status API error: #{e.class} - #{e.message}"
        render json: { detail: e.message }, status: :internal_server_error
      end

      private

      def serialize_sync_state(state)
        {
          id: state.id,
          user_id: state.user_id,
          user_email: state.user.email,
          last_history_id: state.last_history_id,
          last_sync_at: state.last_sync_at,
          watch_expiration: state.watch_expiration,
          watch_resource_id: state.watch_resource_id,
          created_at: state.created_at,
          updated_at: state.updated_at
        }
      end
    end
  end
end
