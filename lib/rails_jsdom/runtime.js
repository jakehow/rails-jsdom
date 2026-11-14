"use strict"

const fs = require("node:fs")
const path = require("node:path")
const readline = require("node:readline")
const vm = require("node:vm")
const { createRequire } = require("node:module")

const STUB_NAMESPACE = "rails-jsdom-stub"
const STUB_SOURCE = "module.exports = Object.create(new Proxy({}, { get: (target, key) => typeof key === 'symbol' || key === 'then' || key === '__esModule' ? undefined : () => {} }))"
const STIMULUS_LOADING = "@hotwired/stimulus-loading"
const INLINE_ELEMENTS = new Set(["a", "abbr", "b", "bdi", "bdo", "cite", "code", "data", "dfn", "em", "i", "kbd", "label", "mark", "output", "q", "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u", "var"])
const CLICKABLE = "button, input[type=submit], input[type=button], input[type=reset], input[type=image], input[type=checkbox], input[type=radio], a[href], summary, label, [role=button]"
const BUTTON_INPUTS = "input[type=submit], input[type=button], input[type=reset], input[type=image]"
const FIELDS = "input:not([type=hidden]), textarea, select"
const FILLABLE = "input:not([type=hidden], [type=checkbox], [type=radio], [type=file], [type=submit], [type=button], [type=reset], [type=image]), textarea"
const KINDS = { link: "a[href]", button: `button, ${BUTTON_INPUTS}`, link_or_button: `a[href], button, ${BUTTON_INPUTS}` }
const DIALOG_HANDLERS = { alert: "accept_alert", confirm: "accept_confirm or dismiss_confirm", prompt: "accept_prompt or dismiss_prompt" }
const UNANSWERED = { alert: undefined, confirm: false, prompt: null }
const QUERY_KINDS = { css: "*", field: FIELDS, button: KINDS.button, link: KINDS.link }
const FOCUSABLE = "a[href], button, input:not([type=hidden]), select, textarea, [tabindex], [contenteditable]"
const PRESSABLE = "button, input[type=checkbox], input[type=radio], input[type=submit], input[type=button], input[type=reset]"
const STEPPABLE = "input[type=range], input[type=number]"
const KEYS = { enter: "Enter", return: "Enter", tab: "Tab", backspace: "Backspace", delete: "Delete", escape: "Escape", space: " ", left: "ArrowLeft", right: "ArrowRight", up: "ArrowUp", down: "ArrowDown", home: "Home", end: "End", page_up: "PageUp", page_down: "PageDown", arrow_left: "ArrowLeft", arrow_right: "ArrowRight", arrow_up: "ArrowUp", arrow_down: "ArrowDown" }
const MODIFIERS = { shift: "shiftKey", control: "ctrlKey", ctrl: "ctrlKey", alt: "altKey", meta: "metaKey", command: "metaKey" }
const NULL_BODY_STATUSES = new Set([101, 103, 204, 205, 304])
const SETTLE_LIMIT = 10000
const MEASUREMENT_LIMIT = 10000
const LAYOUT_LOOP = `RailsJsdom: the page measured element positions ${MEASUREMENT_LIMIT} times without its event loop moving on. jsdom has no layout, so every element and range measures 0x0 at 0,0, and code that waits for a real measurement, such as positioning a menu or popover at the caret, never gets one and repeats forever. If the test does not depend on where things are, give the elements involved a box with stub_layout in that test; otherwise test this behaviour in a system test.`
const LOADABLE = "link[rel~=stylesheet], img[src]:not([src=\"\"])"

const replies = new Map()
const fetchStubs = new Map()
const pending = new Set()
const errors = []
const owners = new WeakMap()
let nextFetchId = 1
let nextPageId = 1
let nextObjectUrl = 1
let nextSocketId = 1
let measurements = 0
const time = { now: 0, epoch: 0, target: null, deadline: null }
let inbox = []
let config = null
let jsdom = null
let wrappers = null
let bundle = null
let page = null
const sessions = new Map()
let session = sessionNamed("default")
let modal = null
let modalMessages = []
let chooser = null
const requests = new WeakMap()

let output = null
const send = message => output.write(`${JSON.stringify({ ...message, clock: time.now })}\n`)
const tick = () => new Promise(resolve => setTimeout(resolve, 0))
let typing = 0
const turn = () => new Promise(resolve => setImmediate(resolve))
const pause = busy => (busy ? turn() : tick())
const normalize = text => String(text ?? "").replace(/\s+/g, " ").trim()

let queue = Promise.resolve()

function start(io) {
  output = io.stdout
  for (const method of ["log", "info", "warn", "error", "debug"]) {
    console[method] = (...args) => io.stderr.write(`${args.map(String).join(" ")}\n`)
  }
  io.on("unhandledRejection", reason => errors.push(reason))
  const input = readline.createInterface({ input: io.stdin })
  input.on("line", line => {
    const message = JSON.parse(line)
    if (message.type === "fetch_response") {
      if (message.sync) applySync(message.sync)
      const resolve = replies.get(message.id)
      replies.delete(message.id)
      resolve(message.response)
    } else {
      queue = queue.then(() => handle(message))
    }
  })
  input.on("close", () => io.exit(0))
}

async function handle(message) {
  try {
    send({ type: "result", value: await perform(message) })
  } catch (error) {
    send({ type: "error", message: describeError(error) })
  }
}

function describeError(error) {
  return error && error.stack ? String(error.stack) : String(error)
}

const READS = {
  setup: message => setup(message),
  snapshot: message => snapshot(message.scope),
  query: message => query(message),
  read: message => describe(elementFor(message.handle)),
  session: message => switchSession(message.name),
  stub_fetch: message => stubFetch(message.url, message.response),
  stub_layout: message => stubLayout(message.selector, message.box),
  reset: () => reset(),
  expect_modal: message => expectModal(message),
  modal_messages: () => takeModalMessages(),
  expect_file_chooser: message => expectFileChooser(message.files),
  file_chooser_opened: () => takeFileChooser()
}

const ACTIONS = {
  load: message => loadFresh(message.html, message.url, message.history),
  click: message => click(find(message, byClickable, KINDS[message.kind])),
  hover: message => hover(find(message, byClickable)),
  double_click: message => doubleClick(find(message, byClickable)),
  right_click: message => rightClick(find(message, byClickable)),
  fill_in: message => fill(find(message, byField, FILLABLE), message.with),
  check: message => setChecked(find(message, byField, "input[type=checkbox]"), message.checked),
  choose: message => setChecked(find(message, byField, "input[type=radio]"), true),
  select: message => selectOption(message),
  attach: message => attachFiles(find(message, byField, "input[type=file]"), message.files),
  send_keys: message => sendKeys(null, message.keys),
  element: message => elementAction(message),
  traverse: message => traverse(message.delta),
  evaluate: message => evaluate(message),
  settle: () => null,
  catch_up: null
}

async function perform(message) {
  if (message.sync) applySync(message.sync)
  if (READS[message.command]) return READS[message.command](message)
  if (!Object.hasOwn(ACTIONS, message.command)) throw new Error(`RailsJsdom: unknown command ${message.command}`)
  errors.length = 0
  await catchUp()
  const value = ACTIONS[message.command] ? await act(ACTIONS[message.command], message) : null
  if (errors.length > 0) throw new Error(errors.splice(0).map(describeError).join("\n\n"))
  return value === undefined ? null : JSON.parse(JSON.stringify(value) ?? "null")
}

async function act(action, message) {
  let state = "running"
  const outcome = Promise.resolve().then(() => action(message)).then(value => { state = "done"; return value }, error => { state = "failed"; throw error })
  outcome.catch(() => {})
  await settle(() => state, config.horizon)
  return await outcome
}

async function catchUp() {
  if (page && (inbox.length > 0 || time.target !== null || page.clock.due(time.now))) await settle(() => "done", 0)
}

function stubFetch(url, response) {
  fetchStubs.set(url, response)
  return null
}

