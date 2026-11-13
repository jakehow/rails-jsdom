"use strict"

const { describe, it } = require("node:test")
const { RuleTester } = require("eslint")
const noComments = require("../../eslint/no-comments")

RuleTester.describe = describe
RuleTester.it = it
RuleTester.itOnly = it.only

const tester = new RuleTester({ languageOptions: { ecmaVersion: 2022, sourceType: "module" } })
const comment = { messageId: "comment" }

tester.run("no-comments", noComments, {
  valid: [
    { name: "a doc comment on a function", code: "/** Starts the runner. */\nfunction start() {}" },
    { name: "a doc comment on a class", code: "/** A page. */\nclass Page {}" },
    { name: "doc comments on class members", code: "class Page {\n  /** Loads it. */\n  load() {}\n  /** Its title. */\n  title = \"\"\n}" },
    { name: "a doc comment on a constant", code: "/** The horizon in milliseconds. */\nconst HORIZON = 1000" },
    { name: "a doc comment on an export", code: "/** The runner. */\nexport function start() {}" },
    { name: "a doc comment on a default export", code: "/** The default page. */\nexport default class {}" },
    { name: "code with no comments", code: "const value = 1" }
  ],
  invalid: [
    { name: "a line comment", code: "// explains\nconst value = 1", errors: [comment] },
    { name: "a block comment", code: "/* explains */\nconst value = 1", errors: [comment] },
    { name: "a trailing comment", code: "const value = 1 // explains", errors: [comment] },
    { name: "a doc comment separated from its declaration", code: "/** Floating. */\n\nconst value = 1", errors: [comment] },
    { name: "a doc comment on an expression", code: "/** Inside an expression. */\nvalue = 1", errors: [comment] },
    { name: "a doc comment inside a function body", code: "function start() {\n  /** Not a declaration. */\n  return 1\n}", errors: [comment] },
    { name: "a doc comment at the end of the file", code: "const value = 1\n/** At the end. */", errors: [comment] }
  ]
})
