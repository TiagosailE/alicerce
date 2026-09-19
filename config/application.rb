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
    config.time_zone = "Brasilia"
    config.x.spa_index = Rails.public_path.join("spa/index.html")
  end
end
