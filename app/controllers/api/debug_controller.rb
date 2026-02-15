module Api
  class DebugController < ApplicationController
    def email_debug
      email = Email.find(params[:email_id])
      events = EmailEvent.where(user_id: email.user_id, gmail_thread_id: email.gmail_thread_id)
                         .order(:created_at)
      llm_calls = LlmCall.where(gmail_thread_id: email.gmail_thread_id)
                         .order(:created_at)
      agent_runs = AgentRun.where(user_id: email.user_id, gmail_thread_id: email.gmail_thread_id)
                           .order(:created_at)

      timeline = build_timeline(events, llm_calls, agent_runs)

      summary = {
        event_count: events.count,
        llm_call_count: llm_calls.count,
        agent_run_count: agent_runs.count,
        classifications: events.where(event_type: "classified").count,
        drafts_created: events.where(event_type: "draft_created").count,
        errors: events.where(event_type: "error").count
      }

      render json: {
        email: email,
        events: events,
        llm_calls: llm_calls,
        agent_runs: agent_runs,
        timeline: timeline,
        summary: summary
      }
    rescue ActiveRecord::RecordNotFound
      render json: { detail: "Email not found" }, status: :not_found
    end

    def emails_list
      scope = Email.all
      scope = scope.by_status(params[:status]) if params[:status].present?
      scope = scope.by_classification(params[:classification]) if params[:classification].present?

      if params[:q].present?
        q = "%#{params[:q]}%"
        scope = scope.left_joins(:user)
                     .joins("LEFT JOIN llm_calls ON llm_calls.gmail_thread_id = emails.gmail_thread_id")
                     .where(
                       "emails.subject LIKE :q OR emails.snippet LIKE :q OR emails.reasoning LIKE :q " \
                       "OR emails.sender_email LIKE :q OR emails.gmail_thread_id LIKE :q " \
                       "OR llm_calls.user_message LIKE :q",
                       q: q
                     ).distinct
      end

      limit = [ (params[:limit] || 50).to_i, 500 ].min
      emails = scope.order(id: :desc).limit(limit)

      emails_with_counts = emails.map do |email|
        email_json = email.as_json
        email_json["event_count"] = EmailEvent.where(
          user_id: email.user_id, gmail_thread_id: email.gmail_thread_id
        ).count
        email_json["llm_call_count"] = LlmCall.where(
          gmail_thread_id: email.gmail_thread_id
        ).count
        email_json["agent_run_count"] = AgentRun.where(
          user_id: email.user_id, gmail_thread_id: email.gmail_thread_id
        ).count
        email_json
      end

      render json: {
        count: emails_with_counts.size,
        limit: limit,
        filters: {
          status: params[:status],
          classification: params[:classification],
          q: params[:q]
        },
        emails: emails_with_counts
      }
    end

    def reclassify
      email = Email.find(params[:email_id])

      unless email.gmail_message_id.present?
        return render json: { detail: "Email has no Gmail message ID" }, status: :bad_request
      end

      job = Job.create!(
        user_id: email.user_id,
        job_type: "classify",
        payload: {
          gmail_message_id: email.gmail_message_id,
          gmail_thread_id: email.gmail_thread_id,
          force: true
        }.to_json
      )

      render json: {
        status: "queued",
        job_id: job.id,
        email_id: email.id,
        current_classification: email.classification
      }
    rescue ActiveRecord::RecordNotFound
      render json: { detail: "Email not found" }, status: :not_found
    end

    private

    def build_timeline(events, llm_calls, agent_runs)
      timeline = []

      events.each do |e|
        timeline << {
          type: "event",
          timestamp: e.created_at,
          event_type: e.event_type,
          detail: e.detail
        }
      end

      llm_calls.each do |c|
        timeline << {
          type: "llm_call",
          timestamp: c.created_at,
          call_type: c.call_type,
          model: c.model,
          total_tokens: c.total_tokens,
          latency_ms: c.latency_ms
        }
      end

      agent_runs.each do |r|
        timeline << {
          type: "agent_run",
          timestamp: r.created_at,
          profile: r.profile,
          status: r.status,
          iterations: r.iterations
        }
      end

      timeline.sort_by { |t| t[:timestamp] || Time.at(0) }
    end
  end
end
