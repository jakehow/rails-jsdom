"use strict"

const path = require("node:path")
const readline = require("node:readline")
const { EventEmitter } = require("node:events")
const { PassThrough } = require("node:stream")
const { start } = require("../../lib/rails_jsdom/runtime.js")

const APP = path.join(__dirname, "fixtures", "app")
const HOST = "http://app.test"
const NO_CABLE = () => null

const SETUP = {
  command: "setup",
  root: APP,
  controllers: path.join(APP, "app/javascript/controllers"),
  modules: {
    "@hotwired/stimulus": path.join(APP, "vendor/stimulus.js"),
    "@hotwired/turbo-rails": path.join(APP, "vendor/turbo.js")
  },
  stubs: ["remote-analytics"],
  directories: { lib: path.join(APP, "app/javascript/lib") },
  horizon: 1000,
  hidden: "[hidden], template, script, style, noscript, dialog:not([open]), [style*='display: none'], [style*='display:none']"
}

function document(body, title = "Page") {
  return `<!DOCTYPE html><html><head><title>${title}</title></head><body>${body}</body></html>`
}

function html(url, body, title) {
  return { status: 200, headers: { "content-type": "text/html" }, body: document(body, title), url, redirected: false }
}

function fakeProcess() {
  const io = new EventEmitter()
  io.stdin = new PassThrough()
  io.stdout = new PassThrough()
  io.stderr = new PassThrough()
  io.exits = []
  io.exit = code => io.exits.push(code)
  io.logged = ""
  io.stderr.on("data", chunk => { io.logged += chunk })
  return io
}

function answerFetch(runner, message) {
  if (message.request.kind === "cable") return runner.reply(message.id, runner.cable(message.request, message), runner.sync(message))
  runner.requests.push(message.request)
  const route = runner.routes[`${message.request.method} ${message.request.url}`]
  if (route === "hold") runner.held.push(message)
  else runner.reply(message.id, route ?? { status: 404, headers: {}, body: "missing", url: message.request.url, redirected: false })
}

function connect() {
  const io = fakeProcess()
  start(io)
  const runner = client(io)
  readline.createInterface({ input: io.stdout }).on("line", line => {
    const message = JSON.parse(line)
    if (message.type === "fetch") answerFetch(runner, message)
    else runner.waiting.shift()(message)
  })
  return runner
}

function client(io) {
  const runner = {
    io,
    waiting: [],
    requests: [],
    held: [],
    routes: {},
    cable: NO_CABLE, logged: () => io.logged, frames: [], deadline: null, sync: message => queuedSync(runner, message),
    send: message => io.stdin.write(`${JSON.stringify(message)}\n`),
    call: message => new Promise(resolve => {
      runner.waiting.push(resolve)
      runner.send(message)
    }),
    async run(message) {
      const reply = await runner.call(message)
      if (reply.type === "error") throw new Error(reply.message)
      return reply.value
    },
    reply: (id, response, sync) => runner.send({ type: "fetch_response", id, response, sync }),
    load: (body, url = `${HOST}/`, title) => runner.run({ command: "load", html: document(body, title), url, history: "push" }),
    evaluate: script => runner.run({ command: "evaluate", script }),
    snapshot: (scope = []) => runner.run({ command: "snapshot", scope })
  }
  return runner
}

function queuedSync(runner, message) {
  return { epoch: 0, now: message.clock, deadline: runner.deadline, frames: runner.frames.splice(0) }
}

function bodyText(request) {
  return Buffer.from(request.body, "base64").toString()
}

async function prepare(runner) {
  await runner.run(SETUP)
}

async function clear(runner) {
  await runner.run({ command: "reset" })
  runner.requests.length = 0
  runner.held.length = 0
  runner.routes = {}
  runner.cable = NO_CABLE
  runner.frames = []
  runner.deadline = null
  runner.sync = message => queuedSync(runner, message)
}

module.exports = { HOST, SETUP, bodyText, connect, document, html, prepare, clear }
