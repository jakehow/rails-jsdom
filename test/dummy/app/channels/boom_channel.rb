class BoomChannel < ActionCable::Channel::Base
  rescue_from ArgumentError, with: :report_argument_error

  def subscribed
    raise "subscribing failed" if params[:fail]
  end

  def explode(_data)
    raise "boom"
  end

  def explode_argument(_data)
    raise ArgumentError, "handled by the channel"
  end

  def explode_key(_data)
    raise KeyError, "handled by the connection"
  end

  private

  def report_argument_error(error)
    transmit({ "handled" => error.message })
  end
end
