# Instructions for coding agents

This page is for an AI coding agent working in a Rails app that uses, or is moving to, `rails-jsdom`. It covers setting the gem up, writing interaction tests, and converting an existing system test suite. The full API reference is at https://jakehow.github.io/rails-jsdom/. This page is also published as Markdown at https://jakehow.github.io/rails-jsdom/agents.md.

## What rails-jsdom is

- Interaction tests for Rails apps that use importmap, Turbo and Stimulus, without a browser or a test server.
- Rails renders the real pages. The real Stimulus controllers and Turbo run in jsdom, in one Node process per test worker.
- Every request the page makes (`fetch`, `XMLHttpRequest`, Turbo Drive visits, form submissions) is answered by Rails inside the test process, in the test's session.
- The helpers use the system test method names: `visit`, `click_on`, `fill_in`, `within`, `accept_confirm`, `assert_selector`, `find` and so on.

## Set up an app

1. Add `gem "rails-jsdom"` to the `:test` group of the `Gemfile` and run `bundle install`.
2. Run `bin/rails generate rails_jsdom:install`. It:
   - requires the library in `test/test_helper.rb`;
   - creates `test/interactions/`;
   - adds `jsdom` and `esbuild` to `package.json` and runs `npm install`;
   - sets `min-release-age=7` in `.npmrc`;
   - ignores `node_modules`.
3. Make CI install the Node packages before the tests, with `npm ci` after setting up Node 26 (or 22.22.2+ or 24.15+).
4. Commit `package.json`, `package-lock.json` and `.npmrc`.

## Write an interaction test

```ruby
require "test_helper"

class CartInteractionTest < RailsJsdom::TestCase
  setup do
    sign_in_as users(:shopper)
    visit product_path(products(:mug))
  end

  test "adding an item updates the cart" do
    fill_in "Quantity", with: 2
    click_on "Add to cart"

    assert_selector "#cart-count", text: "2"
    assert_text "Added to your cart"
  end
end
```

- Put the test in `test/interactions/` and subclass `RailsJsdom::TestCase`. It is an `ActionDispatch::IntegrationTest`, so fixtures, `perform_enqueued_jobs` and Rails assertions work.
- Sign in the way the app's integration tests do, usually by posting to the session controller.
- Every action settles the page before it returns: timers up to one second ahead have run, no request is pending, and every Action Cable message the server has sent has reached the page. Never add `sleep`, waits or retries.
- Time is virtual and shared: Ruby's time is frozen at the start of the test, and the page's `Date` follows the page's clock. Use `travel` or `travel_to` to move time; the page catches up before the next command.
- Broadcasts must come from the test, a page request or `perform_enqueued_jobs`. A broadcast from another thread fails the next command.
- An error in connection or channel code that no `rescue_from` handles fails the next command. Fix the error, or handle it with `rescue_from` if it is expected.
- A JavaScript error, an unhandled promise rejection or an unexpected `alert`, `confirm` or `prompt` fails the action. CSS that jsdom cannot parse does not. Wrap actions that show a dialog in `accept_alert`, `accept_confirm`, `dismiss_confirm`, `accept_prompt` or `dismiss_prompt`.
- `assert_selector` and `find` count only visible elements unless you pass `visible: false`. `assert_dom` and `assert_select` see every element.
- Requests to other hosts fail like a network error. Answer them with `stub_fetch` after the page loads.
- Broadcasts made with `broadcast_*_later` arrive when the test performs the jobs, for example `perform_enqueued_jobs { click_on "Post" }`.
- `using_session(:name) { ... }` runs a block as another user with their own cookies and page.

## Convert a system test suite

Work through `test/system/` one file at a time.

1. **Sort each test.** Convert it if it checks behaviour: what the page shows, what is hidden, where it navigates, what Rails receives. Keep it as a system test, or delete it, if it needs what jsdom cannot do:
   - computed CSS, layout or geometry (a test that only fails because a library waits for a real measurement, such as an editor positioning a menu at the caret, can stay an interaction test with `stub_layout` on the elements involved);
   - CSS media-query breakpoints;
   - screenshots;
   - drag and drop;
   - real iframes or new windows;
   - third-party scripts from a CDN.
