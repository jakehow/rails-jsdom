module RailsJsdom
  # Helpers for driving a page in jsdom from an integration test. Their names
  # and options follow the system test methods you already use.
  #
  # Inherit from RailsJsdom::TestCase, which includes this module, or include
  # it in your own `ActionDispatch::IntegrationTest`.
  #
  # ## Locators
  #
  # Actions find their element with a locator, tried in this order. The first
  # rule that matches anything wins:
  #
  # 1. **Stimulus action shorthand.** `click "dropdown#toggle"` finds the
  #    element whose `data-action` calls `dropdown#toggle`.
  # 2. **Text.**
  #    - For #click, #click_on, #click_link, #click_button, #hover,
  #      #double_click, #right_click, #find_button and #find_link: a button,
  #      link, submit, checkbox, radio, `summary`, `label` or `[role=button]`
  #      whose text, `aria-label`, `title`, `id` or button value equals the
  #      locator, or else contains it.
  #    - For #fill_in, #check, #uncheck, #choose, #attach_file, #find_field
  #      and the `from:` of #select: the field of a `label` whose text equals,
  #      or else contains, the locator; then a field whose `placeholder`,
  #      `name`, `id` or `aria-label` equals it.
  # 3. **CSS selector.** `click "#checkout"`.
  #
  # #click_link only matches links, #click_button only buttons, #click_on
  # both; #fill_in only text-like fields; #check and #uncheck only
  # checkboxes; #choose only radio buttons; #attach_file only file fields.
  #
  # More than one match raises, unless you pass `match: :first`.
  #
  # ## Filters
  #
  # #find, #all, #first, #find_field, #find_button, #find_link, the
  # `has_*?` predicates and the `assert_*` element assertions take these
  # filters:
  #
  # - `text:` the visible text includes a String, or matches a Regexp.
  # - `exact_text:` the visible text equals a String, or matches a Regexp.
  # - `visible:` `true` (the default) only visible elements; `false` or
  #   `:all` every element; `:hidden` only hidden ones.
  # - `with:` a field's current value.
  # - `checked:`, `unchecked:` a checkbox or radio button's state.
  # - `disabled:` `false` (the default for fields and buttons), `true`, or
  #   `:all`.
  # - `href:` a link's `href`.
  # - `type:` an input's type, or the tag name of other fields.
  #
  # Count assertions also take `count:`, or `minimum:` and `maximum:`.
  #
  # ## Scoping
  #
  # #within, #within_fieldset and #within_table scope every action, finder
  # and assertion in their block, including `assert_dom`, to one element.
  # Blocks nest.
  #
  # ## Dialogs
  #
  # An alert, confirm or prompt that appears during an action fails it, unless
  # the action runs inside the matching #accept_alert, #accept_confirm,
  # #dismiss_confirm, #accept_prompt or #dismiss_prompt.
  #
  # ## Settling
  #
  # Every action returns once the page has settled: due timers have run on a
  # virtual clock, no Rails request is pending, and Turbo Stream broadcasts
  # made so far have been applied. JavaScript errors and unhandled promise
  # rejections raised during the action fail it. Assertions and predicates
  # read the settled page, so they never need to wait or retry.
  module TestHelper
    # Requests `path` with `GET` through Rails, follows redirects, loads the
    # response into a new page and settles it.
    #
    #   visit project_path(projects(:billing))
    def visit(path)
      rails_jsdom_visit(path, "push")
    end

    # Requests the current URL again and loads it as a new page, without
    # adding a history entry.
    def refresh
      rails_jsdom_visit(URI(current_url).request_uri, "none")
    end

    # Goes back one history entry: a Turbo Drive visit or a full page load.
    # Does nothing on the first page.
    def go_back
      rails_jsdom_call(command: "traverse", delta: -1)
    end

    # Goes forward one history entry after #go_back.
    def go_forward
      rails_jsdom_call(command: "traverse", delta: 1)
    end

    # Runs the block as another user, with its own cookies and its own page.
    # The other session's page stays as it was, and receives Turbo Stream
    # broadcasts when the test returns to it.
    #
    #   using_session(:ada) { sign_in_as users(:ada); visit chat_path }
    #   using_session(:grace) { visit chat_path; fill_in "Message", with: "Hi"; click_on "Send" }
    #   using_session(:ada) { assert_text "Hi" }
    def using_session(name)
      previous = rails_jsdom_session_name
      rails_jsdom_switch_session(name.to_s)
      yield
    ensure
      rails_jsdom_switch_session(previous)
    end

    # Renders `partial` with `ApplicationController.render` and loads it as a
    # page, so its Stimulus controllers connect. No route is needed.
    #
    #   mount_partial "shared/counter", locals: { start: 2 }
    def mount_partial(partial, locals: {}, assigns: {})
      mount_html(ApplicationController.render(partial: partial, locals: locals, assigns: assigns))
    end

    # Loads an HTML fragment as the body of a page on the application host.
    #
    #   mount_html %(<div data-controller="counter"></div>)
    def mount_html(html)
      rails_jsdom_call(command: "load", html: RailsJsdom.document(html), url: "http://#{host}/", history: "push")
    end

    # Answers the page's requests to `url` with the given response instead of
    # sending them to Rails. Call it after the page is loaded; #visit and the
    # `mount_*` methods clear all stubs.
    #
    #   stub_fetch "/api/agents", body: [].to_json
    def stub_fetch(url, body: "", status: 200, headers: { "content-type" => "application/json" })
      RailsJsdom.bridge.call(command: "stub_fetch", url: url, response: { status: status, headers: headers, body: body })
    end

    # Gives elements matching `selector`, anything inside them, and text ranges
    # that start inside them the box `width` by `height` at `left`, `top`,
    # instead of the 0x0 box at 0,0 that jsdom gives everything, until the next
    # page load. For a test whose page waits for a real measurement, such as an
    # editor that positions a menu at the caret, when where things are does not
    # matter to the test. Call it after the page is loaded.
    #
    #   stub_layout "#composer .lexxy-editor__content"
    def stub_layout(selector, width: 100, height: 20, top: 10, left: 10)
      RailsJsdom.bridge.call(command: "stub_layout", selector: selector, box: { width: width, height: height, top: top, left: left })
    end

    # The page: an object with every helper in this module, plus
    # RailsJsdom::Page#body and RailsJsdom::Page#title.
    def page
      @rails_jsdom_page ||= Page.new(self)
    end

    # Clicks any element found by `locator` (see Locators) and settles the
    # page. Turbo links and forms are answered by Rails in-process.
    #
    #   click "dropdown#toggle"
    def click(locator, match: nil)
      rails_jsdom_act("click", locator, match)
    end

    # Clicks the link or button found by `locator`.
    #
    #   click_on "Add to cart"
    def click_on(locator = nil, match: nil)
      rails_jsdom_act("click", locator, match, kind: "link_or_button")
    end
    alias_method :click_link_or_button, :click_on

    # Clicks the link found by `locator`.
    #
    #   click_link "Second page"
    def click_link(locator = nil, match: nil)
      rails_jsdom_act("click", locator, match, kind: "link")
    end

    # Clicks the button found by `locator`.
    #
    #   click_button "Save"
    def click_button(locator = nil, match: nil)
      rails_jsdom_act("click", locator, match, kind: "button")
    end

    # Moves the pointer over the element found by `locator`, dispatching
    # `pointerover`, `pointerenter`, `mouseover`, `mouseenter`, `pointermove`
    # and `mousemove`. CSS `:hover` styles are not applied.
    #
    #   hover "Help"
    def hover(locator, match: nil)
      rails_jsdom_act("hover", locator, match)
    end

    # Clicks the element found by `locator` twice, then dispatches `dblclick`.
    def double_click(locator, match: nil)
      rails_jsdom_act("double_click", locator, match)
    end

    # Dispatches a right-button `mousedown`, `mouseup` and `contextmenu` on the
    # element found by `locator`.
    def right_click(locator, match: nil)
      rails_jsdom_act("right_click", locator, match)
    end

    # Sets the value of the text-like field found by `locator`, dispatches
    # `input` and `change`, and settles the page.
    #
    #   fill_in "Quantity", with: 2
    def fill_in(locator, with:, match: nil)
      rails_jsdom_act("fill_in", locator, match, with: with.to_s)
    end

    # Checks the checkbox found by `locator`, unless it is already checked.
    #
    #   check "Remember me"
    def check(locator, match: nil)
      rails_jsdom_act("check", locator, match, checked: true)
    end

    # Unchecks the checkbox found by `locator`, unless it is already unchecked.
    def uncheck(locator, match: nil)
      rails_jsdom_act("check", locator, match, checked: false)
    end

    # Selects the radio button found by `locator`.
    #
    #   choose "Monthly"
    def choose(locator, match: nil)
      rails_jsdom_act("choose", locator, match)
    end

    # Selects the option whose text equals, or else contains, `value`, in the
    # select found by the `from:` locator, or in any select when `from:` is
    # left out. Dispatches `input` and `change`.
    #
    #   select "Canada", from: "Country"
    def select(value, from: nil, match: nil)
      rails_jsdom_call(command: "select", option: value.to_s, from: from, selected: true, scope: rails_jsdom_scope, match: match)
    end

    # Deselects the option `value` in a select that allows multiple options.
    #
    #   unselect "Red", from: "Colours"
    def unselect(value, from: nil, match: nil)
      rails_jsdom_call(command: "select", option: value.to_s, from: from, selected: false, scope: rails_jsdom_scope, match: match)
    end

    # Puts the files at `paths` (one path or an array) in the file field found
    # by `locator`, replacing any files it had, and dispatches `input` and
    # `change`. Several files need a field with `multiple`. A form submits the
    # files to Rails as a multipart request, so controllers receive
    # `ActionDispatch::Http::UploadedFile` params.
    #
    #   attach_file "Avatar", file_fixture("avatar.png")
    #
    # With a block, `attach_file` takes only the paths, and puts them in the
    # file field that the block opens a file chooser for, as when a script
    # calls `click()` on a file field it created. The field need not be on
    # the page. Raises RailsJsdom::Error if the block opened no file chooser.
    #
    #   attach_file(file_fixture("avatar.png")) { click_on "Upload" }
    def attach_file(locator, paths = nil, match: nil, **options)
      RailsJsdom.reject_options(options.keys)
      if block_given?
        RailsJsdom.bridge.call(command: "expect_file_chooser", files: rails_jsdom_files(locator))
        yield
        RailsJsdom.bridge.call(command: "file_chooser_opened") || raise(Error, "No file chooser opened in the attach_file block")
      else
        rails_jsdom_act("attach", locator, match, files: rails_jsdom_files(paths))
      end
    end

    # Types `keys` into the focused element. A String types its characters; a
    # Symbol presses a key: `:enter`, `:tab`, `:backspace`, `:delete`,
    # `:escape`, `:space`, `:left`, `:right`, `:up`, `:down`, `:home`, `:end`,
    # `:page_up` or `:page_down`. An Array presses its last key while holding
    # the modifiers before it: `:shift`, `:control`, `:alt`, `:meta`.
    #
    # Each key dispatches `keydown`, `keypress` for characters and `keyup`.
    # Unless a listener prevents it, the key then does what a browser does:
    # characters and Backspace edit the end of a text field, Enter submits the
    # field's form or clicks a focused button or link, Space clicks a focused
    # button or checkbox, Tab and Shift+Tab move the focus (firing `change` on
    # a field you typed in), and the arrow keys, Home and End step a range or
    # number field. Typing always happens at the end of the value: there is no
    # caret or selection.
    #
    #   find_field("Search").send_keys("mugs", :enter)
    #   send_keys [ :shift, :tab ]
    def send_keys(*keys)
      rails_jsdom_call(command: "send_keys", keys: RailsJsdom.keys(keys))
    end

    # Scopes every action, finder and assertion in the block to the one
    # element that matches the CSS `selector`, or to an element from #find.
    #
    #   within "#cart" do
    #     click_on "Remove"
    #     assert_no_text "Mug"
    #   end
    def within(selector, &block)
      rails_jsdom_within(selector.is_a?(Element) ? { handle: selector.handle } : { css: selector }, &block)
    end

    # Like #within, for the `fieldset` whose `id` or `legend` text is
    # `locator`.
    def within_fieldset(locator, &block)
      rails_jsdom_within({ fieldset: locator }, &block)
    end

    # Like #within, for the `table` whose `id` or `caption` text is `locator`.
    def within_table(locator, &block)
      rails_jsdom_within({ table: locator }, &block)
    end

    # The one element that matches the CSS `selector` and the filters. Raises
    # RailsJsdom::Error when none matches, or when several do unless you pass
    # `match: :first`.
    #
    #   find(".cart-item", text: "Mug").click
    def find(selector = nil, match: nil, **filters)
      rails_jsdom_find(Query.new("css", selector || "*", **filters), match)
    end

    # The one field found by `locator` (see Locators) that matches the
    # filters, or the only field when `locator` is left out.
    #
    #   find_field("Quantity", with: "2")
    def find_field(locator = nil, match: nil, **filters)
      rails_jsdom_find(Query.new("field", locator, **filters), match)
    end

    # The one button found by `locator` that matches the filters.
    def find_button(locator = nil, match: nil, **filters)
      rails_jsdom_find(Query.new("button", locator, **filters), match)
    end

    # The one link found by `locator` that matches the filters.
    def find_link(locator = nil, match: nil, **filters)
      rails_jsdom_find(Query.new("link", locator, **filters), match)
    end

    # Every element that matches the CSS `selector` and the filters, possibly
    # none.
    #
    #   all(".cart-item").map(&:text)
    def all(selector = nil, **filters)
      rails_jsdom_elements(Query.new("css", selector || "*", **filters))
    end

    # The first element that matches the CSS `selector` and the filters.
    # Raises RailsJsdom::Error when none matches.
    def first(selector = nil, **filters)
      rails_jsdom_find(Query.new("css", selector || "*", **filters), :first)
    end

    # Runs `script` in the page, settles it and returns the script's value,
    # awaited if it is a promise. The value must be JSON-serialisable.
    #
    #   evaluate_script("document.title") # => "Projects"
    def evaluate_script(script, *arguments)
      rails_jsdom_script(script, arguments, "expression")
    end

    # Runs `script` in the page and settles it, returning nothing. As in
    # system tests, extra arguments are available to the script as
    # `arguments`; an element from `find` arrives as that DOM element.
    def execute_script(script, *arguments)
      rails_jsdom_script(script, arguments, "statements")
      nil
    end

    # Accepts every alert that appears while the block runs, and returns the
    # first alert message that matches `text` (a String the message must
    # include, or a Regexp). Raises RailsJsdom::Error if no matching alert
    # appeared.
    #
    #   accept_alert "Saved" do
    #     click_on "Save"
    #   end
    def accept_alert(text = nil, &block)
      rails_jsdom_modal("alert", true, text, &block)
    end

    # Accepts every confirm dialog that appears while the block runs. It
    # matches and returns the message like #accept_alert.
    #
    #   accept_confirm "Remove the first item?" do
    #     click_on "Remove"
    #   end
    def accept_confirm(text = nil, &block)
      rails_jsdom_modal("confirm", true, text, &block)
    end

    # Dismisses every confirm dialog that appears while the block runs. It
    # matches and returns the message like #accept_alert.
    #
    #   dismiss_confirm { click_on "Remove" }
    def dismiss_confirm(text = nil, &block)
      rails_jsdom_modal("confirm", false, text, &block)
    end

    # Answers every prompt that appears while the block runs with `with:`, or
    # with the prompt's default value when `with:` is left out. It matches and
    # returns the message like #accept_alert.
    #
    #   accept_prompt with: "Ada" do
    #     click_on "Rename"
    #   end
    def accept_prompt(text = nil, with: nil, &block)
      rails_jsdom_modal("prompt", true, text, with: with, &block)
    end

    # Cancels every prompt that appears while the block runs. It matches and
    # returns the message like #accept_alert.
    def dismiss_prompt(text = nil, &block)
      rails_jsdom_modal("prompt", false, text, &block)
    end

    # The path of the page's current URL, after any Turbo navigation.
    def current_path
      URI(current_url).path
    end

    # The page's current URL, after any Turbo navigation.
    def current_url
      rails_jsdom_snapshot.fetch("url")
    end

    # The visible text of the page, or of the current #within scope. Hidden
    # elements, templates, scripts and closed dialogs are left out.
    def page_text
      rails_jsdom_snapshot.fetch("text")
    end

    # Whether the visible text includes `text`, or matches it when it is a
    # Regexp.
    def has_text?(text)
      Query.like?(page_text, text)
    end
    alias_method :has_content?, :has_text?

    # Whether the visible text does not include `text`.
    def has_no_text?(text)
      !has_text?(text)
    end
    alias_method :has_no_content?, :has_no_text?

    # Whether the current path matches `path`, as #assert_current_path
    # compares it.
    def has_current_path?(path, ignore_query: false, url: false)
      Query.same?(rails_jsdom_current(ignore_query, url), path)
    end

    # Whether the current path does not match `path`.
    def has_no_current_path?(path, **options)
      !has_current_path?(path, **options)
    end

    # Whether the page title includes `title`, or matches it when it is a
    # Regexp.
    def has_title?(title)
      Query.like?(rails_jsdom_snapshot.fetch("title"), title)
    end

    # Whether the page title does not include `title`.
    def has_no_title?(title)
      !has_title?(title)
    end

    # Whether elements match the CSS `selector` and the filters: at least one,
    # exactly `count:`, or between `minimum:` and `maximum:`.
    def has_selector?(selector, count: nil, minimum: nil, maximum: nil, **filters)
      rails_jsdom_counted?(Query.new("css", selector, **filters), count, minimum, maximum)
    end
    alias_method :has_css?, :has_selector?

    # Whether no element matches the CSS `selector` and the filters.
    def has_no_selector?(selector, **filters)
      rails_jsdom_matches(Query.new("css", selector, **filters)).empty?
    end
    alias_method :has_no_css?, :has_no_selector?

    # Whether a field found by `locator` matches the filters.
    def has_field?(locator = nil, count: nil, minimum: nil, maximum: nil, **filters)
      rails_jsdom_counted?(Query.new("field", locator, **filters), count, minimum, maximum)
    end

    # Whether no field found by `locator` matches the filters.
    def has_no_field?(locator = nil, **filters)
      rails_jsdom_matches(Query.new("field", locator, **filters)).empty?
    end

    # Whether a checked checkbox or radio button is found by `locator`.
    def has_checked_field?(locator = nil, **filters)
      has_field?(locator, checked: true, **filters)
    end

    # Whether an unchecked checkbox or radio button is found by `locator`.
    def has_unchecked_field?(locator = nil, **filters)
      has_field?(locator, unchecked: true, **filters)
    end

    # Whether a button found by `locator` matches the filters.
    def has_button?(locator = nil, count: nil, minimum: nil, maximum: nil, **filters)
      rails_jsdom_counted?(Query.new("button", locator, **filters), count, minimum, maximum)
    end

    # Whether no button found by `locator` matches the filters.
    def has_no_button?(locator = nil, **filters)
      rails_jsdom_matches(Query.new("button", locator, **filters)).empty?
    end

    # Whether a link found by `locator` matches the filters.
    def has_link?(locator = nil, count: nil, minimum: nil, maximum: nil, **filters)
      rails_jsdom_counted?(Query.new("link", locator, **filters), count, minimum, maximum)
    end

    # Whether no link found by `locator` matches the filters.
    def has_no_link?(locator = nil, **filters)
      rails_jsdom_matches(Query.new("link", locator, **filters)).empty?
    end

    # Asserts that the visible text includes `text`, or matches it when it is
    # a Regexp.
    def assert_text(text)
      assert has_text?(text), "Expected the page text to include #{text.inspect}"
    end

    # Asserts that the visible text does not include `text`.
    def assert_no_text(text)
      assert has_no_text?(text), "Expected the page text not to include #{text.inspect}"
    end
    alias_method :refute_text, :assert_no_text

    # Asserts that the current path and query equal `path`, or match it when
    # it is a Regexp. Pass `ignore_query: true` to compare the path only, or
    # `url: true` to compare the whole URL.
    #
    #   assert_current_path project_path(project)
    def assert_current_path(path, ignore_query: false, url: false)
      actual = rails_jsdom_current(ignore_query, url)
      assert Query.same?(actual, path), "Expected the current path to be #{path.inspect}, but it was #{actual.inspect}"
    end

    # Asserts that the current path does not match `path`.
    def assert_no_current_path(path, ignore_query: false, url: false)
      actual = rails_jsdom_current(ignore_query, url)
      assert_not Query.same?(actual, path), "Expected the current path not to be #{path.inspect}"
    end

    # Asserts that the page title includes `title`, or matches it when it is a
    # Regexp.
    def assert_title(title)
      assert has_title?(title), "Expected the title to include #{title.inspect}, but it was #{rails_jsdom_snapshot.fetch("title").inspect}"
    end

    # Asserts that the page title does not include `title`.
    def assert_no_title(title)
      assert has_no_title?(title), "Expected the title not to include #{title.inspect}"
    end

    # Asserts that elements match the CSS `selector` and the filters: at least
    # one by default, exactly `count:`, or between `minimum:` and `maximum:`.
    # Only visible elements count, unless you pass `visible: false`.
    #
    #   assert_selector ".cart-item", count: 2
    #   assert_selector "li", text: "Mug"
    def assert_selector(selector, count: nil, minimum: nil, maximum: nil, **filters)
      rails_jsdom_assert_count(Query.new("css", selector, **filters), count, minimum, maximum)
    end
    alias_method :assert_css, :assert_selector

    # Asserts that no element matches the CSS `selector` and the filters.
    def assert_no_selector(selector, **filters)
      rails_jsdom_assert_none(Query.new("css", selector, **filters))
    end
    alias_method :refute_selector, :assert_no_selector
    alias_method :assert_no_css, :assert_no_selector

    # Asserts that a field found by `locator` matches the filters.
    #
    #   assert_field "Quantity", with: "2"
    def assert_field(locator = nil, count: nil, minimum: nil, maximum: nil, **filters)
      rails_jsdom_assert_count(Query.new("field", locator, **filters), count, minimum, maximum)
    end

    # Asserts that no field found by `locator` matches the filters.
    def assert_no_field(locator = nil, **filters)
      rails_jsdom_assert_none(Query.new("field", locator, **filters))
    end

    # Asserts that the checkbox or radio button found by `locator` is checked.
    def assert_checked_field(locator = nil, **filters)
      assert_field(locator, checked: true, **filters)
    end

    # Asserts that the checkbox or radio button found by `locator` is
    # unchecked.
    def assert_unchecked_field(locator = nil, **filters)
      assert_field(locator, unchecked: true, **filters)
    end

    # Asserts that a button found by `locator` matches the filters. Disabled
    # buttons only match with `disabled: true` or `disabled: :all`.
    def assert_button(locator = nil, count: nil, minimum: nil, maximum: nil, **filters)
      rails_jsdom_assert_count(Query.new("button", locator, **filters), count, minimum, maximum)
    end

    # Asserts that no button found by `locator` matches the filters.
    def assert_no_button(locator = nil, **filters)
      rails_jsdom_assert_none(Query.new("button", locator, **filters))
    end

    # Asserts that a link found by `locator` matches the filters.
    #
    #   assert_link "Second page", href: "/second"
    def assert_link(locator = nil, count: nil, minimum: nil, maximum: nil, **filters)
      rails_jsdom_assert_count(Query.new("link", locator, **filters), count, minimum, maximum)
    end

    # Asserts that no link found by `locator` matches the filters.
    def assert_no_link(locator = nil, **filters)
      rails_jsdom_assert_none(Query.new("link", locator, **filters))
    end

    # The root of the live page's DOM, or the current #within element. Rails
    # uses it for `assert_dom`, `assert_select` and `css_select`, so those
    # assertions read the page.
    def document_root_element
      html = rails_jsdom_snapshot.fetch("html")
      rails_jsdom_scope.empty? ? Nokogiri::HTML5(html).root : Nokogiri::HTML5.fragment(html, context: "template").element_children.first
    end

    def rails_jsdom_script(script, arguments, kind, receiver = nil) # :nodoc:
      if arguments.empty? && receiver.nil?
        rails_jsdom_call(command: "evaluate", script: script)
      else
        rails_jsdom_call(command: "evaluate", script: script, kind: kind, receiver: receiver, args: arguments.map { |argument| rails_jsdom_script_value(argument) })
      end
    end

    def rails_jsdom_script_value(argument) # :nodoc:
      argument.is_a?(Element) ? { rails_jsdom_element: argument.handle } : argument
    end

    def rails_jsdom_element(handle, action, **options) # :nodoc:
      rails_jsdom_call(command: "element", handle: handle, action: action, **options)
    end

    def rails_jsdom_read(handle) # :nodoc:
      rails_jsdom_catch_up
      RailsJsdom.bridge.call(command: "read", handle: handle)
    end

    def rails_jsdom_page_snapshot # :nodoc:
      rails_jsdom_catch_up
      RailsJsdom.bridge.call(command: "snapshot", scope: [])
    end

    def rails_jsdom_answer(request) # :nodoc:
      request["kind"] == "cable" ? rails_jsdom_cable_answer(request) : rails_jsdom_http_answer(request)
    end

    def rails_jsdom_sync # :nodoc:
      rails_jsdom_clock.view.merge(frames: rails_jsdom_cable.drain)
    end

    def rails_jsdom_page_clock(now) # :nodoc:
      rails_jsdom_clock.page_time(now)
    end

    def rails_jsdom_clock # :nodoc:
      @rails_jsdom_clock ||= Clock.new(Time.now) { |time| travel_to(time, with_usec: true) }
    end

    def rails_jsdom_take_over_pubsub # :nodoc:
      @rails_jsdom_previous_pubsub = ActionCable.server.pubsub
      @rails_jsdom_pubsub = CableAdapter.new(ActionCable.server)
      ActionCable.server.instance_variable_set(:@pubsub, @rails_jsdom_pubsub)
    end

    def rails_jsdom_restore_pubsub # :nodoc:
      ActionCable.server.instance_variable_set(:@pubsub, @rails_jsdom_previous_pubsub)
    end

    def rails_jsdom_close_cables # :nodoc:
      (@rails_jsdom_cables || {}).each_value(&:close)
    end

    private

    def rails_jsdom_visit(path, history)
      rails_jsdom_request("GET", path, headers: {})
      rails_jsdom_call(command: "load", html: response.body, url: request.original_url, history: history)
    end

    def rails_jsdom_session_name
      @rails_jsdom_session_name || "default"
    end

    def rails_jsdom_switch_session(name)
      sessions = (@rails_jsdom_sessions ||= {})
      sessions[rails_jsdom_session_name] = integration_session
      @integration_session = sessions[name] || create_session(app)
      copy_session_variables!
      @rails_jsdom_session_name = name
      RailsJsdom.bridge.call(command: "session", name: name)
    end

    def rails_jsdom_scope
      @rails_jsdom_scope ||= []
    end

    def rails_jsdom_within(entry)
      rails_jsdom_scope.push(entry)
      yield
    ensure
      rails_jsdom_scope.pop
    end

    def rails_jsdom_act(command, locator, match, **options)
      rails_jsdom_call(command: command, locator: locator, scope: rails_jsdom_scope, match: match, **options)
    end

    def rails_jsdom_files(paths)
      Array(paths).map { |path| { name: File.basename(path), type: Rack::Mime.mime_type(File.extname(path.to_s)), base64: [ File.binread(path) ].pack("m0") } }
    end

    def rails_jsdom_modal(type, accept, text, with: nil)
      RailsJsdom.bridge.call(command: "expect_modal", type: type, accept: accept, with: with)
      yield
      messages = RailsJsdom.bridge.call(command: "modal_messages")
      messages.find { |message| text.nil? || Query.like?(message, text) } || raise(Error, "Unable to find a #{type} dialog#{" matching #{text.inspect}" if text}. Saw #{messages.inspect}.")
    end

    def rails_jsdom_matches(query)
      rails_jsdom_catch_up
      query.filter(RailsJsdom.bridge.call(**query.message, scope: rails_jsdom_scope))
    end

    def rails_jsdom_elements(query)
      rails_jsdom_matches(query).map { |descriptor| Element.new(self, descriptor.fetch("handle")) }
    end

    def rails_jsdom_find(query, match)
      found = rails_jsdom_elements(query)
      if found.empty?
        raise Error, "Unable to find #{query.description}"
      elsif found.size > 1 && match.to_s != "first"
        raise Error, "Ambiguous match: #{found.size} elements match #{query.description}"
      else
        found.first
      end
    end

    def rails_jsdom_range(count, minimum, maximum)
      count ? count..count : (minimum || 1)..maximum
    end

    def rails_jsdom_counted?(query, count, minimum, maximum)
      rails_jsdom_range(count, minimum, maximum).cover?(rails_jsdom_matches(query).size)
    end

    def rails_jsdom_assert_count(query, count, minimum, maximum)
      range = rails_jsdom_range(count, minimum, maximum)
      found = rails_jsdom_matches(query).size
      assert range.cover?(found), "Expected #{range} elements matching #{query.description}, found #{found}"
    end

    def rails_jsdom_assert_none(query)
      found = rails_jsdom_matches(query).size
      assert found.zero?, "Expected no elements matching #{query.description}, found #{found}"
    end

    def rails_jsdom_current(ignore_query, url)
      uri = URI(current_url)
      uri.query = nil if ignore_query
      url ? uri.to_s : uri.request_uri
    end

    def rails_jsdom_snapshot
      rails_jsdom_catch_up
      RailsJsdom.bridge.call(command: "snapshot", scope: rails_jsdom_scope)
    end

    def rails_jsdom_cable_answer(request)
      uri = URI(request.fetch("url", "ws://#{host}"))
      uri.host == host ? rails_jsdom_cable.answer(request, rails_jsdom_cookie(uri)) : { error: "RailsJsdom opens cable connections only to #{host}, not to #{uri}." }
    end

    def rails_jsdom_cookie(uri)
      integration_session.cookies.for(URI("http://#{host}#{uri.path}"))
    end

    def rails_jsdom_catch_up
      if rails_jsdom_cable.active?
        rails_jsdom_call(command: "settle")
      elsif rails_jsdom_clock.moved? || rails_jsdom_cable_failed?
        rails_jsdom_call(command: "catch_up")
      end
    end

    def rails_jsdom_cable_failed?
      !!@rails_jsdom_pubsub&.failed?
    end

    def rails_jsdom_cable
      (@rails_jsdom_cables ||= {})[rails_jsdom_session_name] ||= Cable.new(rails_jsdom_clock)
    end

    def rails_jsdom_call(message)
      @rails_jsdom_pubsub&.raise_failure
      RailsJsdom.bridge.call(message, self)
    end

    def rails_jsdom_http_answer(fetch)
      uri = URI(fetch.fetch("url"))
      if uri.host == host
        redirected = rails_jsdom_request(fetch.fetch("method"), uri.request_uri, params: fetch["body"]&.unpack1("m"), headers: fetch.fetch("headers"))
        rails_jsdom_fetch_reply(redirected)
      else
        { error: "RailsJsdom sends fetch only to #{host}, not to #{uri}." }
      end
    end

    def rails_jsdom_fetch_reply(redirected)
      { status: response.status, headers: response.headers.to_h.except("set-cookie"), body: response.body, url: request.original_url, redirected: redirected }
    end

    def rails_jsdom_request(method, path, headers:, params: nil)
      process(method.downcase.to_sym, path, params: params, headers: headers)
      rails_jsdom_follow_redirects(headers.slice("accept"), false)
    end

    def rails_jsdom_follow_redirects(headers, redirected)
      if response.redirect?
        follow_redirect!(headers: headers)
        rails_jsdom_follow_redirects(headers, true)
      else
        redirected
      end
    end
  end
end
