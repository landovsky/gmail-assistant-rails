module Admin
  class EmailEventsController < BaseController
    def index
      scope = EmailEvent.order(created_at: :desc)
      scope = search_filter(scope, %w[gmail_thread_id event_type detail])
      result = paginate(scope)
      render json: result
    end
  end
end