2. **Move the file** from `test/system/` to `test/interactions/`, and change the test class's superclass from `ApplicationSystemTestCase` to `RailsJsdom::TestCase`.
3. **Remove browser setup:** `driven_by`, `using_wait_time`, `Capybara.*` settings, `sleep`, `wait_for_*` helpers, `take_screenshot` and window-size code.
4. **Replace sign-in.** System tests often sign in by filling in the login form. That still works. A faster equivalent is the app's integration-test helper that posts to the session controller.
5. **Translate the methods** with the table below. Most methods keep their names. The common changes:
   - CSS or layout assertions become behaviour assertions (`assert_selector ".panel[hidden]"`, not checks of `display` or position);
   - `page.driver` and browser-specific calls are removed;
   - `send_keys` is limited to the keys listed in the table notes.
6. **Run the converted file** with `bin/rails test test/interactions/<file>` and fix any failure before moving on. Typical failures:
   - an unexpected dialog: wrap the action in the matching `accept_*` or `dismiss_*`;
   - a request to another host: stub it with `stub_fetch`;
   - a missing browser API: stub it in the test with `execute_script`;
   - an element found more than once: scope it with `within` or pass `match: :first`.
7. **When `test/system/` is empty,** remove `ApplicationSystemTestCase`, the `capybara` and `selenium-webdriver` gems, and the CI steps that installed a browser.

Interaction tests are faster than system tests, so do not merge tests to save time. Keep one behaviour per test. Group checks of the same result into one test only when they would otherwise repeat the same steps.

## System test methods in rails-jsdom

✅ works in rails-jsdom. ❌ does not. Each link goes to the method's reference.

