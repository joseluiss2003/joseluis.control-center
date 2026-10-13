// Pure helpers for the control center. Names from the network status are
// untrusted: cap them and drop control characters. The panel renders with
// PlainText.

function plain(value, maxLen) {
  var limit = Number(maxLen)
  if (!isFinite(limit) || limit < 1) limit = 160
  limit = Math.min(400, Math.floor(limit))
  var text = String(value == null ? "" : value)
  text = text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
  text = text.replace(/^\s+|\s+$/g, "")
  if (text.length > limit) text = text.slice(0, limit)
  return text
}

function brightnessPercent(text) {
  var match = String(text || "").match(/(\d{1,3})/)
  if (!match) return null
  var n = Number(match[1])
  if (!isFinite(n)) return null
  return Math.max(0, Math.min(100, n))
}

function brightnessArg(percent) {
  var n = Math.round(Number(percent))
  if (!isFinite(n)) return null
  n = Math.max(1, Math.min(100, n))
  return n + "%"
}

function flagEnabled(text) {
  var raw = String(text || "").replace(/^\s+|\s+$/g, "")
  if (!raw) return null
  try {
    var parsed = JSON.parse(raw)
    return !!(parsed && parsed.enabled === true)
  } catch (e) {
    return null
  }
}

function dndEnabled(text) {
  var raw = String(text || "").replace(/^\s+|\s+$/g, "")
  if (!raw) return false
  try {
    var parsed = JSON.parse(raw)
    if (!parsed || typeof parsed.dnd !== "boolean") return null
    return parsed.dnd === true
  } catch (e) {
    return null
  }
}

function networkStatus(text) {
  var line = String(text || "").split("\n")[0]
  var parts = line.split("\t")
  var kind = parts[0] || ""
  if (kind !== "wifi" && kind !== "ethernet" && kind !== "disconnected") kind = "disconnected"
  return { kind: kind, name: plain(parts[1] || "", 64) }
}

function dndArg(on) {
  return on ? "on" : "off"
}

function idleArg(stayAwake) {
  return stayAwake ? "stay-awake" : "allow-idle"
}

function bluetoothPowerArg(on) {
  return on ? "on" : "off"
}

// Fixed argv only. Unknown ids return null so a menu row can never
// invent a shell command.
function sessionCommand(actionId) {
  if (actionId === "lock") return ["omarchy-system-lock"]
  if (actionId === "suspend") return ["systemctl", "suspend"]
  if (actionId === "hibernate") return ["systemctl", "hibernate"]
  if (actionId === "logout") return ["omarchy-system-logout"]
  if (actionId === "reboot") return ["omarchy-system-reboot"]
  if (actionId === "shutdown") return ["omarchy-system-shutdown"]
  return null
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    plain: plain,
    brightnessPercent: brightnessPercent,
    brightnessArg: brightnessArg,
    flagEnabled: flagEnabled,
    dndEnabled: dndEnabled,
    networkStatus: networkStatus,
    dndArg: dndArg,
    idleArg: idleArg,
    bluetoothPowerArg: bluetoothPowerArg,
    sessionCommand: sessionCommand
  }
}
