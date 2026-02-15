module Admin
  class LlmCallsController < BaseController
    def index
      scope = LlmCall.order(created_at: :desc)
      scope = search_filter(scope, %w[gmail_thread_id call_type model])
      result = paginate(scope)
      render json: result
    end
  end
end
