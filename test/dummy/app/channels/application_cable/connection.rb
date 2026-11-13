module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :visitor

    rescue_from KeyError, with: :report_key_error

    def connect
      reject_unauthorized_connection if cookies[:banned]
      raise "connecting failed" if cookies[:broken]
      self.visitor = cookies[:visitor] || "guest"
    end

    private

    def report_key_error(error)
      transmit({ "handled" => error.message })
    end
  end
end
