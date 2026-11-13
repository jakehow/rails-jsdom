# rails-jsdom

Browserless interaction tests for Rails apps built with Stimulus, Turbo and importmap.

`rails-jsdom` lets you write tests that read like system tests — `visit`, `click_on`, `fill_in`, `assert_selector`, `assert_text` — without Capybara, a test server or a browser. Your real pages render through Rails, your real Stimulus controllers and Turbo run in [jsdom](https://github.com/jsdom/jsdom), and every request the page makes is answered by Rails in the same test process. Tests run deterministically, fail on JavaScript errors, and in [37signals' open-source apps](#results-on-37signals-open-source-apps) ran 1.8x to 16.5x faster than the same tests as system tests.

Using a coding agent? Point it at the **[instructions for coding agents](https://jakehow.github.io/rails-jsdom/docs/agents_md.html)**, also published as Markdown at https://jakehow.github.io/rails-jsdom/agents.md. They cover setting the gem up, writing interaction tests, and converting a system test suite.

```ruby
class CartInteractionTest < RailsJsdom::TestCase
  test "adding an item updates the cart through its Turbo Stream" do
    sign_in_as users(:shopper)
    visit product_path(products(:mug))
    fill_in "Quantity", with: 2
    click_on "Add to cart"

    assert_dom "#cart-count", text: "2"
    assert_text "Added to your cart"
  end
end
```

## Contents

- [How it works](#how-it-works)
- [Results on 37signals' open-source apps](#results-on-37signals-open-source-apps)
- [Trade-offs compared with system tests](#trade-offs-compared-with-system-tests)
- [Requirements](#requirements)
- [Installation](#installation)
- [Writing tests](#writing-tests)
- [API](#api)
- [Action Cable and Turbo Stream broadcasts](#action-cable-and-turbo-stream-broadcasts)
- [Timers and time](#timers-and-time)
- [Continuous integration](#continuous-integration)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Contributing](CONTRIBUTING.md)
- [License](#license)

## How it works

1. Each test worker starts one persistent Node process running jsdom.
2. Node bundles your importmap's `application` module and your Stimulus controllers once with [esbuild](https://esbuild.github.io), from your app's own importmap, so the versions under test are the ones your app ships.
3. `visit` makes a real Rails request and loads the response into a jsdom window. Your `application` module runs, Turbo and Stimulus boot, and controllers connect in the same order as with `stimulus-loading` in a browser.
4. Every `fetch` and `XMLHttpRequest` the page makes, including Turbo visits, form submissions, frames and direct uploads, is answered by Rails in the same process, with the test's session.
5. After every action, the page **settles**: timers run on a virtual clock, Action Cable messages are delivered, and pending requests finish. Assertions then read the live DOM, so there is nothing to wait for.
6. JavaScript errors, unhandled rejections, Stimulus errors and unexpected dialogs fail the action that caused them.

## Results on 37signals' open-source apps

We moved the system tests of [Campfire](https://github.com/basecamp/once-campfire), [Fizzy](https://github.com/basecamp/fizzy) and [Writebook](https://github.com/basecamp/writebook) to interaction tests wherever possible. The times compare only the tests that moved, each as a system test against the interaction test that replaced it, in one process on one machine.

| App | System tests | Moved | Moved tests as system tests | As interaction tests | Speedup |
|---|---|---|---|---|---|
| Campfire | 30 | 28 | 317.7s | 19.3s | 16.5x |
| Fizzy | 47 | 18 | 21.5s | 9.6s | 2.2x |
| Writebook | 3 | 3 | 6.8s | 3.7s | 1.8x |

Campfire gains the most because its system tests spend most of their time in Capybara calls that block until a timeout. The tests that stay system tests need layout, a canvas, screenshots or other things a browser engine does. **[The full results](https://jakehow.github.io/rails-jsdom/docs/reference_apps_md.html)** ([source](docs/reference_apps.md)) cover how we measured, the bugs found, the changes each app needed, and why each remaining system test stays.

## Trade-offs compared with system tests

**What you gain**

- **Speed.** No browser, no test server, no Chrome.
- **Determinism.** Ruby and the page share one virtual clock and Action Cable runs in the test's thread, so there are no sleeps, waits or retries, and a slow machine does not change what a test sees.
- **Real code paths.** Real controllers, views, Stimulus controllers, Turbo and session; only the browser engine is replaced.
- **Clear failures.** A JavaScript error or an unexpected dialog fails the test instead of being swallowed.

**What you lose**

jsdom runs the DOM and JavaScript but does not lay out or paint pages. Keep a few system tests for:

- **Computed CSS, responsive breakpoints and themes** that only change CSS.
- **Layout and geometry.** Every element measures 0x0 at 0,0. If a page waits for a real measurement, such as a menu placed at the caret, the action fails with an error that says so. When position does not matter to the test, give the elements a box with `stub_layout`.
- **Drag and drop**, which finds drop targets from element positions.
- **Screenshots** and other visual evidence.

**Partly supported**

- **Keyboard input.** `send_keys` performs the common browser actions: typing, Backspace, Enter, Space, Tab, and the arrow keys, Home and End in range and number fields. In a contenteditable each key fires `beforeinput` and `input` and edits at the caret. Moving the caret with keys, selecting text and OS shortcuts are not supported.
- **Several users.** Each `using_session` has its own cookies, page and storage, but pages do not run at the same time: a page receives what happened while it was in the background when the test returns to it.

**Not supported yet**

- **Third-party scripts from a CDN.** Remote importmap pins load as empty modules. Pins vendored with `bin/importmap pin --download` work.
- **iframes and new windows.** Turbo Frames work. Check a `target="_blank"` link with `assert_link`, then `visit` it.

## Requirements

- Ruby 3.3, 3.4 or 4.0
- Rails 8.1 with `importmap-rails`, `propshaft`, `turbo-rails` and `stimulus-rails`
- Stimulus controllers under `app/javascript/controllers`, named `*_controller.js`
- Node.js 22.22.2+, 24.15+ or 26+, the supported LTS lines that jsdom 31 runs on

CI also runs the suite against edge Rails.

## Installation

```ruby
group :test do
  gem "rails-jsdom"
end
```

```bash
bundle install
bin/rails generate rails_jsdom:install
```

The install generator adds `require "rails_jsdom"` to `test/test_helper.rb`, creates `test/interactions/`, adds `jsdom` and `esbuild` to `package.json` and runs `npm install` (pass `--skip-npm` to run it yourself). Running it again changes nothing that is already set up.

It also protects you from compromised npm releases:

- `package.json` allows newer minor and patch releases of jsdom and esbuild, never a new major version.
- `.npmrc` gets `min-release-age=7`, so npm skips versions published in the last 7 days. This needs npm 11.10 or later, and the generator warns if yours is older.
- Commit `package-lock.json` and use `npm ci` in CI, so new versions only arrive when someone updates and commits them.

## Writing tests

Inherit from `RailsJsdom::TestCase`, which is an `ActionDispatch::IntegrationTest`, so fixtures, `sign_in` helpers that post to your session controller, `perform_enqueued_jobs` and all Rails assertions work as usual.

```ruby
class ProjectFilterInteractionTest < RailsJsdom::TestCase
  setup do
    sign_in_as users(:owner)
    visit projects_path
  end

  test "filtering by name leaves one card visible" do
    fill_in "search", with: "Billing"

    assert_dom "[data-project-filter-target=card]:not([hidden])", count: 1
  end
end
```

Turbo forms and Turbo Stream responses are applied before the action returns. Requests to other hosts fail like a network error, so a page cannot reach the internet.

## API

The full API reference is at **[jakehow.github.io/rails-jsdom](https://jakehow.github.io/rails-jsdom/)**. Every helper is documented in [`RailsJsdom::TestHelper`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html), with the locator rules, filters, scoping, dialogs and settling.

### System test methods

| System test method | Status | Notes |
| --- | --- | --- |
| [`visit`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-visit) | ✅ |  |
| [`refresh`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-refresh) | ✅ | Requests the current URL again, without a history entry |
| [`go_back`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-go_back), [`go_forward`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-go_forward) | ✅ | Across Turbo Drive visits and full page loads |
| [`using_session`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-using_session) | ✅ | Each session has its own cookies and page; broadcasts reach a session's page when the test returns to it |
| [`click_on`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-click_on), [`click_link_or_button`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-click_link_or_button) | ✅ | A button also matches by its `name`, as in system tests. Without a locator, clicks the only link or button in the current `within` scope |
| [`click_link`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-click_link) | ✅ | Without a locator, clicks the only link in the current `within` scope |
| [`click_button`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-click_button) | ✅ | Without a locator, clicks the only button in the current `within` scope, as in system tests |
| [`fill_in`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-fill_in) | ✅ | Text-like fields only, as in system tests |
| [`check`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-check), [`uncheck`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-uncheck) | ✅ |  |
| [`choose`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-choose) | ✅ |  |
| [`select`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-select), [`unselect`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-unselect) | ✅ |  |
| [`attach_file`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-attach_file) | ✅ | Forms submit files to Rails as multipart requests. The block form, `attach_file(paths) { click_on "Upload" }`, answers the file chooser a script opens. Hidden file fields work, so `make_visible:` raises an error that says to remove it |
| [`send_keys`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-send_keys) | ✅ | Keys perform the common browser default actions; typing happens at the end of the value, with no caret or selection. Key names are the system test ones, including `:arrow_down` and `:return` |
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
| Waiting (`default_max_wait_time`, retrying assertions) | — | Not needed: the page settles before every action and assertion. A `wait:` option raises an error that says to remove it, and any other option a method does not support raises an `ArgumentError` that names it |

### Only in rails-jsdom

| Method | What it does |
| --- | --- |
| [`click`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-click) | Clicks any element by locator, including Stimulus action shorthand (`click "dropdown#toggle"`) |
| [`mount_partial`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-mount_partial) | Renders a partial and loads it as a page, with no route |
| [`mount_html`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-mount_html) | Loads an HTML fragment as a page |
| [`stub_fetch`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-stub_fetch) | Answers a page request without Rails |
| [`stub_layout`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-stub_layout) | Gives elements matching a selector, and ranges inside them, a box instead of 0x0, for a test whose page waits for a real measurement |
| [`page_text`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html#method-i-page_text) | The visible text of the page or the current `within` scope |

`assert_dom`, `assert_select` and `css_select` work as in any Rails test and read the live page.

## Action Cable and Turbo Stream broadcasts

A page's WebSocket connects to your app's real Action Cable server, in the test process, with the test session's cookies. Your `ApplicationCable::Connection` and channels run as in production, and pages that use `turbo_stream_from` or your own consumers receive what the server sends:

```ruby
test "a new comment appears for everyone watching the task" do
  visit task_path(tasks(:open))
  perform_enqueued_jobs { Comment.create!(task: tasks(:open), body: "Looks good") }

  assert_text "Looks good"
end
```

- Action Cable runs in the test's thread. Every message, including each broadcast, is ready for the page before the call that caused it returns, and arrives before the page's next timer.
- `assert_broadcasts` and `assert_broadcast_on` keep working.
- Broadcasts must come from the test, from a request the page makes, or from `perform_enqueued_jobs`. A broadcast from another thread fails the test with an explanation.
- An error in connection or channel code that no `rescue_from` handles fails the test, with the error and its backtrace. Action Cable would only log it.

## Timers and time

- `setTimeout`, `setInterval` and `requestAnimationFrame` run on a virtual clock. After each action, timers due within one second run; timers further out, such as polling, stay pending.
- Ruby and every page share the clock. Ruby's time is frozen at the start of each test, the page's `Date` and `performance.now()` follow the clock, and timestamps the server writes agree with the page.
- `travel` and `travel_to` move the pages too, running the timers due on the way in order.
- Action Cable's heartbeat and channels' `periodically` timers run on the same clock.

## Continuous integration

CI needs Node and your app's npm packages before the tests run:

```yaml
- uses: actions/setup-node@v7
  with:
    node-version: 26
- run: npm ci
- run: bin/rails test
```

## Troubleshooting

- **Node output and page console messages** go to `Rails.logger`, prefixed with `[rails_jsdom]` (by default in `log/test.log`).
- **`Cannot find module 'jsdom'`**: run `npm install --save-dev jsdom esbuild` in the app, and `npm ci` in CI.
- **"The RailsJsdom Node process exited"** or **a page that never stops**: see the `[rails_jsdom]` lines in your log. A command that gets no answer within `RailsJsdom.command_timeout` seconds (default 30) fails, and the next command starts a new Node process.
- **An exception in your Rails code while answering a page request** fails the test with that exception.
- **An element is not found**: check the [locator rules](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html), or scope with `within`.

## Limitations

See [what you lose](#trade-offs-compared-with-system-tests). In addition:

- jsdom lacks some browser APIs, so the runtime stubs the common ones to keep controllers working: `matchMedia` never matches, `IntersectionObserver` and `ResizeObserver` never report, scrolling does nothing, stylesheets and images fire `load` without being fetched, and the clipboard, Fullscreen API, `DataTransfer` and form-associated custom elements are provided. The page behaves as a desktop browser without touch. A page that needs another missing API needs a small stub in your controller or test.
- On a page loaded with `mount_html`, a link or form that leads to a full app page fails. Start such tests from a real page with `visit`.
- Stimulus outlets are not tested yet.

## License

MIT — see [LICENSE](LICENSE).
