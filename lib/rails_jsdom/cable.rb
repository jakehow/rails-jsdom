module RailsJsdom
  class Cable # :nodoc:
    def initialize
      @sockets = {}
      @frames = Thread::Queue.new
      @expected = Set.new
      @active = false
    end

    def answer(request, cookie)
      case request.fetch("action")
      when "open" then open(request.fetch("socket"), request.fetch("url"), request.fetch("protocols"), cookie)
      when "send" then send_data(request.fetch("socket"), request.fetch("data"))
      when "close" then close_socket(request.fetch("socket"))
      else receive
      end
    end

    def open?
      @sockets.any?
    end

    def close
      @sockets.each_value(&:close)
      @sockets.clear
      ActiveSupport::Notifications.unsubscribe(@broadcasts) if @broadcasts
    end

    private

    def open(id, url, protocols, cookie)
      @broadcasts ||= ActiveSupport::Notifications.subscribe("broadcast.action_cable") { @active = true }
      @expected << [ id, "welcome" ]
      @sockets[id] = CableSocket.new(url, protocols, cookie) { |frame| @frames << frame.merge(socket: id) }
      { protocol: @sockets[id].protocol }
    rescue CableSocket::Refused => error
      @expected.delete([ id, "welcome" ])
      { error: error.message }
    end

    def send_data(id, data)
      @active = true
      command = parse(data)
      @expected << [ id, command["identifier"] ] if command["command"] == "subscribe"
      @sockets.fetch(id).send_text(data)
      nil
    end

    def close_socket(id)
      @sockets.delete(id)&.close
      forget(id)
      nil
    end

    def receive
      frames = []
      deadline = monotonic + RailsJsdom.cable_reply_timeout
      while (frame = next_frame(frames.any?, deadline))
        frames << note(frame)
      end
      @expected.clear if monotonic >= deadline
      @active = false
      frames
    end

    def next_frame(received, deadline)
      @frames.empty? ? wait_for_frame(received, deadline) : @frames.pop
    end

    def wait_for_frame(received, deadline)
      if @expected.any?
        @frames.pop(timeout: [ deadline - monotonic, 0 ].max)
      elsif @active || received
        @frames.pop(timeout: RailsJsdom.cable_quiet_period)
      end
    end

    def note(frame)
      forget(frame[:socket]) if frame[:closed]
      @expected.delete(fulfilled(frame[:socket], parse(frame[:data])))
      frame
    end

    def fulfilled(socket, message)
      case message["type"]
      when "welcome", "disconnect" then [ socket, "welcome" ]
      when "confirm_subscription", "reject_subscription" then [ socket, message["identifier"] ]
      end
    end

    def forget(id)
      @expected.delete_if { |socket, _| socket == id }
    end

    def parse(data)
      value = data && JSON.parse(data)
      value.is_a?(Hash) ? value : {}
    rescue JSON::ParserError
      {}
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