| System test method | Status | Notes |
| --- | --- | --- |
| [`visit`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-visit) | ✅ |  |
| [`refresh`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-refresh) | ✅ | Requests the current URL again, without a history entry |
| [`go_back`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-go_back), [`go_forward`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-go_forward) | ✅ | Across Turbo Drive visits and full page loads |
| [`using_session`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-using_session) | ✅ | Each session has its own cookies and page; broadcasts reach a session's page when the test returns to it |
| [`click_on`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-click_on), [`click_link_or_button`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-click_link_or_button) | ✅ |  |
| [`click_link`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-click_link) | ✅ |  |
| [`click_button`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-click_button) | ✅ | Without a locator, clicks the only button in the current `within` scope, as in system tests |
| [`fill_in`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-fill_in) | ✅ | Text-like fields only, as in system tests |
| [`check`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-check), [`uncheck`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-uncheck) | ✅ |  |
| [`choose`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-choose) | ✅ |  |
| [`select`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-select), [`unselect`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-unselect) | ✅ |  |
| [`attach_file`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-attach_file) | ✅ | Forms submit files to Rails as multipart requests |
| [`send_keys`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-send_keys) | ✅ | Keys perform the common browser default actions; typing happens at the end of the value, with no caret or selection |
| [`within`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-within) | ✅ | CSS selector or an element from `find`; also scopes `assert_dom` |
| [`within_fieldset`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-within_fieldset), [`within_table`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-within_table) | ✅ |  |
| [`find`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-find), [`all`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-all), [`first`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-first) | ✅ | `text:`, `exact_text:`, `visible:`, `id:`, `class:` (a list, with `"!name"` excluding a class) and the field filters; without a selector they match any element |
| [`find_field`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-find_field), [`find_button`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-find_button), [`find_link`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-find_link) | ✅ | `with:`, `checked:`, `unchecked:`, `disabled:`, `href:`, `type:` |
| Element [`.click`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-click), [`.set`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-set), [`.text`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-text), [`.value`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-value), [`.[]`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-5B-5D), [`.checked?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-checked-3F), [`.selected?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-selected-3F), [`.disabled?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-disabled-3F), [`.visible?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-visible-3F), [`.send_keys`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-send_keys), [`.select_option`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-select_option), [`.hover`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Element.html#method-i-hover) | ✅ | Plus the finders and assertions inside the element; using an element that left the page raises |
| [`page`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-page) | ✅ | Every helper, plus [`body`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Page.html#method-i-body) and [`title`](https://jakehow.github.io/rails-jsdom/RailsJsdom/Page.html#method-i-title) |
| [`assert_text`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_text), [`assert_no_text`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_no_text), [`refute_text`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-refute_text) | ✅ | String or Regexp |
| [`assert_selector`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_selector), [`assert_css`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_css) | ✅ | Counts visible elements, as in system tests; `count:`, `minimum:`, `maximum:` |
| [`assert_no_selector`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_no_selector), [`assert_no_css`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_no_css), [`refute_selector`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-refute_selector) | ✅ |  |
| [`assert_field`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_field), [`assert_no_field`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_no_field) | ✅ |  |
| [`assert_checked_field`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_checked_field), [`assert_unchecked_field`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_unchecked_field) | ✅ |  |
| [`assert_button`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_button), [`assert_no_button`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_no_button) | ✅ | Disabled buttons match only with `disabled:` |
| [`assert_link`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_link), [`assert_no_link`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_no_link) | ✅ |  |
| [`assert_current_path`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_current_path), [`assert_no_current_path`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_no_current_path) | ✅ | `ignore_query:`, `url:`, Regexp |
| [`assert_title`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_title), [`assert_no_title`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-assert_no_title) | ✅ |  |
| [`has_text?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_text-3F), [`has_content?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_content-3F), [`has_no_text?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_no_text-3F), [`has_no_content?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_no_content-3F) | ✅ |  |
| [`has_selector?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_selector-3F), [`has_css?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_css-3F), [`has_no_selector?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_no_selector-3F), [`has_no_css?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_no_css-3F) | ✅ |  |
| [`has_field?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_field-3F), [`has_no_field?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_no_field-3F), [`has_checked_field?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_checked_field-3F), [`has_unchecked_field?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_unchecked_field-3F) | ✅ |  |
| [`has_button?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_button-3F), [`has_no_button?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_no_button-3F), [`has_link?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_link-3F), [`has_no_link?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_no_link-3F) | ✅ |  |
| [`has_current_path?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_current_path-3F), [`has_no_current_path?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_no_current_path-3F), [`has_title?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_title-3F), [`has_no_title?`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-has_no_title-3F) | ✅ |  |
| [`current_path`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-current_path), [`current_url`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-current_url) | ✅ |  |
| [`evaluate_script`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-evaluate_script) | ✅ | Awaits a returned promise; extra arguments arrive as `arguments`, elements as DOM elements, and an element's own `evaluate_script` runs with `this` set to it |
| [`execute_script`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-execute_script) | ✅ | Extra arguments as in `evaluate_script`; also on an element |
| [`accept_alert`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-accept_alert) | ✅ | An unexpected alert fails the test |
| [`accept_confirm`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-accept_confirm), [`dismiss_confirm`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-dismiss_confirm) | ✅ | An unexpected confirm fails the test |
| [`accept_prompt`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-accept_prompt), [`dismiss_prompt`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-dismiss_prompt) | ✅ | An unexpected prompt fails the test |
| [`hover`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-hover), [`double_click`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-double_click), [`right_click`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-right_click) | ✅ | Element methods in system tests; here they also take a locator. CSS `:hover` styles do not apply |
| `within_frame` | ❌ | Not planned: real iframes are mostly cross-origin; Turbo Frames already work |
| `within_window`, `switch_to_window` | ❌ | Not planned: check a `target="_blank"` link with `assert_link`, then `visit` it |
| `drag_to` | ❌ | Never: drag-and-drop needs layout, which jsdom does not have |
| `take_screenshot` | ❌ | Never: jsdom does not render pages |
| Waiting (`default_max_wait_time`, retrying assertions) | — | Not needed: the page settles before every action and assertion. A `wait:` option raises an error that says to remove it |

## Limits

- **No layout or painting.** Computed CSS, geometry, breakpoints, screenshots and drag and drop cannot be tested.
- **Stubbed browser APIs.** jsdom lacks some browser APIs, so rails-jsdom stubs these: `matchMedia` never matches, `IntersectionObserver` and `ResizeObserver` never report, scrolling does nothing, `checkVisibility` is false for elements that assertions treat as hidden, `MessageChannel` delivers messages on the virtual clock, inserted stylesheet `<link>` elements, and images once their `src` is set, fire `load` without fetching anything, `URL.createObjectURL` returns a `blob:` URL nothing can fetch, `DataTransfer` and `ClipboardEvent` exist so a test can dispatch a paste, and `navigator.clipboard` drops writes. A page that needs another missing API needs a stub in the test.
- **Remote importmap pins** load as empty modules. Vendor a pin with `bin/importmap pin --download` to test it.
- **Requirements:** Ruby 3.3, 3.4 or 4.0, and Rails 8.1 with importmap, Propshaft, Turbo and Stimulus. Stimulus controllers must live under `app/javascript/controllers`.
