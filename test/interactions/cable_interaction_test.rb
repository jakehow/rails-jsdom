require "test_helper"

class CableInteractionTest < RailsJsdom::TestCase
  setup do
    PresenceChannel.departed = []
  end

  test "each session's cable connection carries that session's cookies" do
    cookies[:visitor] = "ada"
    mount_html subscriber_page(channel: "VisitorChannel")
    using_session(:bob) do
      cookies[:visitor] = "bob"
      mount_html subscriber_page(channel: "VisitorChannel")
    end
    using_session(:anonymous) { mount_html subscriber_page(channel: "VisitorChannel") }

    assert_equal %w[ada bob guest], [ visitor_seen, using_session(:bob) { visitor_seen }, using_session(:anonymous) { visitor_seen } ]
  end

  test "a channel's periodic timer runs on the test's clock" do
    started = Time.now
    mount_html subscriber_page(channel: "TickerChannel")
    travel 5.seconds, with_usec: true

    assert_equal [ (started + 5).to_r.to_s ], evaluate_script("messages.map(message => message.ticked_at).filter(Boolean)")
  end

  test "a connection the app rejects is closed, and the test goes on" do
    cookies[:banned] = "1"
    mount_html subscriber_page(channel: "VisitorChannel")

    assert_equal [ [ "unauthorized" ], true ], evaluate_script("[messages.map(message => message.reason).filter(Boolean), closed]")
  end

  test "an error in a channel's subscribed that no rescue_from handles fails the next command, naming the command" do
    mount_html subscriber_page(channel: "BoomChannel", fail: true)

    assert_match(/RuntimeError: subscribing failed was raised in Action Cable code while handling the page's command .*BoomChannel/, assert_raises(RailsJsdom::Error) { evaluate_script("1") }.message)
  end

  test "an error in the connection's connect that no rescue_from handles fails the next command" do
    cookies[:broken] = "1"
    mount_html subscriber_page(channel: "VisitorChannel")

    assert_match(/RuntimeError: connecting failed was raised in Action Cable code/, assert_raises(RailsJsdom::Error) { evaluate_script("1") }.message)
  end

  test "an error the connection handles with rescue_from reaches the page and fails nothing" do
    mount_html subscriber_page(channel: "BoomChannel", perform: "explode_key")

    assert_equal [ "handled by the connection" ], evaluate_script("messages.map(message => message.handled).filter(Boolean)")
  end

  test "leaving a page runs its channels' unsubscribed" do
    cookies[:visitor] = "ada"
    mount_html subscriber_page(channel: "PresenceChannel")
    visit second_path

    assert_equal [ "ada" ], PresenceChannel.departed
  end

  private

  def visitor_seen
    evaluate_script("messages.map(message => message.visitor).find(Boolean)")
  end

  def subscriber_page(channel:, perform: nil, **params)
    identifier = { channel: channel, **params }.to_json
    <<~HTML
      <script>
        window.messages = []
        window.closed = false
        const socket = new WebSocket("/cable", ["actioncable-v1-json"])
        const identifier = #{identifier.to_json}
        socket.onclose = () => { closed = true }
        socket.onmessage = event => {
          const message = JSON.parse(event.data)
          if (message.type === "welcome") socket.send(JSON.stringify({ command: "subscribe", identifier }))
          if (message.type === "confirm_subscription" && #{perform.to_json}) socket.send(JSON.stringify({ command: "message", identifier, data: JSON.stringify({ action: #{perform.to_json} }) }))
          if (message.message) messages.push(message.message)
          else if (message.type === "disconnect" || message.handled) messages.push(message)
        }
      </script>
    HTML
  end
end
