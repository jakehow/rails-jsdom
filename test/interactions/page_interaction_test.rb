require "test_helper"

class PageInteractionTest < RailsJsdom::TestCase
  test "a visited page boots its Stimulus controllers with their values" do
    visit root_path

    assert_dom "[data-counter-target=count]", text: "2"
  end

  test "a visited page keeps the URL that was visited when middleware moves part of the path into the script name" do
    visit "/123"

    assert_equal "http://www.example.com/123", current_url
  end

  test "a full page load keeps the URL of the link when middleware moves part of the path into the script name" do
    visit second_path
    click_on "Full reload to a prefixed page"

    assert_equal "http://www.example.com/123", current_url
  end

  test "a Turbo Drive visit to a page with new head styles renders the page" do
    visit second_path
    click_link "Styled page"

    assert_selector "h1", text: "Styled page"
  end

  test "clicking a Stimulus action updates its targets" do
    visit root_path
    click "Increment"
    click "Increment"

    assert_dom "[data-counter-target=count]", text: "4"
  end

  test "clicking by Stimulus action shorthand finds the button" do
    visit root_path
    click "toggle#flip"

    assert_dom "[data-toggle-target=panel]:not([hidden])", text: "Hidden details"
  end

  test "text assertions ignore hidden content until it is shown" do
    visit root_path

    refute_text "Hidden details"
  end

  test "a link inside a Turbo Frame replaces only that frame" do
    visit framed_path
    click_on "Next step"

    assert_dom "#step", text: "Step 2"
    assert_dom "#outside", text: "Outside 1"
  end

  test "a page in an endless loop fails the command, and the next page works in a new process" do
    RailsJsdom.command_timeout = 2
    visit login_path
    error = assert_raises(RailsJsdom::Error) { execute_script("while (true) {}") }
    visit login_path

    assert_equal [ true, true ], [ error.message.include?("did not answer within 2 seconds"), has_field?("Your name") ]
  ensure
    RailsJsdom.command_timeout = nil
  end

  test "a page fetch reaches Rails in the test's session" do
    visit login_path
    fill_in "Your name", with: "Ada"
    click "Sign in"
    visit root_path
    click "Load greeting"

    assert_dom "[data-greeting-target=output]", text: "Hello, Ada"
  end

  test "a page fetch follows a Rails redirect" do
    visit root_path
    click "Load greeting"

    assert_dom "[data-greeting-target=output]", text: "Please sign in"
  end

  test "a form without Turbo submits a full page load and follows the redirect" do
    visit login_path
    fill_in "Your name", with: "Grace"
    click "Sign in"

    assert_equal "/secret", current_path
    assert_dom "h1", text: "Secret for Grace"
  end

  test "visiting a protected page follows the redirect to sign in" do
    visit secret_path

    assert_equal "/login", current_path
  end

  test "a Turbo form submission applies the Turbo Stream response" do
    visit root_path
    fill_in "Item name", with: "Second item"
    click "Add item"

    assert_dom "#items li", count: 2
    assert_text "Second item"
  end

  test "fill_in finds a field by its placeholder" do
    visit root_path
    fill_in "New item", with: "Placeholder item"
    click "Add item"

    assert_text "Placeholder item"
  end

  test "accepting a Turbo confirmation runs the action" do
    visit root_path
    accept_confirm { click "Remove" }

    assert_dom "#item_1", count: 0
  end

  test "dismissing a Turbo confirmation keeps the page unchanged" do
    visit root_path
    dismiss_confirm { click "Remove" }

    assert_dom "#item_1"
  end

  test "accept_confirm returns the message of the confirmation" do
    visit root_path

    assert_equal("Remove the first item?", accept_confirm { click "Remove" })
  end

  test "accept_confirm finds the confirmation whose message matches a pattern" do
    visit root_path

    assert_equal "Remove the first item?", accept_confirm(/first item/) { click "Remove" }
  end

  test "accept_confirm fails when no confirmation matches the text" do
    visit root_path

    assert_raises(RailsJsdom::Error) { accept_confirm("Delete everything?") { click "Remove" } }
  end

  test "a confirmation after accept_confirm is unexpected again" do
    visit root_path
    accept_confirm { click "Remove" }

    assert_raises(RailsJsdom::Error) { evaluate_script("window.confirm('Again?')") }
  end

  test "clicking a link navigates with Turbo Drive" do
    visit root_path
    evaluate_script("window.keptAcrossNavigation = true")
    click "Second page"

    assert_equal "/second", current_path
    assert evaluate_script("window.keptAcrossNavigation")
  end

  test "a mounted partial runs its Stimulus controller" do
    mount_partial "shared/counter", locals: { start: 7 }
    click "Increment"

    assert_dom "[data-counter-target=count]", text: "8"
  end

  test "a stubbed fetch answers from its stub" do
    visit root_path
    stub_fetch "/greeting", body: { greeting: "Stubbed hello" }.to_json
    click "Load greeting"

    assert_dom "[data-greeting-target=output]", text: "Stubbed hello"
  end

  test "a fetch outside the application fails like a network error" do
    visit root_path

    assert_equal "TypeError", evaluate_script("fetch('https://cdn.example.com/player.js').catch(error => error.name)")
  end

  test "a page timer within the settle horizon runs before the action returns" do
    visit root_path
    evaluate_script("setTimeout(() => document.body.dataset.timer = 'ran', 500)")

    assert_dom "body[data-timer='ran']"
  end

  test "a page timer beyond the settle horizon stays pending" do
    visit root_path
    evaluate_script("setTimeout(() => document.body.dataset.timer = 'ran', 5000)")

    assert_dom "body[data-timer]", count: 0
  end

  test "an error thrown by page code fails the action" do
    visit root_path

    assert_raises(RailsJsdom::Error) { evaluate_script("setTimeout(() => { throw new Error('page bug') }, 0)") }
  end

  test "a confirm the test did not expect fails the action" do
    visit root_path

    assert_raises(RailsJsdom::Error) { evaluate_script("window.confirm('Continue?')") }
  end

  test "a confirm expected by the test that never appears fails accept_confirm" do
    visit root_path

    assert_raises(RailsJsdom::Error) { accept_confirm { click "Increment" } }
  end

  test "an exception Rails raises while answering a page fetch fails the test" do
    visit root_path

    assert_raises(RuntimeError) { evaluate_script("fetch('/broken')") }
  end

  test "the next page works after a page fetch raised in Rails" do
    visit root_path
    assert_raises(RuntimeError) { evaluate_script("fetch('/broken')") }
    visit root_path

    assert_dom "[data-counter-target=count]", text: "2"
  end

  test "a reset leaves no page behind" do
    visit root_path
    RailsJsdom.bridge.reset

    assert_raises(RailsJsdom::Error) { page_text }
  end

  test "a reset clears the previous fetch stubs" do
    visit root_path
    stub_fetch "/greeting", body: { greeting: "Stubbed hello" }.to_json
    RailsJsdom.bridge.reset
    visit root_path
    click "Load greeting"

    assert_dom "[data-greeting-target=output]", text: "Please sign in"
  end
end
