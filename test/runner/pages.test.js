"use strict"

const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { JSDOM, VirtualConsole } = require("jsdom")
const { HOST, bodyText, connect, html, prepare, clear } = require("./support")

const runner = connect()

before(() => prepare(runner))
beforeEach(() => clear(runner))

const expect = (type, accept, answer) => runner.run({ command: "expect_modal", type, accept, with: answer })
const messages = () => runner.run({ command: "modal_messages" })
const ok = url => ({ status: 200, headers: {}, body: "", url, redirected: false })

async function waitFor(condition) {
  while (!condition()) await new Promise(resolve => setTimeout(resolve, 1))
}

test("load answers with a new page id each time", async () => {
  const first = await runner.load("<p>One</p>")
  const second = await runner.run({ command: "load", html: "<p>Two</p>", url: `${HOST}/two` })

  assert.equal(second, first + 1)
})

test("an unexpected dialog fails the action and names the helper to use", async () => {
  await runner.load("<p>Page</p>")

  await assert.rejects(runner.evaluate("alert('Hi')"), /unexpected alert dialog "Hi". Wrap the action in accept_alert\./)
  await assert.rejects(runner.evaluate("confirm('Sure?')"), /Wrap the action in accept_confirm or dismiss_confirm\./)
  await assert.rejects(runner.evaluate("prompt('Name?')"), /Wrap the action in accept_prompt or dismiss_prompt\./)
})

test("an expected alert is accepted and its message recorded", async () => {
  await runner.load("<p>Page</p>")
  await expect("alert", true, null)
  const value = await runner.evaluate("alert('Saved') === undefined")

  assert.deepEqual([value, await messages()], [true, ["Saved"]])
})

test("an expected confirm answers with the test's choice", async () => {
  await runner.load("<p>Page</p>")
  await expect("confirm", false, null)

  assert.equal(await runner.evaluate("confirm('Delete?')"), false)
})

test("an expected prompt answers with the given text, the default, an empty string or nothing", async () => {
  await runner.load("<p>Page</p>")
  await expect("prompt", true, "Ada")
  const given = await runner.evaluate("prompt('Name?', 'Grace')")
  await expect("prompt", true, null)
  const fallback = await runner.evaluate("prompt('Name?', 'Grace')")
  await expect("prompt", true, null)
  const empty = await runner.evaluate("prompt('Name?')")
  await expect("prompt", false, "Ada")
  const dismissed = await runner.evaluate("prompt('Name?')")

  assert.deepEqual([given, fallback, empty, dismissed], ["Ada", "Grace", "", null])
})

test("a dialog of another type than expected is unexpected", async () => {
  await runner.load("<p>Page</p>")
  await expect("confirm", true, null)

  await assert.rejects(runner.evaluate("alert('Hi')"), /unexpected alert dialog/)
})

test("dialog elements open and close, firing close only when they were open", async () => {
  await runner.load(`<dialog id="d"></dialog>`)
  const result = await runner.evaluate(`
    const dialog = document.getElementById("d")
    let closes = 0
    dialog.addEventListener("close", () => closes += 1)
    dialog.close()
    dialog.showModal()
    const opened = dialog.open
    dialog.close("done")
    dialog.show()
    dialog.close()
    ;[opened, dialog.open, dialog.returnValue, closes]
  `)

  assert.deepEqual(result, [true, false, "done", 2])
})

test("a stylesheet jsdom cannot parse does not fail the page, as browsers skip CSS they cannot parse", async () => {
  await runner.load("<style>@@@ {{{ display: none</style><p>Page</p>")

  assert.equal((await runner.snapshot()).text, "Page")
})

test("jsdom reports a stylesheet it cannot parse, and parses nested CSS", () => {
  const types = []
  const virtualConsole = new VirtualConsole()
  virtualConsole.on("jsdomError", error => types.push(error.type))
  new JSDOM("<style>.a { .b { display: none } }</style><style>@@@ {{{ display: none</style>", { virtualConsole })

  assert.deepEqual(types, ["css-parsing"])
})

test("jsdom fires load for an inserted style element by itself", async () => {
  const { window } = new JSDOM("")
  const loaded = []
  const style = window.document.createElement("style")
  style.addEventListener("load", () => loaded.push("style"))
  window.document.head.append(style)
  await new Promise(resolve => setImmediate(resolve))

  assert.deepEqual(loaded, ["style"])
})

