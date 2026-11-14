"use strict"

const { test, before, beforeEach } = require("node:test")
const assert = require("node:assert/strict")
const { HOST, connect, prepare, clear } = require("./support")

const runner = connect()

before(() => prepare(runner))
beforeEach(() => clear(runner))

const read = script => runner.evaluate(script)
const typeInto = async (keys, selector) => {
  const [element] = await runner.run({ command: "query", strategy: "css", locator: selector, scope: [] })
  return runner.run({ command: "element", handle: element.handle, action: "send_keys", keys })
}
const type = (keys, selector) => selector ? runner.evaluate(`document.querySelector("${selector}").focus()`).then(() => runner.run({ command: "send_keys", keys })) : runner.run({ command: "send_keys", keys })
const text = value => ({ text: value })
const key = (name, modifiers) => modifiers ? { key: name, modifiers } : { key: name }

async function waitFor(condition) {
  while (!condition()) await new Promise(resolve => setTimeout(resolve, 1))
}

test("send_keys by handle focuses the element first", async () => {
  await runner.load(`<input id="a">`)
  const [field] = await runner.run({ command: "query", strategy: "css", locator: "#a", scope: [] })
  await runner.run({ command: "element", handle: field.handle, action: "send_keys", keys: [text("hi")] })

  assert.equal(await read("a.value"), "hi")
})

test("characters dispatch keydown, keypress, input and keyup with their key and code", async () => {
  await runner.load(`<input id="a"><script>window.events = []; for (const type of ["keydown", "keypress", "input", "keyup"]) a.addEventListener(type, e => events.push([type, e.key ?? e.data, e.code ?? e.inputType].join(" ")))</script>`)
  await type([text("a7 ")], "#a")

  assert.deepEqual(await read("events"), [
    "keydown a KeyA", "keypress a KeyA", "input a insertText", "keyup a KeyA",
    "keydown 7 Digit7", "keypress 7 Digit7", "input 7 insertText", "keyup 7 Digit7",
    "keydown   Space", "keypress   Space", "input   insertText", "keyup   Space"
  ])
})

test("modifiers are set on the key events and a held control key types nothing", async () => {
  await runner.load(`<input id="a" onkeydown="window.seen = [event.shiftKey, event.ctrlKey, event.altKey, event.metaKey]">`)
  await type([{ text: "a", modifiers: ["shift", "ctrl", "alt", "command"] }], "#a")

  assert.deepEqual(await read("[seen, a.value]"), [[true, true, true, true], ""])
})

test("a prevented keydown or keypress stops the character", async () => {
  await runner.load(`<input id="a" onkeydown="if (event.key === 'x') event.preventDefault()" onkeypress="if (event.key === 'y') event.preventDefault()">`)
  await type([text("axyb")], "#a")

  assert.equal(await read("a.value"), "ab")
})

test("backspace deletes the last character, and does nothing in an empty field", async () => {
  await runner.load(`<input id="a" value="ab"><input id="e" oninput="window.fired = true">`)
  await type([key("backspace")], "#a")
  await type([key("backspace")], "#e")

  assert.deepEqual(await read("[a.value, window.fired]"), ["a", null])
})

test("keys do not edit a disabled or read-only field", async () => {
  await runner.load(`<input id="r" readonly value="r">`)
  await type([text("x"), key("backspace")], "#r")

  assert.equal(await read("r.value"), "r")
})

test("enter in a textarea adds a new line", async () => {
  await runner.load(`<textarea id="t">a</textarea>`)
  await type([key("enter"), text("b")], "#t")

  assert.equal(await read("t.value"), "a\nb")
})

test("enter clicks a focused link or button", async () => {
  await runner.load(`<button id="b" onclick="window.pressed = 'button'">B</button><a id="l" href="#x" onclick="window.followed = true">L</a>`)
  await type([key("enter")], "#b")
  await type([key("enter")], "#l")

  assert.deepEqual(await read("[pressed, followed]"), ["button", true])
})

