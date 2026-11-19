const fs = require("fs")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const Model = new Function(source + "; return { parsePalette, pickTints, hexToRgb, rgbToHsl, hueGap, contrast, speedPercentFromSensitivity, sensitivityFromSpeedPercent, scrollPercentFromFactor, factorFromScrollPercent, parseState, statePayload, withValue, uiValue, layout, focusTargets, speedId, sliderText, nextOption, emptyState }")()

let failures = 0
function check(name, actual, expected) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures++
    console.log("FAIL " + name + "\n  expected " + JSON.stringify(expected) + "\n  got      " + JSON.stringify(actual))
  }
}

check("speed 0 sensitivity is 50%", Model.speedPercentFromSensitivity(0), 50)
check("speed round trip", Model.sensitivityFromSpeedPercent(Model.speedPercentFromSensitivity(0.3)), 0.3)
check("scroll default sits mid-track", Model.scrollPercentFromFactor(1), 50)
check("scroll clamps high", Model.factorFromScrollPercent(500), 2)

const live = JSON.stringify({
  mouse: { sensitivity: 0, accelProfile: "adaptive", naturalScroll: false, scrollFactor: 1, leftHanded: false, forceNoAccel: false, buttonScroll: false, buttonScrollLock: false },
  touchpad: { sensitivity: 1, accelProfile: "flat", naturalScroll: true, scrollFactor: 0.4, leftHanded: false, tapToClick: true, disableWhileTyping: false, clickfinger: true, tapAndDrag: true, dragLock: false, middleEmulation: false, tapButtonMap: "lrm", scrollMethod: "2fg", drag3fg: "off", gestures: false, gestureFingers: "3", gestureInvert: true, swipeDistance: 300 },
  cursor: { size: 24, theme: "default", inactiveTimeout: 0, hideOnKeyPress: true, hideOnTouch: true, followMouse: "1", warpToFocus: true, warpOnWorkspace: true, zoom: 1, resizeOnBorder: true },
  mice: { "logitech-pro-x-1": { custom: false, sensitivity: 0, accelProfile: "adaptive", naturalScroll: false, scrollFactor: 1, leftHanded: false } },
  connectedMice: ["logitech-pro-x-1"],
  themes: ["default", "Adwaita"],
  hasTouchpad: true
})
const s = Model.parseState(live)
check("parses ok", s.ok, true)
check("devices stay separate", [Model.uiValue(s, "all", "m.speed"), Model.uiValue(s, "all", "t.speed")], [50, 100])
check("primary maps to left/right", Model.uiValue(s, "all", "t.primary"), "left")
check("garbage is not ok", Model.parseState("<b>nope</b>").ok, false)
check("wrong types fall back", Model.parseState('{"mouse":{"sensitivity":"9"}}').mouse.sensitivity, 0)
check("unsafe mouse names dropped", Object.keys(Model.parseState('{"mice":{"a\\"b":{}}}').mice), [])
check("themes kept", s.themes, ["default", "Adwaita"])

const faster = Model.withValue(s, "all", "t.speed", 75)
check("touchpad speed changes alone", [faster.touchpad.sensitivity, faster.mouse.sensitivity, s.touchpad.sensitivity], [0.5, 0, 1])
const left = Model.withValue(s, "all", "m.primary", "right")
check("primary right is left-handed", left.mouse.leftHanded, true)
const zoom = Model.withValue(s, "all", "c.zoom", 9)
check("zoom clamps", zoom.cursor.zoom, 3)

const own = Model.withValue(s, "logitech-pro-x-1", "m.custom", true)
check("own settings copies all-mice values", own.mice["logitech-pro-x-1"].custom, true)
const ownFast = Model.withValue(own, "logitech-pro-x-1", "m.speed", 100)
check("per-mouse speed edits that mouse only", [ownFast.mice["logitech-pro-x-1"].sensitivity, ownFast.mouse.sensitivity], [1, 0])
check("per-mouse edit without own settings goes to all mice", Model.withValue(s, "logitech-pro-x-1", "m.speed", 100).mouse.sensitivity, 0)

const payload = JSON.parse(Model.statePayload(ownFast))
check("payload has only settings", Object.keys(payload).sort(), ["cursor", "mice", "mouse", "touchpad"])