test("an inserted stylesheet fires load, as a browser fires it once the sheet is ready", async () => {
  await runner.load("<p>Page</p>")
  const result = await runner.evaluate(`(async () => {
    const loaded = []
    const listen = element => element.addEventListener("load", () => loaded.push(element.localName + (element.rel ? "." + element.rel : "")))
    const style = document.createElement("style")
    const sheet = Object.assign(document.createElement("link"), { rel: "stylesheet", href: "/app.css" })
    const icon = Object.assign(document.createElement("link"), { rel: "icon", href: "/icon.png" })
    const wrapper = document.createElement("div")
    const nested = document.createElement("style")
    wrapper.append(nested)
    ;[style, sheet, icon, nested].forEach(listen)
    document.head.append(style, sheet, icon, "text")
    document.body.append(wrapper)
    const before = loaded.length
    await new Promise(resolve => setTimeout(resolve, 1))
    return [before, loaded]
  })()`)

  assert.deepEqual(result, [0, ["style", "style", "link.stylesheet"]])
})

test("browser APIs jsdom lacks are stubbed", async () => {
  await runner.load(`<p id="p">Page</p>`)
  const result = await runner.evaluate(`(async () => {
    const media = matchMedia("(min-width: 600px)")
    media.addListener(); media.removeListener(); media.addEventListener(); media.removeEventListener()
    scrollTo(0, 0); scroll(0, 0); scrollBy(0, 0)
    const p = document.getElementById("p")
    p.scrollIntoView(); p.scrollTo(0, 0); p.scroll(0, 0); p.scrollBy(0, 0)
    const observer = new IntersectionObserver(() => {})
    observer.observe(); observer.unobserve(); observer.disconnect()
    await navigator.clipboard.writeText("copied")
    return [media.matches, media.media, media.dispatchEvent(), observer.takeRecords(), await navigator.clipboard.readText(), typeof ResizeObserver]
  })()`)

  assert.deepEqual(result, [false, "(min-width: 600px)", false, [], "", "function"])
})

test("checkVisibility is false for an element that assertions treat as hidden", async () => {
  await runner.load(`<p id="shown">Shown</p><p id="hidden" hidden><span id="inside">Inside</span></p><details><summary id="summary">More</summary><span id="closed">Closed</span></details>`)
  const result = await runner.evaluate(`["shown", "hidden", "inside", "summary", "closed"].map(id => document.getElementById(id).checkVisibility())`)

  assert.deepEqual(result, [true, false, false, true, false])
})

test("a MessageChannel delivers each message to the other port as a task on the clock", async () => {
  await runner.load("<p>Page</p>")
  const result = await runner.evaluate(`(async () => {
    const received = []
    const { port1, port2 } = new MessageChannel()
    port1.addEventListener("message", event => received.push(["listener", event.data]))
    port1.onmessage = event => received.push(["handler", event.data])
    port2.onmessage = event => received.push(["back", event.data.count])
    port1.start()
    const message = { count: 1 }
    port2.postMessage(message)
    message.count = 2
    port1.postMessage(message)
    const before = received.length
    await new Promise(resolve => setTimeout(resolve, 0))
    return [before, received]
  })()`)

  assert.deepEqual(result, [0, [["listener", { count: 1 }], ["handler", { count: 1 }], ["back", 2]]])
})

test("a closed MessagePort neither sends nor receives", async () => {
  await runner.load("<p>Page</p>")
  const result = await runner.evaluate(`(async () => {
    const received = []
    const first = new MessageChannel()
    first.port1.addEventListener("message", event => received.push(event.data))
    first.port2.postMessage("sent before closing")
    first.port1.close()
    const second = new MessageChannel()
    second.port2.onmessage = event => received.push(event.data)
    second.port1.close()
    second.port1.postMessage("sent after closing")
    await new Promise(resolve => setTimeout(resolve, 0))
    return received
  })()`)

  assert.deepEqual(result, [])
})

test("a pasted DataTransfer carries its data to a paste listener", async () => {
  await runner.load(`<div id="editor" contenteditable="true"></div>`)
  const result = await runner.evaluate(`(() => {
    const data = new DataTransfer()
    data.setData("Text", "first")
    data.setData("text/plain", "plain")
    data.setData("URL", "https://example.test/")
    data.setData("text/html", "<b>html</b>")
    data.clearData("text/html")
    data.setDragImage()
    const editor = document.getElementById("editor")
    const seen = []
    editor.addEventListener("paste", event => seen.push(event instanceof Event, event.clipboardData.getData("text"), event.clipboardData.getData("url"), event.clipboardData.getData("text/html")))
    editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true }))
    return [seen, data.dropEffect, data.effectAllowed, new ClipboardEvent("copy").clipboardData]
  })()`)

  assert.deepEqual(result, [[true, "plain", "https://example.test/", ""], "none", "all", null])
})

