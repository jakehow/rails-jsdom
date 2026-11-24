require "test_helper"

class HistoryInteractionTest < RailsJsdom::TestCase
  test "go_back returns from a Turbo Drive visit" do
    visit root_path
    click_link "Second page"
    go_back

    assert_current_path "/"
    assert_selector "h1", text: "Home"
  end

  test "go_forward repeats a Turbo Drive visit after go_back" do
    visit root_path
    click_link "Second page"
    go_back
    go_forward

    assert_current_path "/second"
    assert_selector "h1", text: "Second page"
  end

  test "go_back returns from a full page load" do
    visit root_path
    click_link "Full reload to second page"
    go_back

    assert_current_path "/"
    assert_selector "h1", text: "Home"
  end

  test "go_forward repeats a full page load after go_back" do
    visit root_path
    click_link "Full reload to second page"
    go_back
    go_forward

    assert_current_path "/second"
  end

  test "go_back returns to the page before a visit" do
    visit root_path
    visit forms_path
    go_back

    assert_current_path "/"
  end

  test "go_back on the first page stays on it" do
    visit root_path
    go_back

    assert_current_path "/"
  end

  test "go_forward without a later page stays on the page" do
    visit root_path
    go_forward

    assert_current_path "/"
  end

  test "a new visit after go_back drops the forward entries" do
    visit root_path
    visit forms_path
    go_back
    visit keys_path
    go_forward

    assert_current_path "/keys"
  end

  test "refresh adds no history entry" do
    visit root_path
    visit forms_path
    refresh
    go_back

    assert_current_path "/"
  end

  test "go_back needs a page" do
    assert_raises(RailsJsdom::Error) { go_back }
  end

  test "a script that assigns location loads the page and adds a history entry" do
    visit keys_path
    click_on "Go by script"

    assert_current_path second_path

    go_back

    assert_current_path keys_path
  end
end