function ids(rows) { return Model.focusTargets(rows).map(t => t.id) }
function types(rows) { return rows.map(r => r.type) }
check("mouse tab", ids(Model.layout("mouse", "all", s)), ["tab", "m.target", "m.speed", "m.accel", "m.primary", "m.scroll", "m.natural", "more.mouse"])
check("more open shows extras", ids(Model.layout("mouse", "all", s, { mouse: true })).slice(-3), ["more.mouse", "m.noaccel", "m.btnscroll"])
const btn = Model.withValue(s, "all", "m.btnscroll", true)
check("lock appears with middle-button scroll", ids(Model.layout("mouse", "all", btn)).slice(-1), ["m.btnlock"])
const raw = Model.withValue(s, "all", "m.noaccel", true)
check("raw input warns", types(Model.layout("mouse", "all", raw)).indexOf("warning") > 0, true)
check("single mouse not customised", ids(Model.layout("mouse", "logitech-pro-x-1", s)), ["tab", "m.target", "m.custom"])
check("single mouse customised", ids(Model.layout("mouse", "logitech-pro-x-1", own)).slice(-2), ["m.scroll", "m.natural"])
check("own settings noted on all mice", Model.layout("mouse", "all", own).filter(r => r.type === "note")[0].labelKey, "note.ownOne")
check("swipe options hidden when off", ids(Model.layout("touchpad", "all", s)).indexOf("t.fingers"), -1)
const swipe = Model.withValue(s, "all", "t.gestures", true)
check("swipe options shown when on", ids(Model.layout("touchpad", "all", swipe)).filter(i => i.startsWith("t.") && ["t.fingers", "t.distance", "t.invert"].includes(i)), ["t.fingers", "t.distance", "t.invert"])
const clash = Model.withValue(swipe, "all", "t.drag3fg", "3")
const clashRows = Model.layout("touchpad", "all", clash)
check("finger conflict warns", clashRows.filter(r => r.type === "warning").map(r => [r.labelKey, r.arg]), [["warn.fingerConflict", "3"]])
check("conflict opens more", clashRows.filter(r => r.type === "more")[0].open, true)
check("no tap hides tap options", ids(Model.layout("touchpad", "all", Model.withValue(s, "all", "t.tap", false), { touchpad: true })).indexOf("t.tapmap"), -1)
check("cursor tab", ids(Model.layout("cursor", "all", s)), ["tab", "c.size", "c.theme", "c.hide", "c.hidekey", "c.hidetouch", "c.focus", "c.warp", "c.warpws", "more.cursor"])
const zoomed = Model.withValue(s, "all", "c.zoom", 2)
check("zoom warns with reset", ids(Model.layout("cursor", "all", zoomed)).slice(-3), ["c.resize", "c.zoom", "c.zoom.reset"])
check("conflict is danger", clashRows.filter(r => r.type === "warning")[0].level, "danger")
check("zoom is caution", Model.layout("cursor", "all", zoomed).filter(r => r.type === "warning")[0].level, "caution")
check("palette reads named colors", Model.parsePalette('accent = "#7aa2f7"\ngreen = "#9ece6a"\nmagenta="#ad8ee6"\nbackground = "#000000"'), { accent: "#7aa2f7", green: "#9ece6a", magenta: "#ad8ee6", background: "#000000" })
check("palette ignores junk", Model.parsePalette('red = "url(x)"\nblue = "#12345"'), {})
function tintCheck(name, palette) {
  const tints = Model.pickTints(palette, palette.accent, palette.background)
  const list = [tints.mouse, tints.touchpad, tints.cursor]
  const hsl = list.map(x => Model.rgbToHsl(Model.hexToRgb(x)))
  const grey = hsl[0].s < 0.15
  const gaps = [Model.hueGap(hsl[1].h, hsl[2].h)]
  if (!grey) gaps.push(Model.hueGap(hsl[0].h, hsl[1].h), Model.hueGap(hsl[0].h, hsl[2].h))
  const bg = Model.hexToRgb(palette.background)
  check(name + ": tabs are distinct", Math.min(...gaps) >= 60, true)
  check(name + ": tabs are readable", Math.min(...list.map(x => Model.contrast(Model.hexToRgb(x), bg))) >= 3, true)
  check(name + ": mouse keeps a readable accent hue", Math.round(hsl[0].h) === Math.round(Model.rgbToHsl(Model.hexToRgb(palette.accent)).h) || grey, true)
}
tintCheck("green equals accent", Model.parsePalette('accent = "#ff9f0a"\nbackground = "#1c1c1e"\nred = "#ff5f4a"\nyellow = "#ffc27a"\norange = "#ff6a3d"\ngreen = "#ff9f0a"\ncyan = "#a6dcef"\nblue = "#8fb8de"\nmagenta = "#ff8fa3"'))
tintCheck("monochrome", Model.parsePalette('accent = "#8d8d8d"\nbackground = "#0d0d0d"\nred = "#8d8d8d"\ngreen = "#8d8d8d"\nblue = "#8d8d8d"\nmagenta = "#8d8d8d"'))
tintCheck("light theme", Model.parsePalette('accent = "#1e66f5"\nbackground = "#eff1f5"\nred = "#d20f39"\nyellow = "#df8e1d"\ngreen = "#40a02b"\nblue = "#1e66f5"\nmagenta = "#ea76cb"'))
tintCheck("empty palette", Model.parsePalette('accent = "#7aa2f7"\nbackground = "#1a1b26"'))
const fallback = Model.pickTints({}, "not a color", "")
check("bad input still gives three colors", [fallback.mouse, fallback.touchpad, fallback.cursor].every(x => /^#[0-9a-f]{6}$/.test(x)), true)
const tn = Model.pickTints(Model.parsePalette('accent = "#7aa2f7"\nbackground = "#1a1b26"\nred = "#f7768e"\nyellow = "#e0af68"'), "#7aa2f7", "#1a1b26")
check("tabs avoid warning red", Model.hueGap(Model.rgbToHsl(Model.hexToRgb(tn.touchpad)).h, Model.rgbToHsl(Model.hexToRgb("#f7768e")).h) >= 30, true)
check("zoom 1 reads off", Model.sliderText("c.zoom", 1).key, "fmt.off")
const noPad = Model.parseState('{"hasTouchpad":false}')
check("no touchpad hides the tab", Model.layout("mouse", "all", noPad)[0].options.map(o => o.value), ["mouse", "cursor"])
check("no mice has no target picker", ids(Model.layout("mouse", "all", noPad)).indexOf("m.target"), -1)

check("speed id follows tab", [Model.speedId("touchpad", "all", s), Model.speedId("mouse", "all", s), Model.speedId("mouse", "logitech-pro-x-1", s)], ["t.speed", "m.speed", ""])
check("idle never", Model.sliderText("c.hide", 0).key, "fmt.never")
check("next option wraps", Model.nextOption([{ value: "a" }, { value: "b" }], "b", 1), "a")

console.log(failures ? failures + " failure(s)" : "all model tests passed")
process.exit(failures ? 1 : 0)