function stubLayout(selector, box) {
  if (!page) throw new Error("RailsJsdom: visit a page or mount a partial first")
  page.layoutStubs.push({ selector, box })
  return null
}

function loadFresh(html, url, history) {
  fetchStubs.clear()
  return load(html, url, history)
}

async function setup(message) {
  config = message
  const appRequire = createRequire(path.join(config.root, "package.json"))
  jsdom = appRequire("jsdom")
  wrappers = appRequire("jsdom/lib/generated/idl/utils.js")
  const esbuild = appRequire("esbuild")
  const result = await esbuild.build({
    stdin: { contents: entrySource(), resolveDir: config.root, sourcefile: "rails-jsdom-entry.js", loader: "js" },
    bundle: true,
    write: false,
    format: "iife",
    globalName: "RailsJsdomBundle",
    logLevel: "silent",
    plugins: [importmapPlugin()]
  })
  bundle = new vm.Script(result.outputFiles[0].text, { filename: "rails-jsdom-bundle.js" })
  return {}
}

function controllerFiles(directory, prefix) {
  return fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name)).flatMap(entry => {
    if (entry.isDirectory()) return controllerFiles(path.join(directory, entry.name), `${prefix}${entry.name}/`)
    return entry.name.endsWith("_controller.js") ? [[`${prefix}${entry.name}`, path.join(directory, entry.name)]] : []
  })
}

function identifierFor(relative) {
  return relative.replace(/_controller\.js$/, "").replace(/\//g, "--").replace(/_/g, "-")
}

function entrySource() {
  const files = controllerFiles(config.controllers, "")
  return [
    "import \"@hotwired/turbo-rails\"",
    "export { Application } from \"@hotwired/stimulus\"",
    ...files.map(([, file], index) => `import controller${index} from ${JSON.stringify(file)}`),
    `export const controllers = { ${files.map(([relative], index) => `${JSON.stringify(identifierFor(relative))}: controller${index}`).join(", ")} }`,
    ...(config.modules.application ? ["import \"application\""] : [])
  ].join("\n")
}

function importmapPlugin() {
  return {
    name: "rails-jsdom-importmap",
    setup(build) {
      build.onResolve({ filter: /^[^./]/ }, args => resolveImport(args.path) ?? unresolvedImport(args))
      build.onLoad({ filter: /.*/, namespace: STUB_NAMESPACE }, () => ({ contents: STUB_SOURCE, loader: "js" }))
    }
  }
}

function unresolvedImport(args) {
  return args.kind === "dynamic-import" ? { path: args.path, external: true } : undefined
}

function resolveImport(specifier) {
  const directory = Object.keys(config.directories).find(prefix => specifier.startsWith(`${prefix}/`))
  if (specifier === STIMULUS_LOADING || config.stubs.includes(specifier)) return { path: specifier, namespace: STUB_NAMESPACE }
  if (config.modules[specifier]) return { path: config.modules[specifier] }
  if (config.directories[specifier]) return { path: path.join(config.directories[specifier], "index.js") }
  if (directory) return { path: `${path.join(config.directories[directory], specifier.slice(directory.length + 1))}.js` }
  return undefined
}

class Clock {
  constructor() {
    this.sequence = 0
    this.timers = new Map()
  }

  get now() {
    return time.now
  }

  install(window) {
    window.setTimeout = (callback, delay, ...args) => this.schedule(callback, delay, args, false)
    window.setInterval = (callback, delay, ...args) => this.schedule(callback, delay, args, true)
    window.requestAnimationFrame = callback => this.schedule(() => callback(this.now), 0, [], false)
    window.clearTimeout = window.clearInterval = window.cancelAnimationFrame = id => { this.timers.delete(id) }
    addVirtualTime(window)
  }

  schedule(callback, delay, args, repeat) {
    const wait = Math.max(repeat ? 4 : 0, Number(delay) || 0)
    this.sequence += 1
    this.timers.set(this.sequence, { callback, args, at: this.now + wait, every: repeat ? wait : 0, order: this.sequence })
    return this.sequence
  }

  due(limit) {
    let next = null
    for (const entry of this.timers) {
      const timer = entry[1]
      if (timer.at <= limit && (!next || timer.at < next[1].at || (timer.at === next[1].at && timer.order < next[1].order))) next = entry
    }
    return next
  }

  run([id, timer]) {
    measurements = 0
    time.now = Math.max(time.now, timer.at)
    if (timer.every) {
      this.sequence += 1
      timer.at += timer.every
      timer.order = this.sequence
    } else {
      this.timers.delete(id)
    }
    try {
      if (typeof timer.callback === "function") timer.callback(...timer.args)
    } catch (error) {
      errors.push(error)
    }
  }
}

async function settle(status, ahead) {
  let idle = 0
  let horizon = null
  let progress = 0
  for (let round = 0; idle < 3; round += 1) {
    if (progress > SETTLE_LIMIT) throw notSettled()
    await pause(idle === 0 && round > 0)
    if (status() === "failed" || !page) return
    horizon = horizonFor(horizon, ahead)
    const busy = await advance(reachable(horizon))
    progress += Number(busy)
    idle = busy || status() !== "done" ? 0 : idle + 1
  }
  reachTarget()
}

function reachable(horizon) {
  return typing > 0 ? -Infinity : horizon.limit
}

function notSettled() {
  return new Error("RailsJsdom: the page did not settle")
}

function horizonFor(previous, ahead) {
  const limit = previous && previous.page === page ? previous.limit : time.now + ahead
  return { page, limit: Math.max(limit, time.target ?? limit) }
}

async function advance(limit) {
  measurements = 0
  if (pending.size > 0) {
    await Promise.race(pending)
    return true
  }
  if (deliverInbox()) return true
  const timer = page.clock.due(limit)
  if (time.deadline !== null && time.deadline <= (timer ? timer[1].at : time.target ?? time.now)) {
    await tickRails()
    return true
  }
  if (timer) page.clock.run(timer)
  return Boolean(timer)
}

function applySync(sync) {
  time.epoch = sync.epoch
  time.deadline = sync.deadline
  if (sync.now > time.now) time.target = Math.max(time.target ?? sync.now, sync.now)
  inbox.push(...sync.frames)
}

function reachTarget() {
  if (time.target === null) return
  time.now = Math.max(time.now, time.target)
  time.target = null
}

function deliverInbox() {
  if (inbox.length === 0) return false
  for (const frame of inbox.splice(0)) deliverFrame(page.sockets.get(frame.socket), frame)
  return true
}

async function tickRails() {
  time.now = Math.max(time.now, time.deadline)
  time.deadline = null
  await requestRails({ kind: "cable", action: "tick" })
}

function deliverFrame(socket, frame) {
  if (socket && frame.closed) socket.closed(frame.code)
  else if (socket) socket.received(frame.data)
}

const socketContexts = new WeakMap()

function cableSocketClass(window, owner) {
  class WebSocket extends window.EventTarget {
    constructor(url, protocols = []) {
      super()
      socketContexts.set(this, { window, owner })
      openSocket(this, socketUrl(window, url), [].concat(protocols))
    }
  }
  Object.assign(WebSocket.prototype, SOCKET_METHODS)
  return Object.assign(WebSocket, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 })
}

function socketUrl(window, url) {
  const resolved = new window.URL(url, window.location.href)
  resolved.protocol = resolved.protocol.replace(/^http/, "ws")
  return resolved.href
}

function openSocket(socket, url, protocols) {
  Object.assign(socket, { url, readyState: 0, protocol: "", extensions: "", binaryType: "blob", bufferedAmount: 0, onopen: null, onmessage: null, onclose: null, onerror: null, id: `${process.pid}:${nextSocketId}` })
  nextSocketId += 1
  socketContexts.get(socket).owner.sockets.set(socket.id, socket)
  requestRails({ kind: "cable", action: "open", socket: socket.id, url, protocols }).then(reply => socket.opened(reply))
}

