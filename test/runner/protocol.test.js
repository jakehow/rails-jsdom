"use strict"

const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { HOST, connect, prepare, clear } = require("./support")

const runner = connect()

before(() => prepare(runner))
beforeEach(() => clear(runner))

test("an unknown command fails", async () => {
  await runner.load("<p>Page</p>")

  await assert.rejects(runner.run({ command: "noop" }), /RailsJsdom: unknown command noop/)
})

test("a command that fails answers with its error and stack", async () => {
  const reply = await runner.call({ command: "click", locator: "Missing" })

  assert.equal(reply.type, "error")
  assert.match(reply.message, /TypeError: Cannot read properties of null/)
})

test("a rejection that is not an error answers with its text", async () => {
  await runner.load("<p>Page</p>")

  await assert.rejects(runner.evaluate("Promise.reject('plain reason')"), { message: "plain reason" })
})

test("a value the protocol cannot carry answers with null", async () => {
  await runner.load("<p>Page</p>")

  assert.deepEqual([await runner.evaluate("undefined"), await runner.evaluate("() => 1"), await runner.evaluate("({ a: [1, 'b'] })")], [null, null, { a: [1, "b"] }])
})

test("page console output goes to the error stream", async () => {
  await runner.load("<script>console.log('logged', 42)</script>")

  assert.match(runner.logged(), /logged 42\n/)
})

test("an unhandled rejection during an action fails it", async () => {
  await runner.load("<p>Page</p>")
  runner.routes[`GET ${HOST}/slow`] = "hold"
  const action = runner.evaluate("fetch('/slow')")
  await waitFor(() => runner.held.length === 1)
  runner.io.emit("unhandledRejection", new Error("late rejection"))
  runner.reply(runner.held[0].id, { status: 200, headers: {}, body: "", url: `${HOST}/slow`, redirected: false })

  await assert.rejects(action, /late rejection/)
})

test("a page that keeps scheduling timers fails to settle", async () => {
  await runner.load("<p>Page</p>")

  await assert.rejects(runner.evaluate("(function loop() { setTimeout(loop, 0) })()"), /the page did not settle/)
})

test("reading the page before loading one fails", async () => {
  await assert.rejects(runner.snapshot(), /visit a page or mount a partial first/)
  await assert.rejects(runner.run({ command: "query", strategy: "css", locator: "p", scope: [] }), /visit a page or mount a partial first/)
  await assert.rejects(runner.run({ command: "read", handle: 1 }), /the element is no longer on the page/)
  await assert.rejects(runner.run({ command: "traverse", delta: -1 }), /visit a page or mount a partial first/)
})

test("settle without a page answers nothing", async () => {
  assert.equal(await runner.run({ command: "settle" }), null)
})

test("settle settles the page and answers nothing", async () => {
  await runner.load("<p>Page</p>")

  assert.equal(await runner.run({ command: "settle" }), null)
})

test("closing the input stream exits", async () => {
  runner.io.stdin.end()
  await waitFor(() => runner.io.exits.length === 1)

  assert.deepEqual(runner.io.exits, [0])
})

async function waitFor(condition) {
  while (!condition()) await new Promise(resolve => setTimeout(resolve, 1))
}
