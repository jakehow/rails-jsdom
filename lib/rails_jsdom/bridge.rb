module RailsJsdom
  class Bridge # :nodoc:
    def initialize(command:, setup:, logger:)
      @command = command
      @setup = setup
      @logger = logger
    end

    def call(message, peer = nil)
      start unless started?
      write(peer ? message.merge(sync: peer.rails_jsdom_sync) : message)
      receive(peer)
    end

    def started?
      !!@input
    end

    def reset
      call(command: "reset") if started?
    end

    private

    def start
      @input, @output, error, @process = Open3.popen3(*@command)
      @log = Thread.new { log(error) }
      write(@setup)
      receive
    end

    def log(error)
      error.each_line { |line| @logger.info("[rails_jsdom] #{line.chomp}") }
      error.close
    end

    def stop
      @input.close
      @output.close
      Process.kill("TERM", @process.pid) if @process&.alive?
      @log.join
      @input = nil
    end

    def receive(peer = nil)
      message = read
      peer&.rails_jsdom_page_clock(message.fetch("clock"))
      case message.fetch("type")
      when "fetch" then reply(message, peer)
      when "error" then raise Error, message.fetch("message")
      else message.fetch("value")
      end
    end

    def reply(message, peer)
      write(type: "fetch_response", id: message.fetch("id"), response: answer(message.fetch("request"), peer), sync: peer.rails_jsdom_sync)
      receive(peer)
    end

    def answer(request, peer)
      peer.rails_jsdom_answer(request)
    rescue StandardError
      stop
      raise
    end

    def read
      line = Timeout.timeout(RailsJsdom.command_timeout) { @output.gets }
      if line
        JSON.parse(line)
      else
        stop
        raise Error, "The RailsJsdom Node process exited. See the [rails_jsdom] lines in the Rails log."
      end
    rescue Timeout::Error
      stop
      raise Error, "The page did not answer within #{RailsJsdom.command_timeout} seconds, so its Node process was stopped. A script may be in an endless loop. The next command starts a new process. Raise RailsJsdom.command_timeout if your pages need longer."
    end

    def write(payload)
      @input.puts(JSON.generate(payload))
      @input.flush
    end
  end
end
