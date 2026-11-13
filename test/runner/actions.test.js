"use strict"

const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { connect, prepare, clear } = require("./support")

const runner = connect()

before(() => prepare(runner))
beforeEach(() => clear(runner))

const act = (command, locator, options = {}) => runner.run({ command, locator, scope: [], match: null, ...options })
const read = script => runner.evaluate(script)
const query = (strategy, locator, scope = []) => runner.run({ command: "query", strategy, locator, scope })
const element = (handle, action, options = {}) => runner.run({ command: "element", handle, action, ...options })
const handleOf = async (selector, scope) => (await query("css", selector, scope))[0].handle

test("click finds a button by Stimulus action shorthand, ignoring the event and options", async () => {
  await runner.load(`<button data-action="click->menu#open:prevent other#run" onclick="this.dataset.clicked = 'yes'">Open</button>`)
  await act("click", "menu#open")

  assert.equal(await read(`document.querySelector("button").dataset.clicked`), "yes")
})

test("click finds an element by exact text before partial text", async () => {
  await runner.load(`<button onclick="window.hit = 'long'">Save draft</button><button onclick="window.hit = 'exact'">Save</button>`)
  await act("click", "Save")

  assert.equal(await read("hit"), "exact")
})

test("click finds an element by partial text, aria-label, title, id or button value", async () => {
  await runner.load(`
    <button onclick="hits.push('partial')">Archive all</button>
    <button aria-label="Close dialog" onclick="hits.push('aria')">x</button>
    <a href="#" title="Help page" onclick="hits.push('title')">?</a>
    <span id="badge" role="button" onclick="hits.push('id')">!</span>
    <input type="submit" value="Send now" onclick="hits.push('value'); return false">
    <script>window.hits = []</script>`)
  for (const locator of ["Archive", "Close dialog", "Help page", "badge", "Send now"]) await act("click", locator)

  assert.deepEqual(await read("hits"), ["partial", "aria", "title", "id", "value"])
})

test("click finds a button by its name, as system tests do", async () => {
  await runner.load(`
    <button name="log_in" onclick="hits.push('button'); return false"><span>Go</span></button>
    <input type="submit" name="save" value="Keep" onclick="hits.push('input'); return false">
    <script>window.hits = []</script>`)
  for (const locator of ["log_in", "save"]) await act("click", locator)

  assert.deepEqual(await read("hits"), ["button", "input"])
})

test("click does not find a link by its name, as system tests do not", async () => {
  await runner.load(`<a href="#" name="log_out">Leave</a>`)

  await assert.rejects(act("click", "log_out"), /unable to find "log_out"/)
})

test("click falls back to a CSS selector, and an invalid selector finds nothing", async () => {
  await runner.load(`<p class="tap" onclick="window.hit = true">Text</p>`)
  await act("click", "p.tap")

  assert.equal(await read("hit"), true)
  await assert.rejects(act("click", "[[["), /unable to find "\[\[\["/)
})

test("click only matches the requested kind of element", async () => {
  await runner.load(`<a href="#x">Go</a><button>Go</button>`)

  await assert.rejects(act("click", "Go"), /"Go" matches 2 elements/)
  await assert.rejects(act("click", "Nothing", { kind: "link" }), /unable to find "Nothing"/)
  assert.equal(await act("click", "Go", { kind: "button" }), null)
})

test("match first picks the first of several matches", async () => {
  await runner.load(`<button onclick="window.hit = 1">Go</button><button onclick="window.hit = 2">Go</button>`)
  await act("click", "Go", { match: "first" })

  assert.equal(await read("hit"), 1)
})

test("click fails on a disabled element", async () => {
  await runner.load(`<button disabled>Off</button>`)

  await assert.rejects(act("click", "Off"), /<button disabled="">Off<\/button> is disabled/)
})

test("click dispatches events on an element without its own click method", async () => {
  await runner.load(`<svg><circle id="dot" onclick="window.hit = true"></circle></svg>`)
  await act("click", "#dot")

  assert.equal(await read("hit"), true)
})

