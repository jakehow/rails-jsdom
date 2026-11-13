class VisitorChannel < ActionCable::Channel::Base
  def subscribed
    transmit({ "visitor" => connection.visitor })
  end
end