test("DataTransfer items hold strings and files, read strings as a task, and can be removed", async () => {
  await runner.load("<p>Page</p>")
  const result = await runner.evaluate(`(async () => {
    const data = new DataTransfer()
    data.setData("text/plain", "plain")
    data.items.add("link", "TEXT/URI-LIST")
    data.items.add(new File(["f"], "a.txt", { type: "text/plain" }))
    const seen = []
    data.items[0].getAsString(text => seen.push(text))
    data.items[0].getAsString()
    data.items[2].getAsString(() => seen.push("file as string"))
    const before = seen.length
    await new Promise(resolve => setTimeout(resolve, 1))
    const listed = [data.types, data.files.map(file => file.name), data.items.map(item => item.kind), data.items[0].getAsFile()]
    data.items.remove(0)
    const removed = data.types
    data.clearData()
    const cleared = data.types
    data.items.clear()
    return [before, seen, listed, removed, cleared, data.types]
  })()`)

  assert.deepEqual(result, [0, ["plain"], [["text/plain", "text/uri-list", "Files"], ["a.txt"], ["string", "string", "file"], null], ["text/uri-list", "Files"], ["Files"], []])
})

test("a Range has an empty bounding box and no client rects, as an element without layout does", async () => {
  await runner.load("<p id=\"p\">Text</p>")
  const result = await runner.evaluate(`(() => {
    const range = document.createRange()
    range.selectNodeContents(document.getElementById("p"))
    const box = range.getBoundingClientRect()
    return [box instanceof DOMRect, box.width, box.height, range.getClientRects().length]
  })()`)

  assert.deepEqual(result, [true, 0, 0, 0])
})

test("CSS.escape serialises identifiers as browsers do", async () => {
  await runner.load("<p>Page</p>")
  const result = await runner.evaluate(`["1a-b c", "-2", "-", "\\0\\u0001\u00e9_x"].map(value => CSS.escape(value))`)

  assert.deepEqual(result, ["\\31 a-b\\ c", "-\\32 ", "\\-", "\uFFFD\\1 \u00e9_x"])
})

test("jsdom still lacks the browser APIs the runtime adds", () => {
  const { window } = new JSDOM("<dialog></dialog>")
  const dialog = window.document.querySelector("dialog")
  const missing = {
    matchMedia: window.matchMedia,
    IntersectionObserver: window.IntersectionObserver,
    ResizeObserver: window.ResizeObserver,
    clipboard: window.navigator.clipboard,
    scrollIntoView: window.Element.prototype.scrollIntoView,
    elementScrollTo: window.Element.prototype.scrollTo, elementScroll: window.Element.prototype.scroll, elementScrollBy: window.Element.prototype.scrollBy,
    checkVisibility: window.Element.prototype.checkVisibility,
    MessageChannel: window.MessageChannel,
    DataTransfer: window.DataTransfer, ClipboardEvent: window.ClipboardEvent,
    rangeBoundingClientRect: window.Range.prototype.getBoundingClientRect, rangeClientRects: window.Range.prototype.getClientRects,
    show: dialog.show, showModal: dialog.showModal, close: dialog.close,
    setFormValue: window.ElementInternals.prototype.setFormValue,
    requestFullscreen: window.Element.prototype.requestFullscreen, exitFullscreen: window.document.exitFullscreen,
    isContentEditable: Object.getOwnPropertyDescriptor(window.HTMLElement.prototype, "isContentEditable"),
    Request: window.Request, Response: window.Response
  }

  assert.deepEqual(Object.keys(missing).filter(name => missing[name] !== undefined), [])
})

test("jsdom's own scrolling methods report that they are not implemented", () => {
  const errors = []
  const virtualConsole = new VirtualConsole()
  virtualConsole.on("jsdomError", error => errors.push(error.message))
  const { window } = new JSDOM("", { virtualConsole })
  window.scrollTo(0, 0)
  window.scroll(0, 0)
  window.scrollBy(0, 0)

  assert.deepEqual(errors, ["Not implemented: Window's scrollTo() method", "Not implemented: Window's scroll() method", "Not implemented: Window's scrollBy() method"])
})

test("Request and Response headers are instances of the page's Headers", async () => {
  await runner.load("<p>Page</p>")
  const result = await runner.evaluate(`[new Request("${HOST}/x").headers instanceof Headers, new Response("x").headers instanceof Headers]`)

  assert.deepEqual(result, [true, true])
})

test("timers run in order of time, then of scheduling, up to the horizon", async () => {
  await runner.load("<p>Page</p>")
  await runner.evaluate(`
    window.order = []
    setTimeout(() => order.push("b"), 10)
    setTimeout(() => order.push("a"), 5)
    setTimeout(() => order.push("c"), 10)
    setTimeout(x => order.push(x), "soon", "d")
    requestAnimationFrame(now => order.push("frame " + now))
    clearTimeout(setTimeout(() => order.push("cleared"), 1))
    setTimeout("not a function", 1)
    setTimeout(() => order.push("late"), 2000)
  `)

  assert.deepEqual(await runner.evaluate("order"), ["d", "frame 0", "a", "b", "c"])
})