test("within scopes to one element by CSS, fieldset legend or id, table caption or id, or handle", async () => {
  await runner.load(`
    <div id="a"><button onclick="hits.push('css')">Go</button></div>
    <fieldset><legend>Billing</legend><button onclick="hits.push('legend')">Go</button></fieldset>
    <fieldset id="shipping"><button onclick="hits.push('fieldset id')">Go</button></fieldset>
    <table><caption>Prices</caption><tr><td><button onclick="hits.push('caption')">Go</button></td></tr></table>
    <table id="totals"><tr><td><button onclick="hits.push('table id')">Go</button></td></tr></table>
    <section><button onclick="hits.push('handle')">Go</button></section>
    <script>window.hits = []</script>`)
  const section = await handleOf("section")
  for (const scope of [[{ css: "#a" }], [{ fieldset: "Billing" }], [{ fieldset: "shipping" }], [{ table: "Prices" }], [{ table: "totals" }], [{ handle: section }]]) await act("click", "Go", { scope })

  assert.deepEqual(await read("hits"), ["css", "legend", "fieldset id", "caption", "table id", "handle"])
})

test("within fails unless its scope matches exactly one element", async () => {
  await runner.load(`<div class="x"></div><div class="x"></div>`)

  await assert.rejects(act("click", "Go", { scope: [{ css: ".x" }] }), /within {"css":".x"} matches 2 elements/)
})

test("fill_in finds a field by label, then placeholder, name, id or aria-label, and fires input and change", async () => {
  await runner.load(`
    <label for="a">Email</label><input id="a">
    <input placeholder="Search">
    <input name="city">
    <input id="zip">
    <input aria-label="Phone">
    <textarea name="notes"></textarea>
    <script>window.events = []; document.addEventListener("input", e => events.push("input " + e.target.value)); document.addEventListener("change", e => events.push("change"))</script>`)
  for (const [locator, value] of [["Email", "a@b.test"], ["Search", "mugs"], ["city", "Oslo"], ["zip", "0150"], ["Phone", "123"], ["notes", "hi"]]) await act("fill_in", locator, { with: value })

  assert.equal((await read("events")).length, 12)
  assert.deepEqual(await read(`[...document.querySelectorAll("input, textarea")].map(f => f.value)`), ["a@b.test", "mugs", "Oslo", "0150", "123", "hi"])
})

test("fill_in fails on a disabled or read-only field and finds nothing for a missing label", async () => {
  await runner.load(`<input name="off" disabled><input name="fixed" readonly><label>Orphan</label>`)

  await assert.rejects(act("fill_in", "off", { with: "x" }), /is not editable/)
  await assert.rejects(act("fill_in", "fixed", { with: "x" }), /is not editable/)
  await assert.rejects(act("fill_in", "Orphan", { with: "x" }), /unable to find "Orphan"/)
})

test("check and choose click only when the state changes", async () => {
  await runner.load(`<input type="checkbox" name="a"><input type="checkbox" name="b" checked><input type="radio" name="r" id="r1"><script>window.clicks = 0; document.addEventListener("click", () => clicks += 1)</script>`)
  await act("check", "a", { checked: true })
  await act("check", "a", { checked: true })
  await act("check", "b", { checked: false })
  await act("choose", "r1")

  assert.deepEqual(await read(`[document.querySelector("[name=a]").checked, document.querySelector("[name=b]").checked, document.getElementById("r1").checked, clicks]`), [true, false, true, 3])
})

test("select picks an option by exact or partial text, in a named select or any select", async () => {
  await runner.load(`
    <label for="c">Country</label><select id="c"><option>Canada</option><option>Mexico City</option></select>
    <select id="m" multiple><option selected>Red</option><option>Green</option></select>`)
  await runner.run({ command: "select", option: "Mexico", from: "Country", selected: true, scope: [], match: null })
  await runner.run({ command: "select", option: "Green", from: null, selected: true, scope: [], match: null })
  await runner.run({ command: "select", option: "Red", from: null, selected: false, scope: [], match: null })

  assert.deepEqual(await read(`[document.getElementById("c").value, [...document.getElementById("m").selectedOptions].map(o => o.text)]`), ["Mexico City", ["Green"]])
})

test("select fails for a missing option, a disabled select or unselect on a single select", async () => {
  await runner.load(`<select id="s"><option>A</option></select><select id="off" disabled><option>B</option></select>`)

  await assert.rejects(runner.run({ command: "select", option: "Z", from: "s", selected: true, scope: [], match: null }), /option "Z" matches 0 elements/)
  await assert.rejects(runner.run({ command: "select", option: "B", from: null, selected: true, scope: [], match: null }), /is disabled/)
  await assert.rejects(runner.run({ command: "select", option: "A", from: null, selected: false, scope: [], match: "first" }), /unselect works only on a select that allows multiple options/)
})

