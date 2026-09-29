// Pure time-zone and format math for the dual clock bar widget.
// No Qt, no DOM: runnable under node for a quick self-test
//   node kshitij.dual-clock/Model.js
// The QML owns all rendering; everything here decides what gets rendered.

// Format presets walked by left-click, matching the stock clock's ring style.
var FORMAT_PRESETS = ["HH:mm", "h:mm AP", "ddd HH:mm", "d MMM HH:mm"]

// Time zone presets walked by right-click. The configured zone is always
// appended to the ring, so a hand-set zone is reachable but never lost.
var TIMEZONE_PRESETS = ["America/Chicago", "UTC", "Asia/Kathmandu", "Asia/Kolkata", "Europe/London"]

// IANA zone ids are letters, digits, underscores, plus/minus, and slashes
// ("America/Chicago", "UTC"). Anything else never reaches the TZ env var.
function isValidTimezone(tz) {
  if (typeof tz !== "string") return false
  return /^[A-Za-z0-9_+-]+(\/[A-Za-z0-9_+-]+)*$/.test(tz)
}

// `date +%z` output ("-0500", "+0545") -> minutes east of UTC, or null when
// the reading is not a wall-clock offset (a failed run prints an error, an
// exotic zone can print "+0000 UTC", and neither gets to move the clock).
function parseOffset(text) {
  var trimmed = String(text === undefined || text === null ? "" : text).trim()
  var match = /^([+-])([0-9]{2})([0-9]{2})$/.exec(trimmed)
  if (!match) return null
  var hourPart = parseInt(match[2], 10)
  var minutePart = parseInt(match[3], 10)
  if (minutePart > 59 || hourPart * 60 + minutePart > 14 * 60) return null
  var minutes = hourPart * 60 + minutePart
  return match[1] === "-" ? -minutes : minutes
}

// `date +%Z` output. Zones the database has no abbreviation for (Nepal,
// some fixed-offset entries) print their offset instead — that is not a
// name to show next to a time, so it reads as no suffix at all and the
// configured label, if any, speaks instead.
function cleanAbbrev(text) {
  var trimmed = String(text === undefined || text === null ? "" : text).trim()
  if (trimmed === "" || /^[+-]/.test(trimmed)) return ""
  return trimmed
}

// Wall-clock time in the target zone as a Date whose local fields already
// hold it, so Qt.formatDateTime renders it unchanged. Shifting by the
// zone's offset plus the machine's own keeps this correct in either
// hemisphere and for half-hour machines like +0545.
function shiftedDate(now, offsetMinutes) {
  var date = now instanceof Date ? now : new Date(now)
  if (offsetMinutes === undefined || offsetMinutes === null) return date
  var offset = Number(offsetMinutes)
  if (!isFinite(offset)) return date
  return new Date(date.getTime() + (offset + date.getTimezoneOffset()) * 60000)
}

// Presets plus the configured value, deduplicated in a stable order: the
// cycle writes its result back to shell.json, and a ring that reshuffled
// itself around the current value would bounce instead of walking.
function ring(configured, presets) {
  var out = []
  var candidates = (presets || []).concat([configured])
  for (var i = 0; i < candidates.length; i++) {
    var value = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (value === "" || out.indexOf(value) !== -1) continue
    out.push(value)
  }
  return out.length > 0 ? out : presets && presets.length ? [String(presets[0])] : [""]
}

function nextInRing(values, current) {
  if (!values || values.length === 0) return ""
  var index = values.indexOf(String(current === undefined || current === null ? "" : current))
  return values[(index + 1) % values.length]
}

// Suffix rides with the last line of a possibly multi-line (vertical bar)
// format, so a stacked label still names which zone it is showing.
function appendSuffix(text, suffix) {
  var body = String(text === undefined || text === null ? "" : text)
  var tag = String(suffix === undefined || suffix === null ? "" : suffix).trim()
  if (tag === "") return body
  if (body === "") return tag
  var lineBreak = body.lastIndexOf("\n")
  if (lineBreak === -1) return body + " " + tag
  return body.slice(0, lineBreak + 1) + body.slice(lineBreak + 1) + " " + tag
}

