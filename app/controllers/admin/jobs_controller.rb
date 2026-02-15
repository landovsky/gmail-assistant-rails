module Admin
  class JobsController < BaseController
    def index
      scope = Job.order(created_at: :desc)
      scope = scope.where(job_type: params[:job_type]) if params[:job_type].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = search_filter(scope, %w[job_type status])
      result = paginate(scope)
      render json: result
    end
  end
end