test("an interval repeats until it is cleared", async () => {
  await runner.load("<p>Page</p>")
  await runner.evaluate("window.ticks = 0; window.timer = setInterval(() => { ticks += 1; if (ticks === 3) clearInterval(timer) }, 100)")

  assert.equal(await runner.evaluate("ticks"), 3)
})

test("a timer that throws fails the action", async () => {
  await runner.load("<p>Page</p>")

  await assert.rejects(runner.evaluate("setTimeout(() => { throw new Error('timer bug') }, 1)"), /timer bug/)
})

test("fetch asks Rails with the method, headers and a URL relative to the page", async () => {
  await runner.load("<p>Page</p>", `${HOST}/items/`)
  runner.routes[`POST ${HOST}/items/new`] = { status: 201, headers: { "x-id": "7" }, body: "made", url: `${HOST}/items/new`, redirected: true }
  const result = await runner.evaluate(`fetch("new", { method: "post", headers: { "X-Token": "t" }, body: "raw" }).then(async r => [r.status, r.headers.get("x-id"), await r.text(), r.url, r.redirected])`)

  assert.deepEqual(result, [201, "7", "made", `${HOST}/items/new`, true])
  assert.deepEqual(runner.requests[0], { method: "POST", url: `${HOST}/items/new`, headers: { "x-token": "t" }, body: Buffer.from("raw").toString("base64") })
})

test("fetch takes a Request and defaults to GET", async () => {
  await runner.load("<p>Page</p>")
  runner.routes[`GET ${HOST}/a`] = { status: 200, headers: {}, body: "a", url: `${HOST}/a`, redirected: false }

  assert.equal(await runner.evaluate(`fetch(new Request("${HOST}/a")).then(r => r.text())`), "a")
})

test("fetch answers a stub by full URL or by path and query, without asking Rails", async () => {
  await runner.load("<p>Page</p>")
  await runner.run({ command: "stub_fetch", url: `${HOST}/full`, response: { status: 200, headers: {}, body: "full" } })
  await runner.run({ command: "stub_fetch", url: "/path?q=1", response: { status: 200, headers: {}, body: "path" } })

  assert.deepEqual(await runner.evaluate(`Promise.all([fetch("/full"), fetch("/path?q=1")].map(p => p.then(r => r.text())))`), ["full", "path"])
  assert.equal(runner.requests.length, 0)
})

test("a refused fetch rejects like a network error", async () => {
  await runner.load("<p>Page</p>")
  runner.routes["GET https://cdn.test/x.js"] = { error: "refused" }

  assert.equal(await runner.evaluate(`fetch("https://cdn.test/x.js").catch(e => e.name + ": " + e.message)`), "TypeError: refused")
})

test("a response with a no-body status has an empty body", async () => {
  await runner.load("<p>Page</p>")
  runner.routes[`DELETE ${HOST}/a`] = { status: 204, headers: {}, body: "ignored", url: `${HOST}/a`, redirected: false }

  assert.equal(await runner.evaluate(`fetch("/a", { method: "DELETE" }).then(r => r.text())`), "")
})

test("fetch encodes form data and search params as a form", async () => {
  await runner.load("<p>Page</p>")
  await runner.evaluate(`const data = new FormData(); data.append("a", "1"); Promise.all([fetch("/f", { method: "POST", body: data }), fetch("/s", { method: "POST", body: new URLSearchParams({ b: "2" }) })])`)

  assert.deepEqual(runner.requests.map(request => [bodyText(request), request.headers["content-type"]]), [["a=1", "application/x-www-form-urlencoded;charset=UTF-8"], ["b=2", "application/x-www-form-urlencoded;charset=UTF-8"]])
})

test("fetch encodes form data with files as multipart", async () => {
  await runner.load("<p>Page</p>")
  await runner.evaluate(`const data = new FormData(); data.append('na"me', "line\\none"); data.append("file", new File(["hi"], "a.txt", { type: "text/plain" })); data.append("blob", new Blob(["x"]), "b.bin"); fetch("/m", { method: "POST", body: data })`)
  const [request] = runner.requests
  const boundary = request.headers["content-type"].split("boundary=")[1]

  assert.equal(bodyText(request), [
    `--${boundary}`, `Content-Disposition: form-data; name="na%22me"`, "", "line\none",
    `--${boundary}`, `Content-Disposition: form-data; name="file"; filename="a.txt"`, "Content-Type: text/plain", "", "hi",
    `--${boundary}`, `Content-Disposition: form-data; name="blob"; filename="b.bin"`, "Content-Type: application/octet-stream", "", "x",
    `--${boundary}--`, ""
  ].join("\r\n"))
})