test("enter in a field submits its form through the first submit button", async () => {
  await runner.load(`<form action="/a"><input id="q" name="q" value="x"><button type="button">No</button><button name="via" value="go">Go</button></form>`)
  await type([key("enter")], "#q")

  assert.equal(runner.requests[0].url, `${HOST}/a?q=x&via=go`)
})

test("enter in a field of a form without a submit button submits the form", async () => {
  await runner.load(`<form action="/b"><input id="q" name="q" value="y"></form>`)
  await type([key("enter")], "#q")

  assert.equal(runner.requests[0].url, `${HOST}/b?q=y`)
})

test("enter outside a form, or on a field that is not text, does nothing", async () => {
  await runner.load(`<input id="loose"><form action="/c"><input type="checkbox" id="c"></form>`)
  await type([key("enter")], "#loose")
  await type([key("enter")], "#c")

  assert.equal(runner.requests.length, 0)
})

test("space presses a focused button or checkbox", async () => {
  await runner.load(`<button id="b" onclick="window.pressed = true">B</button><input type="checkbox" id="c">`)
  await type([key("space")], "#b")
  await type([key("space")], "#c")

  assert.deepEqual(await read("[pressed, c.checked]"), [true, true])
})

test("arrow keys, home and end step range and number fields", async () => {
  await runner.load(`<input type="range" id="r" min="2" max="8" value="5"><input type="range" id="d" value="50"><input type="number" id="n" value="1">`)
  await type([key("right"), key("up"), key("left")], "#r")
  const stepped = await read("r.value")
  await type([key("home")], "#r")
  const lowest = await read("r.value")
  await type([key("end")], "#r")
  const highest = await read("r.value")
  await type([key("home")], "#d")
  const defaultLowest = await read("d.value")
  await type([key("end")], "#d")
  await type([key("down")], "#n")

  assert.deepEqual([stepped, lowest, highest, defaultLowest, await read("d.value"), await read("n.value")], ["6", "2", "8", "0", "100", "0"])
})

test("keys without a default action, or on an element they do not affect, only dispatch events", async () => {
  await runner.load(`<input type="range" id="r" value="5"><p id="p" tabindex="0">P</p><script>window.keys = []; document.addEventListener("keydown", e => keys.push(e.key))</script>`)
  await type([key("escape"), key("delete"), key("page_up"), key("page_down")], "#r")
  await type([text("x")], "#p")

  assert.deepEqual(await read("[keys, r.value]"), [["Escape", "Delete", "PageUp", "PageDown", "x"], "5"])
})

test("tab moves focus in tab order, positive tabindex first, skipping disabled, hidden and negative tabindex", async () => {
  await runner.load(`<input id="a"><input id="off" disabled><input id="gone" hidden><input id="skip" tabindex="-1"><input id="b"><input id="two" tabindex="2"><input id="one" tabindex="1">`)
  const order = []
  await type([key("tab")])
  for (let index = 0; index < 4; index += 1) {
    order.push(await read("document.activeElement.id"))
    await type([key("tab")])
  }

  assert.deepEqual(order, ["one", "two", "a", "b"])
  assert.equal(await read("document.activeElement.id"), "one")
})

test("shift+tab moves focus back, and from the page to the last element", async () => {
  await runner.load(`<input id="a"><input id="b">`)
  await type([key("tab", ["shift"])])
  const fromPage = await read("document.activeElement.id")
  await type([key("tab", ["shift"])])

  assert.deepEqual([fromPage, await read("document.activeElement.id")], ["b", "a"])
})

test("tab fires change on a field whose typed value changed", async () => {
  await runner.load(`<input id="a" onchange="window.changes = (window.changes || 0) + 1"><input id="b">`)
  await type([text("x"), key("backspace"), key("tab")], "#a")
  const unchanged = await read("window.changes")
  await type([text("y"), key("tab")], "#a")

  assert.deepEqual([unchanged, await read("window.changes")], [null, 1])
})

