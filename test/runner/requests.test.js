"use strict"

const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { HOST, bodyText, connect, prepare, clear } = require("./support")

const runner = connect()

before(() => prepare(runner))
beforeEach(() => clear(runner))

const reply = (url, body, headers = {}, status = 200) => ({ status, headers, body, url, redirected: false })
const file = (name, text) => ({ name, type: "text/plain", base64: Buffer.from(text).toString("base64") })

async function waitFor(condition) {
  while (!condition()) await new Promise(resolve => setTimeout(resolve, 1))
}

test("XMLHttpRequest asks Rails with the method, headers and body, and fires its events with the reply", async () => {
  await runner.load("<p>Page</p>", `${HOST}/items/`)
  runner.routes[`PUT ${HOST}/items/new`] = reply(`${HOST}/items/new`, "{\"id\":7}", { "Content-Type": "application/json" }, 201)
  const result = await runner.evaluate(`new Promise(resolve => {
    const events = []
    const xhr = new XMLHttpRequest()
    xhr.onreadystatechange = () => events.push("readystatechange " + xhr.readyState)
    xhr.open("put", "new")
    xhr.responseType = "json"
    xhr.setRequestHeader("X-Token", "t")
    xhr.overrideMimeType("application/json")
    xhr.upload.addEventListener("progress", event => events.push("upload progress " + event.loaded + "/" + event.total))
    xhr.upload.onload = () => events.push("upload load")
    xhr.addEventListener("load", () => events.push("load"))
    xhr.onloadend = () => resolve([events, xhr.status, xhr.response.id, xhr.responseText, xhr.responseURL, xhr.getResponseHeader("content-type"), xhr.getResponseHeader("x-missing"), xhr.getAllResponseHeaders()])
    xhr.send("raw")
  })`)

  assert.deepEqual(result, [["readystatechange 1", "upload progress 3/3", "upload load", "readystatechange 4", "load"], 201, 7, "{\"id\":7}", `${HOST}/items/new`, "application/json", null, "content-type: application/json\r\n"])
  assert.deepEqual(runner.requests[0], { method: "PUT", url: `${HOST}/items/new`, headers: { "x-token": "t" }, body: Buffer.from("raw").toString("base64") })
})

test("XMLHttpRequest reads text, and empty JSON as null", async () => {
  await runner.load("<p>Page</p>")
  runner.routes[`GET ${HOST}/text`] = reply(`${HOST}/text`, "plain")
  runner.routes[`GET ${HOST}/empty`] = reply(`${HOST}/empty`, null, {}, 204)
  const result = await runner.evaluate(`Promise.all([["text", "/text"], ["", "/text"], ["json", "/empty"]].map(([type, url]) => new Promise(resolve => {
    const xhr = new XMLHttpRequest()
    xhr.open("GET", url)
    xhr.responseType = type
    xhr.onload = () => resolve(xhr.response)
    xhr.send()
  })))`)

  assert.deepEqual(result, ["plain", "plain", null])
})

test("XMLHttpRequest answers a stub without asking Rails", async () => {
  await runner.load("<p>Page</p>")
  await runner.run({ command: "stub_fetch", url: "/stubbed", response: { status: 200, headers: {}, body: "stubbed" } })
  const result = await runner.evaluate(`new Promise(resolve => {
    const xhr = new XMLHttpRequest()
    xhr.open("GET", "/stubbed")
    xhr.onload = () => resolve(xhr.responseText)
    xhr.send()
  })`)

  assert.deepEqual([result, runner.requests.length], ["stubbed", 0])
})

test("a refused XMLHttpRequest fires error with status 0", async () => {
  await runner.load("<p>Page</p>")
  runner.routes["GET https://elsewhere.test/x"] = { error: "refused" }
  const result = await runner.evaluate(`new Promise(resolve => {
    const xhr = new XMLHttpRequest()
    xhr.open("GET", "https://elsewhere.test/x")
    xhr.onerror = () => resolve(["error", xhr.status, xhr.readyState])
    xhr.send()
  })`)

  assert.deepEqual(result, ["error", 0, 4])
})

test("an aborted XMLHttpRequest fires nothing when Rails answers", async () => {
  await runner.load("<p>Page</p>")
  runner.routes[`GET ${HOST}/slow`] = reply(`${HOST}/slow`, "late")
  const result = await runner.evaluate(`(async () => {
    const events = []
    const xhr = new XMLHttpRequest()
    xhr.open("GET", "/slow")
    xhr.onloadend = () => events.push("loadend")
    xhr.send()
    xhr.abort()
    await new Promise(resolve => setTimeout(resolve, 10))
    return events
  })()`)

  assert.deepEqual(result, [])
})

test("XMLHttpRequest refuses synchronous requests and unsupported response types", async () => {
  await runner.load("<p>Page</p>")
  runner.routes[`GET ${HOST}/blob`] = reply(`${HOST}/blob`, "data")

  await assert.rejects(runner.evaluate(`new XMLHttpRequest().open("GET", "/x", false)`), /synchronous XMLHttpRequest is not supported/)
  await assert.rejects(runner.evaluate(`const xhr = new XMLHttpRequest(); xhr.open("GET", "/blob"); xhr.responseType = "blob"; xhr.send()`), /responseType "blob" is not supported/)
})

