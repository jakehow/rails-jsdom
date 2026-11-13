require "test_helper"

module RailsJsdom
  class ClockTest < ActiveSupport::TestCase
    setup do
      @epoch = Time.at(Rational(1_700_000_000_250, 1000))
      @clock = Clock.new(@epoch) { |time| travel_to(time, with_usec: true) }
    end

    test "a new clock freezes Ruby's time at its epoch" do
      assert_equal @epoch.to_r, Time.now.to_r
    end

    test "page time moves Ruby's time to the epoch plus the page's clock" do
      @clock.page_time(1500.25)

      assert_equal (@epoch + 1.50025r).to_r, Time.now.to_r
    end

    test "a timer runs once its interval has passed on the page's clock, at its own time" do
      times = []
      @clock.every(2) { times << Time.now.to_r }
      @clock.page_time(1999)
      @clock.page_time(2500)

      assert_equal [ (@epoch + 2).to_r ], times
    end

    test "after its timers run, Ruby's time is the page's time again" do
      @clock.every(2) { nil }
      @clock.page_time(2500)

      assert_equal (@epoch + 2.5r).to_r, Time.now.to_r
    end

    test "a timer repeats at its interval" do
      runs = 0
      @clock.every(1.second) { runs += 1 }
      @clock.page_time(3000)

      assert_equal 3, runs
    end

    test "timers due at the same moment run in the order they were made" do
      order = []
      @clock.every(1) { order << :first }
      @clock.every(1) { order << :second }
      @clock.page_time(1000)

      assert_equal %i[first second], order
    end

    test "a timer that is shut down never runs" do
      runs = 0
      @clock.every(1) { runs += 1 }.shutdown
      @clock.page_time(5000)

      assert_equal 0, runs
    end

    test "kept-alive sockets beat at each three-second mark of the clock" do
      socket = mock
      socket.expects(:beat).twice
      @clock.page_time(1000)
      @clock.keep_alive(socket)
      @clock.page_time(6000)
    end

    test "a socket that is let go beats no more" do
      socket = mock
      socket.expects(:beat).never
      @clock.keep_alive(socket)
      @clock.let_go(socket)
      @clock.page_time(6000)
    end

    test "the page's view has the epoch and clock in milliseconds and no deadline without timers" do
      @clock.page_time(250)

      assert_equal({ epoch: (@epoch.to_r * 1000).to_f, now: 250.0, deadline: nil }, @clock.view)
    end

    test "the page's view has the next timer's time as its deadline" do
      @clock.every(4) { nil }
      @clock.every(2) { nil }

      assert_in_delta 2000.0, @clock.view.fetch(:deadline)
    end

    test "after the test travels forward, the page's view is ahead by the same time" do
      @clock.page_time(500)
      travel 10.seconds, with_usec: true

      assert_in_delta 10_500.0, @clock.view.fetch(:now)
    end

    test "after the test travels back, the page's epoch moves back and its clock stays" do
      @clock.page_time(500)
      travel_to @epoch - 60, with_usec: true
      view = @clock.view

      assert_equal [ ((@epoch - 60.5r).to_r * 1000).to_f, 500.0 ], view.values_at(:epoch, :now)
    end

    test "the clock has not moved while Ruby's time is the page's time" do
      @clock.page_time(500)

      assert_not_predicate @clock, :moved?
    end

    test "the clock has moved once the test travels" do
      travel 1.minute

      assert_predicate @clock, :moved?
    end

    test "after a block travel, the clock keeps the exact time from before it" do
      @clock.page_time(500)
      travel(1.hour, with_usec: true) { @clock.page_time(700) }

      assert_equal [ false, (@epoch + 0.7r).to_r ], [ @clock.moved?, Time.now.to_r ]
    end

    test "freezing time again mid-test leaves the page where it is" do
      @clock.page_time(500)
      freeze_time

      assert_equal [ (@epoch.to_r * 1000).to_f, 500.0 ], @clock.view.values_at(:epoch, :now)
    end

    test "a travel to the current time without its fraction keeps the exact time" do
      @clock.page_time(500)
      travel_to Time.now
      @clock.view

      assert_equal (@epoch + 0.5r).to_r, Time.now.to_r
    end

    test "a travel back by a whole second is a real travel back" do
      @clock.page_time(500)
      travel_to Time.now - 1, with_usec: true

      assert_equal ((@epoch - 1).to_r * 1000).to_f, @clock.view.fetch(:epoch)
    end

    test "a time with no fraction to drop is left alone" do
      clock = Clock.new(Time.at(1_700_000_000)) { |time| travel_to(time, with_usec: true) }

      assert_not_predicate clock, :moved?
    end
  end
end
