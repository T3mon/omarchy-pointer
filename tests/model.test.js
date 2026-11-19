const fs = require("fs")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const Model = new Function(source + "; return { speedPercentFromSensitivity, sensitivityFromSpeedPercent, scrollPercentFromFactor, factorFromScrollPercent, parseState, statePayload, withField, visibleSections, toggleField }")()

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
check("scroll round trip low stays within one percent step", Math.abs(Model.factorFromScrollPercent(Model.scrollPercentFromFactor(0.4)) - 0.4) <= 0.02, true)
check("scroll clamps high", Model.factorFromScrollPercent(500), 2)

const live = '{"mouse":{"sensitivity":0.0,"accelProfile":"adaptive","naturalScroll":false,"scrollFactor":1.0,"leftHanded":false},"touchpad":{"sensitivity":0.15,"accelProfile":"flat","naturalScroll":true,"scrollFactor":0.4,"leftHanded":false,"tapToClick":true,"disableWhileTyping":true,"clickfinger":true,"drag3fg":false},"touchpads":["elan0788:00-04f3:321a-touchpad"],"hasTouchpad":true}'
const s = Model.parseState(live)
check("parses ok", s.ok, true)
check("mouse and touchpad stay separate", [s.mouse.sensitivity, s.touchpad.sensitivity], [0, 0.15])
check("touchpad accel", s.touchpad.accelProfile, "flat")
check("mouse has no touchpad-only fields", "tapToClick" in s.mouse, false)
check("hasTouchpad", s.hasTouchpad, true)

check("garbage is not ok", Model.parseState("<b>nope</b>").ok, false)
check("hasTouchpad must be a real true", Model.parseState('{"hasTouchpad":"yes"}').hasTouchpad, false)
check("out of range sensitivity clamps", Model.parseState('{"mouse":{"sensitivity":9}}').mouse.sensitivity, 1)
check("unknown accel falls back", Model.parseState('{"mouse":{"accelProfile":"custom 1 2"}}').mouse.accelProfile, "adaptive")

const edited = Model.withField(s.touchpad, "sensitivity", 0.5)
check("withField copies", [edited.sensitivity, s.touchpad.sensitivity], [0.5, 0.15])
const payload = JSON.parse(Model.statePayload(s.mouse, edited))
check("payload carries both devices", [payload.mouse.sensitivity, payload.touchpad.sensitivity], [0, 0.5])
check("payload drops extra keys", Object.keys(payload).sort(), ["mouse", "touchpad"])

check("mouse tab without touchpad", Model.visibleSections("mouse", false), ["speed", "scroll", "accel", "primary", "natural"])
check("touchpad tab ignored without touchpad", Model.visibleSections("touchpad", false)[0], "speed")
check("touchpad tab", Model.visibleSections("touchpad", true).slice(-5), ["natural", "tap", "dwt", "clickfinger", "drag3fg"])
check("device switch is first", Model.visibleSections("mouse", true)[0], "device")
check("toggle field", Model.toggleField("dwt"), "disableWhileTyping")

console.log(failures ? failures + " failure(s)" : "all model tests passed")
process.exit(failures ? 1 : 0)
