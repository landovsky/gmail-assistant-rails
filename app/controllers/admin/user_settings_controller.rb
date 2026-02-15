module Admin
  class UserSettingsController < BaseController
    def index
      scope = UserSetting.order(user_id: :desc)
      scope = search_filter(scope, %w[setting_key])
      result = paginate(scope)
      render json: result
    end
  end
end
