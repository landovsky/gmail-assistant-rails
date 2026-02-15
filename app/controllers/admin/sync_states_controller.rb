module Admin
  class SyncStatesController < BaseController
    def index
      scope = SyncState.order(user_id: :desc)
      result = paginate(scope)
      render json: result
    end
  end
end
