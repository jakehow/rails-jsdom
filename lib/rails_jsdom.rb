require "json"
require "open3"
require "timeout"
require "action_cable"
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
  COMMAND_TIMEOUT = 30
  OPTION_ADVICE = {
    wait: "rails-jsdom settles the page before every finder and assertion",
    make_visible: "rails-jsdom attaches files to hidden fields too"
  }.freeze

  class << self
    attr_writer :command_timeout

    # Seconds to wait for the page to answer a command. A page in an endless
    # loop never answers; after this long its Node process is stopped and the
    # command fails, instead of the test run hanging.
    def command_timeout
      @command_timeout || COMMAND_TIMEOUT
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

    def reject_options(keywords) # :nodoc:
      advised = keywords.find { |keyword| OPTION_ADVICE.key?(keyword) }
      raise ArgumentError, "#{advised}: does nothing here, because #{OPTION_ADVICE.fetch(advised)}. Remove it." if advised
      raise ArgumentError, unknown_keywords(keywords) if keywords.any?
    end

    def unknown_keywords(keywords) # :nodoc:
      "unknown keyword#{"s" if keywords.many?}: #{keywords.map(&:inspect).join(", ")}"
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
require_relative "rails_jsdom/clock"
require_relative "rails_jsdom/cable_adapter"
require_relative "rails_jsdom/cable_server"
require_relative "rails_jsdom/cable_failure"
require_relative "rails_jsdom/cable_socket"
require_relative "rails_jsdom/cable"
require_relative "rails_jsdom/element"
require_relative "rails_jsdom/test_helper"
require_relative "rails_jsdom/page"
require_relative "rails_jsdom/test_case"

ActionCable::Server::Base.prepend(RailsJsdom::CableServer::Takeover)
