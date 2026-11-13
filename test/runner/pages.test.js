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

test("browser APIs jsdom lacks are stubbed", async () => {
  await runner.load(`<p id="p">Page</p>`)
  const result = await runner.evaluate(`(async () => {
    const media = matchMedia("(min-width: 600px)")
    media.addListener(); media.removeListener(); media.addEventListener(); media.removeEventListener()
    scrollTo(0, 0); scroll(0, 0); scrollBy(0, 0)
    document.getElementById("p").scrollIntoView()
    const observer = new IntersectionObserver(() => {})
    observer.observe(); observer.unobserve(); observer.disconnect()
    await navigator.clipboard.writeText("copied")
    return [media.matches, media.media, media.dispatchEvent(), observer.takeRecords(), await navigator.clipboard.readText(), typeof ResizeObserver]
  })()`)

  assert.deepEqual(result, [false, "(min-width: 600px)", false, [], "", "function"])
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
    CSS: window.CSS,
    matchMedia: window.matchMedia,
    IntersectionObserver: window.IntersectionObserver,
    ResizeObserver: window.ResizeObserver,
    clipboard: window.navigator.clipboard,
    scrollIntoView: window.Element.prototype.scrollIntoView,
    show: dialog.show,
    showModal: dialog.showModal,
    close: dialog.close,
    Request: window.Request,
    Response: window.Response
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

test("delivered Turbo Stream messages go to Turbo", async () => {
  await runner.load("<p>Page</p>")
  await runner.run({ command: "deliver", messages: ["<p>One</p>", "<p>Two</p>"] })

  assert.equal((await runner.snapshot()).text, "Page One Two")
})

test("stream sources list their signed stream names for Turbo's channel only", async () => {
  await runner.load(`
    <turbo-cable-stream-source channel="Turbo::StreamsChannel" signed-stream-name="a"></turbo-cable-stream-source>
    <turbo-cable-stream-source signed-stream-name="b"></turbo-cable-stream-source>
    <turbo-cable-stream-source channel="ChatChannel" signed-stream-name="c"></turbo-cable-stream-source>`)

  assert.deepEqual(await runner.run({ command: "streams" }), ["a", "b"])
})
