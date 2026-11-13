require "test_helper"

module RailsJsdom
  class TestHelperTest < ActiveSupport::TestCase
    FETCH = { "method" => "POST", "url" => "http://www.example.com/items?page=2", "headers" => { "accept" => "text/html", "content-type" => "text/plain" }, "body" => [ "a=1" ].pack("m0") }.freeze

    setup do
      @helper = Class.new { include ActiveSupport::Testing::TimeHelpers, RailsJsdom::TestHelper }.new
    end

    teardown do
      @helper.travel_back
    end

    test "#visit loads the Rails response into Node" do
      RailsJsdom.stubs(:bridge).returns(bridge = stub_bridge)
      @helper.stubs(:process)
      @helper.stubs(:response).returns(stub(redirect?: false, body: "<p>Hi</p>"))
      @helper.stubs(:request).returns(stub(original_url: "http://www.example.com/hi"))
      bridge.expects(:call).with({ command: "load", html: "<p>Hi</p>", url: "http://www.example.com/hi", history: "push" }, @helper)

      @helper.visit("/hi")
    end

    test "#visit requests the page from Rails" do
      RailsJsdom.stubs(:bridge).returns(stub_bridge)
      @helper.stubs(:response).returns(stub(redirect?: false, body: ""))
      @helper.stubs(:request).returns(stub(original_url: "http://www.example.com/hi"))
      @helper.expects(:process).with(:get, "/hi", params: nil, headers: {})

      @helper.visit("/hi")
    end

    test "#visit follows redirects before it loads the page" do
      RailsJsdom.stubs(:bridge).returns(stub_bridge)
      @helper.stubs(:process)
      @helper.stubs(:response).returns(stub(redirect?: true), stub(redirect?: false, body: ""))
      @helper.stubs(:request).returns(stub(original_url: "http://www.example.com/session/new"))
      @helper.expects(:follow_redirect!).with(headers: {}).once

      @helper.visit("/dashboard")
    end

    test "#mount_html loads the HTML as a page on the application host" do
      RailsJsdom.stubs(:bridge).returns(bridge = stub_bridge)
      @helper.stubs(:host).returns("www.example.com")
      bridge.expects(:call).with({ command: "load", html: "<!DOCTYPE html><html><head></head><body><p>Fragment</p></body></html>", url: "http://www.example.com/", history: "push" }, @helper)

      @helper.mount_html("<p>Fragment</p>")
    end

    test "#stub_fetch registers a canned JSON response in Node" do
      RailsJsdom.stubs(:bridge).returns(bridge = mock)
      bridge.expects(:call).with({ command: "stub_fetch", url: "/api/agents", response: { status: 200, headers: { "content-type" => "application/json" }, body: "[]" } })

      @helper.stub_fetch("/api/agents", body: "[]")
    end

    test "#mount_partial loads the rendered partial as a page" do
      RailsJsdom.stubs(:bridge).returns(bridge = stub_bridge)
      ApplicationController.stubs(:render).with(partial: "shared/card", locals: { title: "Hi" }, assigns: { packs: [] }).returns("<p>Card</p>")
      @helper.stubs(:host).returns("www.example.com")
      bridge.expects(:call).with({ command: "load", html: "<!DOCTYPE html><html><head></head><body><p>Card</p></body></html>", url: "http://www.example.com/", history: "push" }, @helper)

      @helper.mount_partial("shared/card", locals: { title: "Hi" }, assigns: { packs: [] })
    end

    test "#click sends the locator with its scope and match" do
      RailsJsdom.stubs(:bridge).returns(bridge = stub_bridge)
      bridge.expects(:call).with({ command: "click", locator: "Save", scope: [ { css: "form" } ], match: :first }, @helper)

      @helper.within("form") { @helper.click("Save", match: :first) }
    end

    test "#fill_in sends the value as text" do
      RailsJsdom.stubs(:bridge).returns(bridge = stub_bridge)
      bridge.expects(:call).with({ command: "fill_in", locator: "Team seats", with: "30", scope: [], match: nil }, @helper)

      @helper.fill_in("Team seats", with: 30)
    end

    test "#evaluate_script returns the value of the script" do
      RailsJsdom.stubs(:bridge).returns(stub_bridge(42))

      assert_equal 42, @helper.evaluate_script("6 * 7")
    end

    test "#current_path reads the path of the page in Node" do
      RailsJsdom.stubs(:bridge).returns(stub_bridge("url" => "http://www.example.com/api_tokens?page=2"))

      assert_equal "/api_tokens", @helper.current_path
    end

    test "#page_text reads the visible text of the page in Node" do
      RailsJsdom.stubs(:bridge).returns(stub_bridge("text" => "Choose your plan"))

      assert_equal "Choose your plan", @helper.page_text
    end

    test "#assert_text asserts that the page text includes the text" do
      RailsJsdom.stubs(:bridge).returns(stub_bridge("text" => "Choose your plan"))
      @helper.expects(:assert).with(true, "Expected the page text to include \"your plan\"")

      @helper.assert_text("your plan")
    end

    test "#refute_text asserts that the page text leaves out the text" do
      RailsJsdom.stubs(:bridge).returns(stub_bridge("text" => "Choose your plan"))
      @helper.expects(:assert).with(true, "Expected the page text not to include \"NaN\"")

      @helper.refute_text("NaN")
    end

    test "#document_root_element parses the page in Node" do
      RailsJsdom.stubs(:bridge).returns(stub_bridge("html" => "<!DOCTYPE html><html><body><p>Mutated</p></body></html>"))

      assert_equal "Mutated", @helper.document_root_element.at_css("p").text
    end

    test "#click routes a fetch from the page to Rails" do
      bridge_answering(FETCH)
      @helper.stubs(:host).returns("www.example.com")
      @helper.stubs(:response).returns(stub(redirect?: false, status: 200, headers: {}, body: ""))
      @helper.stubs(:request).returns(stub(original_url: "http://www.example.com/items"))
      @helper.expects(:process).with(:post, "/items?page=2", params: "a=1", headers: FETCH.fetch("headers"))

      @helper.click("Save")
    end

    test "#click answers a fetch with the Rails response" do
      replies = bridge_answering(FETCH)
      @helper.stubs(:host).returns("www.example.com")
      @helper.stubs(:process)
      @helper.stubs(:response).returns(stub(redirect?: false, status: 201, headers: { "content-type" => "text/html", "set-cookie" => "session=1" }, body: "<p>Saved</p>"))
      @helper.stubs(:request).returns(stub(original_url: "http://www.example.com/items"))
      @helper.click("Save")

      assert_equal [ { status: 201, headers: { "content-type" => "text/html" }, body: "<p>Saved</p>", url: "http://www.example.com/items", redirected: false } ], replies
    end

    test "#click follows a fetch's redirects with its Accept header" do
      bridge_answering(FETCH)
      @helper.stubs(:host).returns("www.example.com")
      @helper.stubs(:process)
      @helper.stubs(:response).returns(stub(redirect?: true), stub(redirect?: false, status: 200, headers: {}, body: ""))
      @helper.stubs(:request).returns(stub(original_url: "http://www.example.com/items/1"))
      @helper.expects(:follow_redirect!).with(headers: { "accept" => "text/html" }).once

      @helper.click("Save")
    end

    test "#click reports that Rails redirected a fetch" do
      replies = bridge_answering(FETCH)
      @helper.stubs(:host).returns("www.example.com")
      @helper.stubs(:process)
      @helper.stubs(:follow_redirect!)
      @helper.stubs(:response).returns(stub(redirect?: true), stub(redirect?: false, status: 200, headers: {}, body: ""))
      @helper.stubs(:request).returns(stub(original_url: "http://www.example.com/items/1"))
      @helper.click("Save")

      assert_equal([ true ], replies.map { |reply| reply.fetch(:redirected) })
    end

    test "#click refuses a fetch outside the application" do
      replies = bridge_answering(FETCH.merge("url" => "https://cdn.example.com/player.js"))
      @helper.stubs(:host).returns("www.example.com")
      @helper.click("Play")

      assert_equal [ { error: "RailsJsdom sends fetch only to www.example.com, not to https://cdn.example.com/player.js." } ], replies
    end

    test "#click refuses a cable connection outside the application" do
      replies = bridge_answering({ "kind" => "cable", "action" => "open", "socket" => "1:1", "url" => "wss://push.example.com/socket", "protocols" => [] })
      @helper.stubs(:host).returns("www.example.com")
      @helper.click("Connect")

      assert_equal [ { error: "RailsJsdom opens cable connections only to www.example.com, not to wss://push.example.com/socket." } ], replies
    end

    test "#click opens a cable connection with the session's cookies for the socket's path" do
      request = { "kind" => "cable", "action" => "open", "socket" => "1:1", "url" => "ws://www.example.com/cable", "protocols" => [] }
      bridge_answering(request)
      jar = stub
      jar.stubs(:for).with(URI("http://www.example.com/cable")).returns("visitor=ada")
      @helper.stubs(host: "www.example.com", integration_session: stub(cookies: jar))
      RailsJsdom::Cable.any_instance.expects(:answer).with(request, "visitor=ada").returns({ protocol: "actioncable-v1-json" })

      @helper.click("Connect")
    end

    private

    def stub_bridge(value = nil)
      mock.tap { |bridge| bridge.stubs(:call).returns(value) }
    end

    def bridge_answering(fetch)
      replies = []
      bridge = Object.new
      bridge.define_singleton_method(:call) { |_message, peer| replies << peer.rails_jsdom_answer(fetch) }
      RailsJsdom.stubs(:bridge).returns(bridge)
      replies
    end
  end
end
