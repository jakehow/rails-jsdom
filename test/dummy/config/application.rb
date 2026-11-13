require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "active_job/railtie"
require "propshaft"
require "importmap-rails"
require "turbo-rails"
require "stimulus-rails"
require_relative "../lib/numeric_prefix"

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.1
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "rails-jsdom-dummy-secret-key-base-for-tests-only-0123456789abcdef"
    config.active_job.queue_adapter = :test
    config.action_controller.allow_forgery_protection = false
    config.action_dispatch.show_exceptions = :none
    config.middleware.use NumericPrefix
    config.logger = Logger.new(File.expand_path("../log/test.log", __dir__))
  end
end
