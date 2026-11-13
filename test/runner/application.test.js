"use strict"

const path = require("node:path")
const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { SETUP, connect, clear } = require("./support")

const runner = connect()
const modules = { ...SETUP.modules, application: path.join(SETUP.root, "app/javascript/application.js") }

before(() => runner.run({ ...SETUP, modules }))
beforeEach(() => clear(runner))

test("the app's application module runs on every page", async () => {
  await runner.load("<p>Page</p>")

  assert.equal(await runner.evaluate("window.Current.greeting"), "Hello, the app entry")
})

test("controllers connect on the Stimulus application the app started", async () => {
  await runner.load(`<p data-controller="hello"></p>`)
  const result = await runner.evaluate("window.Stimulus === window.AppStimulus")

  assert.deepEqual([result, (await runner.snapshot()).text], [true, "Hello, Ada from tiny"])
})

test("a controller error on the app's Stimulus application fails the action", async () => {
  await assert.rejects(runner.load(`<p data-controller="broken"></p>`), /Error connecting broken: Error: broken controller/)
})

test("a bare pin directory name imports that directory's index", async () => {
  await runner.load("<p>Page</p>")

  assert.equal(await runner.evaluate("window.LibIndexLoaded"), true)
})
