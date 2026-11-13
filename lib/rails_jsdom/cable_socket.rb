require "socket"
require "rack/mock_request"

module RailsJsdom
  class CableSocket # :nodoc:
    class Refused < StandardError; end

    HANDSHAKE_TIMEOUT = 5

    attr_reader :protocol

    def self.env(url, protocols, cookie, io)
      origin = origin(URI(url))
      Rack::MockRequest.env_for("#{origin}#{URI(url).request_uri}", headers(origin, protocols, cookie)).tap do |env|
        env["rack.hijack?"] = true
        env["rack.hijack"] = -> { env["rack.hijack_io"] = io }
      end
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

    def initialize(url, protocols, cookie, &on_frame)
      server_io, @io = UNIXSocket.pair
      status, = ActionCable.server.call(self.class.env(url, protocols, cookie, server_io))
      raise Refused, "the cable endpoint answered #{status}" if status != -1

      @protocol = handshake
      @reader = Thread.new { read_frames(&on_frame) }
    end

    def send_text(text)
      write(CableFrame::TEXT, text)
    end

    def close
      write(CableFrame::CLOSE, [ 1000 ].pack("n"))
      @reader.join(HANDSHAKE_TIMEOUT)
    ensure
      @io.close
    end

    private

    def handshake
      _status, *lines = read_head.split("\r\n")
      header_values(lines).fetch("sec-websocket-protocol", "")
    end

    def header_values(lines)
      lines.filter_map { |line| line.split(": ", 2) }.to_h { |name, value| [ name.downcase, value ] }
    end

    def read_head
      head = +""
      head << read_byte until head.end_with?("\r\n\r\n")
      head
    end

    def read_byte
      @io.read(1) || raise(Refused, "the cable endpoint closed the connection")
    end

    def read_frames
      code = 1006
      loop do
        opcode, payload = CableFrame.read(@io)
        opcode == CableFrame::CLOSE ? code = acknowledge_close(payload) : yield(data: payload.force_encoding(Encoding::UTF_8))
      end
    rescue IOError
      yield closed: true, code: code
    end

    def acknowledge_close(payload)
      write(CableFrame::CLOSE, payload)
      payload.unpack1("n") || 1005
    end

    def write(opcode, payload)
      @io.write(CableFrame.encode(opcode, payload))
    rescue IOError, SystemCallError
      nil
    end
  end
end
