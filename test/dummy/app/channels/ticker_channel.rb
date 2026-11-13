class TickerChannel < ActionCable::Channel::Base
  periodically every: 5.seconds do
    transmit({ "ticked_at" => Time.now.to_r.to_s })
  end

  def subscribed
    stream_from("ticker") { |message| transmit({ "relayed" => message }) }
  end
end
