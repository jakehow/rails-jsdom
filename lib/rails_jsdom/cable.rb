module RailsJsdom
  class Cable # :nodoc:
    def initialize(clock)
      @clock = clock
      @sockets = {}
      @frames = []
    end

    def answer(request, cookie)
      case request.fetch("action")
      when "open" then open(request.fetch("socket"), request.fetch("url"), request.fetch("protocols"), cookie)
      when "send" then send_data(request.fetch("socket"), request.fetch("data"))
      when "close" then close_socket(request.fetch("socket"))
      end
    end

    def drain
      @frames.slice!(0..)
    end

    def active?
      @frames.any? || @sockets.each_value.any?(&:open?)
    end

    def close
      @sockets.each_value(&:close_by_page)
      @sockets.clear
    end

    private

    def open(id, url, protocols, cookie)
      socket = CableSocket.new(id, @frames, @clock)
      socket.open(url, protocols, cookie).tap { |reply| @sockets[id] = socket if reply.key?(:protocol) }
    end

    def send_data(id, data)
      @sockets.fetch(id).receive(data)
      nil
    end

    def close_socket(id)
      @sockets.delete(id)&.close_by_page
      nil
    end
  end
end
