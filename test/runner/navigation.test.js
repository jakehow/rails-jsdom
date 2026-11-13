"use strict"

const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { HOST, connect, html, prepare, clear } = require("./support")

const runner = connect()

before(() => prepare(runner))
beforeEach(() => clear(runner))

const traverse = delta => runner.run({ command: "traverse", delta })
const url = async () => (await runner.snapshot()).url
const session = name => runner.run({ command: "session", name })

test("traverse moves through history entries the page pushed", async () => {
  await runner.load(`<p>Page</p>`)
  await runner.evaluate(`history.pushState({}, "", "/one"); history.pushState({}, "", "/two")`)
  await traverse(-1)
  const back = await url()
  await traverse(1)

  assert.deepEqual([back, await url()], [`${HOST}/one`, `${HOST}/two`])
})

test("traverse moves through full page loads", async () => {
  runner.routes[`GET ${HOST}/`] = html(`${HOST}/`, "<p>First again</p>")
  runner.routes[`GET ${HOST}/second`] = html(`${HOST}/second`, "<p>Second again</p>")
  await runner.load(`<p>First</p>`)
  await runner.load(`<p>Second</p>`, `${HOST}/second`)
  await traverse(-1)
  const back = await runner.snapshot()
  await traverse(1)

  assert.deepEqual([back.url, back.text, await url()], [`${HOST}/`, "First again", `${HOST}/second`])
})

test("traverse at either end of the history stays on the page", async () => {
  await runner.load(`<p>Only</p>`)
  await traverse(-1)
  await traverse(1)

  assert.deepEqual([await url(), runner.requests.length], [`${HOST}/`, 0])
})

test("a load without history replaces the page and keeps the entries", async () => {
  runner.routes[`GET ${HOST}/`] = html(`${HOST}/`, "<p>First again</p>")
  await runner.load(`<p>First</p>`)
  await runner.load(`<p>Second</p>`, `${HOST}/second`)
  await runner.run({ command: "load", html: "<p>Refreshed</p>", url: `${HOST}/second`, history: "none" })
  await traverse(-1)

  assert.equal(await url(), `${HOST}/`)
})

test("a new load after going back drops the forward entries", async () => {
  runner.routes[`GET ${HOST}/`] = html(`${HOST}/`, "<p>First again</p>")
  await runner.load(`<p>First</p>`)
  await runner.load(`<p>Second</p>`, `${HOST}/second`)
  await traverse(-1)
  await runner.load(`<p>Third</p>`, `${HOST}/third`)
  await traverse(1)

  assert.equal(await url(), `${HOST}/third`)
})

test("each session keeps its own page and history", async () => {
  await runner.load(`<p>Default</p>`)
  await session("other")
  const empty = await runner.snapshot().then(() => "page", () => "none")
  await runner.load(`<p>Other</p>`, `${HOST}/other`)
  await session("default")
  const defaultPage = await runner.snapshot()
  await session("other")

  assert.deepEqual([empty, defaultPage.text, (await runner.snapshot()).text], ["none", "Default", "Other"])
})

test("reset leaves only an empty default session", async () => {
  await session("other")
  await runner.load(`<p>Other</p>`)
  await runner.run({ command: "reset" })
  await session("other")

  await assert.rejects(runner.snapshot(), /visit a page or mount a partial first/)
})

test("reset clears local and session storage, so nothing leaks into the next test", async () => {
  await runner.load(`<script>localStorage.setItem("draft", "Hello"); sessionStorage.setItem("tab", "1")</script>`)
  await runner.run({ command: "reset" })
  await runner.load(`<p>Next test</p>`)

  assert.deepEqual(await runner.evaluate(`[localStorage.length, sessionStorage.length]`), [0, 0])
})

test("local and session storage last across page loads in a session, as in one browser tab, and not into another session", async () => {
  await runner.load(`<script>localStorage.setItem("draft", "Hello"); sessionStorage.setItem("tab", "1")</script>`)
  await runner.load(`<p>Next</p>`, `${HOST}/next`)
  const kept = await runner.evaluate(`[localStorage.getItem("draft"), sessionStorage.getItem("tab")]`)
  await session("other")
  await runner.load(`<p>Other</p>`)
  const other = await runner.evaluate(`[localStorage.getItem("draft"), sessionStorage.getItem("tab")]`)
  await session("default")

  assert.deepEqual([kept, other], [["Hello", "1"], [null, null]])
})
