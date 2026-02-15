module Api
  class BriefingController < ApplicationController
    CATEGORIES = %w[needs_response action_required payment_request fyi waiting].freeze
    MAX_ITEMS_PER_CATEGORY = 10

    def show
      user = User.find_by(email: params[:user_email])
      return render json: { detail: "User not found" }, status: :not_found unless user

      emails = user.emails
      summary = {}

      CATEGORIES.each do |category|
        category_emails = emails.by_classification(category)
        active_emails = category_emails.active

        items = active_emails.order(received_at: :desc).limit(MAX_ITEMS_PER_CATEGORY).map do |e|
          {
            thread_id: e.gmail_thread_id,
            subject: e.subject,
            sender: e.sender_email,
            status: e.status,
            confidence: e.confidence
          }
        end

        summary[category] = {
          total: category_emails.count,
          active: active_emails.count,
          items: items
        }
      end

      action_items = emails
        .where(classification: %w[needs_response action_required])
        .active
        .order(received_at: :desc)
        .map do |e|
          {
            thread_id: e.gmail_thread_id,
            subject: e.subject,
            sender: e.sender_email,
            status: e.status,
            classification: e.classification,
            confidence: e.confidence
          }
        end

      pending_drafts = emails.needs_response.pending.count

      render json: {
        user: user.email,
        summary: summary,
        pending_drafts: pending_drafts,
        action_items: action_items
      }
    end
  end
end
