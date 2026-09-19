require "active_support/core_ext/integer/time"

app_host = ENV.fetch("APP_HOST") { ENV.fetch("RENDER_EXTERNAL_HOSTNAME") }

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}, immutable" }

  config.assume_ssl = true
  config.force_ssl = true
  config.hosts = [ app_host ]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  config.log_tags = [ :request_id ]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false

  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :solid_queue
  config.action_mailer.default_url_options = { host: app_host, protocol: "https" }

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]
end
