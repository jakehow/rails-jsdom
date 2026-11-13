require "test_helper"

class BroadcastInteractionTest < RailsJsdom::TestCase
  test "a page subscribed with turbo_stream_from receives a broadcast" do
    visit root_path
    Turbo::StreamsChannel.broadcast_append_to("items", target: "items", html: "<li>Broadcast item</li>")

    assert_text "Broadcast item"
  end

  test "a subscribed stream receives a broadcast append" do
    mount_html stream_page(Turbo::StreamsChannel.signed_stream_name("rails_jsdom"))
    Turbo::StreamsChannel.broadcast_append_to("rails_jsdom", target: "list", html: "<p>Delivered</p>")

    assert_dom "#list p", text: "Delivered"
  end

  test "a broadcast to a stream the page does not subscribe to stays off the page" do
    mount_html stream_page(Turbo::StreamsChannel.signed_stream_name("rails_jsdom"))
    Turbo::StreamsChannel.broadcast_append_to("elsewhere", target: "list", html: "<p>Delivered</p>")

    assert_dom "#list p", count: 0
  end

  test "a stream source with a forged signature receives no broadcast" do
    mount_html stream_page("forged--signature")
    Turbo::StreamsChannel.broadcast_append_to("rails_jsdom", target: "list", html: "<p>Delivered</p>")

    assert_dom "#list p", count: 0
  end

  test "a broadcast made before the page subscribed stays off the page" do
    Turbo::StreamsChannel.broadcast_append_to("rails_jsdom", target: "list", html: "<p>Early</p>")
    mount_html stream_page(Turbo::StreamsChannel.signed_stream_name("rails_jsdom"))

    assert_dom "#list p", count: 0
  end

  test "a broadcast from a job the test performs reaches the page" do
    mount_html stream_page(Turbo::StreamsChannel.signed_stream_name("rails_jsdom"))
    perform_enqueued_jobs { Turbo::StreamsChannel.broadcast_append_later_to("rails_jsdom", target: "list", html: "<p>Later</p>") }

    assert_dom "#list p", text: "Later"
  end

  test "a delivered broadcast is not applied again by later actions" do
    mount_html stream_page(Turbo::StreamsChannel.signed_stream_name("rails_jsdom"))
    Turbo::StreamsChannel.broadcast_append_to("rails_jsdom", target: "list", html: "<p>Once</p>")
    evaluate_script("document.title")
    evaluate_script("document.title")

    assert_dom "#list p", count: 1
  end

  test "a stream source added to the page later receives broadcasts" do
    mount_html "<div id='list'></div>"
    evaluate_script("document.body.insertAdjacentHTML('beforeend', #{stream_source(Turbo::StreamsChannel.signed_stream_name('rails_jsdom')).to_json})")
    Turbo::StreamsChannel.broadcast_append_to("rails_jsdom", target: "list", html: "<p>Late subscriber</p>")

    assert_dom "#list p", text: "Late subscriber"
  end

  test "a stream source for an app channel receives what that channel streams" do
    mount_html stream_page(RoomChannel.signed_stream_name("room"), channel: "RoomChannel")
    Turbo::StreamsChannel.broadcast_append_to("room", target: "list", html: "<p>Room message</p>")

    assert_dom "#list p", text: "Room message"
  end

  test "Turbo marks a stream source connected once its subscription is confirmed, and a rejected one not" do
    mount_html stream_page(Turbo::StreamsChannel.signed_stream_name("rails_jsdom")) + stream_source("forged--signature")

    assert_selector "turbo-cable-stream-source[connected]", count: 1, visible: false
  end

  test "a stream source for a channel that streams nothing, or no such channel, receives nothing" do
    signed_name = Turbo::StreamsChannel.signed_stream_name("rails_jsdom")
    mount_html "#{stream_source(signed_name, channel: "ChatChannel")}#{stream_source(signed_name, channel: "MissingChannel")}<div id='list'></div>"
    Turbo::StreamsChannel.broadcast_append_to("rails_jsdom", target: "list", html: "<p>Delivered</p>")

    assert_dom "#list p", count: 0
  end

  test "an error a channel action does not handle fails the next command" do
    mount_html boom_page("explode")

    assert_match(/RuntimeError: boom was raised in Action Cable code/, assert_raises(RailsJsdom::Error) { evaluate_script("1") }.message)
  end

  test "an error the channel handles with rescue_from reaches the page and fails nothing" do
    mount_html boom_page("explode_argument")

    assert_equal [ "handled by the channel" ], evaluate_script("handled")
  end

  private

  def boom_page(action)
    <<~HTML
      <script>
        window.handled = []
        const socket = new WebSocket("/cable", ["actioncable-v1-json"])
        const identifier = JSON.stringify({ channel: "BoomChannel" })
        socket.onmessage = event => {
          const message = JSON.parse(event.data)
          if (message.type === "welcome") socket.send(JSON.stringify({ command: "subscribe", identifier }))
          if (message.type === "confirm_subscription") socket.send(JSON.stringify({ command: "message", identifier, data: JSON.stringify({ action: "#{action}" }) }))
          if (message.message) handled.push(message.message.handled)
        }
      </script>
    HTML
  end

  def stream_page(signed_name, channel: "Turbo::StreamsChannel")
    "#{stream_source(signed_name, channel: channel)}<div id='list'></div>"
  end

  def stream_source(signed_name, channel: "Turbo::StreamsChannel")
    "<turbo-cable-stream-source channel=\"#{channel}\" signed-stream-name=\"#{signed_name}\"></turbo-cable-stream-source>"
  end
end
