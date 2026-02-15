module Admin
  class EmailsController < BaseController
    def index
      scope = Email.order(id: :desc)
      scope = scope.by_status(params[:status]) if params[:status].present?
      scope = scope.by_classification(params[:classification]) if params[:classification].present?
      scope = search_filter(scope, %w[subject sender_email gmail_thread_id])
      result = paginate(scope)
      render json: result
    end

    def show
      email = Email.find(params[:id])
      render json: email
    end
  end
end
