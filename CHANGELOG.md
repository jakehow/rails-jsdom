# Changelog

## 0.2.0 (2026-11-14)

### Breaking changes

- Requires Rails 8.1 or later (Action Cable and Action Pack 8.1). Earlier versions are end of life.
- Requires jsdom 31 and Node.js 22.22.2+, 24.15+ or 26+. The installer now adds `jsdom` `^31.0.0`; change `package.json` in apps installed with 0.1.0.
- Ruby's time is frozen at the start of each interaction test, and pages share that clock. Code that reads the real time during a test now sees the test's clock.
- An error in connection or channel code that no `rescue_from` handles now fails the test.
- A broadcast from a thread other than the test's now fails the test.
- The installer no longer checks the test environment's Action Cable adapter. Each test installs its own.

### Added

- Your importmap's `application` module runs on every page, as in a browser, so its initializers and globals are there.
- Controllers register on your app's `window.Stimulus` when it sets one, and connect after the page's scripts, one per task, in file order, as with `stimulus-loading`.
- Action Cable over the page's own `WebSocket`, in process. The connection goes through your app with the test session's cookies, and your connection and channels run as in production, including `periodically`, `rescue_from`, `unsubscribed` and remote disconnects.
- Action Cable is deterministic: every message is ready before the call that caused it returns, and `assert_broadcasts` and `assert_broadcast_on` keep working.
- One virtual clock for Ruby and every page. The page's `Date` and `performance.now()` follow it, `travel` and `travel_to` move the pages, and Action Cable's heartbeat and `periodically` timers run on it.
- `XMLHttpRequest` answered by Rails, including upload progress and `Blob` bodies, so Active Storage direct uploads work.
- `attach_file` with a block answers a file chooser that a script opens.
- Typing into a contenteditable with `send_keys`, through `beforeinput` and `input` at the caret.
- `localStorage` and `sessionStorage` last across page loads in a session.
- `stub_layout`, which gives the elements a test needs a box instead of 0x0.
- A page that waits forever for a real measurement fails with an error that says so and suggests `stub_layout`.
- `RailsJsdom.command_timeout` (default 30 seconds): a page that never answers fails the command instead of hanging.
- As in system tests: `id:` and `class:` filters, finders without a selector, `click_on`, `click_link` and `click_button` without a locator, buttons found by `name`, Selenium's key names (`:arrow_down`, `:return` and the rest), and arguments to `evaluate_script` and `execute_script`, also on an element.
- `wait:` and `make_visible:` raise an error that says to remove them.
- Browser APIs for controllers: form-associated custom elements, `DataTransfer` and `ClipboardEvent`, `Range` client rects, the Fullscreen API, element scrolling, `checkVisibility` and `MessageChannel`. The page behaves as a desktop browser without touch.
- Instructions for coding agents and the runtime protocol, published as Markdown.
- [Results on 37signals' open-source apps](docs/reference_apps.md): the same tests ran 1.8x to 16.5x faster than as system tests.
- CI also runs against edge Rails.

### Changed

- Pages settle faster.
- A stylesheet that jsdom cannot parse no longer fails the page.
- The page's URL is the URL that was requested, even when middleware rewrites the path into `SCRIPT_NAME`.
- Stylesheet `<link>` elements and images fire `load` without being fetched, so Turbo merges a new page's head.
- A dynamic `import()` of a module your importmap does not pin fails when the page runs it, as in a browser, instead of failing the bundle.

### Fixed

- Turbo Frames load. They needed `CSS.escape` (#1), which jsdom 31 now provides.
- The installer works when npm prints warnings with its version.
- Backspace after a line break in a contenteditable deletes the typed text.
- On Rails 8.1, a page's cable connection no longer builds an unused WebSocket driver, so no `websocket-driver` files load in the middle of a test (#4).
- `send_keys` takes no real time, and settling counts only progress, so a slow machine no longer fails a test with "the page did not settle". An action that waits for something that never arrives now fails at `RailsJsdom.command_timeout` (#5).

## 0.1.0 (2026-11-12)

- First release.
- `bin/rails generate rails_jsdom:install` sets an app up: it requires the library, creates `test/interactions`, adds jsdom and esbuild to `package.json` and installs them, ignores `node_modules`, and checks the ActionCable test adapter. It pins jsdom and esbuild to a major version and sets `min-release-age=7` in `.npmrc`, warning when npm is too old to honour it.
- `RailsJsdom::TestCase`: interaction tests on `ActionDispatch::IntegrationTest` with the system test methods: navigation (`visit`, `refresh`, `go_back`, `go_forward`, `using_session`), actions (`click_on`, `click_link`, `click_button`, `fill_in`, `check`, `uncheck`, `choose`, `select`, `unselect`, `attach_file`, `send_keys`, `hover`, `double_click`, `right_click`), scoping (`within`, `within_fieldset`, `within_table`), finders and elements (`find`, `all`, `first`, `find_field`, `find_button`, `find_link`, `page`), dialogs (`accept_alert`, `accept_confirm`, `dismiss_confirm`, `accept_prompt`, `dismiss_prompt`), scripts (`evaluate_script`, `execute_script`), and the `assert_*` and `has_*?` assertions for text, selectors, fields, buttons, links, the current path and the title. Plus `click`, `mount_partial`, `mount_html`, `stub_fetch` and `page_text`. `assert_dom` and `assert_select` read the live page.
- One persistent Node + jsdom process per test worker; Stimulus controllers bundled once per process with esbuild from your importmap.
- Page `fetch`, Turbo Drive visits and Turbo form submissions are answered by Rails in-process, in the test's session, following redirects.
- Turbo Stream responses and Turbo Stream broadcasts (`turbo_stream_from`, `broadcast_*`, `broadcast_*_later` performed by the test) reach the page.
- Deterministic settling on a virtual clock; page errors, unhandled rejections and unexpected alert, confirm and prompt dialogs fail the test.
- Node output and page console messages are written to `Rails.logger`, prefixed with `[rails_jsdom]`.
- If Rails raises while answering a page fetch, the exception fails the test and the next command starts a fresh Node process.
