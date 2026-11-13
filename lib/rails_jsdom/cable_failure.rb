module RailsJsdom
  class CableFailure # :nodoc:
    COMMANDS = %i[dispatch dispatch_websocket_message].freeze

    def initialize(error, receiver, method, args)
      @error = error
      @receiver = receiver
      @method = method
      @args = args
    end

    def message
      "#{@error.class}: #{@error.message} was raised in Action Cable code while #{doing}, and no rescue_from handled it. " \
        "Action Cable would log it and carry on; RailsJsdom fails the test so the error is not missed. " \
        "If the error is expected, handle it with rescue_from in the channel or the connection.\n#{backtrace}"
    end

    private

    def doing
      COMMANDS.include?(@method) ? "handling the page's command #{@args.first}" : "running #{@receiver.class.name}##{@method}"
    end

    def backtrace
      Array(@error.backtrace).first(10).join("\n")
    end
  end
end
