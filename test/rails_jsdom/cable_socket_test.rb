require "test_helper"

module RailsJsdom
  class CableSocketTest < ActiveSupport::TestCase
    class Connection
      attr_reader :server, :socket, :events

      def initialize(server, socket)
        @server = server
        @socket = socket
        @events = []
      end

      def handle_open
        events << :open
        socket.transmit(type: "welcome")
        check(socket.request.cookies)
      end

      def handle_incoming(payload)
        events << payload
        public_send(payload["do"], payload) if payload["do"]
      end

      def work(payload)
        socket.perform_work(self, :later, payload["name"])
      end

      def close(_payload)
        socket.close
      end

      def every(payload)
        server.executor.timer(payload["seconds"]) { socket.transmit(type: "tick") }
      end

      def post(_payload)
        server.executor.post { events << :posted }
      end

      def crash(_payload)
        raise "command failed"
      end

      def handle_close
        events << :close
      end

      def beat
        socket.transmit(type: "ping")
      end

      private

      def check(cookies)
        raise "opening failed" if cookies["broken"]

        socket.close if cookies["banned"]
      end

      def later(name)
        raise "work failed" if name == "fail"

        events << :"after #{name}"
      end
    end

    Socket = Class.new(CableSocket) { include CableSocket::Modern }

    setup do
      @logger = ActionCable.server.logger
      ActionCable.server.stubs(:new_tagged_logger).returns(@logger)
      ActionCable.server.stubs(:allow_request_origin?).returns(true)
      ActionCable.server.config.stubs(:connection_class).returns(-> { Connection })
      @clock = Clock.new(Time.now) { |time| travel_to(time, with_usec: true) }
      @frames = []
      @socket = Socket.new(1, @frames, @clock)
      @previous_pubsub = ActionCable.server.pubsub
      ActionCable.server.instance_variable_set(:@pubsub, CableAdapter.new(ActionCable.server))
    end

    teardown do
      ActionCable.server.instance_variable_set(:@pubsub, @previous_pubsub)
    end

    test "opening hands the app connection the server and the socket, then runs its handle_open" do
      open_socket

      assert_equal [ CableServer, @socket, [ :open ] ], [ connection.server.class, connection.socket, connection.events ]
    end

    test "opening answers with the protocol and queues what handle_open transmits" do
      assert_equal [ { protocol: "actioncable-v1-json" }, [ { socket: 1, data: { type: "welcome" }.to_json } ] ], [ open_socket, @frames ]
    end

    test "a request origin the server does not allow is refused before the connection opens" do
      ActionCable.server.stubs(:allow_request_origin?).returns(false)

      assert_equal [ { error: "the cable endpoint answered 404" }, false ], [ open_socket, @socket.open? ]
    end

    test "the socket's logger is the server's tagged logger" do
      open_socket

      assert_same @logger, @socket.logger
    end

    test "the socket's request carries the app's env config and the upgrade request" do
      open_socket(cookie: "visitor=ada")

      assert_equal [ "ada", Rails.application.env_config["action_dispatch.secret_key_base"] ], [ @socket.request.cookies["visitor"], @socket.request.env["action_dispatch.secret_key_base"] ]
    end

    test "a received command is decoded and handled before receiving returns" do
      open_socket
      @socket.receive({ command: "subscribe" }.to_json)

      assert_equal [ :open, { "command" => "subscribe" } ], connection.events
    end

    test "a command that is not JSON fails the test" do
      open_socket
      @socket.receive("nope")

      assert_match(/JSON::ParserError: .* while handling the page's command nope/, reported_failure)
    end

    test "an error the connection does not handle in a command fails the test, naming the command" do
      open_socket
      @socket.receive({ do: "crash" }.to_json)

      assert_match(/\ARuntimeError: command failed was raised in Action Cable code while handling the page's command \{"do":"crash"\}/, reported_failure)
    end

    test "a command Action Cable cannot route is logged, as Action Cable logs it, and fails nothing" do
      routing_error = Class.new(StandardError)
      routing_error.stubs(:module_parent).returns(ActionCable::Connection::Subscriptions)
      Connection.any_instance.stubs(:handle_incoming).raises(routing_error, "Channel not found: MissingChannel")
      open_socket
      @logger.expects(:error).with(includes("Channel not found: MissingChannel"))
      @socket.receive({ command: "subscribe" }.to_json)

      assert_not ActionCable.server.pubsub.failed?
    end

    test "an error in handle_open fails the test, naming the connection" do
      open_socket(cookie: "broken=1")

      assert_match(/RuntimeError: opening failed was raised in Action Cable code while running RailsJsdom::CableSocketTest::Connection#handle_open/, reported_failure)
    end

    test "an error in work the connection asked for fails the test, and later work still runs" do
      open_socket
      @socket.receive({ do: "work", name: "fail" }.to_json)
      @socket.receive({ do: "work", name: "two" }.to_json)

      assert_equal [ true, :"after two" ], [ reported_failure.include?("work failed"), connection.events.last ]
    end

    test "work the connection asks for runs after the job that asked for it, before receiving returns" do
      open_socket
      @socket.receive({ do: "work", name: "one" }.to_json)

      assert_equal [ :open, { "do" => "work", "name" => "one" }, :"after one" ], connection.events
    end

    test "a timer the connection starts runs on the test clock" do
      open_socket
      @socket.receive({ do: "every", seconds: 2 }.to_json)
      @frames.clear
      @clock.page_time(2000)

      assert_equal([ { type: "tick" }.to_json ], @frames.map { |frame| frame[:data] })
    end

    test "the connection's executor runs posted work at once" do
      open_socket
      @socket.receive({ do: "post" }.to_json)

      assert_equal :posted, connection.events.last
    end

    test "an open connection beats at each three-second mark" do
      open_socket
      @frames.clear
      @clock.page_time(3000)

      assert_equal([ { type: "ping" }.to_json ], @frames.map { |frame| frame[:data] })
    end

    test "a connection the app closes while opening gets no heartbeat" do
      open_socket(cookie: "banned=1")
      @frames.clear
      @clock.page_time(3000)

      assert_empty @frames
    end

    test "closing from the server queues the close and runs handle_close" do
      open_socket
      @frames.clear
      @socket.receive({ do: "close" }.to_json)

      assert_equal [ [ { socket: 1, closed: true, code: 1000 } ], :close ], [ @frames, connection.events.last ]
    end

    test "a command after the connection closed is not handled" do
      open_socket
      @socket.receive({ do: "close" }.to_json)
      @socket.receive({ command: "late" }.to_json)

      assert_equal :close, connection.events.last
    end

    test "closing from the page runs handle_close without queuing a close" do
      open_socket
      @frames.clear
      @socket.close_by_page

      assert_equal [ [], :close ], [ @frames, connection.events.last ]
    end

    test "closing twice closes once" do
      open_socket
      @socket.close_by_page
      @socket.close

      assert_equal 1, connection.events.count(:close)
    end

    test "nothing is transmitted once the connection is closed" do
      open_socket
      @socket.close_by_page
      @frames.clear
      @socket.transmit(type: "late")

      assert_empty @frames
    end

    private

    def open_socket(cookie: "")
      @socket.open("ws://www.example.com/cable", [ "actioncable-v1-json" ], cookie)
    end

    def reported_failure
      assert_raises(Error) { ActionCable.server.pubsub.raise_failure }.message
    end

    def connection
      @socket.instance_variable_get(:@connection)
    end
  end
end