const SOCKET_METHODS = {
  opened(reply) {
    const { window } = socketContexts.get(this)
    if (this.readyState !== 0) return
    if (reply.error) {
      this.fire(new window.Event("error"))
      this.closed(1006)
    } else {
      Object.assign(this, { readyState: 1, protocol: reply.protocol })
      this.fire(new window.Event("open"))
    }
  },

  send(data) {
    if (this.readyState !== 1) throw new (socketContexts.get(this).window.DOMException)("The WebSocket is not open", "InvalidStateError")
    requestRails({ kind: "cable", action: "send", socket: this.id, data: String(data) })
  },

  close(code = 1000) {
    if (this.readyState > 1) return
    this.readyState = 2
    requestRails({ kind: "cable", action: "close", socket: this.id }).then(() => this.closed(code))
  },

  received(data) {
    if (this.readyState === 1) this.fire(new (socketContexts.get(this).window.MessageEvent)("message", { data }))
  },

  closed(code) {
    const { window, owner } = socketContexts.get(this)
    if (this.readyState === 3) return
    this.readyState = 3
    owner.sockets.delete(this.id)
    this.fire(new window.CloseEvent("close", { code, wasClean: code === 1000 }))
  },

  fire(event) {
    this.dispatchEvent(event)
    const handler = this[`on${event.type}`]
    if (typeof handler === "function") handler.call(this, event)
  }
}

function track(promise) {
  pending.add(promise)
  const forget = () => pending.delete(promise)
  promise.then(forget, forget)
  return promise
}

function requestRails(request) {
  const id = nextFetchId
  nextFetchId += 1
  return track(new Promise(resolve => {
    replies.set(id, resolve)
    send({ type: "fetch", id, request })
  }))
}

function sessionNamed(name) {
  if (!sessions.has(name)) sessions.set(name, { page: null, back: [], forward: [], storage: { localStorage: new Map(), sessionStorage: new Map() } })
  return sessions.get(name)
}

function switchSession(name) {
  session = sessionNamed(name)
  page = session.page
  return null
}

function load(html, url, history = "push") {
  const previous = page
  if (previous) keepStorage(previous.window, session.storage)
  if (history === "push" && previous) pushHistory(previous.window.location.href)
  const current = { id: nextPageId, clock: new Clock(), closed: false, position: 0, length: 1, handles: new Map(), ids: new WeakMap(), nextHandle: 0, edited: new Map(), sockets: new Map(), layoutStubs: [] }
  nextPageId += 1
  const report = error => { if (page === current) errors.push(error) }
  session.page = current
  page = current
  current.dom = new jsdom.JSDOM(html, {
    url,
    runScripts: "dangerously",
    pretendToBeVisual: true,
    virtualConsole: pageConsole(report),
    beforeParse: window => prepare(window, current)
  })
  current.window = current.dom.window
  bundle.runInContext(current.dom.getInternalVMContext())
  boot(current.window, report)
  if (previous) close(previous)
  return current.id
}

function pushHistory(url) {
  session.back.push(url)
  session.forward = []
}

function pageConsole(report) {
  const virtualConsole = new jsdom.VirtualConsole()
  virtualConsole.forwardTo(console, { jsdomErrors: "none" })
  virtualConsole.on("jsdomError", error => { if (error.type !== "css-parsing") report(error) })
  return virtualConsole
}

async function evaluate(message) {
  if (message.kind === undefined) return await page.window.eval(message.script)
  const body = message.kind === "expression" ? `return (${message.script}\n)` : message.script
  const receiver = message.receiver === null ? page.window : elementFor(message.receiver)
  return await new page.window.Function(body).apply(receiver, message.args.map(scriptArgument))
}

function scriptArgument(value) {
  return value !== null && typeof value === "object" && "rails_jsdom_element" in value ? elementFor(value.rails_jsdom_element) : value
}

function reset() {
  for (const each of sessions.values()) if (each.page) close(each.page, false)
  sessions.clear()
  session = sessionNamed("default")
  page = null
  modal = null
  modalMessages = []
  chooser = null
  errors.length = 0
  fetchStubs.clear()
  replies.clear()
  pending.clear()
  inbox = []
  Object.assign(time, { now: 0, epoch: 0, target: null, deadline: null })
  return null
}

function keepStorage(window, storage) {
  for (const [area, entries] of Object.entries(storage)) {
    entries.clear()
    for (let index = 0; index < window[area].length; index += 1) entries.set(window[area].key(index), window[area].getItem(window[area].key(index)))
  }
}

function restoreStorage(window, storage) {
  for (const [area, entries] of Object.entries(storage)) for (const [key, value] of entries) window[area].setItem(key, value)
}

function close(target, notify = true) {
  target.closed = true
  for (const socket of target.sockets.values()) notify ? socket.close() : socket.closed(1001)
  target.clock.timers.clear()
  if (target.window) target.window.close()
}

function prepare(window, current) {
  owners.set(window, current)
  restoreStorage(window, session.storage)
  current.clock.install(window)
  trackHistory(window, current)
  window.fetch = (resource, init) => owners.get(window).closed ? new Promise(() => {}) : track(pageFetch(window, resource, init ?? {}))
  addXMLHttpRequest(window)
  openFileChoosers(window)
  window.WebSocket = cableSocketClass(window, current)
  window.alert = message => dialog("alert", message)
  window.confirm = message => dialog("confirm", message)
  window.prompt = (message, defaultValue) => dialog("prompt", message, defaultValue)
  window.HTMLFormElement.prototype.submit = function () { submitNatively(this, null) }
  stubMissingBrowserApis(window)
  addMessageChannel(window, current.clock)
  addClipboardData(window, current.clock)
  fireResourceLoads(window, current.clock)
}

function addVirtualTime(window) {
  const RealDate = window.Date
  const current = () => time.epoch + time.now
  function VirtualDate(...args) {
    if (!new.target) return new RealDate(current()).toString()
    return Reflect.construct(RealDate, args.length === 0 ? [current()] : args, new.target)
  }
  Object.setPrototypeOf(VirtualDate, RealDate)
  VirtualDate.prototype = RealDate.prototype
  VirtualDate.now = () => Math.floor(current())
  window.Date = VirtualDate
  Object.defineProperty(window.performance, "now", { configurable: true, value: () => time.now })
}

function trackHistory(window, current) {
  const pushState = window.history.pushState.bind(window.history)
  window.history.pushState = (...args) => {
    pushState(...args)
    current.position += 1
    current.length = current.position + 1
  }
}

function addFormParticipation(window) {
  const hosts = new WeakMap()
  const states = new WeakMap()
  const attach = window.HTMLElement.prototype.attachInternals
  window.HTMLElement.prototype.attachInternals = function () {
    const internals = attach.call(this)
    hosts.set(internals, this)
    states.set(this, { value: null, validity: { valid: true }, message: "" })
    return internals
  }
  defineInternals(window.ElementInternals.prototype, internals => states.get(hosts.get(internals)), internals => hosts.get(internals))
  window.FormData = formDataWithCustomElements(window.FormData, states)
}

function defineInternals(prototype, state, host) {
  Object.defineProperties(prototype, {
    form: { configurable: true, get() { return owningForm(host(this)) } },
    validity: { configurable: true, get() { return state(this).validity } },
    validationMessage: { configurable: true, get() { return state(this).message } },
    willValidate: { configurable: true, get: () => true }
  })
  prototype.setFormValue = function (value) { state(this).value = value }
  prototype.setValidity = function (flags = {}, message = "") {
    const invalid = Object.values(flags).some(Boolean)
    Object.assign(state(this), { validity: { ...flags, valid: !invalid }, message: invalid ? String(message) : "" })
  }
  prototype.checkValidity = prototype.reportValidity = function () { return state(this).validity.valid }
}

function owningForm(element) {
  const id = element.getAttribute("form")
  return id ? element.ownerDocument.getElementById(id) : element.closest("form")
}

function formDataWithCustomElements(NativeFormData, states) {
  return class FormData extends NativeFormData {
    constructor(form, submitter) {
      super(form, submitter)
      if (form) for (const element of form.ownerDocument.querySelectorAll("[name]")) appendCustomValue(this, element, form, states.get(element))
    }
  }
}

