# Runtime protocol

`rails-jsdom` has two halves. The Ruby side (`RailsJsdom::Bridge`) runs in the test process. The Node side (`lib/rails_jsdom/runtime.js`) runs the pages in jsdom. This page describes the messages between them, for anyone working on either half. Tests never use it directly.

## Transport

- Ruby starts one Node process per test worker: `node lib/rails_jsdom/runner.js`.
- Each message is one JSON object on one line.
- Ruby writes commands to Node's stdin. Node writes replies to its stdout.
- Node's stderr is for log lines only. Ruby writes each line to `Rails.logger` with a `[rails_jsdom]` prefix. Page `console` output arrives here too.
- Node handles one command at a time, in the order received. Every command gets exactly one reply.
- Closing stdin ends the Node process.

## Replies from Node

| Message | Meaning |
| --- | --- |
| `{ "type": "result", "value": …, "clock": … }` | The command succeeded. `value` is JSON; a value JSON cannot carry, such as `undefined` or a function, becomes `null`. |
| `{ "type": "error", "message": "…", "clock": … }` | The command failed. `message` includes the JavaScript stack. Ruby raises `RailsJsdom::Error` with it. |
| `{ "type": "fetch", "id": 7, "request": { … }, "clock": … }` | Not a reply. The page asked for a URL, and Node waits for Ruby's answer before the command can finish. |

Every message from Node carries `clock`: the test clock in milliseconds since the test started. Before Ruby handles the message, it moves its frozen time to the test's start plus `clock` and runs its own timers that are due (see [Time](#time)).

## Requests to Rails

While a command runs, the page may request URLs: its own `fetch` and `XMLHttpRequest` calls, link clicks, form submissions and Turbo visits. Node sends each as a `fetch` message:

| Field | Value |
| --- | --- |
| `request.method` | `"GET"`, `"POST"` and so on |
| `request.url` | The absolute URL |
| `request.headers` | Header names in lower case |
| `request.body` | The body as base64, or `null`. Form bodies are `application/x-www-form-urlencoded`; forms with files are `multipart/form-data`, with the boundary in `content-type`. |

