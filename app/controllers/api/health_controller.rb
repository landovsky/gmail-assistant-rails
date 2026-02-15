# frozen_string_literal: true

module Api
  # Health check endpoint for monitoring and load balancers
  class HealthController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:show]

    # GET /api/health
    # Returns service health status including database and queue connectivity
    def show
      health_status = {
        status: "ok",
        db: check_database,
        queue: check_queue
      }

      render json: health_status, status: :ok
    rescue => e
      Rails.logger.error "Health check error: #{e.class} - #{e.message}"
      render json: { status: "error", detail: e.message }, status: :internal_server_error
    end

    private

    def check_database
      # Try to execute a simple query to verify database connectivity
      ActiveRecord::Base.connection.execute("SELECT 1")
      "connected"
    rescue => e
      Rails.logger.error "Database health check failed: #{e.message}"
      "disconnected"
    end

    def check_queue
      # Check if Solid Queue is running by checking if jobs table is accessible
      Job.count
      "running"
    rescue => e
      Rails.logger.error "Queue health check failed: #{e.message}"
      "stopped"
    end
  end
end
