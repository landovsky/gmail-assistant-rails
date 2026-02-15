Rails.application.config.after_initialize do
  server = AppConfig.server
  if server["admin_user"].present? && server["admin_password"].present?
    Rails.application.config.middleware.use BasicAuthMiddleware
  end
end
