const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const State = require("./State.js")

const dir = __dirname

test("untrusted names stay bounded and lose control characters", function() {
  const tracker = '<img src="https://example.invalid/tracker">'
  const name = State.plain("\u0000" + tracker + "x".repeat(500), 64)
  assert.ok(name.length <= 64)
  assert.equal(name.includes("\u0000"), false)
  assert.ok(name.startsWith("<img"))
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
