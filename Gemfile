source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

# Google APIs
gem "google-apis-gmail_v1"
gem "googleauth"

# LLM integration (OpenAI-compatible)
gem "ruby-openai"

# Configuration
gem "anyway_config"

# HTTP client
gem "faraday"

# Background scheduling
gem "rufus-scheduler"

# Sentry error tracking
gem "sentry-ruby"
gem "sentry-rails"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "webmock"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
end
