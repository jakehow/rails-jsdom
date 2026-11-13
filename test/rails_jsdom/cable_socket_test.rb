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
        socket.close if socket.request.cookies["banned"]
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

      def handle_close
        events << :close
      end

      def beat
        socket.transmit(type: "ping")
      end

      private

      def later(name)
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

    test "a command that is not JSON is logged, not handled" do
      open_socket
      @logger.expects(:error).with(regexp_matches(/Could not handle incoming message: "nope"/))
      @socket.receive("nope")
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

    def connection
      @socket.instance_variable_get(:@connection)
    end
  end
end
