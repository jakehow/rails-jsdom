"use strict"

const path = require("node:path")
const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { SETUP, connect, clear } = require("./support")

const APP = path.join(__dirname, "fixtures", "bundled")
const runner = connect()

before(() => runner.run({
  ...SETUP,
  root: APP,
  controllers: null,
  entry: path.join(APP, "app/javascript/application.js"),
  esbuild: path.join(APP, "esbuild.config.mjs"),
  modules: {},
  stubs: [],
  directories: {}
}))
beforeEach(() => clear(runner))

test("the entry runs on every page, bundled with the app's esbuild config", async () => {
  await runner.load("<p>Page</p>")

  assert.deepEqual(await runner.evaluate("window.Current"), { greeting: "Hello from a plugin", builtBy: "the app's esbuild config" })
})

test("a controller the entry registers connects once", async () => {
  await runner.load(`<p data-controller="counter"></p>`)

  assert.match((await runner.snapshot()).html, /data-connections="1"/)
})

test("a controller error on the entry's Stimulus application fails the action", async () => {
  await assert.rejects(runner.load(`<p data-controller="broken"></p>`), /Error connecting broken: Error: broken controller/)
})

test("a dynamic import of a package is bundled from node_modules", async () => {
  await runner.load(`<p data-controller="lazy" data-module="package"></p>`)

  assert.equal((await runner.snapshot()).text, "loaded from node_modules")
})

test("a dynamic import of a URL is left to load when it runs", async () => {
  await runner.load(`<p data-controller="lazy" data-module="url"></p>`)

  assert.equal((await runner.snapshot()).text, "not loaded")
})
