"use strict"

const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { HOST, connect, html, prepare, clear } = require("./support")

const runner = connect()

before(() => prepare(runner))
beforeEach(() => clear(runner))

const EPOCH = 1700000000000
const sync = (now, extra = {}) => ({ epoch: EPOCH, now, deadline: null, frames: [], ...extra })
const evaluate = (script, now = 0, extra = {}) => runner.run({ command: "evaluate", script, sync: sync(now, extra) })
const opening = (record = () => {}) => (request, message) => {
  record(message, request)
  return request.action === "open" ? { protocol: "actioncable-v1-json" } : null
}
const later = (delay, expression) => `new Promise(resolve => setTimeout(() => resolve(${expression}), ${delay}))`

test("the page's Date starts at the epoch Ruby sends", async () => {
  await runner.load("<p>Clock</p>")

  assert.equal(await evaluate("Date.now()"), EPOCH)
})

test("the page's Date follows the virtual clock", async () => {
  await runner.load("<p>Clock</p>")

  assert.deepEqual(await evaluate(later(500, "[Date.now(), new Date().getTime()]")), [EPOCH + 500, EPOCH + 500])
})

test("Date called as a function gives a string, and with arguments the date they name", async () => {
  await runner.load("<p>Clock</p>")

  assert.deepEqual(await evaluate("[typeof Date(), new Date(0).getTime(), new Date(2020, 0, 1).getFullYear(), new Date() instanceof Date]"), ["string", 0, 2020, true])
})

test("a page class that extends Date keeps working", async () => {
  await runner.load("<p>Clock</p>")

  assert.deepEqual(await evaluate("(() => { class Stamp extends Date { label() { return 'at ' + this.getTime() } }; const stamp = new Stamp(); return [stamp instanceof Stamp, stamp.label()] })()"), [true, `at ${EPOCH}`])
})

test("performance.now counts the virtual clock", async () => {
  await runner.load("<p>Clock</p>")

  assert.equal(await evaluate(later(250, "performance.now()")), 250)
})

test("every message to Ruby carries the page's clock", async () => {
  runner.routes[`GET ${HOST}/a`] = html(`${HOST}/a`, "")
  await runner.load("<p>Clock</p>")
  const clocks = []
  runner.cable = opening(message => clocks.push(message.clock))
  await evaluate(later(300, "new WebSocket('/cable')"))

  assert.deepEqual(clocks, [300])
})

test("when Ruby's time is ahead, the page catches up before the action, running the timers due on the way in order", async () => {
  await runner.load("<script>window.fired = []; setTimeout(() => fired.push(Date.now()), 5000); setTimeout(() => fired.push(Date.now()), 2000)</script>")

  assert.deepEqual(await evaluate("fired.concat(Date.now())", 10000), [EPOCH + 2000, EPOCH + 5000, EPOCH + 10000])
})

test("catching up to Ruby's time runs no timer due after it", async () => {
  await runner.load("<script>window.fired = false; setTimeout(() => { fired = true }, 3000)</script>")
  await runner.run({ command: "catch_up", sync: sync(2000) })

  assert.equal(await evaluate("fired", 2000), false)
})

test("a time Ruby sends while the page settles moves its clock forward too", async () => {
  runner.routes[`GET ${HOST}/a`] = html(`${HOST}/a`, "")
  await runner.load("<p>Clock</p>")
  runner.cable = opening()
  runner.sync = () => sync(4000)
  const now = await evaluate(`new Promise(resolve => { new WebSocket('/cable'); setTimeout(() => resolve(Date.now()), 3500) })`, 0)

  assert.equal(now - EPOCH, 3500)
})

test("a second time ahead from Ruby while the page catches up takes the later one", async () => {
  await runner.load("<p>Clock</p>")
  runner.cable = opening()
  runner.sync = () => sync(6000)
  await evaluate("new WebSocket('/cable')", 1000)

  assert.equal(await evaluate("Date.now()", 6000), EPOCH + 6000)
})

test("a time from Ruby behind the page's leaves its clock where it is", async () => {
  await runner.load("<p>Clock</p>")
  await evaluate(later(400, "1"))

  assert.equal(await evaluate("performance.now()", 100), 400)
})

test("Ruby's timers tick before page timers due after them", async () => {
  await runner.load("<p>Clock</p>")
  const ticks = []
  runner.cable = opening((message, request) => { if (request.action === "tick") ticks.push(message.clock) })
  runner.sync = message => sync(message.clock, { deadline: message.clock < 300 ? 300 : null })
  await evaluate("new WebSocket('/cable')")
  const fired = await evaluate(later(500, "performance.now()"), 0, { deadline: 300 })

  assert.deepEqual([ticks, fired], [[300], 500])
})

test("Ruby's timers tick on the way to a time Ruby is ahead to", async () => {
  await runner.load("<p>Clock</p>")
  const ticks = []
  runner.cable = (request, message) => { if (request.action === "tick") ticks.push(message.clock) }
  await evaluate("1", 5000, { deadline: 3000 })

  assert.deepEqual(ticks, [3000])
})

test("Ruby's timers due after the horizon wait", async () => {
  await runner.load("<p>Clock</p>")
  const ticks = []
  runner.cable = request => { if (request.action === "tick") ticks.push(request) }
  await evaluate(later(500, "1"), 0, { deadline: 3000 })

  assert.deepEqual(ticks, [])
})

test("a timer that fell due while another session ran runs before that session's next action", async () => {
  await runner.load("<script>window.fired = false; setTimeout(() => { fired = true }, 2000)</script>")
  await runner.run({ command: "session", name: "other" })
  await runner.load("<p>Other</p>")
  await evaluate("1", 3000)
  await runner.run({ command: "session", name: "default" })

  assert.equal(await evaluate("fired", 3000), true)
})

test("catching up without a page does nothing", async () => {
  assert.equal(await runner.run({ command: "catch_up", sync: sync(1000) }), null)
})

test("a reset starts the clock again at zero", async () => {
  await runner.load("<p>Clock</p>")
  await evaluate(later(700, "1"))
  await clear(runner)
  await runner.load("<p>Clock</p>")

  assert.equal(await runner.evaluate("performance.now()"), 0)
})
