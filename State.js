// Pure helpers for the control center. Notification text is untrusted: cap it,
// drop control characters, and keep a markup-neutral form for any sink whose
// text format this plugin cannot set. The panel itself renders with PlainText.

var MAX_NOTIFICATIONS = 12
var MAX_LINE = 8000
var MAX_LINES = 40

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

// Break a tag opener without deleting the characters the sender wrote.
// U+200B is not whitespace to Qt's styled-text parser, so "<img" stops
// being a tag name. Used only when text leaves this plugin's own PlainText.
function sinkSafe(value, maxLen) {
  return plain(value, maxLen).replace(/</g, "<\u200b")
}

function timeLabel(timestamp, now) {
  var t = Number(timestamp)
  var clock = Number(now)
  if (!isFinite(t) || t <= 0 || !isFinite(clock)) return ""
  var delta = clock - t
  if (delta < 0) delta = 0
  if (delta < 60000) return "ahora"
  var minutes = Math.floor(delta / 60000)
  if (minutes < 60) return minutes + " min"
  var hours = Math.floor(minutes / 60)
  if (hours < 48) return hours + " h"
  var days = Math.floor(hours / 24)
  if (days > 99) days = 99
  return days + " d"
}

function notificationsFrom(raw, now) {
  var lines = String(raw || "").split("\n")
  if (lines.length > MAX_LINES) lines = lines.slice(0, MAX_LINES)
  var entries = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line || line.length > MAX_LINE) continue
    var trimmed = line.replace(/^\s+|\s+$/g, "")
    if (!trimmed || trimmed.charAt(0) !== "{") continue
    var value
    try { value = JSON.parse(trimmed) } catch (e) { continue }
    if (!value || typeof value !== "object") continue
    var app = plain(value.app, 80)
    var summary = plain(value.summary, 160)
    var body = plain(value.body, 280)
    if (!app && !summary && !body) continue
    entries.push({
      app: app,
      summary: summary,
      body: body,
      whenLabel: timeLabel(value.timestamp, now),
      timestamp: Number(value.timestamp) || 0
    })
  }
  entries.sort(function(a, b) { return b.timestamp - a.timestamp })
  if (entries.length > MAX_NOTIFICATIONS) entries = entries.slice(0, MAX_NOTIFICATIONS)
  return entries
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
    sinkSafe: sinkSafe,
    timeLabel: timeLabel,
    notificationsFrom: notificationsFrom,
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