test("a page that was replaced sends no more requests and reports no more errors", async () => {
  await runner.load(`<a href="/next">Next</a>`)
  runner.routes[`GET ${HOST}/slow`] = "hold"
  runner.routes[`GET ${HOST}/next`] = html(`${HOST}/next`, "<p>Next</p>")
  const action = runner.evaluate(`fetch("/slow").then(() => { fetch("/after"); window.Stimulus.handleError(new Error("late"), "late") }); document.querySelector("a").click()`)
  await waitFor(() => runner.requests.length === 2)
  await new Promise(resolve => setTimeout(resolve, 20))
  runner.reply(runner.held[0].id, ok(`${HOST}/slow`))
  await action

  assert.deepEqual(runner.requests.map(request => request.url).sort(), [`${HOST}/next`, `${HOST}/slow`])
  assert.equal((await runner.snapshot()).text, "Next")
})

test("a link loads the page Rails answers with", async () => {
  await runner.load(`<a href="/next"><span id="s">Next</span></a>`)
  runner.routes[`GET ${HOST}/next`] = html(`${HOST}/next`, "<p>Next page</p>", "Next")
  await runner.evaluate(`document.getElementById("s").click()`)

  assert.deepEqual(await runner.snapshot(), { html: `<!DOCTYPE html><html><head><title>Next</title></head><body><p>Next page</p></body></html>`, text: "Next page", url: `${HOST}/next`, title: "Next" })
  assert.equal(runner.requests[0].headers.accept, "text/html,application/xhtml+xml")
})

test("links that stay on the page, open elsewhere, download or are prevented do not navigate", async () => {
  await runner.load(`
    <a id="hash" href="#top">Top</a>
    <a id="blank" href="/x" target="_blank">Blank</a>
    <a id="download" href="/x" download>Download</a>
    <a id="mail" href="mailto:a@b.test">Mail</a>
    <a id="prevented" href="/x" onclick="event.preventDefault()">Prevented</a>
    <button id="plain">Plain</button>`)
  await runner.evaluate(`for (const id of ["hash", "blank", "download", "mail", "prevented", "plain"]) document.getElementById(id).click(); document.dispatchEvent(new MouseEvent("click", { bubbles: true }))`)

  assert.equal(runner.requests.length, 0)
})

test("a link to the same path with another query navigates", async () => {
  await runner.load(`<a href="/?page=2#top">Page 2</a>`)
  await runner.evaluate(`document.querySelector("a").click()`)

  assert.equal(runner.requests[0].url, `${HOST}/?page=2#top`)
})

test("a navigation that Rails refuses fails the action", async () => {
  await runner.load(`<a href="https://elsewhere.test/">Away</a>`)
  runner.routes["GET https://elsewhere.test/"] = { error: "RailsJsdom sends fetch only to app.test" }

  await assert.rejects(runner.evaluate(`document.querySelector("a").click()`), /sends fetch only to app.test/)
})

test("a navigation answered with an unusable URL fails the action", async () => {
  await runner.load(`<a href="/bad">Bad</a>`)
  runner.routes[`GET ${HOST}/bad`] = { status: 200, headers: {}, body: "<p>Bad</p>", url: "not a url", redirected: false }

  await assert.rejects(runner.evaluate(`document.querySelector("a").click()`), /Invalid URL/)
})

test("a page that failed to load is closed by reset", async () => {
  await assert.rejects(runner.run({ command: "load", html: "<p>x</p>", url: "not a url" }), /Invalid URL/)

  assert.equal(await runner.run({ command: "reset" }), null)
})

test("a form without a method submits GET with its fields and submitter as the query", async () => {
  await runner.load(`<form action="/search"><input name="q" value="mugs"><input type="file" name="f"><button name="go" value="1">Go</button></form>`)
  await runner.evaluate(`document.querySelector("button").click()`)

  assert.deepEqual([runner.requests[0].method, runner.requests[0].url], ["GET", `${HOST}/search?q=mugs&go=1`])
})

test("a form without an action submits to the page's URL", async () => {
  await runner.load(`<form><input name="q" value="a"></form>`, `${HOST}/here`)
  await runner.evaluate(`document.querySelector("form").submit()`)

  assert.equal(runner.requests[0].url, `${HOST}/here?q=a`)
})

