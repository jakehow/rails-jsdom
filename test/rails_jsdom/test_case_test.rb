require "test_helper"

module RailsJsdom
  class TestCaseTest < ActiveSupport::TestCase
    setup do
      @test_case = RailsJsdom::TestCase.new("lifecycle")
      @previous_pubsub = ActionCable.server.pubsub
      RailsJsdom.stubs(:bridge).returns(@bridge = stub(reset: nil))
    end

    teardown do
      @test_case.travel_back
    end

    test "setup freezes Ruby's time" do
      @test_case.run_callbacks(:setup)

      assert_equal Time.now.to_r, Time.now.to_r
    end

    test "setup puts RailsJsdom's adapter on the cable server" do
      @test_case.run_callbacks(:setup)

      assert_instance_of CableAdapter, ActionCable.server.pubsub
    ensure
      @test_case.run_callbacks(:teardown)
    end

    test "teardown puts the previous adapter back" do
      @test_case.run_callbacks(:setup)
      @test_case.run_callbacks(:teardown)

      assert_same @previous_pubsub, ActionCable.server.pubsub
    end

    test "teardown resets Node" do
      @test_case.run_callbacks(:setup)
      @bridge.expects(:reset)

      @test_case.run_callbacks(:teardown)
    end
  end
end
