function clamp(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function round2(n) {
  return Math.round(n * 100) / 100
}

function speedPercentFromSensitivity(sensitivity) {
  return Math.round(clamp((Number(sensitivity) || 0) + 1, 0, 2) * 50)
}

function sensitivityFromSpeedPercent(percent) {
  return round2(clamp(percent, 0, 100) / 50 - 1)
}

function scrollPercentFromFactor(factor) {
  var f = clamp(factor, 0.1, 2.0)
  if (f <= 1) return Math.round(((f - 0.1) / 0.9) * 50)
  return Math.round(50 + (f - 1.0) * 50)
}

function factorFromScrollPercent(percent) {
  var p = clamp(percent, 0, 100)
  if (p <= 50) return round2(0.1 + (p / 50) * 0.9)
  return round2(1.0 + ((p - 50) / 50))
}

function emptyState() {
  return {
    mouse: { sensitivity: 0, accelProfile: "adaptive", naturalScroll: false, scrollFactor: 1, leftHanded: false,
             forceNoAccel: false, buttonScroll: false, buttonScrollLock: false },
    touchpad: { sensitivity: 0, accelProfile: "adaptive", naturalScroll: false, scrollFactor: 1, leftHanded: false,
                tapToClick: true, disableWhileTyping: true, clickfinger: false, tapAndDrag: true, dragLock: false,
                middleEmulation: false, tapButtonMap: "lrm", scrollMethod: "2fg", drag3fg: "off",
                gestures: false, gestureFingers: "3", gestureInvert: true, swipeDistance: 300 },
    cursor: { size: 24, theme: "default", inactiveTimeout: 0, hideOnKeyPress: true, hideOnTouch: true,
              followMouse: "1", warpToFocus: true, warpOnWorkspace: true, zoom: 1, resizeOnBorder: true },
    mice: {},
    connectedMice: [],
    themes: ["default"],
    hasTouchpad: false,
    ok: false
  }
}

function mergeSection(base, raw) {
  var out = {}
  for (var key in base) {
    var value = raw && typeof raw === "object" && key in raw ? raw[key] : base[key]
    out[key] = typeof value === typeof base[key] ? value : base[key]
  }
  return out
}

function safeName(name) {
  return typeof name === "string" && /^[A-Za-z0-9:._+-]{1,128}$/.test(name)
}

function parseState(raw) {
  var parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return emptyState() }
  if (!parsed || typeof parsed !== "object") return emptyState()
  var base = emptyState()
  var state = {
    mouse: mergeSection(base.mouse, parsed.mouse),
    touchpad: mergeSection(base.touchpad, parsed.touchpad),
    cursor: mergeSection(base.cursor, parsed.cursor),
    mice: {},
    connectedMice: [],
    themes: ["default"],
    hasTouchpad: parsed.hasTouchpad === true,
    ok: true
  }
  var deviceBase = { custom: false, sensitivity: 0, accelProfile: "adaptive", naturalScroll: false, scrollFactor: 1, leftHanded: false }
  if (parsed.mice && typeof parsed.mice === "object") {
    for (var name in parsed.mice) {
      if (safeName(name)) state.mice[name] = mergeSection(deviceBase, parsed.mice[name])
    }
  }
  if (Array.isArray(parsed.connectedMice))
    state.connectedMice = parsed.connectedMice.filter(function(n) { return safeName(n) && n in state.mice })
  if (Array.isArray(parsed.themes)) {
    var themes = parsed.themes.filter(safeName)
    if (themes.length) state.themes = themes
  }
  return state
}

function statePayload(state) {
  return JSON.stringify({ mouse: state.mouse, touchpad: state.touchpad, cursor: state.cursor, mice: state.mice })
}

