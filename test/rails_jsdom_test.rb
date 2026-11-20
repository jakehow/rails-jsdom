require "test_helper"

class RailsJsdomTest < ActiveSupport::TestCase
  test ".bridge runs the Node runner with the Rails logger" do
    Process.stubs(:pid).returns(-101)
    RailsJsdom::Bridge.expects(:new).with(has_entries(command: [ "node", RailsJsdom::RUNNER ], logger: Rails.logger)).returns(:bridge)

    RailsJsdom.bridge
  end

  test ".bridge sends Node the application setup" do
    Process.stubs(:pid).returns(-102)
    RailsJsdom::Bridge.expects(:new).with(has_entry(:setup, has_entries(command: "setup", root: Rails.root.to_s))).returns(:bridge)

    RailsJsdom.bridge
  end

  test ".bridge keeps one bridge for each process" do
    Process.stubs(:pid).returns(-103)

    assert_same RailsJsdom.bridge, RailsJsdom.bridge
  end

  test ".setup points Node at the application and its Stimulus controllers" do
    expected = { command: "setup", root: Rails.root.to_s, controllers: Rails.root.join("app/javascript/controllers").to_s, horizon: RailsJsdom::TIMER_HORIZON, hidden: RailsJsdom::HIDDEN_SELECTOR }

    assert_equal expected, RailsJsdom.setup.slice(*expected.keys)
  end

  test ".setup leaves the entry and esbuild config to the importmap by default" do
    assert_equal({ entry: nil, esbuild: nil }, RailsJsdom.setup.slice(:entry, :esbuild))
  end

  test ".setup points Node at the app's entry and esbuild config" do
    RailsJsdom.stubs(:entry).returns("app/javascript/entry.js")
    RailsJsdom.stubs(:esbuild_config).returns("test/esbuild.config.mjs")

    assert_equal({ entry: Rails.root.join("app/javascript/entry.js").to_s, esbuild: Rails.root.join("test/esbuild.config.mjs").to_s }, RailsJsdom.setup.slice(:entry, :esbuild))
  end

  test ".setup sends no controllers when the app registers its own" do
    RailsJsdom.register_controllers = false

    assert_nil RailsJsdom.setup.fetch(:controllers)
  ensure
    RailsJsdom.register_controllers = true
  end

  test ".modules and .directories are empty without importmap" do
    Rails.application.stubs(:importmap).returns(nil)

    assert_equal [ {}, [], {} ], [ RailsJsdom.modules, RailsJsdom.remote_modules, RailsJsdom.directories ]
  end

  test ".modules resolves local importmap pins to their asset files" do
    Rails.application.importmap.stubs(:packages).returns("@hotwired/stimulus" => stub(path: "stimulus.min.js"))
    Rails.application.assets.load_path.stubs(:find).with("stimulus.min.js").returns(stub(path: Pathname("/gems/stimulus.min.js")))

    assert_equal({ "@hotwired/stimulus" => "/gems/stimulus.min.js" }, RailsJsdom.modules)
  end

  test ".modules leaves a pin without an asset unresolved" do
    Rails.application.importmap.stubs(:packages).returns("missing" => stub(path: "missing.js"))
    Rails.application.assets.load_path.stubs(:find).with("missing.js").returns(nil)

    assert_equal({ "missing" => nil }, RailsJsdom.modules)
  end

  test ".modules leaves out remote pins" do
    Rails.application.importmap.stubs(:packages).returns("lucide" => stub(path: "https://cdn.example.com/lucide.js"))

    assert_empty RailsJsdom.modules
  end

  test ".remote_modules lists the pins served from another host" do
    Rails.application.importmap.stubs(:packages).returns("lucide" => stub(path: "https://cdn.example.com/lucide.js"), "application" => stub(path: "application.js"))

    assert_equal [ "lucide" ], RailsJsdom.remote_modules
  end

  test ".directories maps each pinned directory by its module prefix" do
    Rails.application.importmap.stubs(:directories).returns("app/javascript/controllers" => stub(dir: "app/javascript/controllers", under: "controllers"))

    assert_equal({ "controllers" => Rails.root.join("app/javascript/controllers").to_s }, RailsJsdom.directories)
  end

  test ".document wraps HTML in a page body" do
    assert_equal "<!DOCTYPE html><html><head></head><body><p>Hi</p></body></html>", RailsJsdom.document("<p>Hi</p>")
  end
end
