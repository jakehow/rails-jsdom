require "test_helper"

module RailsJsdom
  class CableTest < ActiveSupport::TestCase
    PROTOCOLS = [ "actioncable-v1-json", "actioncable-unsupported" ].freeze

    setup do
      @cable = Cable.new
    end

    teardown do
      @cable.close
      RailsJsdom.cable_quiet_period = nil
      RailsJsdom.cable_reply_timeout = nil
      ActionCable.server.config.allow_same_origin_as_host = true
    end

    test "opening a connection answers with the protocol Action Cable chose" do
      assert_equal({ protocol: "actioncable-v1-json" }, open_socket)
    end

    test "receiving waits for the welcome the protocol sends after connecting" do
      open_socket

      assert_equal [ "welcome" ], types(receive)
    end

    test "receiving waits for the confirmation of a subscription" do
      open_socket
      receive
      subscribe("room")

      assert_equal [ "confirm_subscription" ], types(receive)
    end

    test "receiving waits for the rejection of a subscription the channel refuses" do
      open_socket
      receive
      send_command(command: "subscribe", identifier: { channel: "RoomChannel", signed_stream_name: "forged--signature" }.to_json)

      assert_equal [ "reject_subscription" ], types(receive)
    end

    test "after a broadcast, receiving waits for the messages it causes" do
      subscribed_socket("room")
      ActionCable.server.broadcast("room", { "text" => "Hi" })

      messages = receive.map { |frame| JSON.parse(frame[:data])["message"] }

      assert_equal [ { "text" => "Hi" } ], messages
    end

    test "with nothing expected and nothing sent, receiving answers at once" do
      subscribed_socket("room")

      assert_empty receive
    end

    test "a reply that never comes stops the wait after the reply timeout, and is not waited for again" do
      RailsJsdom.cable_reply_timeout = 0.1
      open_socket
      receive
      send_command(command: "subscribe", identifier: { channel: "MissingChannel" }.to_json)
      receive
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      receive

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.1
    end

    test "the quiet period is how long receiving waits for more messages after one arrives" do
      RailsJsdom.cable_quiet_period = 0.2
      subscribed_socket("room")
      Thread.new do
        sleep 0.1
        ActionCable.server.broadcast("room", { "text" => "Late" })
      end
      ActionCable.server.broadcast("room", { "text" => "Early" })
      texts = receive.map { |frame| JSON.parse(frame[:data]).dig("message", "text") }

      assert_equal %w[Early Late], texts
    end

    test "a message larger than a short frame arrives whole" do
      subscribed_socket("room")
      ActionCable.server.broadcast("room", { "text" => "x" * 70_000 })

      assert_equal 70_000, JSON.parse(receive.first[:data]).dig("message", "text").size
    end

    test "a message larger than a short frame is sent whole" do
      subscribed_socket("room")
      perform("echo", "text" => "y" * 70_000)

      assert_equal 70_000, JSON.parse(receive.first[:data]).dig("message", "text").size
    end

    test "a cable URL with a port connects with that port in its origin" do
      assert_equal({ protocol: "actioncable-v1-json" }, open_socket("ws://www.example.com:3000/cable"))
    end

    test "closing a socket Action Cable refused answers nothing" do
      ActionCable.server.config.allow_same_origin_as_host = false
      open_socket

      assert_nil @cable.answer({ "action" => "close", "socket" => 1 }, nil)
    end

    test "a command that is not JSON is sent without waiting for a reply" do
      open_socket
      receive
      send_command("not json")

      assert_empty receive
    end

    test "closing a socket ends the connection and reports the close" do
      open_socket
      receive
      @cable.answer({ "action" => "close", "socket" => 1 }, nil)

      closes = receive.select { |frame| frame[:closed] }

      assert_equal [ { closed: true, code: 1000, socket: 1 } ], closes
    end

    test "a connection Action Cable refuses answers with an error" do
      ActionCable.server.config.allow_same_origin_as_host = false

      assert_equal({ error: "the cable endpoint answered 404" }, open_socket)
    end

    test "a cable with open sockets says so" do
      open_socket

      assert_predicate @cable, :open?
    end

    private

    def open_socket(url = "ws://www.example.com/cable")
      @cable.answer({ "action" => "open", "socket" => 1, "url" => url, "protocols" => PROTOCOLS }, "")
    end

    def subscribed_socket(stream)
      open_socket
      receive
      subscribe(stream)
      receive
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

    def receive
      @cable.answer({ "action" => "receive" }, nil)
    end

    def types(frames)
      frames.map { |frame| JSON.parse(frame[:data])["type"] }
    end
  end
end
