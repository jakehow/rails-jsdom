module RailsJsdom
  class CableServer # :nodoc:
    module Takeover
      def call(env)
        socket = env[CableSocket::ENV_KEY]
        socket ? socket.attach(self, env) : super
      end
    end

    delegate :config, :pubsub, :broadcast, to: :@server

    def initialize(server, clock)
      @server = server
      @clock = clock
    end

    def executor
      self
    end

    def post
      yield
    end

    def timer(interval, &block)
      @clock.every(interval, &block)
    end
  end

  class LegacyCableServer < CableServer # :nodoc:
    delegate :logger, to: :@server

    def initialize(server, clock, socket)
      super(server, clock)
      @socket = socket
    end

    def worker_pool
      self
    end

    def event_loop
      self
    end

    def add_connection(_connection); end

    def remove_connection(_connection); end

    def async_invoke(receiver, method, *args, connection: receiver, &block)
      @socket.work(receiver, method, *args, connection: connection, &block)
    end

    def async_exec(receiver, *args, connection:, &block)
      async_invoke(receiver, :instance_exec, *args, connection: connection, &block)
    end
  end

  class LegacyWebSocket # :nodoc:
    module Takeover
      def new(env, *arguments, **options)
        socket = env[CableSocket::ENV_KEY]
        socket ? LegacyWebSocket.new(socket) : super
      end
    end

    delegate :protocol, :close, to: :@socket

    def initialize(socket)
      @socket = socket
    end

    def possible?
      true
    end

    def alive?
      @socket.open?
    end

    def transmit(text)
      @socket.deliver(text)
    end

    def rack_response
      @socket.accept
    end
  end
end

module RailsJsdom
  module LegacyRescue # :nodoc:
    def rescue_with_handler(exception)
      super || raise(exception)
    end
  end
end
