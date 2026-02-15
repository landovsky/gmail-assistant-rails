module Admin
  class UserLabelsController < BaseController
    def index
      scope = UserLabel.order(user_id: :desc)
      scope = search_filter(scope, %w[label_key gmail_label_name])
      result = paginate(scope)
      render json: result
    end

    def show
      user_label = UserLabel.find(params[:id])
      render json: user_label
    end
  end
end