test("attach puts files in a file field and fires change", async () => {
  await runner.load(`<input type="file" name="docs" multiple onchange="window.names = [...this.files].map(f => f.name + ' ' + f.type + ' ' + f.size)">`)
  const file = (name, text) => ({ name, type: "text/plain", base64: Buffer.from(text).toString("base64") })
  await act("attach", "docs", { files: [file("a.txt", "aa"), file("b.txt", "b")] })

  assert.deepEqual(await read("names"), ["a.txt text/plain 2", "b.txt text/plain 1"])
})

test("attach fails on a disabled field, several files for a single field, or a jsdom without private state", async () => {
  await runner.load(`<input type="file" name="off" disabled><input type="file" name="one">`)
  const file = { name: "a.txt", type: "text/plain", base64: "" }

  await assert.rejects(act("attach", "off", { files: [file] }), /is disabled/)
  await assert.rejects(act("attach", "one", { files: [file, file] }), /does not allow multiple files/)
  await read(`Object.defineProperty(document.querySelector("[name=one]"), "files", { value: {} })`)
  await assert.rejects(act("attach", "one", { files: [file] }), /attach_file does not work with this jsdom version/)
})

test("hover, double click and right click dispatch their events", async () => {
  await runner.load(`<div id="t" role="button">Target</div><script>window.events = []; for (const type of ["pointerover", "pointerenter", "mouseover", "mouseenter", "pointermove", "mousemove", "mousedown", "mouseup", "click", "dblclick", "contextmenu"]) document.getElementById("t").addEventListener(type, e => events.push(type + (e.button === 2 ? " right" : "") + (type === "pointerover" ? " " + (e instanceof PointerEvent) : "")))</script>`)
  await act("hover", "Target")
  await act("double_click", "Target")
  await act("right_click", "Target")

  assert.deepEqual(await read("events"), [
    "pointerover true", "pointerenter", "mouseover", "mouseenter", "pointermove", "mousemove",
    "mousedown", "mouseup", "click", "mousedown", "mouseup", "click", "dblclick",
    "mousedown right", "mouseup right", "contextmenu right"
  ])
})

test("query describes matches by CSS, field, button or link, or every element of a kind", async () => {
  await runner.load(`
    <label for="n">Name</label><input id="n" value="Ada" class="f">
    <button disabled>Save</button>
    <a href="/x">Link</a>
    <select name="s"><option selected>One</option></select>`)
  const [field] = await query("field", "Name")

  assert.deepEqual(field, { handle: field.handle, tag: "input", text: "", all_text: "", visible: true, value: "Ada", checked: false, selected: false, disabled: false, type: "text", attributes: { id: "n", value: "Ada", class: "f" } })
  assert.deepEqual((await query("button", "Save")).map(described => [described.tag, described.disabled]), [["button", true]])
  assert.deepEqual((await query("link", null)).map(described => described.attributes.href), ["/x"])
  assert.deepEqual((await query("css", "option")).map(described => [described.type, described.selected, described.value]), [["option", true, "One"]])
  assert.deepEqual((await query("css", "a")).map(described => described.value), [null])
})

test("the same node keeps its handle across queries", async () => {
  await runner.load(`<p>Text</p>`)

  assert.equal(await handleOf("p"), await handleOf("p"))
})

test("read describes an element by handle, and fails once it leaves the page", async () => {
  await runner.load(`<p id="p">Text</p>`)
  const handle = await handleOf("p")
  const described = await runner.run({ command: "read", handle })
  await read(`document.getElementById("p").remove()`)

  assert.equal(described.text, "Text")
  await assert.rejects(runner.run({ command: "read", handle }), /the element is no longer on the page/)
  await assert.rejects(runner.run({ command: "read", handle: 999 }), /the element is no longer on the page/)
})

test("visible text leaves out hidden elements, templates, comments and closed details, and spaces block elements", async () => {
  await runner.load(`<div>One<b>Two</b><!-- note --><span hidden>Hidden</span><template>T</template></div><div>Three</div><details><summary>More</summary><p>Inside</p></details><details open><summary>Open</summary><p>Shown</p></details>`)

  assert.equal((await runner.snapshot()).text, "OneTwo Three More Open Shown")
})