if (typeof module !== "undefined") {
  module.exports = {
    FORMAT_PRESETS: FORMAT_PRESETS,
    TIMEZONE_PRESETS: TIMEZONE_PRESETS,
    isValidTimezone: isValidTimezone,
    parseOffset: parseOffset,
    cleanAbbrev: cleanAbbrev,
    shiftedDate: shiftedDate,
    ring: ring,
    nextInRing: nextInRing,
    appendSuffix: appendSuffix
  }
} else {
  // Quickshell imports the file as a plain script under this name.
  var Model = {
    FORMAT_PRESETS: FORMAT_PRESETS,
    TIMEZONE_PRESETS: TIMEZONE_PRESETS,
    isValidTimezone: isValidTimezone,
    parseOffset: parseOffset,
    cleanAbbrev: cleanAbbrev,
    shiftedDate: shiftedDate,
    ring: ring,
    nextInRing: nextInRing,
    appendSuffix: appendSuffix
  }
}

// ---- Self-test: node kshitij.dual-clock/Model.js
if (typeof require !== "undefined" && typeof module !== "undefined" && require.main === module) {
  var assert = require("assert")
  var m = module.exports

  assert.strictEqual(m.parseOffset("-0500"), -300)
  assert.strictEqual(m.parseOffset("+0545"), 345)
  assert.strictEqual(m.parseOffset("+0000"), 0)
  assert.strictEqual(m.parseOffset("-0560"), null)
  assert.strictEqual(m.parseOffset("CDT"), null)
  assert.strictEqual(m.parseOffset(""), null)
  assert.strictEqual(m.parseOffset(undefined), null)

  assert.strictEqual(m.cleanAbbrev("CDT"), "CDT")
  assert.strictEqual(m.cleanAbbrev("+0545"), "")
  assert.strictEqual(m.cleanAbbrev(""), "")

  assert.ok(m.isValidTimezone("America/Chicago"))
  assert.ok(m.isValidTimezone("UTC"))
  assert.ok(m.isValidTimezone("Asia/Kathmandu"))
  assert.ok(!m.isValidTimezone("America/Chicago; rm -rf /"))
  assert.ok(!m.isValidTimezone("../etc/passwd"))
  assert.ok(!m.isValidTimezone(42))

  // Chicago winter (-360) from a Kathmandu machine (+345): the shifted
  // date's local fields must read 10:15 when UTC reads 16:15, and that
  // answer must not depend on the machine's own offset.
  var utc = new Date(Date.UTC(2026, 0, 15, 16, 15, 0))
  var shifted = m.shiftedDate(utc, -360)
  var expectMinutes = ((16 * 60 + 15 - 360) % 1440 + 1440) % 1440
  assert.strictEqual(shifted.getHours() * 60 + shifted.getMinutes(), expectMinutes)

  assert.deepStrictEqual(m.ring("HH:mm", m.FORMAT_PRESETS), m.FORMAT_PRESETS)
  assert.deepStrictEqual(m.ring("HH:mm:ss", m.FORMAT_PRESETS), m.FORMAT_PRESETS.concat(["HH:mm:ss"]))
  assert.strictEqual(m.nextInRing(m.FORMAT_PRESETS, "HH:mm"), "h:mm AP")
  // Unknown current lands on the top of the ring, matching the stock
  // clock's nextClockFormat: (-1 + 1) % length === 0.
  assert.strictEqual(m.nextInRing(m.FORMAT_PRESETS, "nope"), "HH:mm")
  assert.strictEqual(m.nextInRing(m.FORMAT_PRESETS, "d MMM HH:mm"), "HH:mm")

  assert.strictEqual(m.appendSuffix("08:54", "CDT"), "08:54 CDT")
  assert.strictEqual(m.appendSuffix("08:54", ""), "08:54")
  assert.strictEqual(m.appendSuffix("HH\nmm", "CST"), "HH\nmm CST")
  assert.strictEqual(m.appendSuffix("", "CST"), "CST")

  console.log("Model.js self-test passed")
}
