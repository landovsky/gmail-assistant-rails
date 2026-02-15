module Admin
  class LlmCallsController < BaseController
    def index
      scope = LlmCall.order(created_at: :desc)
      scope = scope.where(call_type: params[:call_type]) if params[:call_type].present?
      scope = scope.where(model: params[:model]) if params[:model].present?
      scope = search_filter(scope, %w[gmail_thread_id call_type model])
      result = paginate(scope)
      render json: result
    end

    def show
      llm_call = LlmCall.find(params[:id])
      render json: llm_call
    end
  end
end
