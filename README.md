# rails-jsdom

Browserless interaction tests for Rails apps built with Stimulus, Turbo and importmap.

`rails-jsdom` lets you write tests that read like system tests — `visit`, `click_on`, `fill_in`, `assert_selector`, `assert_text` — without Capybara, a test server or a browser. Your real pages render through Rails, your real Stimulus controllers and Turbo run in [jsdom](https://github.com/jsdom/jsdom), and every request the page makes is answered by Rails in the same test process.

Interaction tests written this way can be as much as **4–10x faster** than equivalent Rails system tests, run deterministically, and fail on JavaScript errors. `rails-jsdom` aims to match the API available in system tests that users are already familiar with.

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
- [Trade-offs compared with system tests](#trade-offs-compared-with-system-tests)
- [Results on 37signals' open-source apps](#results-on-37signals-open-source-apps)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Supply chain](#supply-chain)
- [Writing tests](#writing-tests)
- [API](#api)
- [Action Cable and Turbo Stream broadcasts](#action-cable-and-turbo-stream-broadcasts)
- [Timers and settling](#timers-and-settling)
- [Continuous integration](#continuous-integration)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Development](#development)
- [Instructions for coding agents](https://jakehow.github.io/rails-jsdom/docs/agents_md.html)
- [License](#license)

## How it works

1. Each test worker starts **one persistent Node process** running jsdom. It stays up for the whole run.
2. On start, Node bundles your importmap's `application` module and every Stimulus controller under `app/javascript/controllers` once with [esbuild](https://esbuild.github.io), resolving `@hotwired/turbo-rails`, `@hotwired/stimulus` and your other pins through your app's importmap and Propshaft load path. The versions under test are exactly the ones your app ships. A dynamic `import()` of a module your importmap does not pin is left out of the bundle and fails when the page runs it, as it would in a browser.
3. `visit` makes a real integration request (`get`), follows redirects, and loads the response HTML into a fresh jsdom window at the URL it requested last: the visited URL, or the target of the last redirect. Middleware that rewrites the path, such as one that moves a prefix into `SCRIPT_NAME`, does not change it. Your `application` module runs, as `javascript_importmap_tags` runs it in a browser, so its initializers and globals are there; Turbo and Stimulus boot; controllers connect. If your `application` module starts Stimulus and sets `window.Stimulus`, controllers register on that application; otherwise the runner starts one. Controllers connect as they do with `stimulus-loading` in a browser: after the page's scripts have run, one per task, in the order of their files. Work your modules queued with `setTimeout`, such as defining custom elements, comes first. `@hotwired/stimulus-loading` is replaced: the runner registers each controller when the page first uses it.
4. Every `fetch` and `XMLHttpRequest` the page makes — your controllers' own calls, Active Storage direct uploads, Turbo Drive visits, Turbo form submissions, Turbo Frames — is sent back to Ruby and answered by Rails **in-process**, with the test's cookies and session, following redirects. Turbo then renders the response exactly as it would in a browser, including Turbo Stream responses.
5. After every action, the runner **settles** the page deterministically: it runs timers on a virtual clock, delivers what Action Cable sent the page, and waits until no Rails request is pending. See [Action Cable and Turbo Stream broadcasts](#action-cable-and-turbo-stream-broadcasts) and [Timers and settling](#timers-and-settling).
6. Assertions read a snapshot of the live DOM: `assert_dom`, `assert_select` and `css_select` work as in any Rails test because `document_root_element` is the page.
7. JavaScript errors, unhandled promise rejections, Stimulus errors and unexpected alert, confirm or prompt dialogs fail the action that caused them. A stylesheet that jsdom cannot parse does not: browsers skip CSS they cannot parse, and jsdom does not parse all valid CSS.

## Trade-offs compared with system tests

**What you gain**

- **Speed.** No browser, no Capybara server, no Puma, no Chrome. A test is a Rails request plus a jsdom page. In [37signals' open-source apps](#results-on-37signals-open-source-apps), the same tests ran 1.8x to 16.5x faster than as system tests.
- **Determinism.** Timers run on a virtual clock that Ruby and the page share, Action Cable runs in the test's thread, and the runner waits for pending requests itself. There are no sleeps, waits or retries to tune, and a slow machine does not change what a test sees.
- **Real code paths.** Real controllers, real views, real Stimulus controllers, real Turbo, real session — only the browser engine is replaced.
- **Clear failures.** A JavaScript exception, an unhandled rejection or a dialog you did not expect fails the test instead of being swallowed by the browser.
- **Parallel-friendly.** Each test worker gets its own Node process; nothing is shared between workers.

**What you lose**

jsdom implements the DOM and runs JavaScript, but it does not lay out or paint pages. These cannot be tested with `rails-jsdom`; if they matter to you, keep a small number of real-browser system tests for them:

- **Computed CSS** — colours, fonts, backgrounds, hover styles.
- **Layout and geometry** — `getBoundingClientRect`, centring, gaps, overflow, wrapping, "these cards are the same height". Every element and range measures 0x0 at 0,0. Code that waits for a real measurement, such as a menu that positions itself at the caret and re-measures until it gets a box, would repeat forever; after 10,000 measurements in one turn of the event loop the page throws an error that says so, and the action fails at once. When where things are does not matter to the test, give the elements involved a box with `stub_layout` in that test, for example `stub_layout "#composer .editor-content"`.
- **CSS media-query breakpoints** — elements shown or hidden only by responsive CSS at a viewport width (for example Tailwind's `md:hidden`). `matchMedia` is stubbed so controllers don't crash, but CSS does not respond to width. Responsive behaviour driven by JavaScript, such as a mobile menu toggle, is still testable.
- **Theme switching** where the theme only changes CSS.
- **Screenshots** and other visual evidence.
- **Drag and drop** — drag-and-drop libraries find the drop target from element positions, which jsdom reports as zero.

Layout assertions are brittle in any case; prefer asserting behaviour — what is in the DOM, what is hidden, what the URL is, what Rails received.

**Partly supported**

These work through the library imitating the browser, so the parts that depend on layout or the platform stay out of reach:

- **Keyboard input.** `send_keys` performs the common browser actions itself: typing and Backspace at the end of a text field, Enter submitting a form or pressing a focused button or link, Space pressing a focused button or checkbox, Tab and Shift+Tab moving focus, and the arrow keys, Home and End stepping a range or number field. In a contenteditable, such as a rich text editor, each key fires `beforeinput` and `input` with the standard input type (`insertText`, `deleteContentBackward`, `insertParagraph`, `insertLineBreak`); if the editor does not cancel `beforeinput`, the character is inserted, or Backspace deletes, at the caret. As in system tests, typing into an element that does not have focus puts the caret after its content. Moving the caret with keys, selecting text, IME input and OS shortcuts are not supported.
- **Several users at once.** `using_session` gives each user their own cookies and page, and their own `localStorage` and `sessionStorage`, which last across page loads as in one browser tab, and Turbo Stream broadcasts reach every page that subscribed. Pages do not run at the same time: a page receives what happened while it was in the background when the test returns to it.

**Not supported yet**

These are limits of this library, not of jsdom, and could be added:

- **Third-party scripts loaded from a CDN.** Remote importmap pins are replaced by empty modules, and `<script src>` tags are not loaded. Pins vendored with `bin/importmap pin --download` are bundled and work. Remote scripts could be downloaded once and cached, but many of them (payment widgets, maps, charts, analytics) need cross-origin iframes, canvas, layout or their vendor's servers, so they would still need stubs.
- **iframes and new windows.** Turbo Frames work, but real `<iframe>` content and links that open a new window or tab are not followed. Check such a link with `assert_link` and its `href`, then `visit` it.

**Where the time goes**

The esbuild bundle is built once per test worker. Each `visit` then costs a Rails render, a jsdom parse and a Turbo/Stimulus boot, and each interaction costs whatever Rails requests it makes. If several tests repeat the same visit and interactions only to check different things about the result, each one pays for them again; checking those things in one test pays once.

## Results on 37signals' open-source apps

To test rails-jsdom on real apps, we moved the system tests of three open-source Rails apps from 37signals to interaction tests wherever possible: [Campfire](https://github.com/basecamp/once-campfire), [Fizzy](https://github.com/basecamp/fizzy) and [Writebook](https://github.com/basecamp/writebook). The work is on the `interaction-tests` branch of each fork: [once-campfire](https://github.com/jakehow/once-campfire/tree/interaction-tests), [fizzy](https://github.com/jakehow/fizzy/tree/interaction-tests) and [writebook](https://github.com/jakehow/writebook/tree/interaction-tests). The upstream apps still use their system tests.

| App | System tests | Moved to interaction tests | Still system tests | System tests (Chrome) | Interaction tests | Speedup |
|---|---|---|---|---|---|---|
| Campfire | 30 | 28 | 3 | 317.7s | 19.3s | 16.5x faster (94% less time) |
| Fizzy | 47 | 18 | 29 | 21.5s | 9.6s | 2.2x faster (55% less time) |
| Writebook | 3 | 3 | 0 | 6.8s | 3.7s | 1.8x faster (45% less time) |

How we measured:

- The two columns of times are for the same tests, the system test from the app's `main` branch against the interaction test that replaced it.
- All runs used one process (`PARALLEL_WORKERS=1`) on one Apple M1 Max.
- System tests ran in headless Chrome through Selenium, as each app configures them.
- Interaction tests ran on Node 26.13.1, jsdom 31.0.0 and Rails 8.2.0.alpha, the edge Rails the apps use.
- Each time is the fastest of three runs.
- The interaction times include starting Node and bundling the app's JavaScript once, about 1.4s.

Why the gains differ:

- Campfire's system tests spend most of their time waiting in the browser, about 11.6s per test. Interaction tests do not wait.
- Fizzy's system tests were already fast, about 1.1s per test, with no waiting. In both kinds of test, most of the time is the page's own work: Rails renders, Stimulus connects controllers and Turbo renders frames and streams.

### Bugs found

- **Writebook, `edit page`.** The system test never saved the page. It gave its content to the editor helper as a `with:` hash, but the helper takes the content as its second argument, so the editor got the hash. The helper also changed the value without an `input` event, so the autosave form stayed clean and Save sent nothing. The assertions only read the editor's preview, so the test passed. The branch fixes the helper and the call, and checks that the page body was saved.
- **Writebook, `publish`.** This system test failed 1 time in 16 in Chrome, because it races the autosave. Its interaction test settles the autosave first and passes on every run.
- **Campfire and Fizzy.** Moving their tests found no bugs in the apps.

### Changes the apps needed

Most tests moved with the same steps. Some needed small changes in the app's test code, not in the app:

- **Campfire.**
  - `ApplicationInteractionTestCase` reads whether a room is read or unread from its CSS classes, not from how the browser draws it.
  - The 2 mention tests call `stub_layout "#composer lexxy-editor"`, because Lexxy positions its mention menu at the caret.
  - The spoofing test reads the server's answer with `fetch`. It no longer saves screenshots; a separate system test keeps them.
  - The link-unfurling tests allow `localhost` in WebMock.
- **Writebook.** The editor helper sends an `input` event after it changes the value, as a person typing does.
- **Fizzy.** No changes to its test code.

### Tests that are still system tests

Each remaining system test needs something that jsdom does not do. The exception is one Fizzy test that we have not tried yet.

**Campfire (3):**

- **`message_id_spoofing_screenshots_test.rb` (1).** It saves before and after screenshots for a security advisory. jsdom cannot take screenshots. The checks in this test also run as an interaction test, so this test can go if nobody needs the screenshots.
- **`push_subscription_resync_test.rb` (2).** These tests fake the notification permission, a service worker and a push subscription through the Chrome DevTools Protocol before the page's scripts run. jsdom has no service workers or Push API, and rails-jsdom cannot run a script before the page's own scripts.

**Fizzy (29):**

- **`mermaid_diagram_test.rb` (18).** Drawing a Mermaid diagram measures text on a canvas, and jsdom has no canvas. The 2 editor tests that do not draw a diagram moved.
- **`board_scroll_test.rb` (4).** They check scroll positions, find elements at a point with `elementFromPoint`, and move the mouse to coordinates. All of these need layout.
- **`activity_pagination_test.rb` (1) and `column_pagination_refresh_test.rb` (1).** The next page loads when its link scrolls into view, through `IntersectionObserver`. jsdom does not lay out the page, so nothing scrolls into view.
- **`code_block_styling_test.rb` (2).** They check the background colours the browser computes from the app's CSS.
- **`oauth_consent_test.rb` (1).** After the consent form posts, the browser follows the redirect to the client only if the page's `form-action` Content Security Policy allows it. The test checks that a real browser does. jsdom does not enforce Content Security Policy.
- **`smoke_test.rb`, `dragging card to a new column` (1).** Drag and drop finds the drop target from element positions.
- **`board_keyboard_focus_test.rb` (1).** We have not tried to move this test yet. It uses keys, focus and Turbo navigation, which rails-jsdom supports.

## Requirements

- Ruby 3.3, 3.4 or 4.0
- Rails 8.1 with `importmap-rails`, `propshaft`, `turbo-rails` and `stimulus-rails`
- Stimulus controllers under `app/javascript/controllers`, named `*_controller.js`
- Node.js 22.22.2+, 24.15+ or 26+, the supported LTS lines that jsdom 31 runs on

These are the versions CI tests and that issues are fixed for. Ruby 3.2 has reached end of life. Older Rails releases may still work, but they are not tested or supported.

## Installation

Add the gem to the test group and install it:

```ruby
group :test do
  gem "rails-jsdom"
end
```

```bash
bundle install
bin/rails generate rails_jsdom:install
```

The install generator:

1. Adds `require "rails_jsdom"` to `test/test_helper.rb`, after `require "rails/test_help"`.
2. Creates `test/interactions/` for your interaction tests. Any test directory works; `bin/rails test` picks them up.
3. Adds `jsdom` and `esbuild` to the `devDependencies` in `package.json`, creating the file if your app has none. The ranges (`^31.0.0`, `^0.28.2`) allow newer minor and patch releases but never a new major version. The gem loads both from your app's `node_modules`.
4. Sets `min-release-age=7` in `.npmrc`, unless it is already set, so npm installs only versions published at least 7 days ago. See [Supply chain](#supply-chain).
5. Warns if your npm is older than 11.10, which ignores `min-release-age`.
6. Runs `npm install`. Pass `--skip-npm` to run it yourself.
7. Adds `/node_modules` to `.gitignore`.

Running it again changes nothing that is already set up.

### Supply chain

jsdom and esbuild run with your test process's access to your machine and CI, so a compromised release of either, or of anything they depend on, could take them over. Compromised npm releases are usually found and removed within days. The install generator sets up three defences:

- **A major-version range.** `npm update` never moves to a new major version without you changing `package.json`.
- **A release age.** With `min-release-age=7` in `.npmrc`, npm skips any version published in the last 7 days when it resolves a range, and fails with `ETARGET` if no older version fits. It needs npm 11.10 or later; older npm reads the setting and ignores it.
- **Your lockfile.** Commit `package-lock.json` and install with `npm ci` in CI. `npm ci` installs exactly the locked versions, whatever your npm version, so new releases only arrive when someone runs `npm install` or `npm update` and commits the result.


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

  test "an unknown name shows the empty state instead of the grid" do
    fill_in "search", with: "no-such-project"

    assert_dom "[data-project-filter-target=noResults]:not([hidden])"
    assert_dom "[data-project-filter-target=grid][hidden]"
  end
end
```

Patterns:

- **Turbo forms** submit through Turbo and Rails answers in-process; Turbo Stream responses are applied before the action returns.
- **Dialogs**: `<dialog>` `showModal`/`close` and `method="dialog"` forms work.
- **Requests to other hosts** fail like a network error (`TypeError`), so a page cannot reach the internet.

## API

The full API reference is at **[jakehow.github.io/rails-jsdom](https://jakehow.github.io/rails-jsdom/)**. Tests inherit from [`RailsJsdom::TestCase`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestCase.html); every helper is documented in [`RailsJsdom::TestHelper`](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html), with the locator rules, filters, scoping, dialogs and settling.

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

A page's WebSocket connects to your app's real Action Cable server, in process. Pages that subscribe with `turbo_stream_from`, and your own channels with their JavaScript consumers, receive what the server sends during the test:

```ruby
test "a new comment appears for everyone watching the task" do
  visit task_path(tasks(:open))
  perform_enqueued_jobs { Comment.create!(task: tasks(:open), body: "Looks good") }

  assert_text "Looks good"
end
```

The page's `WebSocket` is the browser API, so `@rails/actioncable`, Turbo's `<turbo-cable-stream-source>` and your own consumers use it unchanged. Its connection goes through your app as a WebSocket upgrade carrying the test session's cookies, so middleware, routing, origin checks and your `ApplicationCable::Connection` run as in production: `connect` identifies the user or rejects the connection, and each channel runs its own `subscribed` (including `reject`), `stream_from`, `transmit`, actions and `periodically` timers. Broadcasts made before the page subscribed are not delivered, and a channel that rejects a subscription receives nothing. Leaving a page closes its connections, so channels run `unsubscribed`, and `ActionCable.server.remote_connections.where(...).disconnect` disconnects a page as it would a browser. `broadcast_*_later` broadcasts arrive when the test performs the jobs.

Action Cable runs in the test's thread, so nothing is left to chance:

- Every message the server sends — the welcome, the confirmation or rejection of a subscription, what an action transmits, and every broadcast to a stream the page subscribes to — is ready for the page before the call that caused it returns. A broadcast nobody subscribes to costs nothing.
- The page receives the messages before its next timer runs.
- Action Cable's heartbeat ping and channels' `periodically` timers run on the test's [virtual clock](#timers-and-settling).

For this, each `RailsJsdom::TestCase` puts its own pub/sub adapter on `ActionCable.server`, in place of the `test` adapter, and puts the previous one back after the test. It records broadcasts as the `test` adapter does, so `assert_broadcasts` and `assert_broadcast_on` keep working, and it delivers each one as it is made. A broadcast must come from the test, from a request the page makes, or from jobs the test performs with `perform_enqueued_jobs`. A broadcast from another thread is not delivered, and the next command fails with an error that says why.

An error in your connection or channel code that no `rescue_from` handles — in `connect`, `subscribed`, an action, a stream handler or a periodic timer — fails the test at its next command. Action Cable would log it and carry on; the error message names the error, the page command or method that raised it, and the backtrace. Errors your channel or connection handles with `rescue_from` stay handled, and a connection rejected with `reject_unauthorized_connection` does not fail the test.

A page whose script never stops, such as an endless loop, cannot answer. After `RailsJsdom.command_timeout` seconds (default 30) its Node process is stopped and the command fails with an error that says so; the next command starts a new process.

## Timers and settling

`setTimeout`, `setInterval` and `requestAnimationFrame` run on a virtual clock. After each action the runner keeps running due timers and waits for pending Rails requests until nothing is due within a one-second horizon. Timers further out — polling intervals, auto-dismissing flashes — stay pending, so pages never loop forever. A test does not need, and should not use, sleeps or waits.

The clock is the test's clock, shared by Ruby and every page:

- At the start of each test, Ruby's time is frozen with `travel_to`. The page's `Date` and `performance.now()` follow the virtual clock from that time.
- When the page's clock moves, Ruby's time moves with it before Rails handles anything from the page, so timestamps the server writes agree with the page.
- When the test moves time with `travel` or `travel_to`, the page's clock moves forward before the next command, running the timers due on the way in order. Moving back moves the page's `Date` back. Rails restores a stubbed time without its fraction of a second, at the end of a block `travel_to` and in `freeze_time`; when that is the only change, the clock keeps the exact time and the page does not move.
- All sessions share the clock. A session's timers that fell due while another session ran run before its next command.

## Continuous integration

CI needs Node and your app's npm packages before the tests run:

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 26
- run: npm ci
- run: bin/rails test
```

Each parallel test worker starts its own Node process the first time it runs an interaction test.

## Troubleshooting

- **Node output and page console messages** go to `Rails.logger` at info level, prefixed with `[rails_jsdom]`, so they appear wherever your test environment logs (by default `log/test.log`).
- **`Cannot find module 'jsdom'`**: run `npm install --save-dev jsdom esbuild` in the app (and `npm ci` in CI).
- **"The RailsJsdom Node process exited"**: see the `[rails_jsdom]` lines in your Rails log; the next command starts a new process.
- **An exception in your Rails code while answering a page request** fails the test with that exception; the Node process is restarted for the next command.
- **An element is not found**: `assert_dom` your expectation first, check the [locator rules](https://jakehow.github.io/rails-jsdom/RailsJsdom/TestHelper.html), or scope with `within`.

## Limitations

See [what you lose](#trade-offs-compared-with-system-tests). In addition:

- jsdom lacks some browser APIs. The runtime stubs the common ones so controllers keep working: `matchMedia` (never matches), `IntersectionObserver` and `ResizeObserver` (never report), `scrollTo`, `scroll` and `scrollBy` on the window and on elements, and `scrollIntoView` (do nothing), `checkVisibility` (false for the elements that assertions treat as hidden), `MessageChannel` (each message is delivered as a timer on the virtual clock), `load` on inserted stylesheet `<link>` elements and on images once their `src` is set (stylesheets and images are not fetched, so code that waits for them, such as Turbo merging a new page head, goes on), `URL.createObjectURL` (a `blob:` URL that nothing can fetch) and `URL.revokeObjectURL` (does nothing), `DataTransfer` and `ClipboardEvent` (so a test can dispatch a paste, as system tests do), `getBoundingClientRect` and `getClientRects` on a `Range` (an empty box, as elements have), `navigator.clipboard` (writes are dropped, reads are empty), `<dialog>` `show`, `showModal` and `close`, the Fullscreen API (`requestFullscreen`, `exitFullscreen`, `fullscreenElement`, `fullscreenEnabled` and `fullscreenchange`, as on a desktop browser; nothing is drawn), and form participation for form-associated custom elements (`ElementInternals` `form`, `setFormValue`, `setValidity` and `validity`; their values are part of `new FormData(form)`). The page also behaves as a desktop browser without touch: `ontouchstart` and the other touch handlers are absent and `navigator.maxTouchPoints` is 0. A page that needs another missing API needs a small stub in your controller or test.
- Stimulus outlets are not tested yet.

## Development

```bash
bundle install
npm install
bundle exec rake test
bundle exec rubocop
```

`bundle exec rake test` runs, in order:

1. ESLint over all JavaScript (`bundle exec rake lint_js`).
2. The Node tests for the runtime and the ESLint rule (`bundle exec rake test_runner`).
3. The Ruby tests.

CI runs the same, plus RuboCop, on each supported Ruby with the latest Rails release. One more CI job runs it on Ruby 4.0 with edge Rails, from `gemfiles/rails_edge.gemfile`. To run it locally:

```bash
BUNDLE_GEMFILE=gemfiles/rails_edge.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_edge.gemfile bundle exec rake test
```

The edge Gemfile's lockfile is not committed, so each run tests the current Rails `main`. Ruby coverage is measured, and held at 100%, only with the released Rails. The Rails 8.1 and edge Rails Action Cable paths each run for real in their own job.

This repository's own `.npmrc` sets `min-release-age=7` too, so `npm install` here skips releases from the last 7 days. Use npm 11.10 or later when you change `package.json`.

### How the pieces fit

- The Ruby side (`lib/rails_jsdom`) runs in the test process. The Node side (`lib/rails_jsdom/runtime.js`) runs the pages in jsdom.
- They talk over a line protocol, documented in **[Runtime protocol](https://jakehow.github.io/rails-jsdom/docs/protocol_md.html)** ([source](docs/protocol.md)). Update that page whenever a command, field or reply changes.

### Tests

The library is tested against a small Rails app in `test/dummy`, with importmap, Turbo and Stimulus.

When you add or change a helper, add its real usage to the dummy app and cover it with interaction tests in `test/interactions`:

- Put the markup it acts on in a dummy page (`test/dummy/app/views`), with a route and controller action if it needs one. Prefer what a real app has: Rails form helpers, Turbo forms and links, Stimulus controllers.
- Add one variant to the page for each behaviour that differs: each option and filter, each kind of element it matches, Turbo and non-Turbo forms, and the cases that must fail, such as no match, several matches, a disabled field or an unexpected dialog.
- Write one interaction test per variant against the real page, and check the outcome Rails or the page sees, such as submitted params, the current path or the DOM.
- Keep the unit tests in `test/rails_jsdom` for code that does not need a page.

The Node runtime has its own unit tests in `test/runner/*.test.js`, written with Node's built-in test runner:

- They drive the runtime only through its public interface, the line protocol. `test/runner/support.js` plays the Ruby side and answers the runtime's requests to Rails.
- They bundle a small fixture app in `test/runner/fixtures`, with stand-ins for Stimulus and Turbo.
- Write them in the same style: no reaching into private functions.

### Standards

These are enforced by `rake test` and RuboCop, and CI fails if any of them fails.

- **Coverage:**
  - The Ruby code is held at 100% of lines and branches (SimpleCov).
  - `runtime.js` and the ESLint rule are held at 100% of lines, branches and functions (Node's test coverage).
  - Code that cannot be tested is deleted.
- **Comments:**
  - Only API documentation is allowed. In Ruby that means RDoc: a comment block directly above a class, module, method, constant, attribute, alias or delegation, an RDoc directive such as `:nodoc:`, or a `##` block for a generated method. In JavaScript it means a `/** */` doc comment directly above a declaration.
  - Every other comment fails the build. Put the meaning into a name, a method or a test.
  - Directives that switch a cop off (`# rubocop:disable`, `// eslint-disable`) are not allowed either.
- **API documentation:**
  - Every public class, module, method and constant has RDoc. `bundle exec rdoc -C lib` reports 100%.
  - The API reference is built with `bundle exec rake rdoc` and published to GitHub Pages.
- **Readable code (Ruby):**
  - Implicit returns, with no `return` and no explicit `return nil`.
  - `unless` only as a one-line modifier with a predicate method.
  - No boolean flags set more than once. No ternaries with a `nil`, `true` or `false` branch. No `next unless`. No `.nil?` as a condition.
  - Bang methods start with a verb, and predicate methods return booleans.
  - Blocks are named (`&block`), not forwarded anonymously.
  - These cops live in `rubocop/cop/readability`, with their tests in `test/rubocop`.
- **Size and complexity:**
  - Ruby: methods up to 10 lines, AbcSize 13, cyclomatic and perceived complexity 5, and one level of block nesting.
  - JavaScript: complexity 8, 25 lines and 16 statements per function, nesting depth 2, 4 parameters, and no nested ternaries.
  - When code goes over a limit, remove the complexity: give a concept its own method or class, or split a function by the questions it answers. Never shorten lines with compressed or unusual syntax. A clear method slightly over a limit is better than a contorted one under it.
- **Style:**
  - Ruby follows rubocop-rails-omakase and rubocop-minitest, with RuboCop's Lint and Gemspec departments.
  - Write `case` with each `when` body on its own line.
  - JavaScript: double quotes, no semicolons, two-space indentation, `const` over `let`, and `===`.

Releases are published to RubyGems from GitHub Actions with trusted publishing when a `v*` tag is pushed.

## License

MIT — see [LICENSE](LICENSE).
