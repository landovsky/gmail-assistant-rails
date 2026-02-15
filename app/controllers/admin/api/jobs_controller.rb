# frozen_string_literal: true

module Admin
  module Api
    # Admin API for viewing job queue status
    class JobsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /admin/api/jobs
      # List all jobs with optional filtering
      def index
        jobs = Job.all.includes(:user)

        # Apply filters if provided
        jobs = jobs.where(job_type: params[:type]) if params[:type].present?
        jobs = jobs.where(status: params[:status]) if params[:status].present?

        # Order by most recent first
        jobs = jobs.order(created_at: :desc)

        render json: jobs.map { |job| serialize_job(job) }, status: :ok
      rescue => e
        Rails.logger.error "Admin jobs API error: #{e.class} - #{e.message}"
        render json: { detail: e.message }, status: :internal_server_error
      end

      private

      def serialize_job(job)
        {
          id: job.id,
          user_id: job.user_id,
          user_email: job.user.email,
          job_type: job.job_type,
          status: job.status,
          payload: job.payload,
          attempts: job.attempts,
          max_attempts: job.max_attempts,
          error_message: job.error_message,
          started_at: job.started_at,
          completed_at: job.completed_at,
          created_at: job.created_at,
          updated_at: job.updated_at
        }
      end
    end
  end
end
