require "active_support/core_ext/integer/time"
# lib is autoloaded (config.autoload_lib in config/application.rb), but the
# autoloader is not active yet this early in boot: a plain require here is
# the standard way to reach a lib class from an environment file.
require_relative "../../lib/structured_log_formatter"

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

  # One JSON object per line, tagged with the request, user and
  # organization through Current instead of log_tags (StructuredLogFormatter):
  # TaggedLogging only ever prepends bracketed text to the message, which
  # cannot become real JSON fields (docs/security.md's Observability target).
  config.logger = ActiveSupport::Logger.new(STDOUT, formatter: StructuredLogFormatter.new)
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
