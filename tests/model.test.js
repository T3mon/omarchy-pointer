const fs = require("fs")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const Model = new Function(source + "; return { speedPercentFromSensitivity, sensitivityFromSpeedPercent, scrollPercentFromFactor, factorFromScrollPercent, parseState, statePayload, withValue, uiValue, layout, focusTargets, speedId, sliderText, nextOption, emptyState }")()

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
check("mouse tab", ids(Model.layout("mouse", "all", s)), ["tab", "m.target", "m.speed", "m.scroll", "m.accel", "m.primary", "m.natural", "m.noaccel", "m.btnscroll", "m.btnlock"])
check("single mouse not customised", ids(Model.layout("mouse", "logitech-pro-x-1", s)), ["tab", "m.target", "m.custom"])
check("single mouse customised", ids(Model.layout("mouse", "logitech-pro-x-1", own)).slice(-3), ["m.accel", "m.primary", "m.natural"])
check("touchpad tab has gestures", ids(Model.layout("touchpad", "all", s)).slice(-4), ["t.gestures", "t.invert", "t.fingers", "t.distance"])
check("cursor tab", ids(Model.layout("cursor", "all", s)), ["tab", "c.size", "c.theme", "c.focus", "c.hide", "c.hidekey", "c.hidetouch", "c.warp", "c.warpws", "c.resize", "c.zoom"])
const noPad = Model.parseState('{"hasTouchpad":false}')
check("no touchpad hides the tab option", Model.layout("mouse", "all", noPad)[0].options.map(o => o.value), ["mouse", "cursor"])
check("no touchpad has no target picker", ids(Model.layout("mouse", "all", noPad)).indexOf("m.target"), -1)

check("speed id follows tab", [Model.speedId("touchpad", "all", s), Model.speedId("mouse", "all", s), Model.speedId("mouse", "logitech-pro-x-1", s)], ["t.speed", "m.speed", ""])
check("idle never", Model.sliderText("c.hide", 0).key, "fmt.never")
check("next option wraps", Model.nextOption([{ value: "a" }, { value: "b" }], "b", 1), "a")

console.log(failures ? failures + " failure(s)" : "all model tests passed")
process.exit(failures ? 1 : 0)
