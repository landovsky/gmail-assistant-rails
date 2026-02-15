module Admin
  class SyncStatesController < BaseController
    def index
      scope = SyncState.order(user_id: :desc)
      result = paginate(scope)
      render json: result
    end

    def show
      sync_state = SyncState.find(params[:id])
      render json: sync_state
    end
  end
end
