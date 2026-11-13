require "test_helper"

class AssertionInteractionTest < RailsJsdom::TestCase
  setup { visit forms_path }

  test "text predicates take a String or a Regexp" do
    assert has_text?("Prices")
    assert has_content?(/Pri.es/)
    assert has_no_text?("Hidden note")
    assert has_no_content?(/Hidden/)
  end

  test "assert_text takes a Regexp" do
    assert_text(/\bMug\b/)
  end

  test "current path predicates compare like assert_current_path" do
    assert has_current_path?("/forms")
    assert has_current_path?("http://www.example.com/forms", url: true)
    assert has_no_current_path?("/echo")
  end

  test "assert_no_current_path passes for another path and fails for this one" do
    assert_no_current_path "/echo"
    assert_raises(Minitest::Assertion) { assert_no_current_path "/forms" }
  end

  test "title predicates and assert_no_title" do
    assert has_title?("Forms")
    assert has_no_title?("Echo")
    assert_no_title "Echo"
    assert_raises(Minitest::Assertion) { assert_no_title "Forms" }
  end

  test "has_selector? and has_css? count matches" do
    assert has_selector?("#cart li", count: 2)
    assert has_css?("#cart li", minimum: 1, maximum: 2)
    assert_not has_css?("#cart li", minimum: 3)
  end

  test "has_no_selector? and has_no_css? pass only without a match" do
    assert has_no_selector?("#cart li", text: "Bowl")
    assert_not has_no_css?("#cart li")
  end

  test "assert_css and assert_no_css are the selector assertions" do
    assert_css "#cart li", text: "Mug"
    assert_no_css "#cart li", text: "Cup"
    refute_selector "#missing"
  end

  test "field predicates" do
    assert has_field?("Nickname", with: "Ace")
    assert has_no_field?("Nickname", with: "Bee")
    assert has_checked_field?("Newsletter")
    assert has_unchecked_field?("Remember me")
    assert has_field?(type: "checkbox", count: 2)
  end

  test "button predicates" do
    assert has_button?("Save preferences")
    assert has_no_button?("Archive")
    assert has_button?("Archive", disabled: true)
    within("#cart") { assert has_button?(count: 2) }
  end

  test "link predicates" do
    assert has_link?("Second page", href: "/second")
    assert has_no_link?("Second page", href: "/third")
    assert has_link?(minimum: 2)
  end

  test "assert_field checks a field's value" do
    assert_field "Nickname", with: "Ace"
    assert_field "Nickname", with: /\AA/
    assert_no_field "Nickname", with: "Bee"
  end

  test "assert_field fails without a matching field" do
    assert_raises(Minitest::Assertion) { assert_field "Nickname", with: "Bee" }
  end

  test "assert_no_field fails with a matching field" do
    assert_raises(Minitest::Assertion) { assert_no_field "Nickname" }
  end

  test "assert_checked_field and assert_unchecked_field check a checkbox's state" do
    assert_checked_field "Newsletter"
    assert_unchecked_field "Remember me"
    assert_raises(Minitest::Assertion) { assert_checked_field "Remember me" }
  end

  test "the wait option of system tests fails and says to remove it" do
    error = assert_raises(ArgumentError) { assert_selector "h1", wait: 5 }

    assert_equal "wait: does nothing here, because rails-jsdom settles the page before every finder and assertion. Remove it.", error.message
  end

  test "finders and assertions still reject options they do not know" do
    errors = [ { colour: "red" }, { wiat: 5, colour: "red" } ].map { |options| assert_raises(ArgumentError) { assert_selector "h1", **options }.message }

    assert_equal [ "unknown keyword: :colour", "unknown keywords: :wiat, :colour" ], errors
  end

  test "assert_button matches enabled buttons, and disabled ones on request" do
    assert_button "Save preferences"
    assert_no_button "Archive"
    assert_button "Archive", disabled: true
  end

  test "assert_link checks a link's href" do
    assert_link "Second page", href: "/second"
    assert_no_link "Second page", href: "/third"
    assert_raises(Minitest::Assertion) { assert_link "Second page", href: "/third" }
  end

  test "assertions inside within only see that element" do
    within "#prices" do
      assert_button "Choose", count: 1
      assert_no_field "Nickname"
      assert_no_link "Second page"
    end
  end
end
