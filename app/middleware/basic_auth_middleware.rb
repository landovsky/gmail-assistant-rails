class BasicAuthMiddleware
  PUBLIC_PATHS = [
    %r{\A/webhook/},
    %r{\A/api/health\z}
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) if public_path?(env["PATH_INFO"])

    auth = Rack::Auth::Basic::Request.new(env)

    if auth.provided? && auth.basic? && valid_credentials?(auth.credentials)
      @app.call(env)
    else
      unauthorized_response
    end
  end

  private

  def public_path?(path)
    PUBLIC_PATHS.any? { |pattern| pattern.match?(path) }
  end

  def valid_credentials?(credentials)
    username, password = credentials
    server_config = AppConfig.server
    username == server_config["admin_user"] && password == server_config["admin_password"]
  end

  def unauthorized_response
    [
      401,
      {
        "Content-Type" => "application/json",
        "WWW-Authenticate" => 'Basic realm="Gmail Assistant"'
      },
      [ { detail: "Unauthorized" }.to_json ]
    ]
  end
end
