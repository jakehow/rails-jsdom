require "test_helper"

module RailsJsdom
  class CableTest < ActiveSupport::TestCase
    PROTOCOLS = [ "actioncable-v1-json", "actioncable-unsupported" ].freeze

    setup do
      @previous_pubsub = ActionCable.server.pubsub
      ActionCable.server.instance_variable_set(:@pubsub, CableAdapter.new(ActionCable.server))
      @clock = Clock.new(Time.now) { |time| travel_to(time, with_usec: true) }
      @cable = Cable.new(@clock)
    end

    teardown do
      @cable.close
      ActionCable.server.instance_variable_set(:@pubsub, @previous_pubsub)
      ActionCable.server.config.allow_same_origin_as_host = true
    end

    test "opening a connection answers with the protocol Action Cable chose" do
      assert_equal({ protocol: "actioncable-v1-json" }, open_socket)
    end

    test "a page that offers no Action Cable protocol gets none" do
      assert_equal({ protocol: "" }, open_socket(protocols: [ "chat" ]))
    end

    test "the welcome is queued before opening returns" do
      open_socket

      assert_equal [ "welcome" ], types(@cable.drain)
    end

    test "the app's connection identifies the visitor from the request's cookies" do
      open_socket(cookie: "visitor=ada")
      @cable.drain
      ActionCable.server.remote_connections.where(visitor: "ada").disconnect

      assert_equal [ { "type" => "disconnect", "reason" => "remote", "reconnect" => true }, { closed: true, code: 1000 } ], payloads(@cable.drain)
    end

    test "a connection the app rejects is told why and closed, and gets no heartbeat" do
      open_socket(cookie: "banned=1")
      @cable.drain
      @clock.page_time(3000)

      assert_empty @cable.drain
    end

    test "a connection the app rejects is told it is unauthorized, then closed" do
      open_socket(cookie: "banned=1")

      assert_equal [ { "type" => "disconnect", "reason" => "unauthorized", "reconnect" => false }, { closed: true, code: 1000 } ], payloads(@cable.drain)
    end

    test "the confirmation of a subscription is queued before the send returns" do
      open_socket
      @cable.drain
      subscribe("room")

      assert_equal [ "confirm_subscription" ], types(@cable.drain)
    end

    test "the rejection of a subscription the channel refuses is queued before the send returns" do
      open_socket
      @cable.drain
      send_command(command: "subscribe", identifier: { channel: "RoomChannel", signed_stream_name: "forged--signature" }.to_json)

      assert_equal [ "reject_subscription" ], types(@cable.drain)
    end

    test "a broadcast reaches each subscribed socket before the broadcast returns" do
      subscribed_socket("room")
      ActionCable.server.broadcast("room", { "text" => "Hi" })

      assert_equal([ { "text" => "Hi" } ], @cable.drain.map { |frame| JSON.parse(frame[:data])["message"] })
    end

    test "a broadcast nobody listens to queues nothing" do
      subscribed_socket("room")
      ActionCable.server.broadcast("elsewhere", { "text" => "Hi" })

      assert_empty @cable.drain
    end

    test "what a channel action transmits is queued before the send returns" do
      subscribed_socket("room")
      perform("echo", "text" => "y" * 70_000)

      assert_equal 70_000, JSON.parse(@cable.drain.first[:data]).dig("message", "text").size
    end

    test "a stream with its own handler runs the handler as the broadcast is made" do
      open_socket
      send_command(command: "subscribe", identifier: { channel: "TickerChannel" }.to_json)
      @cable.drain
      ActionCable.server.broadcast("ticker", "tock")

      assert_equal([ { "relayed" => "\"tock\"" } ], @cable.drain.map { |frame| JSON.parse(frame[:data])["message"] })
    end

    test "a channel's periodic timer runs on the test clock, with Ruby's time at the tick" do
      open_socket
      send_command(command: "subscribe", identifier: { channel: "TickerChannel" }.to_json)
      @cable.drain
      started = Time.now
      @clock.page_time(5000)
      ticked = @cable.drain.reject { |frame| frame[:data].include?("ping") }

      assert_equal([ (started + 5).to_r.to_s ], ticked.map { |frame| JSON.parse(frame[:data]).dig("message", "ticked_at") })
    end

    test "every open connection gets a heartbeat ping at each three-second mark of the test clock" do
      open_socket
      open_socket(id: 2)
      @cable.drain
      @clock.page_time(6000)

      assert_equal([ [ 1, "ping" ], [ 2, "ping" ], [ 1, "ping" ], [ 2, "ping" ] ], @cable.drain.map { |frame| [ frame[:socket], JSON.parse(frame[:data])["type"] ] })
    end

    test "a cable URL with a port connects with that port in its origin" do
      assert_equal({ protocol: "actioncable-v1-json" }, open_socket(url: "ws://www.example.com:3000/cable"))
    end

    test "the upgrade is routed by the app, so a path the app does not route fails like a page request" do
      assert_raises(ActionController::RoutingError) { open_socket(url: "ws://www.example.com/nowhere") }
    end

    test "the upgrade passes through the app middleware before it reaches Action Cable" do
      assert_equal({ protocol: "actioncable-v1-json" }, open_socket(url: "ws://www.example.com/42/cable"))
    end

    test "a request that is not from a page socket reaches Action Cable unchanged" do
      status, = Rails.application.call(Rack::MockRequest.env_for("http://www.example.com/cable"))

      assert_equal 404, status
    end

    test "a connection Action Cable refuses answers with an error" do
      ActionCable.server.config.allow_same_origin_as_host = false

      assert_equal({ error: "the cable endpoint answered 404" }, open_socket)
    end

    test "closing a socket Action Cable refused answers nothing" do
      ActionCable.server.config.allow_same_origin_as_host = false
      open_socket

      assert_nil @cable.answer({ "action" => "close", "socket" => 1 }, nil)
    end

    test "closing a socket ends its subscriptions without queuing a close" do
      subscribed_socket("room")
      @cable.answer({ "action" => "close", "socket" => 1 }, nil)
      ActionCable.server.broadcast("room", { "text" => "Hi" })

      assert_empty @cable.drain
    end

    test "a command that is not JSON fails the test" do
      open_socket
      send_command("not json")

      assert_match(/JSON::ParserError: .* while handling the page's command not json/, reported_failure)
    end

    test "an error a channel action does not handle fails the test, naming the command" do
      boom_socket
      perform_on_boom("explode")

      assert_match(/\ARuntimeError: boom was raised in Action Cable code while handling the page's command .*BoomChannel.*explode/, reported_failure)
    end

    test "the failure carries the error's backtrace" do
      boom_socket
      perform_on_boom("explode")

      assert_match(/boom_channel.rb:\d+:in/, reported_failure)
    end

    test "an error the channel handles with rescue_from does not fail the test" do
      boom_socket
      perform_on_boom("explode_argument")

      assert_equal [ false, [ { "handled" => "handled by the channel" } ] ], [ ActionCable.server.pubsub.failed?, @cable.drain.map { |frame| JSON.parse(frame[:data])["message"] } ]
    end

    test "an error the connection handles with rescue_from does not fail the test" do
      boom_socket
      perform_on_boom("explode_key")

      assert_equal [ false, [ { "handled" => "handled by the connection" } ] ], [ ActionCable.server.pubsub.failed?, @cable.drain.map { |frame| JSON.parse(frame[:data]) } ]
    end

    test "an error in subscribed that nothing handles fails the test" do
      open_socket
      send_command(command: "subscribe", identifier: { channel: "BoomChannel", fail: true }.to_json)

      assert_match(/RuntimeError: subscribing failed/, reported_failure)
    end

    test "an error in connect fails the test" do
      open_socket(cookie: "broken=1")

      assert_match(/RuntimeError: connecting failed was raised in Action Cable code while running ApplicationCable::Connection#handle_open/, reported_failure)
    end

    test "a connection the app rejects does not fail the test" do
      open_socket(cookie: "banned=1")

      assert_not_predicate ActionCable.server.pubsub, :failed?
    end

    test "a command sent after the server closed the connection is dropped" do
      open_socket(cookie: "banned=1")
      @cable.drain
      subscribe("room")

      assert_empty @cable.drain
    end

    test "a tick from the page answers nothing" do
      assert_nil @cable.answer({ "action" => "tick" }, nil)
    end

    test "a cable is active while a socket is open" do
      open_socket
      @cable.drain

      assert_predicate @cable, :active?
    end

    test "a cable is active while frames wait for the page" do
      open_socket(cookie: "banned=1")

      assert_predicate @cable, :active?
    end

    test "a cable with no open socket and nothing queued is inactive" do
      open_socket(cookie: "banned=1")
      @cable.drain

      assert_not_predicate @cable, :active?
    end

    test "closing a cable closes its sockets" do
      open_socket
      @cable.drain
      @cable.close

      assert_not_predicate @cable, :active?
    end

    private

    def open_socket(id: 1, url: "ws://www.example.com/cable", protocols: PROTOCOLS, cookie: "")
      @cable.answer({ "action" => "open", "socket" => id, "url" => url, "protocols" => protocols }, cookie)
    end

    def subscribed_socket(stream)
      open_socket
      subscribe(stream)
      @cable.drain
    end

    def subscribe(stream)
      send_command(command: "subscribe", identifier: { channel: "RoomChannel", signed_stream_name: RoomChannel.signed_stream_name(stream) }.to_json)
    end

    def perform(action, data)
      identifier = { channel: "RoomChannel", signed_stream_name: RoomChannel.signed_stream_name("room") }.to_json
      send_command(command: "message", identifier: identifier, data: data.merge("action" => action).to_json)
    end

    def send_command(command)
      @cable.answer({ "action" => "send", "socket" => 1, "data" => command.is_a?(String) ? command : command.to_json }, nil)
    end

    def boom_socket
      open_socket
      send_command(command: "subscribe", identifier: { channel: "BoomChannel" }.to_json)
      @cable.drain
    end

    def perform_on_boom(action)
      send_command(command: "message", identifier: { channel: "BoomChannel" }.to_json, data: { action: action }.to_json)
    end

    def reported_failure
      assert_raises(Error) { ActionCable.server.pubsub.raise_failure }.message
    end

    def types(frames)
      frames.map { |frame| JSON.parse(frame[:data])["type"] }
    end

    def payloads(frames)
      frames.map { |frame| frame[:data] ? JSON.parse(frame[:data]) : frame.except(:socket) }
    end
  end
end