test("a page that was replaced sends no XMLHttpRequest", async () => {
  await runner.load(`<a href="/next">Next</a>`)
  runner.routes[`GET ${HOST}/slow`] = "hold"
  runner.routes[`GET ${HOST}/next`] = reply(`${HOST}/next`, "<p>Next</p>", { "content-type": "text/html" })
  const action = runner.evaluate(`fetch("/slow").then(() => { const xhr = new XMLHttpRequest(); xhr.open("GET", "/after"); xhr.send() }); document.querySelector("a").click()`)
  await waitFor(() => runner.requests.length === 2)
  runner.reply(runner.held[0].id, reply(`${HOST}/slow`, ""))
  await action
  await new Promise(resolve => setTimeout(resolve, 20))

  assert.deepEqual(runner.requests.map(request => request.url).sort(), [`${HOST}/next`, `${HOST}/slow`])
})

test("fetch sends a Blob body with the Blob's type unless a content type is set", async () => {
  await runner.load("<p>Page</p>")
  await runner.evaluate(`Promise.all([
    fetch("/typed", { method: "POST", body: new Blob(["a"], { type: "text/csv" }) }),
    fetch("/set", { method: "POST", headers: { "Content-Type": "image/png" }, body: new Blob(["b"], { type: "text/csv" }) }),
    fetch("/untyped", { method: "POST", body: new Blob(["c"]) })
  ])`)

  assert.deepEqual(runner.requests.map(request => [request.url, bodyText(request), request.headers["content-type"]]), [[`${HOST}/typed`, "a", "text/csv"], [`${HOST}/set`, "b", "image/png"], [`${HOST}/untyped`, "c", undefined]])
})

test("a file chooser that a script opens receives the expected files", async () => {
  await runner.load(`<button id="b">Upload</button>`)
  await runner.evaluate(`document.getElementById("b").addEventListener("click", () => {
    const input = Object.assign(document.createElement("input"), { type: "file", multiple: true })
    input.addEventListener("change", () => { document.body.dataset.files = [...input.files].map(file => file.name).join(",") })
    input.click()
  })`)
  await runner.run({ command: "expect_file_chooser", files: [file("a.txt", "a"), file("b.txt", "b")] })
  await runner.run({ command: "click", locator: "Upload", scope: [], match: null })
  const opened = await runner.run({ command: "file_chooser_opened" })

  assert.deepEqual([opened, await runner.evaluate("document.body.dataset.files")], [true, "a.txt,b.txt"])
})

test("only a file field whose click is not prevented opens a file chooser, once per expectation", async () => {
  await runner.load(`<input type="file" id="prevented"><input type="file" id="off" disabled><input type="checkbox" id="box"><input type="file" id="first"><input type="file" id="second">`)
  await runner.evaluate(`document.getElementById("prevented").addEventListener("click", event => event.preventDefault())`)
  await runner.evaluate(`["prevented", "off", "first"].forEach(id => document.getElementById(id).click())`)
  await runner.run({ command: "expect_file_chooser", files: [file("a.txt", "a")] })
  await runner.evaluate(`["prevented", "off", "box"].forEach(id => document.getElementById(id).click())`)
  const unopened = await runner.run({ command: "file_chooser_opened" })
  await runner.run({ command: "expect_file_chooser", files: [file("a.txt", "a")] })
  await runner.evaluate(`document.getElementById("first").click(); document.getElementById("second").click()`)
  const opened = await runner.run({ command: "file_chooser_opened" })
  const files = await runner.evaluate(`["first", "second"].map(id => document.getElementById(id).files.length)`)

  assert.deepEqual([unopened, opened, files, await runner.run({ command: "file_chooser_opened" }), await runner.evaluate("document.getElementById('box').checked")], [false, true, [1, 0], false, true])
})

test("a file chooser fails the action when its field cannot take the files", async () => {
  await runner.load(`<input type="file" id="one">`)
  await runner.run({ command: "expect_file_chooser", files: [file("a.txt", "a"), file("b.txt", "b")] })

  await assert.rejects(runner.evaluate(`document.getElementById("one").click()`), /does not allow multiple files/)
})

test("images fire load once their source is set, without being fetched", async () => {
  await runner.load(`<img id="parsed" src="/a.png"><img id="empty" src=""><script id="s"></script>`)
  const result = await runner.evaluate(`(async () => {
    const loaded = []
    const listen = (element, name) => element.addEventListener("load", () => loaded.push(name))
    const detached = new Image()
    listen(detached, "detached")
    detached.src = "/b.png"
    detached.src = "/b.png"
    document.body.append(detached)
    const blank = new Image()
    listen(blank, "blank")
    blank.src = ""
    const parsed = document.getElementById("parsed")
    listen(parsed, "changed")
    parsed.setAttribute("src", "/c.png")
    document.getElementById("s").setAttribute("src", "/s.js")
    await new Promise(resolve => setTimeout(resolve, 1))
    return loaded
  })()`)

  assert.deepEqual([result, runner.requests.length], [["detached", "changed"], 0])
})

test("object URLs are blob URLs on the page's origin", async () => {
  await runner.load("<p>Page</p>")
  const result = await runner.evaluate(`[URL.createObjectURL(new Blob(["a"])), URL.createObjectURL(new Blob(["b"])), URL.revokeObjectURL("blob:x")]`)

  assert.match(result[0], new RegExp(`^blob:${HOST}/\\d+$`))
  assert.notEqual(result[0], result[1])
  assert.equal(result[2], null)
})
