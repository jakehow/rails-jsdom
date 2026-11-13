"use strict"

const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { connect, prepare, clear } = require("./support")

const runner = connect()

before(() => prepare(runner))
beforeEach(() => clear(runner))

test("setup answers with an empty result", async () => {
  assert.deepEqual(await runner.run({ ...require("./support").SETUP }), {})
})

test("a controller connects with modules from the importmap, a pin directory, node_modules and a stubbed remote pin", async () => {
  await runner.load(`<p data-controller="hello"></p>`)

  assert.equal((await runner.snapshot()).text, "Hello, Ada from tiny")
})

test("a controller in a subdirectory gets a namespaced identifier", async () => {
  await runner.load(`<p data-controller="admin--user-panel"></p>`)

  assert.match((await runner.snapshot()).html, /data-connected="admin--user-panel"/)
})

test("a controller error fails the action that connected it", async () => {
  await assert.rejects(runner.load(`<p data-controller="broken"></p>`), /Error connecting broken: Error: broken controller/)
})

test("a controller added to the page later connects", async () => {
  await runner.load(`<div id="host"></div>`)
  await runner.evaluate(`document.getElementById("host").innerHTML = '<p data-controller="hello unknown"></p><p data-controller="hello"></p>'`)

  assert.equal((await runner.snapshot()).text, "Hello, Ada from tiny Hello, Ada from tiny")
})

test("an element already on the page that gains a data-controller connects", async () => {
  await runner.load(`<p id="host"></p>`)
  await runner.evaluate(`document.getElementById("host").setAttribute("data-controller", "hello")`)

  assert.equal((await runner.snapshot()).text, "Hello, Ada from tiny")
})

test("a dynamic import of a module the importmap lacks fails only when it runs", async () => {
  await runner.load(`<p data-controller="lazy"></p>`)

  assert.equal((await runner.snapshot()).text, "not loaded")
})

test("controllers connect after tasks the page queued while its scripts ran, as when browsers load them with import()", async () => {
  await runner.load(`<script>window.order = []; setTimeout(() => order.push("page task"), 0)</script><p data-controller="hello"></p><script>new MutationObserver(() => order.push(document.querySelector("p").textContent ? "connected" : "")).observe(document.querySelector("p"), { childList: true })</script>`)

  assert.deepEqual(await runner.evaluate("order"), ["page task", "connected"])
})

test("controllers on a page connect in the order of their files, not of the page, as stimulus-loading imports them", async () => {
  await runner.load(`<p id="h" data-controller="hello"></p><p id="u" data-controller="admin--user-panel"></p><script>
    window.order = []
    new MutationObserver(records => records.forEach(record => order.push(record.target.id))).observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ["data-connected"] })
  </script>`)

  assert.deepEqual(await runner.evaluate("order"), ["u", "h"])
})
