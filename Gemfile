source "https://rubygems.org"

ruby file: ".ruby-version"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.6"
gem "puma", ">= 7.0"
gem "bootsnap", require: false
gem "thruster", require: false
gem "solid_cache"
gem "solid_queue"
gem "strong_migrations", "~> 2.8"
gem "tzinfo-data", platforms: %i[windows jruby]

# ActiveSupport 8.1.3 calls JSON.parse with a positional options hash, which json 3 rejects.
gem "json", "< 3"

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails"
  gem "factory_bot_rails"
end

group :test do
  gem "simplecov", require: false
end
