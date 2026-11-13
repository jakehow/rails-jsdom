# Contributing to rails-jsdom

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

## How the pieces fit

- The Ruby side (`lib/rails_jsdom`) runs in the test process. The Node side (`lib/rails_jsdom/runtime.js`) runs the pages in jsdom.
- They talk over a line protocol, documented in **[Runtime protocol](https://jakehow.github.io/rails-jsdom/docs/protocol_md.html)** ([source](docs/protocol.md)). Update that page whenever a command, field or reply changes.

## Tests

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

## Standards

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