test("visibility follows hidden ancestors and closed details", async () => {
  await runner.load(`<div hidden><p id="a">A</p></div><details><summary id="s">S</summary><p id="d">D</p></details><p id="v">V</p>`)
  const visible = async id => (await query("css", `#${id}`))[0].visible

  assert.deepEqual([await visible("a"), await visible("s"), await visible("d"), await visible("v")], [false, true, false, true])
})

test("snapshot of a scope is that element's HTML and text", async () => {
  await runner.load(`<div id="a"><p>Inside</p></div><p>Outside</p>`)
  const snapshot = await runner.snapshot([{ css: "#a" }])

  assert.deepEqual([snapshot.html, snapshot.text], [`<div id="a"><p>Inside</p></div>`, "Inside"])
})

test("element actions click, hover, double click, right click and set by handle", async () => {
  await runner.load(`<button id="b" onclick="window.clicks = (window.clicks || 0) + 1" onmouseenter="window.hovered = true" oncontextmenu="window.context = true">B</button><input id="t">`)
  const button = await handleOf("#b")
  await element(button, "click")
  await element(button, "hover")
  await element(button, "double_click")
  await element(button, "right_click")
  await element(await handleOf("#t"), "set", { value: "typed" })

  assert.deepEqual(await read(`[clicks, hovered, context, document.getElementById("t").value]`), [3, true, true, "typed"])
})

test("set checks a checkbox, chooses or leaves a radio button and fills contenteditable", async () => {
  await runner.load(`<input type="checkbox" id="c"><input type="radio" id="r"><input type="radio" id="q"><div id="e" contenteditable oninput="window.edited = this.textContent"></div>`)
  await element(await handleOf("#c"), "set", { value: true })
  await element(await handleOf("#r"), "set", { value: true })
  await element(await handleOf("#q"), "set", { value: false })
  await element(await handleOf("#e"), "set", { value: "Draft" })

  assert.deepEqual(await read(`[c.checked, r.checked, q.checked, edited]`), [true, true, false, "Draft"])
})

test("set fails on an element it cannot set", async () => {
  await runner.load(`<select id="s"></select><div id="d" contenteditable="false"></div>`)

  await assert.rejects(element(await handleOf("#s"), "set", { value: "x" }), /set does not work on <select id="s"><\/select>; use select, attach_file or click/)
  await assert.rejects(element(await handleOf("#d"), "set", { value: "x" }), /set does not work on/)
})

test("select_option and unselect_option change an option by handle", async () => {
  await runner.load(`<select id="m" multiple><option id="a" selected>A</option><option id="b">B</option></select><p id="p">P</p>`)
  await element(await handleOf("#b"), "select_option")
  await element(await handleOf("#a"), "unselect_option")

  assert.deepEqual(await read(`[...m.selectedOptions].map(o => o.text)`), ["B"])
  await assert.rejects(element(await handleOf("#p"), "select_option"), /select_option works only on an option inside a select/)
})

test("an unknown element action fails", async () => {
  await runner.load(`<p>P</p>`)

  await assert.rejects(element(await handleOf("p"), "squeeze"), /unknown element action squeeze/)
})

test("click without a locator clicks the only element of its kind in the scope, or the first with match first", async () => {
  await runner.load(`<form id="f"><input name="q"><button onclick="hits.push('save'); return false">Save</button></form><p><a href="#a" onclick="hits.push('a')">A</a><a href="#b" onclick="hits.push('b')">B</a></p><script>window.hits = []</script>`)
  await act("click", null, { kind: "button", scope: [{ css: "#f" }] })
  await act("click", null, { kind: "link", match: "first" })

  assert.deepEqual(await read("hits"), ["save", "a"])
})

test("click without a locator fails when nothing, or more than one element, of its kind is in the scope", async () => {
  await runner.load(`<p><a href="#a">A</a><a href="#b">B</a></p><div id="empty"></div>`)

  await assert.rejects(act("click", null, { kind: "link" }), /any element of that kind matches 2 elements/)
  await assert.rejects(act("click", null, { kind: null, scope: [{ css: "#empty" }] }), /unable to find any element of that kind/)
})