Ruby answers with `{ "type": "fetch_response", "id": 7, "response": { … }, "sync": { … } }`, where `sync` is described under [Time](#time). The response is either:

- `{ "status": 200, "headers": { … }, "body": "…", "url": "…", "redirected": false }`. Rails has followed redirects already; `url` is the URL Rails requested last (the requested URL, or the target of the last redirect), as the browser saw it before any middleware rewrote the path, and `redirected` says whether there was a redirect. For a page navigation, Node loads `body` as the new page at `url`.
- `{ "error": "…" }` when Rails will not answer, for example a URL on another host. The page's `fetch` rejects with a `TypeError`, an `XMLHttpRequest` fires `error` with status 0, and a page navigation fails the command.

Requests from a page that has already been replaced are never sent.

A page's WebSocket uses the same `fetch` message with `request.kind` set to `"cable"`, and Ruby answers it the same way:

| `request.action` | Other fields | Ruby's answer |
| --- | --- | --- |
| `"open"` | `socket` (an id), `url` (`ws:` or `wss:`), `protocols` | `{ "protocol": "…" }`, the subprotocol Action Cable chose, or `{ "error": "…" }` when the connection is refused |
| `"send"` | `socket`, `data` (text) | `null` |
| `"close"` | `socket` | `null` |
| `"tick"` | none | `null`. Sent when the test clock reaches Ruby's next timer; Ruby runs it before answering. |

Ruby runs Action Cable in the test's thread, so everything the server sends because of a request is ready when Ruby answers it. Those messages travel in the answer's `sync.frames`, and messages caused by the test itself travel in the `sync` of the next command. Each frame is `{ "socket", "data" }`, or `{ "socket", "closed": true, "code" }` when the server closed the connection. Node delivers them to the page before its next timer runs.

## Commands

Every command is an object with a `command` field. Fields marked *scope*, *locator* and *match* are described under [Finding elements](#finding-elements).

### Reads

Reads answer at once and do not change the page.

| Command | Fields | Result |
| --- | --- | --- |
| `setup` | `root`, `controllers`, `modules`, `stubs`, `directories`, `horizon`, `hidden` | `{}` once the Stimulus bundle is built. Sent once, first. See [Setup](#setup). |
| `snapshot` | *scope* | `{ html, text, url, title }`: the HTML and visible text of the page or scope, and the page's URL and title |
| `query` | `strategy` (`"css"`, `"field"`, `"button"` or `"link"`), `locator` (or `null` for every element of that kind), *scope* | An array of [element descriptions](#element-descriptions) |
| `read` | `handle` | One element description |
| `stub_fetch` | `url` (full URL, or path and query), `response` | `null`. Later page requests to that URL get `response` without asking Rails, until the next `load`. |
| `stub_layout` | `selector`, `box` (`width`, `height`, `top`, `left`) | `null`. Elements matching `selector`, anything inside them and ranges that start inside them measure as `box` until the next `load` |
| `expect_modal` | `type` (`"alert"`, `"confirm"` or `"prompt"`), `accept`, `with` (prompt answer or `null`) | `null`. Dialogs of that type are answered until `modal_messages`. |
| `modal_messages` | none | The messages of the dialogs shown since `expect_modal`. Stops expecting dialogs. |
| `expect_file_chooser` | `files` (as for `attach`) | `null`. The next file field that a click opens a file chooser for, on the page or not, receives `files` as a timer on the virtual clock, and fires `input` and `change`. |
| `file_chooser_opened` | none | Whether a file chooser opened since `expect_file_chooser`. Stops expecting one. |
| `session` | `name` | `null`. Switches to that session's page and history; a new name starts with no page. |
| `reset` | none | `null`. Closes every page and forgets every session, stub, expected dialog and expected file chooser. Sent after each test. |

### Actions

Actions change the page and carry a `sync` (see [Time](#time)). Before an action, Node catches up: it delivers the frames in `sync`, moves the clock forward to a time Ruby is ahead to, and runs the timers due by then without running later ones. After the action, Node settles the page before it replies:

- It runs timers on the page's virtual clock, up to `horizon` milliseconds ahead.
- It waits for every outstanding request to Rails.
- It repeats both until the page is idle.

An action fails if the page threw an error, rejected a promise, showed an unexpected dialog or never became idle.

| Command | Fields | Does |
| --- | --- | --- |
| `load` | `html`, `url`, `history` (`"push"` or `"none"`) | Loads a new page and boots Turbo and Stimulus. `"push"` adds a history entry. Clears fetch stubs. Result: the page's id. |
| `click` | *locator*, *scope*, *match*, `kind` (`"link"`, `"button"`, `"link_or_button"` or `null`) | Clicks the element |
| `hover`, `double_click`, `right_click` | *locator*, *scope*, *match* | Dispatches the pointer events |
| `fill_in` | *locator*, *scope*, *match*, `with` | Sets a text-like field and dispatches `input` and `change` |
| `check` | *locator*, *scope*, *match*, `checked` | Clicks a checkbox if its state differs |
| `choose` | *locator*, *scope*, *match* | Clicks a radio button if it is not selected |
| `select` | `option`, `from` (a locator or `null` for any select), `selected`, *scope*, *match* | Selects or deselects the option whose text equals, or else contains, `option` |
| `attach` | *locator*, *scope*, *match*, `files` (`[{ name, type, base64 }]`) | Puts the files in a file field and dispatches `input` and `change` |
| `send_keys` | `keys` | Types into the focused element. See [Keys](#keys). |
| `element` | `handle`, `action`, `value` (for `set`), `keys` (for `send_keys`) | Runs `click`, `hover`, `double_click`, `right_click`, `set`, `select_option`, `unselect_option` or `send_keys` on that element |
| `traverse` | `delta` (`-1` or `1`) | Goes back or forward through Turbo history entries, then through full page loads |
| `evaluate` | `script`, optional `kind` (`"expression"` or `"statements"`), `receiver` (a handle or `null`) and `args` (an element arrives for `{ "rails_jsdom_element": handle }`) | Runs the script in the page. Result: its value, awaited if it is a promise. |
| `settle` | none | Settles the page |
| `catch_up` | none | Only catches up, as before any action |

## Setup

| Field | Value |
| --- | --- |
| `root` | The app's root. Node loads `jsdom` and `esbuild` from the app's `node_modules`. |
| `controllers` | The directory of Stimulus controllers. Each `*_controller.js` is bundled under its identifier (`admin/user_panel_controller.js` is `admin--user-panel`). |
| `modules` | The importmap pins that resolve to local files, as `{ name: path }` |
| `stubs` | The pin names that resolve to other hosts. They are bundled as empty modules. |
| `directories` | The importmap `pin_all_from` directories, as `{ prefix: path }` |
| `horizon` | How far ahead, in milliseconds, settling runs timers |
| `hidden` | The CSS selector for elements whose text is not visible |

## Time

The test has one clock, shared by Ruby and every page. Ruby freezes its time when the test starts. Every action and every `fetch_response` carries `sync`:

| Field | Value |
| --- | --- |
| `epoch` | Milliseconds since 1970 at clock zero. The page's `Date` is `epoch` plus the clock; `performance.now()` is the clock. |
| `now` | Ruby's time on the test clock. When it is ahead of the page's clock, because the test travelled, the page moves forward to it and runs the timers due on the way, in order. |
| `deadline` | The clock time of Ruby's next timer — Action Cable's heartbeat and channels' `periodically` timers — or `null`. Before the page runs a timer due after it, Node moves the clock to `deadline` and sends a `tick`. |
| `frames` | Action Cable messages for the session's sockets, as described under [Requests to Rails](#requests-to-rails) |

When the test travels back, `epoch` moves back and the clock stays where it is, so no timer runs again.

## Finding elements

- **locator:** tried as a Stimulus action (`"menu#open"`), then as text (button and link text, a button's `name`, or a field's label, placeholder, `name`, `id` or `aria-label`), then as a CSS selector. The first that matches anything wins.
- **match:** `"first"` picks the first of several matches. Otherwise several matches fail the command.
- **scope:** an array of entries applied in turn. Each entry must match exactly one element:
  - `{ "css": "#cart" }`
  - `{ "fieldset": "Billing" }` (legend text or `id`)
  - `{ "table": "Prices" }` (caption text or `id`)
  - `{ "handle": 3 }` (an element from `query`)

## Element descriptions

| Field | Value |
| --- | --- |
| `handle` | The element's number on this page. The same node keeps its handle. Using a handle whose node has left the page fails. |
| `tag` | The tag name |
| `text` | The visible text |
| `all_text` | All text, including hidden text |
| `visible` | Whether neither it nor an ancestor is hidden |
| `value` | The current value, or `null` for an element without one |
| `checked`, `selected`, `disabled` | The element's state |
| `type` | An input's type, or the tag name of other elements |
| `attributes` | Its attributes, as `{ name: value }` |

## Keys

`keys` is an array. Each entry is one of:

- `{ "text": "abc" }`: types each character.
- `{ "key": "enter" }`: presses a named key. The names are `enter`, `tab`, `backspace`, `delete`, `escape`, `space`, `left`, `right`, `up`, `down`, `home`, `end`, `page_up` and `page_down`.

Either kind can add `"modifiers"`, an array of `shift`, `control`, `alt` and `meta`, held while the key is pressed.
