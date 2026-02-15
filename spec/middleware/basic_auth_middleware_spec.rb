require "rails_helper"

RSpec.describe BasicAuthMiddleware do
  let(:inner_app) { ->(env) { [ 200, { "Content-Type" => "application/json" }, [ '{"ok":true}' ] ] } }
  let(:middleware) { described_class.new(inner_app) }

  before do
    allow(AppConfig).to receive(:server).and_return({
      "admin_user" => "admin",
      "admin_password" => "secret"
    })
  end

  def env_for(path, headers = {})
    Rack::MockRequest.env_for(path, headers)
  end

  def basic_auth_header(user, pass)
    "Basic " + Base64.strict_encode64("#{user}:#{pass}")
  end

  describe "protected paths" do
    it "returns 401 without credentials" do
      status, headers, _body = middleware.call(env_for("/api/users"))
      expect(status).to eq(401)
      expect(headers["WWW-Authenticate"]).to include("Basic")
    end

    it "returns 401 with wrong credentials" do
      env = env_for("/api/users", "HTTP_AUTHORIZATION" => basic_auth_header("wrong", "creds"))
      status, _headers, _body = middleware.call(env)
      expect(status).to eq(401)
    end

    it "allows access with correct credentials" do
      env = env_for("/api/users", "HTTP_AUTHORIZATION" => basic_auth_header("admin", "secret"))
      status, _headers, _body = middleware.call(env)
      expect(status).to eq(200)
    end
  end

  describe "public paths" do
    it "allows /webhook/gmail without auth" do
      status, _headers, _body = middleware.call(env_for("/webhook/gmail"))
      expect(status).to eq(200)
    end

    it "allows /api/health without auth" do
      status, _headers, _body = middleware.call(env_for("/api/health"))
      expect(status).to eq(200)
    end

    it "does not allow /api/users without auth" do
      status, _headers, _body = middleware.call(env_for("/api/users"))
      expect(status).to eq(401)
    end
  end
end
