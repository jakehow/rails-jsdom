# Changelog

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
