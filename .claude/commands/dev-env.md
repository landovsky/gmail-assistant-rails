Set up and manage the local development environment.

## Steps

1. **Check prerequisites:**
   - Ruby version matches `.ruby-version`
   - Bundler is installed (`gem install bundler` if not)
   - Database exists (`bin/rails db:create db:migrate`)

2. **Install dependencies:**
   ```bash
   bundle install
   ```

3. **Set up the database:**
   ```bash
   bin/rails db:setup
   ```

4. **Configure app.yml:**
   - Copy `config/app.yml.example` to `config/app.yml` if it doesn't exist
   - Set LLM API keys (ANTHROPIC_API_KEY or GOOGLE_API_KEY)
   - Set Gmail OAuth credentials path

5. **Start the development server:**
   ```bash
   bin/dev
   ```

6. **Verify health:**
   ```bash
   curl http://localhost:3000/api/health
   ```

## Environment Variables

- `GMA_SERVER_ADMIN_USER` / `GMA_SERVER_ADMIN_PASSWORD` - Basic auth (optional in dev)
- `ANTHROPIC_API_KEY` or `GOOGLE_API_KEY` - LLM provider key
- `GMA_ENVIRONMENT=development` - Environment flag
