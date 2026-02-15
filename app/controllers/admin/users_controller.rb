module Admin
  class UsersController < BaseController
    def index
      scope = User.order(id: :desc)
      scope = search_filter(scope, %w[email display_name])
      result = paginate(scope)
      render json: result
    end
  end
end
