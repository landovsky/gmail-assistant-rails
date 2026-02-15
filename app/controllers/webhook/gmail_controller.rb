module Webhook
  class GmailController < ApplicationController
    def create
      data = decode_notification(params)
      return render json: { detail: "Invalid notification format" }, status: :bad_request unless data

      email_address = data["emailAddress"]
      history_id = data["historyId"]

      unless email_address.present? && history_id.present?
        return render json: { detail: "Missing emailAddress or historyId" }, status: :bad_request
      end

      user = User.find_by(email: email_address)
      unless user
        Rails.logger.info("Webhook: unknown email #{email_address}, ignoring")
        return render json: { status: "ignored" }, status: :ok
      end

      Job.create!(
        user: user,
        job_type: "sync",
        payload: { history_id: history_id }.to_json
      )

      render json: { status: "processed" }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Webhook error: #{e.message}")
      render json: { detail: "Internal error" }, status: :internal_server_error
    end

    private

    def decode_notification(params)
      message = params[:message]
      return nil unless message.is_a?(ActionController::Parameters) || message.is_a?(Hash)

      encoded_data = message[:data]
      return nil unless encoded_data.present?

      decoded = Base64.decode64(encoded_data)
      JSON.parse(decoded)
    rescue JSON::ParserError, ArgumentError
      nil
    end
  end
end