function appendCustomValue(data, element, form, state) {
  if (state && state.value !== null && !element.hasAttribute("disabled") && owningForm(element) === form) data.append(element.getAttribute("name"), state.value)
}

function countMeasurements(prototype, name) {
  const measure = prototype[name]
  prototype[name] = function (...args) {
    measurements += 1
    if (measurements > MEASUREMENT_LIMIT) throw new Error(LAYOUT_LOOP)
    const box = stubbedBox(this)
    return box ? stubbedMeasurement(this, name, box) : measure.apply(this, args)
  }
}

function stubbedBox(target) {
  const node = target.startContainer || target
  const element = node.nodeType === 1 ? node : node.parentElement
  const owner = element && owners.get(element.ownerDocument.defaultView)
  const stub = owner && owner.layoutStubs.find(entry => element.closest(entry.selector))
  return stub ? stub.box : null
}

function stubbedMeasurement(target, name, box) {
  const window = (target.startContainer || target).ownerDocument.defaultView
  const rect = new window.DOMRect(box.left, box.top, box.width, box.height)
  return name === "getClientRects" ? [rect] : rect
}

function addLayoutStubs(window) {
  window.scrollTo = window.scroll = window.scrollBy = () => {}
  window.Element.prototype.scrollIntoView = window.Element.prototype.scrollTo = window.Element.prototype.scroll = window.Element.prototype.scrollBy = () => {}
  window.Element.prototype.checkVisibility = function () { return isVisible(this) }
  window.Range.prototype.getBoundingClientRect = () => new window.DOMRect()
  window.Range.prototype.getClientRects = () => []
  for (const prototype of [window.Element.prototype, window.Range.prototype]) {
    for (const name of ["getBoundingClientRect", "getClientRects"]) countMeasurements(prototype, name)
  }
}

function addFullscreen(window) {
  let fullscreen = null
  const change = target => target.dispatchEvent(new window.Event("fullscreenchange", { bubbles: true }))
  Object.defineProperty(window.Document.prototype, "fullscreenElement", { configurable: true, get: () => fullscreen })
  Object.defineProperty(window.Document.prototype, "fullscreenEnabled", { configurable: true, get: () => true })
  window.Element.prototype.requestFullscreen = function () {
    fullscreen = this
    change(this)
    return Promise.resolve()
  }
  window.Document.prototype.exitFullscreen = function () {
    const previous = fullscreen
    fullscreen = null
    if (previous) change(previous)
    return Promise.resolve()
  }
}

function addContentEditable(window) {
  Object.defineProperty(window.HTMLElement.prototype, "isContentEditable", { configurable: true, get() { return Boolean(editingHost(this)) } })
}

function removeTouchSupport(window) {
  for (const target of [window, window.Document.prototype, window.HTMLElement.prototype, window.SVGElement.prototype]) {
    for (const name of ["ontouchstart", "ontouchend", "ontouchmove", "ontouchcancel"]) deleteFromChain(target, name)
  }
  Object.defineProperty(window.navigator, "maxTouchPoints", { configurable: true, value: 0 })
}

function deleteFromChain(object, name) {
  for (let owner = object; owner; owner = Object.getPrototypeOf(owner)) {
    if (Object.hasOwn(owner, name)) delete owner[name]
  }
}

function stubMissingBrowserApis(window) {
  addFormParticipation(window)
  addContentEditable(window)
  addFullscreen(window)
  removeTouchSupport(window)
  window.Headers = Headers
  window.Request = Request
  window.Response = Response
  window.matchMedia = media => ({ matches: false, media, onchange: null, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent: () => false })
  window.URL.createObjectURL = () => objectUrl(window)
  window.URL.revokeObjectURL = () => {}
  addLayoutStubs(window)
  window.IntersectionObserver = window.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
    takeRecords() { return [] }
  }
  Object.defineProperty(window.navigator, "clipboard", { configurable: true, value: { writeText: async () => {}, readText: async () => "" } })
  addDialogMethods(window)
}

function fireResourceLoads(window, clock) {
  const images = new WeakMap()
  const load = element => {
    if (element.localName === "img" && images.get(element) === element.src) return
    if (element.localName === "img") images.set(element, element.src)
    clock.schedule(() => element.dispatchEvent(new window.Event("load")), 0, [], false)
  }
  new window.MutationObserver(records => records.flatMap(loadedBy).forEach(load)).observe(window.document, { childList: true, subtree: true, attributes: true, attributeFilter: ["src"] })
  const src = Object.getOwnPropertyDescriptor(window.HTMLImageElement.prototype, "src")
  Object.defineProperty(window.HTMLImageElement.prototype, "src", { ...src, set(value) { src.set.call(this, value); if (!this.isConnected && this.matches(LOADABLE)) load(this) } })
}

function loadedBy(record) {
  if (record.type === "attributes") return record.target.matches(LOADABLE) ? [record.target] : []
  return [...record.addedNodes].flatMap(loadablesIn)
}

function loadablesIn(node) {
  if (node.nodeType !== 1) return []
  return [...(node.matches(LOADABLE) ? [node] : []), ...node.querySelectorAll(LOADABLE)]
}

function objectUrl(window) {
  const url = `blob:${window.location.origin}/${nextObjectUrl}`
  nextObjectUrl += 1
  return url
}

function addClipboardData(window, clock) {
  const values = new WeakMap()
  const item = (kind, type, value) => {
    const entry = { kind, type, getAsFile: () => kind === "file" ? value : null, getAsString: callback => { if (kind === "string" && typeof callback === "function") clock.schedule(() => callback(value), 0, [], false) } }
    values.set(entry, value)
    return entry
  }
  window.DataTransfer = class DataTransfer {
    constructor() {
      Object.assign(this, { dropEffect: "none", effectAllowed: "all", items: transferItems(window, item) })
    }

    get types() { return [...new Set(this.items.map(entry => entry.kind === "file" ? "Files" : entry.type))] }

    get files() { return this.items.filter(entry => entry.kind === "file").map(entry => entry.getAsFile()) }

    setData(format, data) {
      this.clearData(format)
      this.items.add(String(data), dataType(format))
    }

    getData(format) { return values.get(this.items.find(entry => entry.kind === "string" && entry.type === dataType(format))) ?? "" }

    clearData(format) { this.items.keep(entry => entry.kind === "file" || (format !== undefined && entry.type !== dataType(format))) }

    setDragImage() {}
  }
  addClipboardEvent(window)
}

function addClipboardEvent(window) {
  window.ClipboardEvent = class ClipboardEvent extends window.Event {
    constructor(type, init = {}) {
      super(type, init)
      this.clipboardData = init.clipboardData ?? null
    }
  }
}

function transferItems(window, item) {
  const list = []
  return Object.assign(list, {
    add: (data, type) => {
      const entry = data instanceof window.File ? item("file", data.type, data) : item("string", String(type).toLowerCase(), String(data))
      list.push(entry)
      return entry
    },
    remove: index => { list.splice(index, 1) },
    clear: () => { list.length = 0 },
    keep: test => { list.splice(0, list.length, ...list.filter(test)) }
  })
}

function dataType(format) {
  const type = String(format).toLowerCase()
  return { text: "text/plain", url: "text/uri-list" }[type] ?? type
}

function addDialogMethods(window) {
  window.HTMLDialogElement.prototype.show = window.HTMLDialogElement.prototype.showModal = function () { this.setAttribute("open", "") }
  window.HTMLDialogElement.prototype.close = function (returnValue) {
    if (returnValue !== undefined) this.returnValue = returnValue
    if (this.hasAttribute("open")) {
      this.removeAttribute("open")
      this.dispatchEvent(new window.Event("close"))
    }
  }
}

