Rails.application.config.after_initialize do
  next if Rails.env.test?

  if AppConfig.sentry_dsn.present? && AppConfig.environment != "development"
    Sentry.init do |config|
      config.dsn = AppConfig.sentry_dsn
      config.send_default_pii = true
      config.max_request_body_size = :always
      config.traces_sample_rate = 0
      config.send_client_reports = false
    end
  end
end
