module Admin
  class UserSettingsController < BaseController
    def index
      scope = UserSetting.order(user_id: :desc)
      scope = search_filter(scope, %w[setting_key])
      result = paginate(scope)
      render json: result
    end

    def show
      user_setting = UserSetting.find(params[:id])
      render json: user_setting
    end
  end
end
