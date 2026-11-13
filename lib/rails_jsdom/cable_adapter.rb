module RailsJsdom
  class CableAdapter < ActionCable::SubscriptionAdapter::Test # :nodoc:
    def initialize(server)
      super
      @thread = Thread.current
      @failures = Thread::Queue.new
    end

    def broadcast(channel, payload)
      Thread.current == @thread ? super : refuse(channel)
    end

    def report(failure)
      @failures << failure
    end

    def failed?
      !@failures.empty?
    end

    def raise_failure
      raise Error, @failures.pop if failed?
    end

    private

    def new_subscriber_map
      ActionCable::SubscriptionAdapter::SubscriberMap.new
    end

    def refuse(channel)
      report "#{channel.inspect} was broadcast from a thread other than the test's, so RailsJsdom did not deliver it. " \
        "Interaction tests deliver each broadcast as it is made, so broadcasts must come from the test, from a request the page makes, " \
        "or from jobs the test runs with perform_enqueued_jobs; a broadcast from another thread could reach the page at any moment."
    end
  end
end
