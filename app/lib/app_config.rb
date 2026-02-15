class AppConfig
  class << self
    def config
      @config ||= load_config
    end

    def reload!
      @config = load_config
    end

    # Top-level accessors
    def auth = config["auth"]
    def database = config["database"]
    def llm = config["llm"]
    def sync = config["sync"]
    def server = config["server"]
    def routing = config["routing"]
    def agent = config["agent"]
    def environment = config["environment"]
    def sentry_dsn = config["sentry_dsn"]

    private

    def load_config
      yaml = YAML.load_file(Rails.root.join("config", "app.yml"))
      apply_env_overrides(yaml)
    end

    def apply_env_overrides(config)
      # GMA_ prefixed env vars override YAML values
      ENV_MAPPINGS.each do |env_key, config_path|
        value = ENV[env_key]
        next unless value

        keys = config_path.split(".")
        target = config
        keys[0..-2].each { |k| target = target[k] ||= {} }
        target[keys.last] = cast_value(value, target[keys.last])
      end
      config
    end

    def cast_value(value, existing)
      case existing
      when Integer then value.to_i
      when Float then value.to_f
      when TrueClass, FalseClass then %w[true 1 yes].include?(value.downcase)
      else value
      end
    end

    ENV_MAPPINGS = {
      "GMA_AUTH_MODE" => "auth.mode",
      "GMA_DB_BACKEND" => "database.backend",
      "GMA_DB_SQLITE_PATH" => "database.sqlite_path",
      "GMA_LLM_CLASSIFY_MODEL" => "llm.classify_model",
      "GMA_LLM_DRAFT_MODEL" => "llm.draft_model",
      "GMA_LLM_CONTEXT_MODEL" => "llm.context_model",
      "GMA_SERVER_HOST" => "server.host",
      "GMA_SERVER_PORT" => "server.port",
      "GMA_SERVER_LOG_LEVEL" => "server.log_level",
      "GMA_SERVER_WORKER_CONCURRENCY" => "server.worker_concurrency",
      "GMA_SERVER_ADMIN_USER" => "server.admin_user",
      "GMA_SERVER_ADMIN_PASSWORD" => "server.admin_password",
      "GMA_SYNC_PUBSUB_TOPIC" => "sync.pubsub_topic",
      "GMA_SYNC_FALLBACK_INTERVAL_MINUTES" => "sync.fallback_interval_minutes",
      "GMA_SYNC_FULL_SYNC_INTERVAL_HOURS" => "sync.full_sync_interval_hours",
      "GMA_SYNC_FULL_SYNC_DAYS" => "sync.full_sync_days",
      "GMA_ENVIRONMENT" => "environment",
      "GMA_SENTRY_DSN" => "sentry_dsn"
    }.freeze
  end
end
