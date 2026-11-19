function clamp(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function asBool(value, fallback) {
  if (value === true || value === false) return value
  return fallback
}

function asNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function normalizeAccel(value) {
  return String(value === undefined || value === null ? "" : value).trim().toLowerCase() === "flat"
    ? "flat" : "adaptive"
}

function speedPercentFromSensitivity(sensitivity) {
  return Math.round(clamp((asNumber(sensitivity, 0) + 1) * 50, 0, 100))
}

function sensitivityFromSpeedPercent(percent) {
  return Math.round((clamp(percent, 0, 100) / 50 - 1) * 100) / 100
}

function scrollPercentFromFactor(factor) {
  var f = clamp(asNumber(factor, 1), 0.1, 2.0)
  if (f <= 1) return Math.round(((f - 0.1) / 0.9) * 50)
  return Math.round(50 + (f - 1.0) * 50)
}

function factorFromScrollPercent(percent) {
  var p = clamp(percent, 0, 100)
  if (p <= 50) return Math.round((0.1 + (p / 50) * 0.9) * 100) / 100
  return Math.round((1.0 + ((p - 50) / 50)) * 100) / 100
}

function mouseDefaults() {
  return { sensitivity: 0, accelProfile: "adaptive", naturalScroll: false, scrollFactor: 1, leftHanded: false }
}

function touchpadDefaults() {
  var d = mouseDefaults()
  d.tapToClick = true
  d.disableWhileTyping = true
  d.clickfinger = false
  d.drag3fg = false
  return d
}

function sanitizeDevice(raw, defaults) {
  var out = {}
  var src = raw && typeof raw === "object" ? raw : {}
  for (var key in defaults) {
    var fallback = defaults[key]
    if (key === "accelProfile") out[key] = normalizeAccel(src[key] === undefined ? fallback : src[key])
    else if (key === "sensitivity") out[key] = clamp(asNumber(src[key], fallback), -1, 1)
    else if (key === "scrollFactor") out[key] = clamp(asNumber(src[key], fallback), 0.1, 2)
    else out[key] = asBool(src[key], fallback)
  }
  return out
}

function emptyState() {
  return { mouse: mouseDefaults(), touchpad: touchpadDefaults(), hasTouchpad: false, ok: false }
}

function parseState(raw) {
  var parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return emptyState() }
  if (!parsed || typeof parsed !== "object") return emptyState()
  return {
    mouse: sanitizeDevice(parsed.mouse, mouseDefaults()),
    touchpad: sanitizeDevice(parsed.touchpad, touchpadDefaults()),
    hasTouchpad: parsed.hasTouchpad === true,
    ok: true
  }
}

function withField(device, key, value) {
  var copy = {}
  for (var k in device) copy[k] = device[k]
  copy[key] = value
  return copy
}

function statePayload(mouse, touchpad) {
  return JSON.stringify({
    mouse: sanitizeDevice(mouse, mouseDefaults()),
    touchpad: sanitizeDevice(touchpad, touchpadDefaults())
  })
}

var MOUSE_SECTIONS = ["speed", "scroll", "accel", "primary", "natural"]
var TOUCHPAD_SECTIONS = ["speed", "scroll", "accel", "primary", "natural", "tap", "dwt", "clickfinger", "drag3fg"]

function visibleSections(device, hasTouchpad) {
  var list = device === "touchpad" && hasTouchpad ? TOUCHPAD_SECTIONS.slice() : MOUSE_SECTIONS.slice()
  if (hasTouchpad) list.unshift("device")
  return list
}

function sectionIsSlider(section) {
  return section === "speed" || section === "scroll"
}

function sectionIsChoice(section) {
  return section === "device" || section === "accel" || section === "primary"
}

function sectionChoiceCount(section) {
  return sectionIsChoice(section) ? 2 : 0
}

function sectionFirstIndex(section) {
  return sectionIsSlider(section) ? -1 : 0
}

var TOGGLE_FIELDS = {
  natural: "naturalScroll",
  tap: "tapToClick",
  dwt: "disableWhileTyping",
  clickfinger: "clickfinger",
  drag3fg: "drag3fg"
}

function toggleField(section) {
  return TOGGLE_FIELDS[section] || ""
}
