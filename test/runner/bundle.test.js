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

test("a dynamic import of a module the importmap lacks fails only when it runs", async () => {
  await runner.load(`<p data-controller="lazy"></p>`)

  assert.equal((await runner.snapshot()).text, "not loaded")
})
