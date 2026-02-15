# frozen_string_literal: true

module Admin
  module Api
    # Admin API for viewing emails
    class EmailsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /admin/api/emails
      # List all emails with optional filtering
      def index
        emails = Email.all.includes(:user)

        # Apply filters if provided
        emails = emails.where(status: params[:status]) if params[:status].present?
        emails = emails.where(classification: params[:classification]) if params[:classification].present?

        # Order by most recent first
        emails = emails.order(created_at: :desc)

        render json: emails.map { |email| serialize_email(email) }, status: :ok
      rescue => e
        Rails.logger.error "Admin emails API error: #{e.class} - #{e.message}"
        render json: { detail: e.message }, status: :internal_server_error
      end

      private

      def serialize_email(email)
        {
          id: email.id,
          user_id: email.user_id,
          user_email: email.user.email,
          gmail_thread_id: email.gmail_thread_id,
          gmail_message_id: email.gmail_message_id,
          sender_email: email.sender_email,
          sender_name: email.sender_name,
          subject: email.subject,
          snippet: email.snippet,
          received_at: email.received_at,
          classification: email.classification,
          confidence: email.confidence,
          reasoning: email.reasoning,
          detected_language: email.detected_language,
          resolved_style: email.resolved_style,
          message_count: email.message_count,
          status: email.status,
          draft_id: email.draft_id,
          rework_count: email.rework_count,
          last_rework_instruction: email.last_rework_instruction,
          vendor_name: email.vendor_name,
          processed_at: email.processed_at,
          drafted_at: email.drafted_at,
          acted_at: email.acted_at,
          created_at: email.created_at,
          updated_at: email.updated_at
        }
      end
    end
  end
end
