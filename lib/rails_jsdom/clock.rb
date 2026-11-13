module RailsJsdom
  class Clock # :nodoc:
    Timer = Struct.new(:at, :every, :order, :action, :clock) do
      def shutdown
        clock.cancel(self)
      end
    end

    BEAT = ActionCable::Server::Connections::BEAT_INTERVAL * 1000

    attr_reader :now

    def initialize(epoch, &travel)
      @epoch = epoch
      @now = 0r
      @travel = travel
      @timers = []
      @order = 0
      @beating = []
      travel.call(epoch)
    end

    def every(interval, &action)
      milliseconds = interval.to_r * 1000
      schedule(@now + milliseconds, milliseconds, action)
    end

    def keep_alive(socket)
      @beating << socket
      @heartbeat ||= schedule(((@now / BEAT).floor + 1) * BEAT, BEAT, -> { @beating.dup.each(&:beat) })
    end

    def let_go(socket)
      @beating.delete(socket)
    end

    def cancel(timer)
      @timers.delete(timer)
    end

    def page_time(now)
      @now = now.to_r
      run_due
      @travel.call(current)
    end

    def moved?
      keep_fraction
      Time.now.to_r != current.to_r
    end

    def view
      keep_fraction
      follow_travel_back
      { epoch: (@epoch.to_r * 1000).to_f, now: (@now + ahead).to_f, deadline: deadline }
    end

    private

    def keep_fraction
      @travel.call(current) if fraction_dropped?
    end

    def fraction_dropped?
      exact = current.to_r
      exact != exact.floor && Time.now.to_r == exact.floor
    end

    def follow_travel_back
      @epoch = Time.now - (@now / 1000) if ahead.negative?
    end

    def deadline
      next_timer&.at&.to_f
    end

    def ahead
      (Time.now.to_r - current.to_r) * 1000
    end

    def run_due
      while (timer = next_due)
        @travel.call(@epoch + (timer.at / 1000))
        repeat(timer)
        timer.action.call
      end
    end

    def current
      @epoch + (@now / 1000)
    end

    def schedule(at, every, action)
      @order += 1
      Timer.new(at, every, @order, action, self).tap { |timer| @timers << timer }
    end

    def repeat(timer)
      @order += 1
      timer.at += timer.every
      timer.order = @order
    end

    def next_timer
      @timers.min_by { |timer| [ timer.at, timer.order ] }
    end

    def next_due
      timer = next_timer
      timer if timer && timer.at <= @now
    end
  end
end