test("a POST form submits its fields as a form body and leaves files out", async () => {
  await runner.load(`<form method="post" action="/items"><input name="name" value="Mug"><input type="file" name="f"><button>Save</button></form>`)
  await runner.evaluate(`document.querySelector("button").click()`)

  assert.deepEqual([runner.requests[0].method, bodyText(runner.requests[0]), runner.requests[0].headers["content-type"]], ["POST", "name=Mug", "application/x-www-form-urlencoded;charset=UTF-8"])
})

test("a multipart form submits its files", async () => {
  await runner.load(`<form method="post" enctype="multipart/form-data" action="/up"><input type="file" name="f"><button>Up</button></form>`)
  await runner.run({ command: "attach", locator: "f", scope: [], match: null, files: [{ name: "a.txt", type: "text/plain", base64: Buffer.from("hi").toString("base64") }] })
  await runner.evaluate(`document.querySelector("button").click()`)

  assert.match(bodyText(runner.requests[0]),/filename="a.txt"\r\nContent-Type: text\/plain\r\n\r\nhi\r\n/)
})

test("a submitter's formmethod and formaction override the form's", async () => {
  await runner.load(`<form method="get" action="/a"><button formmethod="post" formaction="/b">Go</button></form>`)
  await runner.evaluate(`document.querySelector("button").click()`)

  assert.deepEqual([runner.requests[0].method, runner.requests[0].url], ["POST", `${HOST}/b`])
})

test("a dialog form closes its dialog with the submitter's value", async () => {
  await runner.load(`<dialog open><form method="dialog"><button value="yes">Yes</button></form></dialog><form id="loose" method="dialog"></form>`)
  await runner.evaluate(`document.querySelector("button").click(); document.getElementById("loose").submit()`)

  assert.deepEqual(await runner.evaluate(`[document.querySelector("dialog").open, document.querySelector("dialog").returnValue]`), [false, "yes"])
})

test("a dialog form submitted without a submitter closes its dialog", async () => {
  await runner.load(`<dialog open><form method="dialog"></form></dialog>`)
  await runner.evaluate(`document.querySelector("form").submit()`)

  assert.equal(await runner.evaluate(`document.querySelector("dialog").open`), false)
})

test("a form whose submit event is prevented does not submit", async () => {
  await runner.load(`<form action="/a" onsubmit="event.preventDefault()"><button>Go</button></form>`)
  await runner.evaluate(`document.querySelector("button").click()`)

  assert.equal(runner.requests.length, 0)
})

function cableServer(onSend = () => {}) {
  const sent = []
  runner.cable = request => {
    sent.push(request)
    if (request.action === "send") onSend(request)
    if (request.action === "open") return request.url.includes("refused") ? { error: "refused" } : { protocol: "actioncable-v1-json" }
    return null
  }
  return sent
}

function settleWith(frames) {
  return runner.run({ command: "settle", sync: { epoch: 0, now: 0, deadline: null, frames } })
}

const SOCKET_PAGE = `<script>
  window.events = []
  const socket = window.socket = new WebSocket("/cable", ["actioncable-v1-json"])
  socket.onopen = () => events.push("onopen " + socket.protocol + " " + socket.readyState)
  socket.addEventListener("open", () => events.push("open"))
  socket.onmessage = event => events.push("message " + event.data)
  socket.onerror = () => events.push("error")
  socket.onclose = event => events.push("close " + event.code + " " + event.wasClean + " " + socket.readyState)
</script>`

test("a page WebSocket opens through Ruby with the URL, protocols and the protocol Ruby chose", async () => {
  const sent = cableServer()
  await runner.load(SOCKET_PAGE)
  const opened = sent.find(request => request.action === "open")

  assert.deepEqual([opened.url, opened.protocols, await runner.evaluate("events")], ["ws://app.test/cable", ["actioncable-v1-json"], ["open", "onopen actioncable-v1-json 1"]])
})

test("a page WebSocket sends text through Ruby and receives the frames Ruby queued before timers run", async () => {
  const sent = cableServer()
  await runner.load(SOCKET_PAGE)
  const id = await runner.evaluate("socket.id")
  cableServer(() => runner.frames.push({ socket: 0, data: "lost" }, { socket: id, data: "hello" })).push(...sent)
  await runner.evaluate(`socket.send({ toString: () => "hi" }); setTimeout(() => events.push("timer"), 0)`)

  assert.deepEqual(await runner.evaluate("events.slice(2)"), ["message hello", "timer"])
})

test("frames Ruby queued between commands reach the page before the next action runs", async () => {
  cableServer()
  await runner.load(SOCKET_PAGE)
  const id = await runner.evaluate("socket.id")
  const result = await runner.run({ command: "evaluate", script: "events.slice(2)", sync: { epoch: 0, now: 0, deadline: null, frames: [{ socket: id, data: "queued" }] } })

  assert.deepEqual(result, ["message queued"])
})

