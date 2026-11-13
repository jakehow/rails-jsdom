require "test_helper"

class KeyInteractionTest < RailsJsdom::TestCase
  setup { visit keys_path }

  test "typing a String adds its characters to the focused field" do
    find_field("Query").send_keys("mugs")

    assert_field "Query", with: "mugs"
  end

  test "backspace deletes the last character" do
    find_field("Query").send_keys("mugs", :backspace)

    assert_field "Query", with: "mug"
  end

  test "enter in a field submits its form through the submit button" do
    find_field("Query").send_keys("mugs", :enter)

    assert_current_path "/echo?query=mugs"
  end

  test "enter in a form without a submit button still submits the form" do
    find_field("Only field").send_keys("plates", :enter)

    assert_current_path "/echo?only=plates"
  end

  test "enter in a textarea adds a new line" do
    find_field("Notes").send_keys("one", :enter, "two")

    assert_equal "one\ntwo", find_field("Notes").value
  end

  test "enter on a focused button clicks it" do
    find_button("Press me").send_keys(:enter)

    assert_selector "#press[data-pressed=yes]"
  end

  test "space on a focused button clicks it" do
    find_button("Press me").send_keys(:space)

    assert_selector "#press[data-pressed=yes]"
  end

  test "space on a checkbox toggles it" do
    find_field("Agree").send_keys(:space)

    assert_checked_field "Agree"
  end

  test "tab moves the focus to the next field and fires change on a field typed in" do
    find_field("First").send_keys("a", :tab)
    send_keys "b"

    assert_field "Second", with: "b"
    assert_selector "#first[data-changed=yes]"
  end

  test "tab without typing fires no change" do
    find_field("First").send_keys(:tab)

    assert_no_selector "#first[data-changed]"
  end

  test "shift+tab moves the focus back" do
    find_field("Second").send_keys([ :shift, :tab ], "z")

    assert_field "First", with: "z"
  end

  test "tab from the page body goes first to a positive tabindex" do
    send_keys :tab, "x"

    assert_field "Early", with: "x"
  end

  test "arrow keys step a range field" do
    find_field("Volume").send_keys(:right, :right, :up, :left)

    assert_field "Volume", with: "7"
  end

  test "down steps a range field down" do
    find_field("Volume").send_keys(:down)

    assert_field "Volume", with: "4"
  end

  test "end moves a range field to its maximum" do
    find_field("Volume").send_keys(:end)

    assert_field "Volume", with: "10"
  end

  test "home moves a range field to its minimum" do
    find_field("Volume").send_keys(:home)

    assert_field "Volume", with: "0"
  end

  test "arrow keys step a number field" do
    find_field("Amount").send_keys(:up)

    assert_field "Amount", with: "4"
  end

  test "a keydown listener that prevents the default stops the character" do
    find_field("Guarded").send_keys("axb")

    assert_field "Guarded", with: "ab"
  end

  test "key events carry the key, the code and the modifiers" do
    find_field("Logged").send_keys([ :shift, "A" ])

    assert_selector "#key-log", text: "A KeyA true false"
  end

  test "a character with control held dispatches events without typing" do
    find_field("Logged").send_keys([ :control, "a" ])

    assert_field "Logged", with: ""
    assert_selector "#key-log", text: "a KeyA false true"
  end

  test "keys without a default action only dispatch events" do
    find_field("Logged").send_keys(:escape)

    assert_selector "#key-log", text: "Escape Escape false false"
  end

  test "digits have a digit code" do
    find_field("Logged").send_keys("7")

    assert_selector "#key-log", text: "7 Digit7 false false"
  end

  test "an unknown key fails" do
    assert_raises(RailsJsdom::Error) { find_field("Query").send_keys(:launch) }
  end

  test "an unknown modifier fails" do
    assert_raises(RailsJsdom::Error) { find_field("Query").send_keys([ :hyper, "a" ]) }
  end

  test "Selenium's names for the arrow keys and return work as in system tests" do
    find_field("Volume").send_keys(:arrow_up)
    volume = find_field("Volume").value
    find_field("Query").send_keys("mugs", :return)

    assert_equal [ "6", "http://www.example.com/echo?query=mugs" ], [ volume, current_url ]
  end
end
