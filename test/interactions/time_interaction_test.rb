require "test_helper"

class TimeInteractionTest < RailsJsdom::TestCase
  setup do
    @started = Time.now
    mount_html "<p>Clock</p>"
  end

  test "the page's Date starts at Ruby's frozen time" do
    assert_equal milliseconds(@started), evaluate_script("Date.now()")
  end

  test "the page's Date follows its virtual clock" do
    assert_equal milliseconds(@started + 0.5), evaluate_script("new Promise(resolve => setTimeout(() => resolve(Date.now()), 500))")
  end

  test "Date called as a function and with arguments behaves as in a browser" do
    assert_equal [ Time.at(0).utc.year, true, true ], evaluate_script("[new Date(0).getUTCFullYear(), typeof Date() === 'string', new Date() instanceof Date]")
  end

  test "performance.now counts the virtual clock" do
    assert_equal 250, evaluate_script("new Promise(resolve => setTimeout(() => resolve(performance.now()), 250))")
  end

  test "a request the page makes sees Ruby's time at the page's time" do
    now = evaluate_script("new Promise(resolve => setTimeout(() => fetch('/now').then(response => response.json()).then(json => resolve(json.now)), 750))")

    assert_equal (@started + 0.75r).to_r, now.to_r
  end

  test "after a command, Ruby's time is the page's time" do
    evaluate_script("new Promise(resolve => setTimeout(resolve, 300))")

    assert_equal (@started + 0.3r).to_r, Time.now.to_r
  end

  test "when the test travels forward, the page's clock follows and the timers due on the way run in order" do
    evaluate_script("window.fired = []; setTimeout(() => fired.push(Date.now()), 5000); setTimeout(() => fired.push(Date.now()), 9000)")
    travel 10.seconds, with_usec: true

    assert_equal [ milliseconds(@started + 5), milliseconds(@started + 9), milliseconds(@started + 10) ], evaluate_script("fired.concat(Date.now())")
  end

  test "when the test travels back, the page's Date moves back with it" do
    travel_to @started - 1.day, with_usec: true

    assert_equal milliseconds(@started - 1.day), evaluate_script("Date.now()")
  end

  test "after a block travel, the page's Date is exactly the time before it" do
    travel(1.day) { Time.now }

    assert_equal milliseconds(@started), evaluate_script("Date.now()")
  end

  test "freezing time again mid-test leaves the page's Date where it is" do
    freeze_time

    assert_equal milliseconds(@started), evaluate_script("Date.now()")
  end

  test "after a block travel that drove the page, the page's Date is Ruby's time again" do
    travel(1.day, with_usec: true) { evaluate_script("Date.now()") }

    assert_equal milliseconds(Time.now), evaluate_script("Date.now()")
  end

  test "an idle session's timers that fell due while another session ran run when it is driven again" do
    evaluate_script("window.fired = false; setTimeout(() => { fired = true }, 2000)")
    using_session(:other) do
      mount_html "<p>Other</p>"
      travel 3.seconds, with_usec: true
      evaluate_script("1")
    end

    assert evaluate_script("fired")
  end

  test "an open cable gets Action Cable's heartbeat on the virtual clock" do
    evaluate_script("window.received = []; new WebSocket('/cable', ['actioncable-v1-json']).onmessage = event => received.push(JSON.parse(event.data).type)")
    travel 4.seconds, with_usec: true

    assert_equal %w[welcome ping], evaluate_script("received")
  end

  test "a broadcast from another thread fails the next command with an explanation" do
    Thread.new { Turbo::StreamsChannel.broadcast_append_to("rails_jsdom", target: "list", html: "<p>Late</p>") }.join

    assert_match(/broadcast from a thread other than the test's/, assert_raises(RailsJsdom::Error) { evaluate_script("1") }.message)
  end

  test "a broadcast from another thread fails the next read with an explanation" do
    Thread.new { Turbo::StreamsChannel.broadcast_append_to("rails_jsdom", target: "list", html: "<p>Late</p>") }.join

    assert_match(/broadcast from a thread other than the test's/, assert_raises(RailsJsdom::Error) { page_text }.message)
  end

  test "a read after the test travels sees what the page's timers did on the way, with no cable open" do
    execute_script("setTimeout(() => document.body.insertAdjacentHTML('beforeend', '<p id=\"late\">Late</p>'), 5000)")
    travel 6.seconds, with_usec: true

    assert_selector "#late", text: "Late"
  end

  private

  def milliseconds(time)
    (time.to_r * 1000).floor
  end
end