test("tab on a page with nothing to focus keeps the focus where it is", async () => {
  await runner.load(`<p>Nothing to focus</p>`)
  await type([key("tab")])

  assert.equal(await read("document.activeElement.localName"), "body")
})

test("an unknown key or modifier fails", async () => {
  await runner.load(`<input id="a">`)

  await assert.rejects(type([key("launch")], "#a"), /unknown key launch/)
  await assert.rejects(type([{ text: "a", modifiers: ["hyper"] }], "#a"), /unknown modifier key hyper/)
})

const EDITABLE_EVENTS = `<script>
  window.events = []
  for (const type of ["beforeinput", "input"]) document.addEventListener(type, event => events.push([type, event.inputType, event.data].join(" ")))
</script>`

test("typing into a contenteditable puts the caret at the end, then inserts each character as a browser does", async () => {
  await runner.load(`<div id="e" contenteditable="true"><p>Hel</p></div>${EDITABLE_EVENTS}`)
  await typeInto([text("lo")], "#e")

  assert.deepEqual([await read("e.innerHTML"), await read("events")], ["<p>Hello</p>", ["beforeinput insertText l", "input insertText l", "beforeinput insertText o", "input insertText o"]])
})

test("typing into a focused contenteditable keeps the caret where it is", async () => {
  await runner.load(`<div id="e" contenteditable>ac</div>`)
  await read("e.focus(); getSelection().collapse(e.firstChild, 1); true")
  await typeInto([text("b")], "#e")

  assert.equal(await read("e.textContent"), "abc")
})

test("typing into an empty contenteditable creates its text", async () => {
  await runner.load(`<div id="e" contenteditable></div>`)
  await typeInto([text("Hi")], "#e")

  assert.equal(await read("e.innerHTML"), "Hi")
})

test("backspace in a contenteditable deletes before the caret, and nothing at its start", async () => {
  await runner.load(`<div id="e" contenteditable>ab</div>`)
  await typeInto([key("backspace"), key("backspace"), key("backspace")], "#e")

  assert.equal(await read("e.innerHTML"), "")
})

test("enter and shift+enter in a contenteditable insert a break, with the paragraph or line break input type", async () => {
  await runner.load(`<div id="e" contenteditable>a</div>${EDITABLE_EVENTS}`)
  await typeInto([key("enter"), key("enter", ["shift"])], "#e")

  assert.deepEqual([await read("e.innerHTML"), await read("events.filter(event => event.startsWith('input'))")], ["a<br><br>", ["input insertParagraph ", "input insertLineBreak "]])
})

test("backspace after typing past a break in a contenteditable deletes the last character typed", async () => {
  await runner.load(`<div id="e" contenteditable>a</div>`)
  await typeInto([key("enter"), text("xy"), key("backspace")], "#e")

  assert.equal(await read("e.innerHTML"), "a<br>x")
})

test("backspace in a contenteditable deletes a break before the caret, then the text before it", async () => {
  await runner.load(`<div id="e" contenteditable>ab</div>`)
  await typeInto([key("enter"), key("backspace"), key("backspace")], "#e")

  assert.equal(await read("e.innerHTML"), "a")
})

test("backspace in a contenteditable removes an empty text node before the caret", async () => {
  await runner.load(`<div id="e" contenteditable>a</div>`)
  await read(`e.append(""); e.focus(); getSelection().collapse(e, 2); true`)
  await runner.run({ command: "send_keys", keys: [key("backspace")] })

  assert.deepEqual([await read("e.childNodes.length"), await read("e.textContent")], [1, "a"])
})

test("an editor that cancels beforeinput keeps the content, and no input event fires", async () => {
  await runner.load(`<div id="e" contenteditable>a</div>${EDITABLE_EVENTS}<script>e.addEventListener("beforeinput", event => event.preventDefault())</script>`)
  await typeInto([text("b")], "#e")

  assert.deepEqual([await read("e.textContent"), await read("events")], ["a", ["beforeinput insertText b"]])
})

