const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const State = require("./State.js")

const dir = __dirname

test("markup-shaped notification text stays literal, bounded, and sink-safe", function() {
  const tracker = '<img src="https://example.invalid/tracker">'
  const raw = JSON.stringify({
    app: tracker + "Mail",
    summary: "<b>hola</b>",
    body: tracker + "x".repeat(5000),
    execArgv: '["bash","-c","echo pwned"]',
    image: "https://example.invalid/pixel.png",
    timestamp: 1_700_000_000_000
  })
  const rows = State.notificationsFrom(raw, 1_700_000_060_000)
  assert.equal(rows.length, 1)
  assert.equal(rows[0].execArgv, undefined)
  assert.equal(rows[0].image, undefined)
  assert.ok(rows[0].app.includes("<img"))
  assert.ok(rows[0].body.length <= 280)
  assert.equal(State.sinkSafe(rows[0].summary).includes("<b>"), false)
  assert.equal(State.sinkSafe(tracker).includes("<img"), false)
  assert.ok(State.sinkSafe(tracker).includes("img"))
})

test("malformed and oversized notification lines are dropped", function() {
  const huge = " ".repeat(9000)
  const raw = [
    "not json",
    "{",
    huge,
    JSON.stringify({ summary: "ok", timestamp: 20 }),
    JSON.stringify({ summary: "older", timestamp: 10 }),
    JSON.stringify({ app: "", summary: "", body: "" })
  ].join("\n")
  const rows = State.notificationsFrom(raw, 100)
  assert.equal(rows.length, 2)
  assert.equal(rows[0].summary, "ok")
  assert.equal(rows[1].summary, "older")
})

test("notification count is capped", function() {
  const lines = []
  for (var i = 0; i < 30; i++) lines.push(JSON.stringify({ summary: "n" + i, timestamp: i }))
  const rows = State.notificationsFrom(lines.join("\n"), 1000)
  assert.equal(rows.length, 12)
  assert.equal(rows[0].summary, "n29")
})

test("status parsers reject junk and clamp brightness", function() {
  assert.equal(State.brightnessPercent("43\n"), 43)
  assert.equal(State.brightnessPercent("nope"), null)
  assert.equal(State.brightnessPercent("250"), 100)
  assert.equal(State.brightnessArg(0), "1%")
  assert.equal(State.brightnessArg(140), "100%")
  assert.equal(State.brightnessArg("40%"), null)
  assert.equal(State.flagEnabled('{"enabled":true,"temperature":4000}'), true)
  assert.equal(State.flagEnabled('{"enabled":false}'), false)
  assert.equal(State.flagEnabled("on"), null)
  assert.equal(State.dndEnabled(""), false)
  assert.equal(State.dndEnabled('{"version":3,"dnd":true}'), true)
  assert.equal(State.dndEnabled("{"), null)
  const network = State.networkStatus('wifi\t<cafe>\t70\t5200\n')
  assert.equal(network.kind, "wifi")
  assert.equal(network.name, "<cafe>")
  assert.equal(State.networkStatus("weird\tname").kind, "disconnected")
})

test("action arguments are fixed tokens", function() {
  assert.deepEqual([State.dndArg(true), State.dndArg(false)], ["on", "off"])
  assert.deepEqual(
    [State.idleArg(true), State.idleArg(false)],
    ["stay-awake", "allow-idle"]
  )
  assert.deepEqual(
    [State.bluetoothPowerArg(true), State.bluetoothPowerArg(false)],
    ["on", "off"]
  )
  for (const value of ["on", "off", "stay-awake", "allow-idle", "1%", "100%"]) {
    assert.equal(/^[a-z0-9%-]+$/.test(value), true)
  }
})

test("session actions are fixed commands", function() {
  assert.deepEqual(State.sessionCommand("lock"), ["omarchy-system-lock"])
  assert.deepEqual(State.sessionCommand("suspend"), ["systemctl", "suspend"])
  assert.deepEqual(State.sessionCommand("hibernate"), ["systemctl", "hibernate"])
  assert.deepEqual(State.sessionCommand("logout"), ["omarchy-system-logout"])
  assert.deepEqual(State.sessionCommand("reboot"), ["omarchy-system-reboot"])
  assert.deepEqual(State.sessionCommand("shutdown"), ["omarchy-system-shutdown"])
  assert.equal(State.sessionCommand("sep"), null)
  assert.equal(State.sessionCommand(""), null)
  assert.equal(State.sessionCommand("rm -rf /"), null)
  for (const id of ["lock", "suspend", "hibernate", "logout", "reboot", "shutdown"]) {
    for (const arg of State.sessionCommand(id)) assert.equal(/^[a-z0-9-]+$/.test(arg), true)
  }
})

test("panel text elements are plain text", function() {
  const qml = fs.readFileSync(path.join(dir, "ControlCenter.qml"), "utf8")
  assert.match(qml, /component PlainText: Text \{/)
  assert.match(qml, /textFormat: Text\.PlainText/)
  assert.equal(qml.includes("Text.RichText"), false)
  assert.equal(qml.includes("Text.StyledText"), false)
  assert.equal(qml.includes("Text.AutoText"), false)
  assert.equal(qml.includes("Text.MarkdownText"), false)
  const textBlocks = qml.match(/\bText\s*\{/g) || []
  assert.deepEqual(textBlocks, ["Text {"])
  assert.equal(qml.includes("execArgv"), false)
  assert.equal(qml.includes("bash -c"), false)
})
