require "test_helper"

module RailsJsdom
  class BridgeTest < ActiveSupport::TestCase
    setup do
      @logger = ActiveSupport::Logger.new(nil)
      @bridge = RailsJsdom::Bridge.new(command: [ "node", "runner.js" ], setup: { command: "setup" }, logger: @logger)
    end

    test "#call starts Node before sending the setup and the message" do
      input = StringIO.new
      Open3.expects(:popen3).with("node", "runner.js").returns(node(results({}, nil), input: input))
      @bridge.call(command: "click")

      assert_equal([ { "command" => "setup" }, { "command" => "click" } ], input.string.lines.map { |line| JSON.parse(line) })
    end

    test "#call sends each line Node writes to its error output to the logger" do
      Open3.stubs(:popen3).returns(node("", error: "page error\nconsole message\n"))
      @logger.expects(:info).with("[rails_jsdom] page error")
      @logger.expects(:info).with("[rails_jsdom] console message")

      error_from { @bridge.call(command: "click") }
    end

    test "#call returns the value of Node's result" do
      Open3.stubs(:popen3).returns(node(results({}, { "id" => "message" })))

      assert_equal({ "id" => "message" }, @bridge.call(command: "evaluate"))
    end

    test "#call answers each fetch with the peer's answer and the sync that follows it" do
      input = StringIO.new
      Open3.stubs(:popen3).returns(node(lines({ type: "result", value: {} }, { type: "fetch", id: 7, request: { "url" => "/a" }, clock: 0 }, { type: "result", value: nil, clock: 0 }), input: input))
      @bridge.call({ command: "click" }, peer)

      assert_equal({ "type" => "fetch_response", "id" => 7, "response" => { "status" => 200, "url" => "/a" }, "sync" => { "frames" => [ "after /a" ] } }, JSON.parse(input.string.lines.last))
    end

    test "#call sends the peer's sync with the message" do
      input = StringIO.new
      Open3.stubs(:popen3).returns(node(lines({ type: "result", value: {} }, { type: "result", value: nil, clock: 0 }), input: input))
      @bridge.call({ command: "click" }, peer)

      assert_equal({ "command" => "click", "sync" => { "frames" => [] } }, JSON.parse(input.string.lines.last))
    end

    test "#call gives the peer the page clock of every message Node writes" do
      Open3.stubs(:popen3).returns(node(lines({ type: "result", value: {} }, { type: "fetch", id: 7, request: { "url" => "/a" }, clock: 250 }, { type: "result", value: nil, clock: 900 })))
      @bridge.call({ command: "click" }, recorder = peer)

      assert_equal [ 250, 900 ], recorder.clocks
    end

    test "#call raises Node's error message" do
      Open3.stubs(:popen3).returns(node(lines({ type: "result", value: {} }, { type: "error", message: "unable to find" })))

      assert_equal "unable to find", error_from { @bridge.call(command: "click") }.message
    end

    test "#call raises when the Node process exits" do
      Open3.stubs(:popen3).returns(node(""))

      assert_raises(RailsJsdom::Error) { @bridge.call(command: "click") }
    end

    test "#call stops Node when the Node process exits, so the next message starts a new one" do
      Open3.stubs(:popen3).returns(node(""))
      error_from { @bridge.call(command: "click") }

      assert_not @bridge.started?
    end

    test "#call stops Node when answering a fetch raises, so Node is never left waiting" do
      Open3.stubs(:popen3).returns(node(lines({ type: "result", value: {} }, { type: "fetch", id: 7, request: {}, clock: 0 })))
      failing = peer
      failing.define_singleton_method(:rails_jsdom_answer) { |_request| raise ArgumentError }
      assert_raises(ArgumentError) { @bridge.call({ command: "click" }, failing) }

      assert_not @bridge.started?
    end

    test "#call terminates a running Node process when it stops" do
      Open3.stubs(:popen3).returns(node("", process: stub(pid: 4242, alive?: true)))
      Process.expects(:kill).with("TERM", 4242)

      error_from { @bridge.call(command: "click") }
    end

    test "#call leaves an exited Node process alone when it stops" do
      Open3.stubs(:popen3).returns(node("", process: stub(alive?: false)))
      Process.expects(:kill).never

      error_from { @bridge.call(command: "click") }
    end

    test "#call stops Node and fails when the page does not answer in time" do
      RailsJsdom.command_timeout = 0.1
      silent_output, _writer = IO.pipe
      Open3.stubs(:popen3).returns([ StringIO.new, silent_output, StringIO.new, nil ])

      assert_match(/did not answer within 0\.1 seconds/, error_from { @bridge.call(command: "evaluate") }.message)
    ensure
      RailsJsdom.command_timeout = nil
    end

    test "#call starts Node once for every message" do
      Open3.expects(:popen3).once.returns(node(results(nil, nil, nil)))
      @bridge.call(command: "click")
      @bridge.call(command: "click")
    end

    test "#started? is false before the first message" do
      assert_not @bridge.started?
    end

    test "#reset sends Node a reset once Node runs" do
      @bridge.stubs(:started?).returns(true)
      @bridge.expects(:call).with(command: "reset")

      @bridge.reset
    end

    test "#reset leaves Node unstarted before the first message" do
      Open3.expects(:popen3).never

      @bridge.reset
    end

    private

    def peer
      Struct.new(:clocks, :answered) do
        def rails_jsdom_sync
          { frames: answered }
        end
        def rails_jsdom_page_clock(now)
          clocks << now
        end
        def rails_jsdom_answer(request)
          { status: 200, url: request.fetch("url") }.tap { answered << "after #{request.fetch("url")}" }
        end
      end.new([], [])
    end

    def node(output, input: StringIO.new, error: "", process: nil)
      [ input, StringIO.new(output), StringIO.new(error), process ]
    end

    def results(*values)
      lines(*values.map { |value| { type: "result", value: value } })
    end

    def lines(*messages)
      messages.map(&:to_json).join("\n")
    end

    def error_from
      yield
      nil
    rescue RailsJsdom::Error => error
      error
    end
  end
end
