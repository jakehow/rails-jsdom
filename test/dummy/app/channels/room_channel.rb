class RoomChannel < ActionCable::Channel::Base
  extend Turbo::Streams::StreamName

  def subscribed
    stream_name = self.class.verified_stream_name(params[:signed_stream_name])
    stream_name ? stream_from(stream_name) : reject
  end

  def echo(data)
    transmit(data.slice("text"))
  end
end
