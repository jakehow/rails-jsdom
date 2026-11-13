require "test_helper"

module RailsJsdom
  class CableAdapterTest < ActiveSupport::TestCase
    include ActionCable::TestHelper

    setup do
      @previous_pubsub = ActionCable.server.pubsub
      @adapter = CableAdapter.new(ActionCable.server)
      ActionCable.server.instance_variable_set(:@pubsub, @adapter)
    end

    teardown do
      ActionCable.server.instance_variable_set(:@pubsub, @previous_pubsub)
    end

    test "a broadcast reaches its subscribers before the broadcast returns" do
      received = []
      @adapter.subscribe("room", ->(message) { received << message })
      ActionCable.server.broadcast("room", { text: "Hi" })

      assert_equal [ { text: "Hi" }.to_json ], received
    end

    test "a subscription is confirmed before subscribing returns" do
      confirmed = false
      @adapter.subscribe("room", ->(_message) { }, -> { confirmed = true })

      assert confirmed
    end

    test "broadcasts are recorded for assert_broadcasts" do
      ActionCable.server.broadcast("room", { text: "Hi" })

      assert_broadcasts "room", 1
    end

    test "a broadcast from another thread is not delivered" do
      received = []
      @adapter.subscribe("room", ->(message) { received << message })
      Thread.new { ActionCable.server.broadcast("room", { text: "Hi" }) }.join

      assert_empty received
    end

    test "a broadcast from another thread is refused with an explanation" do
      Thread.new { ActionCable.server.broadcast("room", { text: "Hi" }) }.join

      assert_match(/"room" was broadcast from a thread other than the test's/, assert_raises(Error) { @adapter.raise_failure }.message)
    end

    test "a refused broadcast is reported once" do
      Thread.new { ActionCable.server.broadcast("room", { text: "Hi" }) }.join
      assert_raises(Error) { @adapter.raise_failure }

      assert_not_predicate @adapter, :failed?
    end

    test "an adapter with no failure raises nothing" do
      assert_nil @adapter.raise_failure
    end
  end
end
