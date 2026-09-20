require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module Alicerce
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true
    config.middleware.use ActionDispatch::ContentSecurityPolicy::Middleware
    config.action_dispatch.default_headers.merge!(
      "x-frame-options" => "DENY",
      "permissions-policy" => "camera=(), microphone=(), geolocation=(), usb=(), payment=(), fullscreen=(self)"
    )

    # API mode drops cookies and the session middleware; ADR 0007 needs both
    # back for the CSRF token cookie (the actual sign-in token is a separate,
    # hand-managed cookie, never put in the Rails session).
    config.session_store :cookie_store, key: "__Host-csrf", secure: true, httponly: true, same_site: :lax
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options

    config.time_zone = "Brasilia"
    config.active_record.schema_format = :sql
    config.x.spa_index = Rails.root.join("frontend/dist/index.html")
    # Served by SpaController, not copied into public/spa by the frontend
    # build: public_file_server.headers below would cache it for a year as
    # immutable, and unlike the hashed bundle assets its filename never
    # changes to bust that cache.
    config.x.theme_init_script = Rails.root.join("frontend/theme-init.js")
  end
end
