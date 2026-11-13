# Results on 37signals' open-source apps

To test rails-jsdom on real apps, we moved the system tests of three open-source Rails apps from 37signals to interaction tests wherever possible: [Campfire](https://github.com/basecamp/once-campfire), [Fizzy](https://github.com/basecamp/fizzy) and [Writebook](https://github.com/basecamp/writebook). The work is on the `interaction-tests` branch of each fork: [once-campfire](https://github.com/jakehow/once-campfire/tree/interaction-tests), [fizzy](https://github.com/jakehow/fizzy/tree/interaction-tests) and [writebook](https://github.com/jakehow/writebook/tree/interaction-tests). The upstream apps still use their system tests.

| App | System tests on `main` | Moved to interaction tests | Still system tests | Moved tests as system tests | Moved tests as interaction tests | Speedup |
|---|---|---|---|---|---|---|
| Campfire | 30 | 28 | 3 (1 is new, see below) | 317.7s | 19.3s | 16.5x faster (94% less time) |
| Fizzy | 47 | 18 | 29 | 21.5s | 9.6s | 2.2x faster (55% less time) |
| Writebook | 3 | 3 | 0 | 6.8s | 3.7s | 1.8x faster (45% less time) |

The times compare only the tests that moved: each moved test as a system test on the app's `main` branch, against the interaction test that replaced it. The tests that are still system tests are not in either time.

Campfire has 3 system tests left, not 2, because one moved test saved screenshots. Its checks moved to an interaction test, and its screenshots stay in a new system test.

## How we measured

- All runs used one process (`PARALLEL_WORKERS=1`) on one Apple M1 Max.
- System tests ran in headless Chrome through Selenium, as each app configures them.
- Interaction tests ran on Node 26.13.1, jsdom 31.0.0 and Rails 8.2.0.alpha, the edge Rails the apps use.
- Each time is the fastest of three runs.
- The interaction times include starting Node and bundling the app's JavaScript once, about 1.4s.

## Why the gains differ

- Campfire's system tests spend most of their time in Capybara calls that block until a timeout. Interaction tests settle the page instead of waiting, so these calls return at once:
  - Every time a test joins a room, the `join_room` helper calls `page.has_css?("[data-pwa-install-target~='dialog']", wait: 5)` to close an install dialog. Campfire has no element that matches, so each call waits the full 5 seconds and returns false. The moved tests join a room at least 50 times, so at least 250 of the 317.7 seconds are this wait.
  - Other calls wait for Action Cable broadcasts to reach the page, with `wait: 5` and `wait: 10`, or poll the database with `sleep 0.25` until a message is saved.
  - Tests with more than one user open a second Chrome for each `using_session`.
- Fizzy's system tests were already fast, about 1.1s per test, with no waiting. In both kinds of test, most of the time is the page's own work: Rails renders, Stimulus connects controllers and Turbo renders frames and streams.

## Bugs found

- **Writebook, `edit page`.** The system test never saved the page. It gave its content to the editor helper as a `with:` hash, but the helper takes the content as its second argument, so the editor got the hash. The helper also changed the value without an `input` event, so the autosave form stayed clean and Save sent nothing. The assertions only read the editor's preview, so the test passed. The branch fixes the helper and the call, and checks that the page body was saved.
- **Writebook, `publish`.** This system test failed 1 time in 16 in Chrome, because it races the autosave. Its interaction test settles the autosave first and passes on every run.
- **Campfire and Fizzy.** Moving their tests found no bugs in the apps.

## Changes the apps needed

Most tests moved with the same steps. Some needed small changes in the app's test code, not in the app:

- **Campfire.**
  - `ApplicationInteractionTestCase` reads whether a room is read or unread from its CSS classes, not from how the browser draws it.
  - The 2 mention tests call `stub_layout "#composer lexxy-editor"`, because Lexxy positions its mention menu at the caret.
  - The spoofing test reads the server's answer with `fetch`. It no longer saves screenshots; a separate system test keeps them.
  - The link-unfurling tests allow `localhost` in WebMock.
- **Writebook.** The editor helper sends an `input` event after it changes the value, as a person typing does.
- **Fizzy.** No changes to its test code.

## Tests that are still system tests

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
