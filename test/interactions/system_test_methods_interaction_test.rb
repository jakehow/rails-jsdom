require "test_helper"

class SystemTestMethodsInteractionTest < RailsJsdom::TestCase
  test "form helpers set checkboxes, radio buttons and selects that the form submits" do
    visit forms_path
    check "Remember me"
    uncheck "Newsletter"
    choose "Monthly"
    select "Canada", from: "Country"
    unselect "Red", from: "Colours"
    click_button "Save preferences"

    assert_equal({ "remember" => "1", "newsletter" => "0", "plan" => "monthly", "country" => "Canada", "colours" => [ "", "Green" ] }, submitted.slice("remember", "newsletter", "plan", "country", "colours"))
  end

  test "check and choose leave a field that is already set unchanged" do
    visit forms_path
    check "Newsletter"
    choose "Yearly"
    uncheck "Remember me"
    click_button "Save preferences"

    assert_equal({ "remember" => "0", "newsletter" => "1", "plan" => "yearly" }, submitted.slice("remember", "newsletter", "plan"))
  end

  test "select without from: finds the option in any select" do
    visit forms_path
    select "Canada"
    click_on "Save preferences"

    assert_equal "Canada", submitted.fetch("country")
  end

  test "unselect fails on a select that allows one option" do
    visit forms_path

    assert_raises(RailsJsdom::Error) { unselect "Mexico", from: "Country" }
  end

  test "fill_in finds only text-like fields" do
    visit forms_path

    assert_raises(RailsJsdom::Error) { fill_in "Remember me", with: "yes" }
  end

  test "click_link finds only links" do
    visit forms_path

    assert_raises(RailsJsdom::Error) { click_link "Save preferences" }
  end

  test "click_link follows a link" do
    visit forms_path
    click_link "Second page"

    assert_current_path "/second"
  end

  test "click_link_or_button clicks a button" do
    visit forms_path
    click_link_or_button "Save preferences"

    assert_current_path "/echo", ignore_query: true
  end

  test "match: :first picks the first of several matches" do
    visit forms_path
    click_on "Choose", match: :first

    assert_selector "#prices button", text: "Chosen"
  end

  test "within_table scopes actions to the table with that caption" do
    visit forms_path
    within_table("Prices") { click_on "Choose" }

    assert_selector "#prices button", text: "Chosen"
  end

  test "within_fieldset scopes text assertions to the fieldset with that legend" do
    visit forms_path

    within_fieldset "Billing" do
      assert_text "Monthly"
      assert_no_text "Remember me"
    end
  end

  test "within scopes assert_dom to the element, and nested blocks narrow it" do
    visit forms_path

    within "#prices" do
      assert_dom "button", count: 1
      within("tr") { assert_dom "td", count: 2 }
    end
  end

  test "within restores the whole page after its block" do
    visit forms_path

    within("#prices") { assert_text "Mug" }

    assert_text "Plate"
  end

  test "within fails when its selector matches no element" do
    visit forms_path

    assert_raises(RailsJsdom::Error) { within("#missing") { assert_text "Mug" } }
  end

  test "assert_selector counts only visible elements unless visible: false" do
    visit forms_path

    assert_no_selector "#note"
    assert_no_selector ".more"
    assert_selector "#note", visible: false
    assert_selector ".more", text: "Inside details", visible: false
  end

  test "assert_selector checks an exact count or a range" do
    visit forms_path

    assert_selector "table", count: 2
    assert_selector "fieldset", minimum: 2, maximum: 2
    assert_no_selector "td", text: "Bowl"
  end

  test "assert_selector fails when too few elements match" do
    visit forms_path

    assert_raises(Minitest::Assertion) { assert_selector "table", minimum: 3 }
  end

  test "assert_no_selector fails when a visible element matches" do
    visit forms_path

    assert_raises(Minitest::Assertion) { assert_no_selector "td", text: "Mug" }
  end

  test "assert_current_path compares the path and query, a pattern or the whole URL" do
    visit "/echo?page=2"

    assert_current_path "/echo?page=2"
    assert_current_path %r{\A/echo}
    assert_current_path "http://www.example.com/echo?page=2", url: true
  end

  test "assert_current_path fails for a different query" do
    visit "/echo?page=2"

    assert_raises(Minitest::Assertion) { assert_current_path "/echo" }
  end

  test "current_url is the whole URL of the page" do
    visit "/echo?page=2"

    assert_equal "http://www.example.com/echo?page=2", current_url
  end

  test "assert_title matches the page title" do
    visit forms_path

    assert_title "Forms"
    assert_title(/\AForm/)
  end

  test "assert_title fails for a different title" do
    visit forms_path

    assert_raises(Minitest::Assertion) { assert_title "Echo" }
  end

  test "execute_script runs the script and returns nothing" do
    visit forms_path

    assert_nil execute_script("document.title = 'Changed'; 42")
  end

  test "execute_script passes extra arguments, with an element from find arriving as that DOM element" do
    visit forms_path
    execute_script("arguments[0].textContent = arguments[1] + arguments[2].count", find("h1"), "Changed ", { "count" => 2 })

    assert_dom "h1", text: "Changed 2"
  end

  test "evaluate_script with arguments evaluates an expression and returns its value" do
    visit forms_path

    assert_equal "Forms!", evaluate_script("arguments[0].textContent + arguments[1]", find("h1"), "!")
  end

  test "an element runs a script with this set to that element" do
    visit forms_path
    heading = find("h1")
    heading.execute_script("this.dataset.seen = arguments[0]", "yes")

    assert_equal [ "H1", "yes" ], [ heading.evaluate_script("this.tagName"), heading["data-seen"] ]
  end

  test "stub_layout gives the elements a box of the given size, which measuring code then reads" do
    visit forms_path
    stub_layout "h1", width: 300, height: 40

    assert_equal [ 300, 40, 10, 10 ], evaluate_script("(r => [r.width, r.height, r.top, r.left])(document.querySelector('h1').getBoundingClientRect())")
  end

  test "refresh loads the current URL again" do
    visit forms_path
    execute_script("document.querySelector('h1').textContent = 'Changed'")
    refresh

    assert_dom "h1", text: "Forms"
  end

  test "accept_alert returns the alert message" do
    visit forms_path

    assert_equal("Saved", accept_alert { click_on "Alert me" })
  end

  test "an alert the test did not expect fails the action" do
    visit forms_path

    assert_raises(RailsJsdom::Error) { click_on "Alert me" }
  end

  test "a dialog of a different kind than the one expected fails the action" do
    visit forms_path

    assert_raises(RailsJsdom::Error) { accept_confirm { click_on "Alert me" } }
  end

  test "accept_prompt answers with the given text" do
    visit forms_path
    accept_prompt(with: "Ada") { click_on "Ask name" }

    assert_dom "#answer", text: "Ada"
  end

  test "accept_prompt without with: answers with the prompt's default" do
    visit forms_path
    accept_prompt("Your name?") { click_on "Ask name" }

    assert_dom "#answer", text: "Grace"
  end

  test "dismiss_prompt cancels the prompt" do
    visit forms_path
    dismiss_prompt { click_on "Ask name" }

    assert_dom "#answer", text: "null"
  end

  test "an unexpected prompt fails the action" do
    visit forms_path

    assert_raises(RailsJsdom::Error) { click_on "Ask name" }
  end

  test "hover, double_click and right_click dispatch their pointer events" do
    visit forms_path
    hover "#pointer"
    double_click "#pointer"
    right_click "#pointer"

    assert_dom "#pointer[data-hovered=yes][data-doubled=yes][data-context=yes]"
  end

  private

  def submitted
    JSON.parse(css_select("#params").text)
  end
end