function addMessageChannel(window, clock) {
  const peers = new WeakMap()
  const closed = new WeakSet()
  class MessagePort extends window.EventTarget {
    constructor() {
      super()
      this.onmessage = null
    }

    postMessage(message) {
      const data = structuredClone(message)
      if (!closed.has(this)) clock.schedule(() => receiveMessage(window, peers.get(this), data, closed), 0, [], false)
    }

    start() {}

    close() { closed.add(this) }
  }
  window.MessageChannel = class MessageChannel {
    constructor() {
      this.port1 = new MessagePort()
      this.port2 = new MessagePort()
      peers.set(this.port1, this.port2).set(this.port2, this.port1)
    }
  }
}

function receiveMessage(window, port, data, closed) {
  if (closed.has(port)) return
  const event = new window.MessageEvent("message", { data })
  port.dispatchEvent(event)
  if (typeof port.onmessage === "function") port.onmessage(event)
}

function boot(window, report) {
  const { Application, controllers } = window.RailsJsdomBundle
  const application = window.Stimulus instanceof Application ? window.Stimulus : Application.start()
  application.handleError = (error, message) => report(new Error(`${message}: ${describeError(error)}`))
  window.Stimulus = application
  const registered = new Set()
  const register = identifier => {
    registered.add(identifier)
    application.register(identifier, controllers[identifier])
  }
  const discover = (records = [{ target: window.document, type: "attributes" }]) => changedElements(records).flatMap(controllerIdentifiers).filter(identifier => controllers[identifier] && !registered.has(identifier)).forEach(register)
  const present = new Set(controllerIdentifiers(window.document))
  registerInTurn(window, Object.keys(controllers).filter(identifier => present.has(identifier)), register, () => {
    discover()
    new window.MutationObserver(discover).observe(window.document, { subtree: true, childList: true, attributes: true, attributeFilter: ["data-controller"] })
  })
  fallBackLast(window, "click", event => followLink(window, event))
  fallBackLast(window, "submit", event => submitUnhandled(event))
}

function registerInTurn(window, identifiers, register, done) {
  window.setTimeout(() => {
    if (identifiers.length === 0) return done()
    register(identifiers[0])
    registerInTurn(window, identifiers.slice(1), register, done)
  }, 0)
}

function changedElements(records) {
  return records.flatMap(record => record.type === "attributes" ? [record.target] : [...record.addedNodes].filter(node => node.nodeType === 1))
}

function controllerIdentifiers(root) {
  const own = root.nodeType === 1 && root.matches("[data-controller]") ? [root] : []
  return [...own, ...root.querySelectorAll("[data-controller]")].flatMap(element => element.getAttribute("data-controller").split(/\s+/))
}

function fallBackLast(window, type, listener) {
  window.addEventListener(type, () => {
    window.removeEventListener(type, listener)
    window.addEventListener(type, listener)
  }, true)
}

function followLink(window, event) {
  const link = event.target.closest && event.target.closest("a[href]")
  if (event.defaultPrevented || !link || staysInDocument(window, link.href)) return
  event.preventDefault()
  if (!link.hasAttribute("download") && ["", "_self"].includes(link.target) && ["http:", "https:"].includes(new window.URL(link.href).protocol)) navigate({ method: "GET", url: link.href })
}

function staysInDocument(window, href) {
  const target = new window.URL(href)
  const here = new window.URL(window.location.href)
  return href.includes("#") && target.origin === here.origin && target.pathname === here.pathname && target.search === here.search
}

function submitUnhandled(event) {
  if (!event.defaultPrevented) {
    event.preventDefault()
    submitNatively(event.target, event.submitter)
  }
}

function submitNatively(form, submitter) {
  const { window, method, action, data } = submission(form, submitter)
  if (method === "dialog") {
    form.closest("dialog")?.close(submitter?.value)
  } else if (method === "get") {
    action.search = new window.URLSearchParams(textEntries(data)).toString()
    navigate({ method: "GET", url: action.href })
  } else {
    const headers = {}
    const entries = form.enctype === "multipart/form-data" ? [...data] : textEntries(data)
    track(encodeBody(window, entries, headers).then(body => navigate({ method: "POST", url: action.href, body, headers })))
  }
}

function submission(form, submitter) {
  const window = form.ownerDocument.defaultView
  const data = new window.FormData(form)
  if (submitter?.name) data.append(submitter.name, submitter.value)
  return {
    window,
    method: (formSetting(form, submitter, "method") || "get").toLowerCase(),
    action: new window.URL(formSetting(form, submitter, "action") || window.location.href, window.document.baseURI),
    data
  }
}

function formSetting(form, submitter, name) {
  return submitter?.getAttribute(`form${name}`) || form.getAttribute(name)
}

function textEntries(data) {
  return [...data].filter(([, value]) => typeof value === "string")
}

function navigate({ method, url, body = null, headers = {} }, history = "push") {
  requestRails({ method, url, headers: { accept: "text/html,application/xhtml+xml", ...headers }, body }).then(reply => {
    if (reply.error) errors.push(new Error(reply.error))
    else load(reply.body, reply.url, history)
  }).catch(error => errors.push(error))
}

function traverse(delta) {
  if (!page) throw new Error("RailsJsdom: visit a page or mount a partial first")
  const position = page.position + delta
  if (position >= 0 && position < page.length) {
    page.position = position
    page.window.history.go(delta)
    return null
  }
  const url = (delta < 0 ? session.back : session.forward).pop()
  if (url) {
    (delta < 0 ? session.forward : session.back).push(page.window.location.href)
    navigate({ method: "GET", url }, "none")
  }
  return null
}

async function pageFetch(window, resource, init) {
  const url = resourceUrl(window, resource)
  const headers = Object.fromEntries(new Headers(init.headers ?? {}))
  const body = await encodeBody(window, init.body, headers)
  const stub = stubFor(url)
  const reply = stub ? { ...stub, url: url.href, redirected: false } : await requestRails({ method: String(init.method ?? "GET").toUpperCase(), url: url.href, headers, body })
  if (reply.error) throw new TypeError(reply.error)
  return pageResponse(reply)
}

function resourceUrl(window, resource) {
  const address = typeof resource === "object" && "url" in resource ? resource.url : String(resource)
  return new window.URL(address, window.document.baseURI)
}

function stubFor(url) {
  return fetchStubs.get(url.href) || fetchStubs.get(`${url.pathname}${url.search}`)
}

function pageResponse(reply) {
  const response = new Response(NULL_BODY_STATUSES.has(reply.status) ? null : reply.body, { status: reply.status, headers: reply.headers })
  Object.defineProperties(response, { url: { value: reply.url }, redirected: { value: reply.redirected } })
  return response
}

async function encodeBody(window, body, headers) {
  if (body === undefined || body === null) return null
  if (body instanceof window.Blob) return encodeBlob(body, headers)
  if (Array.isArray(body) || body instanceof window.FormData || body instanceof window.URLSearchParams) {
    const entries = [...body]
    if (entries.some(([, value]) => typeof value !== "string")) return multipart(entries, headers)
    headers["content-type"] = "application/x-www-form-urlencoded;charset=UTF-8"
    return Buffer.from(new window.URLSearchParams(entries).toString()).toString("base64")
  }
  return Buffer.from(String(body)).toString("base64")
}

async function encodeBlob(blob, headers) {
  if (blob.type && !headers["content-type"]) headers["content-type"] = blob.type
  return Buffer.from(await blob.arrayBuffer()).toString("base64")
}

function addXMLHttpRequest(window) {
  window.XMLHttpRequest = class XMLHttpRequest extends window.EventTarget {
    constructor() {
      super()
      Object.assign(this, { readyState: 0, status: 0, statusText: "", response: "", responseText: "", responseURL: "", responseType: "", timeout: 0, withCredentials: false, upload: new window.EventTarget() })
      requests.set(this, { headers: {}, responseHeaders: {} })
    }

    open(method, url, async = true) { openRequest(window, this, { method, url, async }) }

    setRequestHeader(name, value) { requests.get(this).headers[String(name).toLowerCase()] = String(value) }

    send(body = null) { track(sendRequest(window, this, body).catch(error => { errors.push(error) })) }

    abort() { requests.get(this).aborted = true }

    getResponseHeader(name) { return requests.get(this).responseHeaders[String(name).toLowerCase()] ?? null }

    getAllResponseHeaders() { return Object.entries(requests.get(this).responseHeaders).map(([name, value]) => `${name}: ${value}\r\n`).join("") }

    overrideMimeType() {}
  }
}