var FIELDS = {
  "m.speed": { scope: "target", key: "sensitivity" },
  "m.scroll": { scope: "target", key: "scrollFactor" },
  "m.accel": { scope: "target", key: "accelProfile" },
  "m.primary": { scope: "target", key: "leftHanded" },
  "m.natural": { scope: "target", key: "naturalScroll" },
  "m.custom": { scope: "device", key: "custom" },
  "m.noaccel": { scope: "mouse", key: "forceNoAccel" },
  "m.btnscroll": { scope: "mouse", key: "buttonScroll" },
  "m.btnlock": { scope: "mouse", key: "buttonScrollLock" },
  "t.speed": { scope: "touchpad", key: "sensitivity" },
  "t.scroll": { scope: "touchpad", key: "scrollFactor" },
  "t.accel": { scope: "touchpad", key: "accelProfile" },
  "t.primary": { scope: "touchpad", key: "leftHanded" },
  "t.natural": { scope: "touchpad", key: "naturalScroll" },
  "t.tap": { scope: "touchpad", key: "tapToClick" },
  "t.dwt": { scope: "touchpad", key: "disableWhileTyping" },
  "t.clickfinger": { scope: "touchpad", key: "clickfinger" },
  "t.tapdrag": { scope: "touchpad", key: "tapAndDrag" },
  "t.draglock": { scope: "touchpad", key: "dragLock" },
  "t.middle": { scope: "touchpad", key: "middleEmulation" },
  "t.tapmap": { scope: "touchpad", key: "tapButtonMap" },
  "t.scrollmethod": { scope: "touchpad", key: "scrollMethod" },
  "t.drag3fg": { scope: "touchpad", key: "drag3fg" },
  "t.gestures": { scope: "touchpad", key: "gestures" },
  "t.fingers": { scope: "touchpad", key: "gestureFingers" },
  "t.invert": { scope: "touchpad", key: "gestureInvert" },
  "t.distance": { scope: "touchpad", key: "swipeDistance" },
  "c.size": { scope: "cursor", key: "size" },
  "c.theme": { scope: "cursor", key: "theme" },
  "c.hide": { scope: "cursor", key: "inactiveTimeout" },
  "c.hidekey": { scope: "cursor", key: "hideOnKeyPress" },
  "c.hidetouch": { scope: "cursor", key: "hideOnTouch" },
  "c.focus": { scope: "cursor", key: "followMouse" },
  "c.warp": { scope: "cursor", key: "warpToFocus" },
  "c.warpws": { scope: "cursor", key: "warpOnWorkspace" },
  "c.zoom": { scope: "cursor", key: "zoom" },
  "c.resize": { scope: "cursor", key: "resizeOnBorder" }
}

var SLIDERS = {
  "speed": { min: 0, max: 100, step: 5, integer: true },
  "scroll": { min: 0, max: 100, step: 5, integer: true },
  "t.distance": { min: 100, max: 600, step: 25, integer: true },
  "c.size": { min: 16, max: 96, step: 4, integer: true },
  "c.hide": { min: 0, max: 30, step: 1, integer: true },
  "c.zoom": { min: 1, max: 3, step: 0.1, integer: false }
}

function sliderKind(id) {
  if (id === "m.speed" || id === "t.speed") return "speed"
  if (id === "m.scroll" || id === "t.scroll") return "scroll"
  return id
}

function sliderSpec(id) {
  return SLIDERS[sliderKind(id)] || { min: 0, max: 100, step: 1, integer: true }
}

function section(state, target, scope) {
  if (scope === "target") return target === "all" ? state.mouse : (state.mice[target] || state.mouse)
  if (scope === "device") return state.mice[target] || {}
  return state[scope] || {}
}

function rawValue(state, target, id) {
  var field = FIELDS[id]
  if (!field) return undefined
  return section(state, target, field.scope)[field.key]
}

function uiValue(state, target, id) {
  var value = rawValue(state, target, id)
  var kind = sliderKind(id)
  if (kind === "speed") return speedPercentFromSensitivity(value)
  if (kind === "scroll") return scrollPercentFromFactor(value)
  if (id === "m.primary" || id === "t.primary") return value ? "right" : "left"
  return value
}

