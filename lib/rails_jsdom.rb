require "json"
require "open3"
require_relative "rails_jsdom/version"

# Browserless interaction tests for Rails apps built with Stimulus, Turbo and
# importmap.
#
# Write tests with RailsJsdom::TestCase. Its helpers are documented in
# RailsJsdom::TestHelper.
module RailsJsdom
  # Raised when an action fails in the page: an element is not found or
  # matches more than once, a JavaScript error or unexpected dialog occurs, or
  # the Node process exits.
  class Error < StandardError; end

  # :stopdoc:

  RUNNER = File.expand_path("rails_jsdom/runner.js", __dir__)
  REMOTE = %r{\A[a-z][a-z0-9+.-]*://}i
  HIDDEN_SELECTOR = "[hidden], template, script, style, noscript, dialog:not([open]), [style*='display: none'], [style*='display:none']".freeze
  TIMER_HORIZON = 1000
  CABLE_QUIET_PERIOD = 0.05
  CABLE_REPLY_TIMEOUT = 2

  class << self
    attr_writer :cable_quiet_period, :cable_reply_timeout

    # Seconds to wait for more cable messages after the page performs an
    # Action Cable action or the app broadcasts, before the page counts as
    # settled. Raise it if messages arrive after assertions on a slow machine.
    def cable_quiet_period
      @cable_quiet_period || CABLE_QUIET_PERIOD
    end

    # Seconds to wait for a reply the Action Cable protocol requires, such as
    # the welcome after connecting or the confirmation of a subscription.
    def cable_reply_timeout
      @cable_reply_timeout || CABLE_REPLY_TIMEOUT
    end

    def bridge
      bridges[Process.pid] ||= Bridge.new(command: [ "node", RUNNER ], setup: setup, logger: Rails.logger)
    end

    def setup
      {
        command: "setup",
        root: Rails.root.to_s,
        controllers: Rails.root.join("app/javascript/controllers").to_s,
        modules: modules,
        stubs: remote_modules,
        directories: directories,
        horizon: TIMER_HORIZON,
        hidden: HIDDEN_SELECTOR
      }
    end

    def modules
      packages.reject { |_name, path| path.match?(REMOTE) }.transform_values { |path| Rails.application.assets.load_path.find(path)&.path&.to_s }
    end

    def remote_modules
      packages.select { |_name, path| path.match?(REMOTE) }.keys
    end

    def directories
      Rails.application.importmap.directories.values.to_h { |directory| [ directory.under, Rails.root.join(directory.dir).to_s ] }
    end

    def keys(keys)
      keys.map { |key| key.is_a?(Array) ? key_entry(key.last).merge(modifiers: key[0...-1].map(&:to_s)) : key_entry(key) }
    end

    def document(html)
      "<!DOCTYPE html><html><head></head><body>#{html}</body></html>"
    end

    private

    def key_entry(key)
      key.is_a?(Symbol) ? { key: key.to_s } : { text: key.to_s }
    end

    def packages
      Rails.application.importmap.packages.transform_values(&:path)
    end

    def bridges
      @bridges ||= {}
    end
  end
end

require_relative "rails_jsdom/bridge"
require_relative "rails_jsdom/query"
require_relative "rails_jsdom/cable_frame"
require_relative "rails_jsdom/cable_socket"
require_relative "rails_jsdom/cable"
require_relative "rails_jsdom/element"
require_relative "rails_jsdom/test_helper"
require_relative "rails_jsdom/page"
require_relative "rails_jsdom/test_case"