test("a held control key or a key without an edit types nothing into a contenteditable", async () => {
  await runner.load(`<div id="e" contenteditable>a</div>${EDITABLE_EVENTS}`)
  await typeInto([{ text: "b", modifiers: ["control"] }, key("up")], "#e")

  assert.deepEqual([await read("e.textContent"), await read("events")], ["a", []])
})

test("an element inside a contenteditable is editable, and contenteditable=false inside it is not", async () => {
  await runner.load(`<div id="e" contenteditable><span id="s">a</span><span id="off" contenteditable="false" tabindex="0"><b id="b">x</b></span></div>`)
  await typeInto([text("c")], "#off")

  assert.deepEqual([await read("e.textContent"), await read("[e.isContentEditable, s.isContentEditable, off.isContentEditable, b.isContentEditable]")], ["ax", [true, true, false, false]])
})

test("tasks queued while a key is handled run before the next key, as between real keystrokes", async () => {
  await runner.load(`<input id="a"><script>window.events = []; a.addEventListener("keydown", event => { events.push(event.key); Promise.resolve().then(() => setTimeout(() => events.push("task " + event.key), 0)) })</script>`)
  await type([text("ab")], "#a")

  assert.deepEqual(await read("events"), ["a", "task a", "b", "task b"])
})

test("typing many keys on a page with nothing else to do settles, however long the keys take", async () => {
  await runner.load(`<input id="a">`)
  await type([text("x".repeat(400))], "#a")

  assert.equal(await read("a.value.length"), 400)
})

test("the clock does not move between keys, so timers a key starts run after the last key", async () => {
  await runner.load(`<input id="a"><script>window.events = []; a.addEventListener("keydown", event => { events.push(event.key); setTimeout(() => events.push("timer " + event.key), 10) })</script>`)
  await type([text("abc")], "#a")

  assert.deepEqual(await read("events"), ["a", "b", "c", "timer a", "timer b", "timer c"])
})

test("a request a key starts is answered before the next key", async () => {
  await runner.load(`<input id="a"><script>window.events = []; a.addEventListener("keydown", event => { events.push(event.key); fetch("/suggest").then(response => response.text()).then(body => events.push(body + " " + event.key)) })</script>`, `${HOST}/`)
  runner.routes[`GET ${HOST}/suggest`] = "hold"
  const answer = { status: 200, headers: {}, body: "answer", url: `${HOST}/suggest`, redirected: false }
  const typing = type([text("ab")], "#a")
  await waitFor(() => runner.held.length === 1)
  await new Promise(resolve => setTimeout(resolve, 20))
  const heldWhileWaiting = runner.held.length
  runner.reply(runner.held[0].id, answer)
  await waitFor(() => runner.held.length === 2)
  runner.reply(runner.held[1].id, answer)
  await typing

  assert.deepEqual([heldWhileWaiting, await read("events")], [1, ["a", "answer a", "b", "answer b"]])
})

test("a key whose tasks never stop fails to settle", async () => {
  await runner.load(`<input id="a"><script>a.addEventListener("keydown", () => { (function loop() { setTimeout(loop, 0) })() })</script>`)

  await assert.rejects(type([text("ab")], "#a"), /the page did not settle/)
})

test("keys sent to a focused contenteditable whose selection is elsewhere type at its end", async () => {
  await runner.load(`<p id="p">Elsewhere</p><div id="e" contenteditable>ab</div>`)
  await read("e.focus(); getSelection().collapse(p.firstChild, 2); true")
  await runner.run({ command: "send_keys", keys: [text("c")] })

  assert.deepEqual([await read("e.textContent"), await read("p.textContent")], ["abc", "Elsewhere"])
})

test("Selenium's names for the arrow keys and return work as in system tests", async () => {
  await runner.load(`<input id="a"><script>window.keys = []; a.addEventListener("keydown", event => keys.push(event.key))</script>`)
  await type([key("arrow_left"), key("arrow_right"), key("arrow_up"), key("arrow_down"), key("return")], "#a")

  assert.deepEqual(await read("keys"), ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Enter"])
})
