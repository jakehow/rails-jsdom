class PresenceChannel < ActionCable::Channel::Base
  cattr_accessor :departed, default: []

  def subscribed
    stream_from "presence"
  end

  def unsubscribed
    departed << connection.visitor
  end
end
