require "test_helper"

class FinderInteractionTest < RailsJsdom::TestCase
  setup { visit forms_path }

  test "find returns the element that matches a selector" do
    assert_equal "h1", find("h1").tag_name
  end

  test "find filters by visible text, as a String or a Regexp" do
    assert_equal "Plate Remove", find("#cart li", text: "Plate").text
    assert_equal "Mug Remove", find("#cart li", text: /\AMug/).text
  end

  test "find filters by exact visible text" do
    assert_equal "td", find("td", exact_text: "Mug").tag_name
  end

  test "find fails when nothing matches" do
    assert_raises(RailsJsdom::Error) { find("#missing") }
  end

  test "find fails when several elements match" do
    assert_raises(RailsJsdom::Error) { find("#cart li") }
  end

  test "find with match: :first returns the first of several" do
    assert_equal "Mug Remove", find("#cart li", match: :first).text
  end

  test "find skips hidden elements unless visible: false" do
    assert_raises(RailsJsdom::Error) { find("#cart li", text: "Bowl") }
    assert_not find("#cart li", text: "Bowl", visible: false).visible?
  end

  test "find with visible: :hidden matches only hidden elements" do
    assert_equal "", find("#cart li", visible: :hidden).text
  end

  test "find with visible: :all matches hidden text" do
    assert_equal "li", find("#cart li", visible: :all, text: "Bowl").tag_name
  end

  test "all returns every visible match" do
    assert_equal [ "Mug Remove", "Plate Remove" ], all("#cart li").map(&:text)
  end

  test "all with visible: false includes hidden matches" do
    assert_equal 3, all("#cart li", visible: false).size
  end

  test "all returns no elements when nothing matches" do
    assert_empty all("#missing")
  end

  test "first returns the first match" do
    assert_equal "Mug Remove", first("#cart li").text
  end

  test "first fails when nothing matches" do
    assert_raises(RailsJsdom::Error) { first("#missing") }
  end

  test "find_field finds a field by label and checks its value" do
    assert_equal "Ace", find_field("Nickname", with: "Ace").value
  end

  test "find_field filters by type" do
    assert_equal "textarea", find_field("Bio", type: "textarea").tag_name
  end

  test "find_field skips disabled fields unless disabled: true or :all" do
    assert_raises(RailsJsdom::Error) { find_field("Locked") }
    assert_predicate find_field("Locked", disabled: true), :disabled?
    assert_predicate find_field("Locked", disabled: :all), :disabled?
  end

  test "find_field filters by checked state" do
    assert_equal "newsletter", find_field(checked: true, type: "checkbox")[:name]
    assert_equal "remember", find_field(unchecked: true, type: "checkbox")[:name]
  end

  test "find_button finds a button by its text" do
    assert_equal "Save preferences", find_button("Save preferences").value
  end

  test "find_button skips a disabled button unless asked" do
    assert_raises(RailsJsdom::Error) { find_button("Archive") }
    assert_predicate find_button("Archive", disabled: true), :disabled?
  end

  test "find_link finds a link by its text and href" do
    assert_equal "/second", find_link("Second page", href: "/second")[:href]
  end

  test "find_link filters by an href pattern" do
    assert_raises(RailsJsdom::Error) { find_link("Second page", href: %r{/missing}) }
  end

  test "an element click runs the page's handler" do
    find("#cart li", text: "Mug").find_button("Remove").click

    assert_equal [ "Plate Remove" ], all("#cart li").map(&:text)
  end

  test "an element that left the page fails when used" do
    item = find("#cart li", text: "Mug")
    item.find_button("Remove").click

    assert_raises(RailsJsdom::Error) { item.text }
  end

  test "set fills a text field" do
    find_field("Nickname").set("Bee")

    assert_field "Nickname", with: "Bee"
  end

  test "set checks and unchecks a checkbox" do
    find_field("Remember me").set(true)
    find_field("Newsletter").set(false)

    assert_checked_field "Remember me"
    assert_unchecked_field "Newsletter"
  end

  test "set true selects a radio button and set false leaves it" do
    find_field("Monthly").set(true)
    find_field("Yearly").set(false)

    assert_checked_field "Monthly"
  end

  test "set fills a contenteditable element" do
    find("#editor").set("Draft")

    assert_selector "#editor", text: "Draft"
  end

  test "set fails on a select" do
    assert_raises(RailsJsdom::Error) { find_field("Country").set("Canada") }
  end

  test "select_option and unselect_option change the options of a select" do
    find("option", text: "Canada").select_option
    find("option", text: "Red").unselect_option

    assert_predicate find("option", text: "Canada"), :selected?
    assert_not find("option", text: "Red").selected?
  end

  test "select_option fails on an element that is not an option" do
    assert_raises(RailsJsdom::Error) { find("h1").select_option }
  end

  test "element hover, double_click and right_click dispatch pointer events" do
    pointer = find("#pointer")
    pointer.hover
    pointer.double_click
    pointer.right_click

    assert_equal [ "yes", "yes", "yes" ], [ pointer[:"data-hovered"], pointer[:"data-doubled"], pointer[:"data-context"] ]
  end

  test "element send_keys focuses the field and types into it" do
    find_field("Nickname").send_keys("!")

    assert_field "Nickname", with: "Ace!"
  end

  test "element readers report checked, disabled and visible state" do
    assert_predicate find_field("Newsletter"), :checked?
    assert_not find_field("Remember me").checked?
    assert_not find_field("Nickname").disabled?
    assert_predicate find("h1"), :visible?
    assert_not find("#note", visible: false).visible?
  end

  test "element [] reads attributes, and the current value for :value" do
    field = find_field("Nickname")
    field.set("Bee")

    assert_equal [ "nickname", "Bee" ], [ field[:name], field[:value] ]
  end

  test "an element without a value has a nil value" do
    assert_nil find("h1").value
  end

  test "element finders search inside the element" do
    table = find("#prices")

    assert_equal "Mug", table.find("td", match: :first).text
    assert_equal 1, table.all("button").size
    assert_equal "Choose", table.first("button").text
    assert_equal "Choose", table.find_button("Choose").text
  end

  test "element find_field and find_link search inside the element" do
    assert_equal "Ace", find("form").find_field("Nickname").value
    assert_raises(RailsJsdom::Error) { find("form").find_link("Second page") }
  end

  test "element assertions and predicates check inside the element" do
    table = find("#prices")

    table.assert_text "Mug"
    table.assert_no_text "Plate"
    table.assert_selector "button", count: 1
    table.assert_no_selector "input"

    assert table.has_text?("Mug")
    assert table.has_no_text?("Plate")
    assert table.has_selector?("td", count: 2)
    assert table.has_no_selector?("input")
  end

  test "within takes an element from find" do
    within(find("#prices")) { click_on "Choose" }

    assert_selector "#prices button", text: "Chosen"
  end

  test "two finds of the same node are equal elements" do
    assert_equal find("h1"), first("h1")
    assert_equal 1, [ find("h1"), first("h1") ].uniq.size
    assert_not_equal find("h1"), "h1"
  end

  test "an element describes itself by its handle" do
    assert_match(/\A#<RailsJsdom::Element \d+>\z/, find("h1").inspect)
  end

  test "page has every helper" do
    page.find("#prices").find_button("Choose").click

    assert page.has_css?("#prices button", text: "Chosen")
    assert page.has_no_css?("#missing")
    assert_equal "/forms", page.current_path
  end

  test "page body and html are the whole page, even inside within" do
    within "#prices" do
      assert_includes page.body, "<h1>Forms</h1>"
      assert_equal page.body, page.html
    end
  end

  test "page title and text read the page" do
    assert_equal "Forms", page.title
    within("#prices") { assert_equal "Prices Mug Choose", page.text }
  end

  test "find without a selector uses the id and class filters, as in system tests" do
    mount_html CLASSED

    assert_equal [ "Read", "Unread", "invite" ], [ find(id: "room_1").text, find(class: [ "room", "unread" ]).text, find(id: "invite_url").value ]
  end

  test "a class filter starting with ! excludes elements with that class" do
    mount_html CLASSED

    assert_equal [ "Read" ], all(class: [ "room", "!unread" ]).map(&:text)
  end

  test "an id filter takes a Regexp, and assertions take id and class filters" do
    mount_html CLASSED

    assert_selector "a", class: "unread", id: /\Aroom_/, count: 1
  end

  CLASSED = %(<a id="room_1" class="room" href="#">Read</a><a id="room_2" class="room unread" href="#">Unread</a><input id="invite_url" value="invite">).freeze
end
