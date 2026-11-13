require "securerandom"

module RailsJsdom
  module CableFrame # :nodoc:
    TEXT = 1
    CLOSE = 8

    def self.encode(opcode, payload)
      bytes = payload.b
      key = SecureRandom.random_bytes(4)
      [ 0x80 | opcode ].pack("C") + length_header(bytes.bytesize) + key + mask(bytes, key)
    end

    def self.mask(bytes, key)
      bytes.bytes.each_with_index.map { |byte, index| byte ^ key.getbyte(index % 4) }.pack("C*")
    end

    def self.length_header(size)
      if size < 126
        [ 0x80 | size ].pack("C")
      elsif size < 65_536
        [ 0x80 | 126, size ].pack("Cn")
      else
        [ 0x80 | 127, size ].pack("CQ>")
      end
    end

    def self.read(io)
      first, second = read_exactly(io, 2).unpack("CC")
      [ first & 0x0f, read_exactly(io, payload_size(io, second & 0x7f)) ]
    end

    def self.payload_size(io, size)
      case size
      when 126 then read_exactly(io, 2).unpack1("n")
      when 127 then read_exactly(io, 8).unpack1("Q>")
      else size
      end
    end

    def self.read_exactly(io, size)
      data = io.read(size)
      raise EOFError, "the cable connection closed" if data.nil? || data.bytesize < size

      data
    end
  end
end