function openRequest(window, xhr, { method, url, async }) {
  if (!async) throw new Error("RailsJsdom: synchronous XMLHttpRequest is not supported")
  if (owners.get(window).closed) return
  Object.assign(requests.get(xhr), { method: String(method).toUpperCase(), url: resourceUrl(window, url), aborted: false })
  xhr.readyState = 1
  fire(window, xhr, "readystatechange")
}

async function sendRequest(window, xhr, body) {
  const request = requests.get(xhr)
  if (owners.get(window).closed) return
  const headers = { ...request.headers }
  const encoded = await encodeBody(window, body, headers)
  const stub = stubFor(request.url)
  const reply = stub ? { ...stub, url: request.url.href } : await requestRails({ method: request.method, url: request.url.href, headers, body: encoded })
  if (request.aborted) return
  if (body !== null) for (const type of ["progress", "load", "loadend"]) fire(window, xhr.upload, type, Buffer.byteLength(encoded, "base64"))
  if (reply.error) finishRequest(window, xhr, { status: 0, url: "", headers: {}, body: "" }, "error")
  else finishRequest(window, xhr, reply, "load")
}

function finishRequest(window, xhr, reply, outcome) {
  const text = String(reply.body ?? "")
  requests.get(xhr).responseHeaders = Object.fromEntries(Object.entries(reply.headers).map(([name, value]) => [name.toLowerCase(), value]))
  Object.assign(xhr, { readyState: 4, status: reply.status, responseURL: reply.url, responseText: text, response: responseFor(window, xhr.responseType, text) })
  for (const type of ["readystatechange", outcome, "loadend"]) fire(window, xhr, type, text.length)
}

function responseFor(window, type, text) {
  if (type === "json") return text === "" ? null : window.JSON.parse(text)
  if (type === "" || type === "text") return text
  throw new Error(`RailsJsdom: XMLHttpRequest responseType "${type}" is not supported`)
}

function fire(window, target, type, size = 0) {
  const event = type === "readystatechange" ? new window.Event(type) : new window.ProgressEvent(type, { lengthComputable: true, loaded: size, total: size })
  target.dispatchEvent(event)
  if (typeof target[`on${type}`] === "function") target[`on${type}`](event)
}

function openFileChoosers(window) {
  const click = window.HTMLElement.prototype.click
  window.HTMLInputElement.prototype.click = function () {
    let activation = null
    const listen = event => { activation = event }
    this.addEventListener("click", listen, true)
    click.call(this)
    this.removeEventListener("click", listen, true)
    if (activation && !activation.defaultPrevented && this.type === "file") openFileChooser(this)
  }
}

function openFileChooser(input) {
  if (!chooser || chooser.opened) return
  const files = chooser.files
  chooser.opened = true
  page.clock.schedule(() => attachFiles(input, files), 0, [], false)
}

function expectFileChooser(files) {
  chooser = { files, opened: false }
  return null
}

function takeFileChooser() {
  const opened = Boolean(chooser && chooser.opened)
  chooser = null
  return opened
}

