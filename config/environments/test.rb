Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = true
  config.cache_store = :memory_store

  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
  config.action_controller.raise_on_missing_callback_actions = true

  config.active_job.queue_adapter = :test
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "example.com" }

  config.active_support.deprecation = :stderr

  config.x.spa_index = Rails.root.join("spec/fixtures/files/spa_index.html")
end