test("a page WebSocket the server closes reports the code and stops", async () => {
  cableServer()
  await runner.load(SOCKET_PAGE)
  const id = await runner.evaluate("socket.id")
  await settleWith([{ socket: id, closed: true, code: 1011 }, { socket: id, data: "late" }])

  assert.deepEqual(await runner.evaluate("events.slice(2)"), ["close 1011 false 3"])
})

test("closing a page WebSocket tells Ruby once, and messages after it are dropped", async () => {
  const sent = cableServer()
  await runner.load(SOCKET_PAGE)
  await runner.evaluate("socket.close(); socket.close(); socket.received('late')")

  assert.deepEqual([sent.filter(request => request.action === "close").length, await runner.evaluate("events.slice(2)")], [1, ["close 1000 true 3"]])
})

test("a page that closes its WebSocket as the server closes it gets one close event, from the server", async () => {
  const sent = cableServer()
  await runner.load(SOCKET_PAGE.replace('events.push("message " + event.data)', '{ events.push("message " + event.data); socket.close() }'))
  const id = await runner.evaluate("socket.id")
  await settleWith([{ socket: id, data: "bye" }, { socket: id, closed: true, code: 1001 }])

  assert.deepEqual([sent.filter(request => request.action === "close").length, await runner.evaluate("events.slice(2)")], [1, ["message bye", "close 1001 false 3"]])
})

test("sending on a WebSocket that is not open fails, and a reply after closing is ignored", async () => {
  cableServer()
  await runner.load("<p>Page</p>")
  const result = await runner.evaluate(`(() => {
    const socket = new WebSocket("/cable")
    let error = null
    try { socket.send("early") } catch (caught) { error = caught.name }
    socket.close()
    return [error, socket.readyState, WebSocket.OPEN]
  })()`)

  assert.deepEqual([...result, await runner.evaluate("document.title")], ["InvalidStateError", 2, 1, "Page"])
})

test("a WebSocket Ruby refuses reports an error, then closes", async () => {
  cableServer()
  await runner.load(SOCKET_PAGE.replace('"/cable"', '"/refused"'))

  assert.deepEqual(await runner.evaluate("events"), ["error", "close 1006 false 3"])
})

test("leaving a page closes its WebSockets through Ruby, and a reset closes them without Ruby", async () => {
  const sent = cableServer()
  await runner.load(SOCKET_PAGE)
  await runner.load("<p>Next</p>", `${HOST}/next`)
  const closes = sent.filter(request => request.action === "close").length
  await runner.load(SOCKET_PAGE)
  await runner.run({ command: "reset" })

  assert.deepEqual([closes, sent.filter(request => request.action === "close").length], [1, 1])
})

const FORM_ASSOCIATED = `<script>
  customElements.define("x-editor", class extends HTMLElement {
    static formAssociated = true
    constructor() { super(); this.internals = this.attachInternals() }
  })
</script>`

test("a form-associated custom element's value is part of its form's data", async () => {
  await runner.load(`${FORM_ASSOCIATED}
    <form id="f"><input name="title" value="Hi"><x-editor name="body"></x-editor><x-editor name="off" disabled></x-editor><x-editor name="blank"></x-editor></form>
    <x-editor name="linked" form="f"></x-editor><x-editor name="outside"></x-editor>`)
  const result = await runner.evaluate(`(() => {
    for (const editor of document.querySelectorAll("x-editor:not([name=blank])")) editor.internals.setFormValue(editor.getAttribute("name") + " value")
    return [...new FormData(document.getElementById("f")).entries()]
  })()`)

  assert.deepEqual(result, [["title", "Hi"], ["body", "body value"], ["linked", "linked value"]])
})

test("a form-associated custom element knows its form and reports the validity it sets", async () => {
  await runner.load(`${FORM_ASSOCIATED}<form id="f"><x-editor name="body"></x-editor></form>`)
  const result = await runner.evaluate(`(() => {
    const { internals } = document.querySelector("x-editor")
    const before = [internals.form.id, internals.validity.valid, internals.willValidate, internals.checkValidity(), new FormData().has("body")]
    internals.setValidity({ valueMissing: true }, "Required")
    const invalid = [internals.validity.valueMissing, internals.validationMessage, internals.reportValidity()]
    internals.setValidity({})
    return [...before, ...invalid, internals.validity.valid, internals.validationMessage]
  })()`)

  assert.deepEqual(result, ["f", true, true, true, false, true, "Required", false, true, ""])
})

