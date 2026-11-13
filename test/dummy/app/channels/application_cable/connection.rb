module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :visitor

    def connect
      reject_unauthorized_connection if cookies[:banned]
      self.visitor = cookies[:visitor] || "guest"
    end
  end
end