async function multipart(entries, headers) {
  const boundary = `----RailsJsdomBoundary${nextFetchId}${Date.now()}`
  const quote = text => String(text).replace(/"/g, "%22").replace(/\r?\n/g, " ")
  const parts = []
  for (const [name, value] of entries) {
    const file = typeof value !== "string"
    const head = file ? `Content-Disposition: form-data; name="${quote(name)}"; filename="${quote(value.name)}"\r\nContent-Type: ${value.type || "application/octet-stream"}` : `Content-Disposition: form-data; name="${quote(name)}"`
    parts.push(Buffer.from(`--${boundary}\r\n${head}\r\n\r\n`), file ? Buffer.from(await value.arrayBuffer()) : Buffer.from(value), Buffer.from("\r\n"))
  }
  parts.push(Buffer.from(`--${boundary}--\r\n`))
  headers["content-type"] = `multipart/form-data; boundary=${boundary}`
  return Buffer.concat(parts).toString("base64")
}

function expectModal({ type, accept, with: answer }) {
  modal = { type, accept, answer }
  modalMessages = []
  return null
}

function takeModalMessages() {
  const messages = modalMessages
  modal = null
  modalMessages = []
  return messages
}

function dialog(type, message, defaultValue) {
  if (!modal || modal.type !== type) {
    errors.push(new Error(`RailsJsdom: unexpected ${type} dialog "${message}". Wrap the action in ${DIALOG_HANDLERS[type]}.`))
    return UNANSWERED[type]
  }
  modalMessages.push(String(message))
  if (type === "confirm") return modal.accept
  if (type === "prompt") return modal.accept ? String(modal.answer ?? defaultValue ?? "") : null
  return undefined
}

function find({ locator, scope, match }, strategy, kind) {
  const root = scopeRoot(scope)
  const description = locator === null ? "any element of that kind" : JSON.stringify(locator)
  const candidates = locator === null ? [...root.querySelectorAll(kind || CLICKABLE)] : located(root, locator, strategy, kind)
  if (candidates.length === 0) throw new Error(`RailsJsdom: unable to find ${description}`)
  return pick(candidates, description, match)
}

function located(root, locator, strategy, kind) {
  return [byAction, strategy, byCss].map(search => search(root, locator).filter(element => !kind || element.matches(kind))).find(list => list.length > 0) || []
}

function scopeRoot(scope = []) {
  return scope.reduce((parent, entry) => only(scoped(parent, entry), `within ${JSON.stringify(entry)}`), page.window.document)
}

function scoped(parent, entry) {
  if (entry.handle !== undefined) return [elementFor(entry.handle)]
  if (entry.fieldset !== undefined) return [...parent.querySelectorAll("fieldset")].filter(fieldset => fieldset.id === entry.fieldset || normalize(fieldset.querySelector(":scope > legend")?.textContent) === entry.fieldset)
  if (entry.table !== undefined) return [...parent.querySelectorAll("table")].filter(table => table.id === entry.table || normalize(table.caption?.textContent) === entry.table)
  return [...parent.querySelectorAll(entry.css)]
}

function pick(list, description, match) {
  return match === "first" && list.length > 0 ? list[0] : only(list, description)
}

function only(list, description) {
  if (list.length !== 1) throw new Error(`RailsJsdom: ${description} matches ${list.length} elements`)
  return list[0]
}

function byAction(root, locator) {
  if (!/^[\w-]+#\w+$/.test(locator)) return []
  return [...root.querySelectorAll("[data-action]")].filter(element => element.getAttribute("data-action").split(/\s+/).some(token => token.split("->").pop().split(":")[0] === locator))
}

function byCss(root, locator) {
  try {
    return [...root.querySelectorAll(locator)]
  } catch {
    return []
  }
}

function names(element) {
  return [element.textContent, element.getAttribute("aria-label"), element.getAttribute("title"), element.id, element.matches(BUTTON_INPUTS) ? element.value : "", element.matches(`button, ${BUTTON_INPUTS}`) ? element.getAttribute("name") : ""].map(normalize).filter(Boolean)
}

function byText(elements, text) {
  const exact = elements.filter(element => names(element).includes(text))
  return exact.length > 0 ? exact : elements.filter(element => names(element).some(name => name.includes(text)))
}

function byClickable(root, text) {
  return byText([...root.querySelectorAll(CLICKABLE)], text)
}

function byField(root, text) {
  const fields = [...root.querySelectorAll(FIELDS)]
  const labelled = byText([...root.querySelectorAll("label")], text).map(label => label.control).filter(Boolean)
  const attributes = ["placeholder", "name", "id", "aria-label"].map(attribute => fields.filter(field => field.getAttribute(attribute) === text))
  return [labelled, ...attributes].find(list => list.length > 0) || []
}

function click(element) {
  const window = element.ownerDocument.defaultView
  const options = { bubbles: true, cancelable: true, composed: true, view: window }
  if (element.disabled) throw new Error(`RailsJsdom: ${element.outerHTML.slice(0, 120)} is disabled`)
  element.dispatchEvent(new window.MouseEvent("mousedown", options))
  if (typeof element.focus === "function") element.focus()
  element.dispatchEvent(new window.MouseEvent("mouseup", options))
  if (typeof element.click === "function") element.click()
  else element.dispatchEvent(new window.MouseEvent("click", options))
}

function fill(element, value) {
  if (element.disabled || element.readOnly) throw new Error(`RailsJsdom: ${element.outerHTML.slice(0, 120)} is not editable`)
  element.focus()
  element.value = value
  changed(element)
}

function changed(element) {
  const window = element.ownerDocument.defaultView
  element.dispatchEvent(new window.Event("input", { bubbles: true }))
  element.dispatchEvent(new window.Event("change", { bubbles: true }))
}

function setChecked(element, checked) {
  if (element.checked !== checked) click(element)
}

function setValue(element, value) {
  if (element.matches("input[type=checkbox]")) return setChecked(element, Boolean(value))
  if (element.matches("input[type=radio]")) return value ? setChecked(element, true) : null
  if (element.matches(FILLABLE)) return fill(element, String(value))
  if (element.matches("[contenteditable]:not([contenteditable=false])")) {
    element.textContent = String(value)
    return element.dispatchEvent(new element.ownerDocument.defaultView.Event("input", { bubbles: true }))
  }
  throw new Error(`RailsJsdom: set does not work on ${element.outerHTML.slice(0, 120)}; use select, attach_file or click`)
}

function chooseOption(option, selected) {
  const select = option.closest("select")
  if (!select) throw new Error("RailsJsdom: select_option works only on an option inside a select")
  if (select.disabled) throw new Error(`RailsJsdom: ${select.outerHTML.slice(0, 120)} is disabled`)
  if (!selected && !select.multiple) throw new Error("RailsJsdom: unselect works only on a select that allows multiple options")
  select.focus()
  option.selected = selected
  changed(select)
}

function attachFiles(input, files) {
  if (input.disabled) throw new Error(`RailsJsdom: ${input.outerHTML.slice(0, 120)} is disabled`)
  if (files.length > 1 && !input.multiple) throw new Error("RailsJsdom: the file field does not allow multiple files")
  const window = input.ownerDocument.defaultView
  const list = internal(input.files)
  list.length = 0
  for (const file of files) list.push(internal(new window.File([Buffer.from(file.base64, "base64")], file.name, { type: file.type })))
  changed(input)
}

function internal(object) {
  const implementation = wrappers.implForWrapper(object)
  if (!implementation) throw new Error("RailsJsdom: attach_file does not work with this jsdom version")
  return implementation
}

function handleFor(element) {
  if (!page.ids.has(element)) {
    page.nextHandle += 1
    page.ids.set(element, page.nextHandle)
    page.handles.set(page.nextHandle, element)
  }
  return page.ids.get(element)
}

function elementFor(handle) {
  const element = page && page.handles.get(handle)
  if (!element || !element.isConnected) throw new Error("RailsJsdom: the element is no longer on the page")
  return element
}

function describe(element) {
  return {
    handle: handleFor(element),
    tag: element.localName,
    text: normalize(visibleText(element)),
    all_text: normalize(element.textContent),
    visible: isVisible(element),
    value: "value" in element ? String(element.value) : null,
    checked: Boolean(element.checked),
    selected: Boolean(element.selected),
    disabled: Boolean(element.disabled),
    type: element.localName === "input" ? element.type : element.localName,
    attributes: Object.fromEntries([...element.attributes].map(attribute => [attribute.name, attribute.value]))
  }
}

function query({ strategy, locator, scope }) {
  if (!page) throw new Error("RailsJsdom: visit a page or mount a partial first")
  return candidates(scopeRoot(scope), strategy, locator).map(describe)
}

function candidates(root, strategy, locator) {
  const kind = QUERY_KINDS[strategy]
  if (locator === null) return [...root.querySelectorAll(kind)]
  if (strategy === "css") return [...root.querySelectorAll(locator)]
  const search = strategy === "field" ? byField : byClickable
  return search(root, locator).filter(element => element.matches(kind))
}

const ELEMENT_ACTIONS = {
  click: element => click(element),
  hover: element => hover(element),
  double_click: element => doubleClick(element),
  right_click: element => rightClick(element),
  set: (element, message) => setValue(element, message.value),
  select_option: element => chooseOption(element, true),
  unselect_option: element => chooseOption(element, false),
  send_keys: (element, message) => sendKeys(element, message.keys)
}

function elementAction(message) {
  const element = elementFor(message.handle)
  if (!ELEMENT_ACTIONS[message.action]) throw new Error(`RailsJsdom: unknown element action ${message.action}`)
  return ELEMENT_ACTIONS[message.action](element, message)
}

async function sendKeys(element, keys) {
  if (element) focusForTyping(element)
  typing += 1
  try {
    await pressKeys(keys)
  } finally {
    typing -= 1
  }
}

async function pressKeys(keys) {
  for (const entry of keys) {
    const modifiers = modifierFlags(entry.modifiers || [])
    for (const key of pressedKeys(entry)) {
      await runQueuedTasks()
      press(key, modifiers)
    }
  }
}

async function runQueuedTasks() {
  let ran = 0
  do {
    if (ran > SETTLE_LIMIT) throw notSettled()
    ran += 1
    await turn()
  } while (await stepNow())
}

async function stepNow() {
  if (pending.size > 0) {
    await Promise.race(pending)
    return true
  }
  return runTaskDueNow()
}

function runTaskDueNow() {
  const timer = page.clock.due(time.now)
  if (timer) page.clock.run(timer)
  return Boolean(timer)
}

function focusForTyping(element) {
  const focused = element.ownerDocument.activeElement === element
  element.focus()
  const host = editingHost(element)
  if (host && !focused) placeCaretAtEnd(host.ownerDocument.defaultView, host)
}

function modifierFlags(names) {
  return Object.fromEntries(names.map(name => {
    if (!MODIFIERS[name]) throw new Error(`RailsJsdom: unknown modifier key ${name}`)
    return [MODIFIERS[name], true]
  }))
}

function pressedKeys(entry) {
  if (entry.text !== undefined) return [...entry.text]
  if (KEYS[entry.key]) return [KEYS[entry.key]]
  throw new Error(`RailsJsdom: unknown key ${entry.key}`)
}

function keyCode(key) {
  if (/^[a-z]$/i.test(key)) return `Key${key.toUpperCase()}`
  if (/^[0-9]$/.test(key)) return `Digit${key}`
  return key === " " ? "Space" : key
}

function press(key, modifiers) {
  const window = page.window
  const target = window.document.activeElement
  const options = { key, code: keyCode(key), bubbles: true, cancelable: true, composed: true, view: window, ...modifiers }
  const proceed = target.dispatchEvent(new window.KeyboardEvent("keydown", options))
  if (proceed && (key.length > 1 || target.dispatchEvent(new window.KeyboardEvent("keypress", options)))) keyAction(target, key, modifiers)
  target.dispatchEvent(new window.KeyboardEvent("keyup", options))
}

function keyAction(target, key, modifiers) {
  if (key === "Tab") return moveFocus(target, modifiers.shiftKey)
  const host = editingHost(target)
  return host ? editContent(host, key, modifiers) : fieldKeyAction(target, key, modifiers)
}

function fieldKeyAction(target, key, modifiers) {
  if (key === "Enter") return pressEnter(target)
  if (key === " " && target.matches(PRESSABLE)) return click(target)
  if (target.matches(STEPPABLE) && ["ArrowUp", "ArrowRight", "ArrowDown", "ArrowLeft", "Home", "End"].includes(key)) return step(target, key)
  if (target.matches(`${FILLABLE}`)) return editText(target, key, modifiers)
  return null
}

function editingHost(element) {
  const nearest = element && element.closest("[contenteditable]")
  if (!nearest || nearest.getAttribute("contenteditable") === "false") return null
  return editingHost(nearest.parentElement) || nearest
}

function editContent(host, key, modifiers) {
  const window = host.ownerDocument.defaultView
  const inputType = contentInputType(key, modifiers)
  const init = { bubbles: true, cancelable: true, composed: true, inputType, data: inputType === "insertText" ? key : null }
  if (inputType && host.dispatchEvent(new window.InputEvent("beforeinput", init))) {
    editAtCaret(window, caretIn(window, host), inputType, init.data)
    host.dispatchEvent(new window.InputEvent("input", { ...init, cancelable: false }))
  }
  return null
}

function contentInputType(key, modifiers) {
  if (key === "Backspace") return "deleteContentBackward"
  if (key === "Enter") return modifiers.shiftKey ? "insertLineBreak" : "insertParagraph"
  return typesCharacter(key, modifiers) ? "insertText" : null
}

function caretIn(window, host) {
  const selection = window.getSelection()
  if (selection.rangeCount === 0 || !host.contains(selection.anchorNode)) placeCaretAtEnd(window, host)
  return selection
}

function placeCaretAtEnd(window, host) {
  const texts = window.document.createTreeWalker(host, window.NodeFilter.SHOW_TEXT)
  let last = null
  while (texts.nextNode()) last = texts.currentNode
  if (last) window.getSelection().collapse(last, last.length)
  else window.getSelection().collapse(host, host.childNodes.length)
}

function editAtCaret(window, selection, inputType, data) {
  if (inputType === "deleteContentBackward") return deleteBeforeCaret(selection)
  const node = selection.anchorNode
  const offset = selection.anchorOffset
  if (inputType === "insertText" && node.nodeType === 3) {
    node.insertData(offset, data)
    selection.collapse(node, offset + data.length)
  } else if (inputType === "insertText") {
    const text = window.document.createTextNode(data)
    selection.getRangeAt(0).insertNode(text)
    selection.collapse(text, data.length)
  } else {
    insertNodeAtCaret(selection, window.document.createElement("br"))
  }
}

function deleteBeforeCaret(selection) {
  const node = selection.anchorNode
  const offset = selection.anchorOffset
  const before = node.nodeType === 3 ? null : node.childNodes[offset - 1]
  if (node.nodeType === 3 && offset > 0) {
    node.deleteData(offset - 1, 1)
    selection.collapse(node, offset - 1)
  } else if (before?.nodeType === 3 && before.length > 0) {
    before.deleteData(before.length - 1, 1)
    selection.collapse(before, before.length)
  } else if (before) {
    before.remove()
    selection.collapse(node, offset - 1)
  }
}

function insertNodeAtCaret(selection, inserted) {
  selection.getRangeAt(0).insertNode(inserted)
  selection.collapse(inserted.parentNode, [...inserted.parentNode.childNodes].indexOf(inserted) + 1)
}

function editText(target, key, modifiers) {
  if (target.disabled || target.readOnly) return null
  const before = target.value
  const after = editedValue(before, key, modifiers)
  if (after === before) return null
  target.value = after
  if (!page.edited.has(target)) page.edited.set(target, before)
  const deleting = key === "Backspace"
  return target.dispatchEvent(new target.ownerDocument.defaultView.InputEvent("input", { bubbles: true, inputType: deleting ? "deleteContentBackward" : "insertText", data: deleting ? null : key }))
}

function editedValue(value, key, modifiers) {
  if (key === "Backspace") return value.slice(0, -1)
  return typesCharacter(key, modifiers) ? value + key : value
}

function typesCharacter(key, modifiers) {
  return key.length === 1 && !modifiers.ctrlKey && !modifiers.metaKey && !modifiers.altKey
}

function pressEnter(target) {
  if (target.localName === "textarea") return editText(target, "\n", {})
  if (target.matches(`a[href], ${KINDS.button}`)) return click(target)
  const form = target.form
  if (!form || !target.matches(FILLABLE)) return null
  const submitter = form.querySelector(`button:not([type]), button[type=submit], input[type=submit], input[type=image]`)
  return submitter ? click(submitter) : form.requestSubmit()
}

function step(target, key) {
  if (key === "Home") target.value = target.min || "0"
  else if (key === "End") target.value = target.max || "100"
  else if (["ArrowUp", "ArrowRight"].includes(key)) target.stepUp()
  else target.stepDown()
  changed(target)
}

function moveFocus(from, backwards) {
  if (page.edited.has(from) && page.edited.get(from) !== from.value) from.dispatchEvent(new from.ownerDocument.defaultView.Event("change", { bubbles: true }))
  page.edited.delete(from)
  const next = nextFocus(tabOrder(from.ownerDocument), from, backwards)
  if (next) next.focus()
}

function tabOrder(document) {
  const focusable = [...document.querySelectorAll(FOCUSABLE)].filter(element => !element.disabled && element.tabIndex >= 0 && isVisible(element))
  const positive = focusable.filter(element => element.tabIndex > 0).sort((a, b) => a.tabIndex - b.tabIndex)
  return [...positive, ...focusable.filter(element => element.tabIndex === 0)]
}

function nextFocus(ordered, from, backwards) {
  const index = ordered.indexOf(from)
  if (index === -1) return backwards ? ordered[ordered.length - 1] : ordered[0]
  const step = backwards ? -1 : 1
  return ordered[(index + step + ordered.length) % ordered.length]
}

function selectOption(message) {
  const root = scopeRoot(message.scope)
  const selects = message.from === null ? [...root.querySelectorAll("select")] : [find({ ...message, locator: message.from }, byField, "select")]
  const options = selects.flatMap(select => [...select.options])
  const exact = options.filter(option => normalize(option.textContent) === message.option)
  const option = pick(exact.length > 0 ? exact : options.filter(option => normalize(option.textContent).includes(message.option)), `option ${JSON.stringify(message.option)}`, message.match)
  chooseOption(option, message.selected)
}

function mouse(element, type, options = {}) {
  const window = element.ownerDocument.defaultView
  const Event = type.startsWith("pointer") ? window.PointerEvent : window.MouseEvent
  element.dispatchEvent(new Event(type, { bubbles: !type.endsWith("enter"), cancelable: true, composed: true, view: window, ...options }))
}

function hover(element) {
  for (const type of ["pointerover", "pointerenter", "mouseover", "mouseenter", "pointermove", "mousemove"]) mouse(element, type)
}

function doubleClick(element) {
  click(element)
  click(element)
  mouse(element, "dblclick", { detail: 2 })
}

function rightClick(element) {
  for (const type of ["mousedown", "mouseup", "contextmenu"]) mouse(element, type, { button: 2, buttons: 2 })
}

function isVisible(element) {
  for (let node = element; node; node = node.parentElement) {
    if (node.matches(config.hidden)) return false
    if (node.parentElement?.localName === "details" && !node.parentElement.open && node.localName !== "summary") return false
  }
  return true
}

function visibleText(node) {
  if (node.nodeType === 3) return node.data
  if (node.nodeType !== 1 || node.matches(config.hidden)) return ""
  const children = node.localName === "details" && !node.open ? [...node.children].filter(child => child.localName === "summary") : [...node.childNodes]
  const text = children.map(visibleText).join("")
  return INLINE_ELEMENTS.has(node.localName) ? text : ` ${text} `
}

function snapshot(scope) {
  if (!page) throw new Error("RailsJsdom: visit a page or mount a partial first")
  const root = scopeRoot(scope)
  const document = root.nodeType === 9
  return { html: document ? page.dom.serialize() : root.outerHTML, text: normalize(visibleText(document ? root.body : root)), url: page.window.location.href, title: page.window.document.title }
}

module.exports = { start }
