require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true
  config.action_controller.perform_caching = false
  config.cache_store = :memory_store

  config.active_job.queue_adapter = :solid_queue
  config.active_job.verbose_enqueue_logs = true

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: "localhost", port: 5173 }

  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_record.query_log_tags_enabled = true
  config.action_dispatch.verbose_redirect_logs = true
  config.action_controller.raise_on_missing_callback_actions = true

  # bin/dev serves plain HTTP; without this, request.ssl? is false and Rails
  # silently never sends the secure session and __Host-session cookies
  # (ADR 0007), so sign-in looks broken in a real browser even though every
  # request spec passes (they force request.ssl? through https!). Real
  # browsers accept a Secure cookie over http://localhost specifically (the
  # W3C "potentially trustworthy origin" exemption), so this is safe without
  # an actual local certificate. Same setting production already uses to
  # trust Render's TLS-terminating proxy.
  config.assume_ssl = true
end