test("evaluate with a kind runs the script as a function, with its arguments, receiver and elements", async () => {
  await runner.load(`<p id="p">Page</p>`)
  const [{ handle }] = await runner.run({ command: "query", strategy: "css", locator: "#p", scope: [] })
  const value = await runner.run({ command: "evaluate", script: "arguments[0].id + arguments[1] + (arguments[2] === null)", kind: "expression", receiver: null, args: [{ rails_jsdom_element: handle }, "!", null] })
  const statements = await runner.run({ command: "evaluate", script: "this.dataset.seen = arguments[0]; return this.dataset.seen", kind: "statements", receiver: handle, args: ["yes"] })

  assert.deepEqual([value, statements], ["p!true", "yes"])
})

test("an evaluated promise that waits on a timer and an animation frame resolves, because the clock runs while it waits", async () => {
  await runner.load("<p>Page</p>")
  const value = await runner.evaluate(`new Promise(resolve => setTimeout(() => requestAnimationFrame(() => resolve("late")), 50))`)

  assert.equal(value, "late")
})

test("the page reports no touch support, as a desktop browser does", async () => {
  await runner.load(`<p id="p">Page</p>`)

  assert.deepEqual(await runner.evaluate(`["ontouchstart" in window, "ontouchend" in document, "ontouchmove" in p, navigator.maxTouchPoints]`), [false, false, false, 0])
})

test("an element can enter and leave fullscreen, as on a desktop browser", async () => {
  await runner.load(`<div id="d"></div><script>window.changes = []; document.addEventListener("fullscreenchange", () => changes.push(document.fullscreenElement && document.fullscreenElement.id))</script>`)
  const result = await runner.evaluate(`(async () => {
    const enabled = document.fullscreenEnabled
    await d.requestFullscreen()
    const inside = document.fullscreenElement.id
    await document.exitFullscreen()
    await document.exitFullscreen()
    return [enabled, inside, document.fullscreenElement, changes]
  })()`)

  assert.deepEqual(result, [true, "d", null, ["d", null]])
})

test("a page that keeps measuring layout in one turn of its event loop fails with an explanation, instead of looping forever", async () => {
  const loop = `<div id="menu"></div><script>
    new MutationObserver(() => {
      if (menu.getBoundingClientRect().width === 0) menu.append(document.createElement("span"))
    }).observe(menu, { childList: true })
  </script>`
  await runner.load(loop)

  await assert.rejects(runner.evaluate("menu.append(document.createElement('span'))"), /measured element positions 10000 times without its event loop moving on\. jsdom has no layout.*stub_layout/s)
})

test("measuring layout again in later turns of the event loop is fine", async () => {
  await runner.load(`<div id="d"></div>`)
  const result = await runner.evaluate(`new Promise(resolve => {
    let count = 0
    const measure = () => {
      for (let index = 0; index < 6000; index += 1) d.getBoundingClientRect()
      count += 1
      if (count < 3) setTimeout(measure, 0)
      else resolve(count)
    }
    measure()
  })`)

  assert.equal(result, 3)
})

test("stub_layout gives matching elements, their contents and ranges inside them a box, and other elements none", async () => {
  await runner.load(`<div id="editor"><p id="p">Text</p></div><div id="other"></div>`)
  await runner.run({ command: "stub_layout", selector: "#editor", box: { width: 100, height: 20, top: 5, left: 7 } })
  const result = await runner.evaluate(`(() => {
    const range = document.createRange()
    range.setStart(p.firstChild, 2)
    const box = rect => [rect.left, rect.top, rect.width, rect.height]
    return [box(editor.getBoundingClientRect()), box(p.getBoundingClientRect()), box(range.getBoundingClientRect()), p.getClientRects().length, box(other.getBoundingClientRect()), other.getClientRects().length]
  })()`)

  assert.deepEqual(result, [[7, 5, 100, 20], [7, 5, 100, 20], [7, 5, 100, 20], 1, [0, 0, 0, 0], 0])
})

test("a page that waits for a real measurement stops once stub_layout gives it a box, and the next page has no stubs", async () => {
  await runner.load(`<div id="menu"></div><script>
    new MutationObserver(() => {
      if (menu.getBoundingClientRect().width === 0) menu.append(document.createElement("span"))
    }).observe(menu, { childList: true })
  </script>`)
  await runner.run({ command: "stub_layout", selector: "#menu", box: { width: 10, height: 10, top: 1, left: 1 } })
  await runner.evaluate("menu.append(document.createElement('span'))")
  const count = await runner.evaluate("menu.children.length")
  await runner.load(`<div id="menu"></div>`, `${HOST}/next`)

  assert.deepEqual([count, await runner.evaluate("menu.getBoundingClientRect().width")], [1, 0])
})

test("stub_layout before a page is loaded fails", async () => {
  await assert.rejects(runner.run({ command: "stub_layout", selector: "p", box: { width: 1, height: 1, top: 0, left: 0 } }), /visit a page or mount a partial first/)
})
