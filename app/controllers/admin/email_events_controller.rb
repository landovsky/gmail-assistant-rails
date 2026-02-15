module Admin
  class EmailEventsController < BaseController
    def index
      scope = EmailEvent.order(created_at: :desc)
      scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
      scope = search_filter(scope, %w[gmail_thread_id event_type detail])
      result = paginate(scope)
      render json: result
    end

    def show
      event = EmailEvent.find(params[:id])
      render json: event
    end
  end
end