function fromUi(id, value) {
  var kind = sliderKind(id)
  if (kind === "speed") return sensitivityFromSpeedPercent(value)
  if (kind === "scroll") return factorFromScrollPercent(value)
  if (id === "m.primary" || id === "t.primary") return value === "right"
  if (SLIDERS[id]) {
    var spec = SLIDERS[id]
    var n = clamp(value, spec.min, spec.max)
    return spec.integer ? Math.round(n) : round2(n)
  }
  return value
}

function copy(obj) {
  var out = {}
  for (var k in obj) out[k] = obj[k]
  return out
}

function withValue(state, target, id, uiVal) {
  var field = FIELDS[id]
  if (!field) return state
  var next = copy(state)
  var value = fromUi(id, uiVal)
  var scope = field.scope
  if (scope === "target" && target !== "all" && state.mice[target]) scope = "device"
  else if (scope === "target") scope = "mouse"
  if (scope === "device") {
    if (!state.mice[target]) return state
    next.mice = copy(state.mice)
    next.mice[target] = copy(state.mice[target])
    if (field.key === "custom" && value === true && !state.mice[target].custom) {
      var src = state.mouse
      var keys = ["sensitivity", "accelProfile", "naturalScroll", "scrollFactor", "leftHanded"]
      for (var i = 0; i < keys.length; i++) next.mice[target][keys[i]] = src[keys[i]]
    }
    next.mice[target][field.key] = value
  } else {
    next[scope] = copy(state[scope])
    next[scope][field.key] = value
  }
  return next
}

function sliderText(id, value, formatNumber) {
  var kind = sliderKind(id)
  var fmt = formatNumber || function(n, d) { return d ? Number(n).toFixed(d) : String(Math.round(n)) }
  if (kind === "speed" || kind === "scroll") return { key: "fmt.percent", arg: fmt(Math.round(value)) }
  if (id === "t.distance" || id === "c.size") return { key: "fmt.px", arg: fmt(Math.round(value)) }
  if (id === "c.hide") return Math.round(value) <= 0 ? { key: "fmt.never", arg: "" } : { key: "fmt.seconds", arg: fmt(Math.round(value)) }
  if (id === "c.zoom") return { key: "fmt.zoom", arg: fmt(value, 1) }
  return { key: "fmt.plain", arg: fmt(value) }
}

function opt(value, labelKey) {
  return { value: value, labelKey: labelKey }
}

var OPTIONS = {
  "tab": [opt("mouse", "tab.mouse"), opt("touchpad", "tab.touchpad"), opt("cursor", "tab.cursor")],
  "accel": [opt("adaptive", "accel.adaptive"), opt("flat", "accel.flat")],
  "primary": [opt("left", "primary.left"), opt("right", "primary.right")],
  "t.tapmap": [opt("lrm", "tapmap.lrm"), opt("lmr", "tapmap.lmr")],
  "t.scrollmethod": [opt("2fg", "scrollmethod.2fg"), opt("edge", "scrollmethod.edge")],
  "t.drag3fg": [opt("off", "drag3fg.off"), opt("3", "drag3fg.3"), opt("4", "drag3fg.4")],
  "t.fingers": [opt("3", "fingers.3"), opt("4", "fingers.4")],
  "c.focus": [opt("0", "focus.0"), opt("1", "focus.1"), opt("2", "focus.2")]
}

function optionsFor(id, hasTouchpad) {
  if (id === "tab") return hasTouchpad ? OPTIONS.tab : [OPTIONS.tab[0], OPTIONS.tab[2]]
  if (id === "m.accel" || id === "t.accel") return OPTIONS.accel
  if (id === "m.primary" || id === "t.primary") return OPTIONS.primary
  return OPTIONS[id] || []
}

function choice(id, labelKey, hasTouchpad) {
  return { type: "choice", id: id, labelKey: labelKey, options: optionsFor(id, hasTouchpad) }
}

function slider(id, labelKey) {
  return { type: "slider", id: id, labelKey: labelKey }
}

