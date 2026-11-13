require_relative "test_helper"

module RailsJsdom
  # Base class for interaction tests. It is an
  # `ActionDispatch::IntegrationTest` that includes RailsJsdom::TestHelper, so
  # fixtures, sign-in helpers that post to your session controller,
  # `perform_enqueued_jobs` and every Rails assertion work as usual.
  #
  #   class ProjectFilterInteractionTest < RailsJsdom::TestCase
  #     setup do
  #       sign_in_as users(:owner)
  #       visit projects_path
  #     end
  #
  #     test "filtering by name leaves one card visible" do
  #       fill_in "search", with: "Billing"
  #
  #       assert_dom "[data-project-filter-target=card]:not([hidden])", count: 1
  #     end
  #   end
  #
  # After each test the page is discarded; the Node process stays up for the
  # next test in the same worker.
  class TestCase < ActionDispatch::IntegrationTest
    include TestHelper

    teardown do
      RailsJsdom.bridge.reset
      rails_jsdom_close_cables
    end
  end
end
