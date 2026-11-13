require "rack/mock_request"

module RailsJsdom
  class CableSocket # :nodoc:
    ENV_KEY = "rails_jsdom.cable_socket".freeze

    module Modern
      def connect
        @logger = @server.new_tagged_logger { request }
        @connection = @server.config.connection_class.call.new(CableServer.new(@server, @clock), self)
        @server.allow_request_origin?(env) ? opened : [ 404, {}, [] ]
      end

      def receive(text)
        work(self, :dispatch, text)
      end

      private

      def opened
        start
        work(@connection, :handle_open)
        work(self, :keep_alive)
        [ -1, {}, [] ]
      end

      def keep_alive
        @clock.keep_alive(self) if open?
      end

      def dispatch(text)
        @connection.handle_incoming(ActiveSupport::JSON.decode(text)) if open?
      rescue StandardError => error
        raise unless routing_error?(error)

        logger.error "Could not handle incoming message: #{text} [#{error.class} - #{error.message}]"
      end

      def routing_error?(error)
        error.class.module_parent == ActionCable::Connection::Subscriptions
      end

      def disconnect
        work(@connection, :handle_close)
      end
    end

    module Legacy
      def self.included(_socket_class)
        ActionCable::Connection::WebSocket.singleton_class.prepend(LegacyWebSocket::Takeover)
      end

      def connect
        @logger = @server.logger
        @connection = @server.config.connection_class.call.new(LegacyCableServer.new(@server, @clock, self), env)
        @connection.singleton_class.prepend(LegacyRescue)
        @connection.process
      end

      def receive(text)
        @connection.on_message(text)
      end

      def accept
        start
        @connection.on_open
        @clock.keep_alive(self) if open?
        [ -1, {}, [] ]
      end

      private

      def disconnect
        @connection.on_close(nil, 1000)
      end
    end

    attr_reader :env, :protocol, :logger

    def self.env(url, protocols, cookie)
      uri = URI(url)
      origin = origin(uri)
      Rack::MockRequest.env_for("#{origin}#{uri.request_uri}", headers(origin, protocols, cookie))
    end

    def self.origin(uri)
      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "http://#{uri.host}#{port}"
    end

    def self.headers(origin, protocols, cookie)
      {
        "HTTP_HOST" => origin.delete_prefix("http://"),
        "HTTP_ORIGIN" => origin,
        "HTTP_COOKIE" => cookie,
        "HTTP_CONNECTION" => "Upgrade",
        "HTTP_UPGRADE" => "websocket",
        "HTTP_SEC_WEBSOCKET_VERSION" => "13",
        "HTTP_SEC_WEBSOCKET_KEY" => SecureRandom.base64(16),
        "HTTP_SEC_WEBSOCKET_PROTOCOL" => protocols.join(", "),
        "REMOTE_ADDR" => "127.0.0.1"
      }
    end

    def initialize(id, outbox, clock)
      @id = id
      @outbox = outbox
      @clock = clock
      @state = :connecting
      @jobs = []
    end

    def open(url, protocols, cookie)
      @protocol = (protocols & ActionCable::INTERNAL[:protocols]).first.to_s
      status, = Rails.application.call(self.class.env(url, protocols, cookie).merge(ENV_KEY => self))
      status == -1 ? { protocol: @protocol } : { error: "the cable endpoint answered #{status}" }
    end

    def attach(server, env)
      @server = server
      @env = env
      connect
    end

    def request
      @request ||= ActionDispatch::Request.new(Rails.application.env_config.merge(env))
    end

    def open?
      @state == :open
    end

    def start
      @state = :open
    end

    def transmit(cable_message)
      deliver(ActiveSupport::JSON.encode(cable_message))
    end

    def deliver(text)
      @outbox << { socket: @id, data: text } if open?
    end

    def close(*)
      shut(1000) if open?
    end

    def close_by_page
      shut(nil) if open?
    end

    def beat
      @connection.beat
    end

    def perform_work(receiver, method, *args)
      work(receiver, method, *args)
    end

    def work(receiver, method, *args, connection: self, &block)
      @jobs << [ receiver, method, args, connection, block ]
      run_jobs unless working?
    end

    private

    def working?
      @working
    end

    def shut(code)
      @state = :closed
      @clock.let_go(self)
      @outbox << { socket: @id, closed: true, code: code } if code
      disconnect
    end

    def run_jobs
      @working = true
      run_job(*@jobs.shift) until @jobs.empty?
    ensure
      @working = false
    end

    def run_job(receiver, method, args, connection, block)
      @server.worker_pool.work(connection) { receiver.send(method, *args, &block) }
    rescue StandardError => error
      @server.pubsub.report(CableFailure.new(error, receiver, method, args).message)
    end

    include({ socket: Modern, env: Legacy }.fetch(ActionCable::Connection::Base.instance_method(:initialize).parameters.dig(1, 1)))
  end
end