function toggles(ids) {
  return { type: "toggles", items: ids.map(function(id) { return { id: id, labelKey: "toggle." + id } }) }
}

function pointerRows(prefix, hasTouchpad) {
  return [
    slider(prefix + ".speed", "section.speed"),
    slider(prefix + ".scroll", "section.scroll"),
    { type: "pair", items: [choice(prefix + ".accel", "section.accel", hasTouchpad), choice(prefix + ".primary", "section.primary", hasTouchpad)] }
  ]
}

function layout(tab, target, state) {
  var hasTouchpad = state.hasTouchpad
  var rows = [choice("tab", "section.device", hasTouchpad)]
  if (tab === "touchpad" && hasTouchpad) {
    rows = rows.concat(pointerRows("t", hasTouchpad))
    rows.push(toggles(["t.natural", "t.tap", "t.dwt", "t.clickfinger", "t.tapdrag", "t.draglock", "t.middle"]))
    rows.push({ type: "pair", items: [choice("t.tapmap", "section.tapmap", hasTouchpad), choice("t.scrollmethod", "section.scrollmethod", hasTouchpad)] })
    rows.push(choice("t.drag3fg", "section.drag3fg", hasTouchpad))
    rows.push({ type: "header", labelKey: "section.gestures" })
    rows.push(toggles(["t.gestures", "t.invert"]))
    rows.push(choice("t.fingers", "section.fingers", hasTouchpad))
    rows.push(slider("t.distance", "section.distance"))
    return rows
  }
  if (tab === "cursor") {
    rows.push(slider("c.size", "section.size"))
    rows.push({ type: "dropdown", id: "c.theme", labelKey: "section.theme" })
    rows.push(choice("c.focus", "section.focus", hasTouchpad))
    rows.push(slider("c.hide", "section.hide"))
    rows.push(toggles(["c.hidekey", "c.hidetouch", "c.warp", "c.warpws", "c.resize"]))
    rows.push(slider("c.zoom", "section.zoom"))
    return rows
  }
  if (state.connectedMice.length > 0) rows.push({ type: "dropdown", id: "m.target", labelKey: "section.target" })
  if (target !== "all" && state.mice[target]) {
    rows.push(toggles(["m.custom"]))
    if (!state.mice[target].custom) {
      rows.push({ type: "note", labelKey: "note.followsAll" })
      return rows
    }
    rows = rows.concat(pointerRows("m", hasTouchpad))
    rows.push(toggles(["m.natural"]))
    return rows
  }
  rows = rows.concat(pointerRows("m", hasTouchpad))
  rows.push(toggles(["m.natural", "m.noaccel", "m.btnscroll", "m.btnlock"]))
  return rows
}

function focusTargets(rows) {
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (row.type === "slider") out.push({ id: row.id, kind: "slider", count: 0 })
    else if (row.type === "choice") out.push({ id: row.id, kind: "choice", count: row.options.length })
    else if (row.type === "dropdown") out.push({ id: row.id, kind: "dropdown", count: 0 })
    else if (row.type === "pair") row.items.forEach(function(item) { out.push({ id: item.id, kind: "choice", count: item.options.length }) })
    else if (row.type === "toggles") row.items.forEach(function(item) { out.push({ id: item.id, kind: "toggle", count: 0 }) })
  }
  return out
}

function findTarget(targets, id) {
  for (var i = 0; i < targets.length; i++) if (targets[i].id === id) return i
  return -1
}

function speedId(tab, target, state) {
  if (tab === "touchpad" && state.hasTouchpad) return "t.speed"
  if (target !== "all" && state.mice[target] && !state.mice[target].custom) return ""
  return "m.speed"
}

function nextOption(options, current, delta) {
  if (!options.length) return current
  var idx = -1
  for (var i = 0; i < options.length; i++) if (String(options[i].value) === String(current)) idx = i
  idx = (idx + delta + options.length) % options.length
  return options[idx].value
}
