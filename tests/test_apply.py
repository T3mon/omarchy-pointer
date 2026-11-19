import importlib.util
import sys
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("apply", Path(__file__).resolve().parent.parent / "apply.py")
apply = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apply)

failures = 0


def check(name, actual, expected):
    global failures
    if actual != expected:
        failures += 1
        print(f"FAIL {name}\n  expected {expected!r}\n  got      {actual!r}")


def state(touchpads):
    return {
        "mouse": apply.sanitize({"sensitivity": -0.2, "accelProfile": "flat"}, apply.COMMON_DEFAULTS),
        "touchpad": apply.sanitize({"sensitivity": 0.4, "leftHanded": True, "drag3fg": True}, apply.TOUCHPAD_DEFAULTS),
        "touchpads": touchpads,
    }


lua = apply.lua_config(state(["elan0788:00-04f3:321a-touchpad"]))
check("mouse speed is global", "    sensitivity = -0.20," in lua, True)
check("touchpad speed is per device", 'hl.device({ name = "elan0788:00-04f3:321a-touchpad", sensitivity = 0.40, accel_profile = "adaptive", left_handed = true })' in lua, True)
check("three-finger drag is an int", "drag_3fg = 1," in lua, True)

evil = 'x", sensitivity = 1 }) os.execute("id") --'
check("unsafe device name rejected", apply.SAFE_DEVICE.match(evil), None)
check("unsafe name never reaches lua", "os.execute" in apply.lua_config(state([evil])), False)
check("newline name rejected", apply.SAFE_DEVICE.match("pad\nos.exit()"), None)

check("sanitize clamps", apply.sanitize({"scrollFactor": 99, "sensitivity": "nan"}, apply.COMMON_DEFAULTS)["scrollFactor"], 2.0)
check("sanitize ignores nan", apply.sanitize({"sensitivity": "nan"}, apply.COMMON_DEFAULTS)["sensitivity"], 0.0)
check("sanitize ignores unknown keys", "evil" in apply.sanitize({"evil": 1}, apply.COMMON_DEFAULTS), False)

with tempfile.TemporaryDirectory() as tmp:
    hypr = Path(tmp)
    apply.HYPR_DIR = hypr
    apply.POINTER_LUA = hypr / "pointer.lua"
    apply.HYPRLAND_LUA = hypr / "hyprland.lua"
    apply.HYPRLAND_LUA.write_text('require("hypr.monitors")\nrequire("hypr.input")\nrequire("hypr.bindings")\n')
    apply.persist(state(["elan0788:00-04f3:321a-touchpad"]))
    text = apply.HYPRLAND_LUA.read_text()
    check("require lands after hypr.input", 'require("hypr.input")\nrequire("hypr.pointer")\n' in text, True)
    apply.persist(state([]))
    check("require added once", apply.HYPRLAND_LUA.read_text().count("hypr.pointer"), 1)
    saved = apply.saved_state()
    check("state round trips", saved["touchpad"]["sensitivity"], 0.4)
    check("mouse state round trips", saved["mouse"]["accelProfile"], "flat")

    (hypr / "input.lua").write_text('hl.device({ name = "pad-touchpad", sensitivity = 0.15, accel_profile = "flat" })\n-- hl.device({ name = "pad-touchpad", sensitivity = 0.9 })\n')
    check("existing override seeds touchpad", apply.existing_device_override(["pad-touchpad"]), {"sensitivity": 0.15, "accelProfile": "flat"})

print(f"{failures} failure(s)" if failures else "all apply tests passed")
sys.exit(1 if failures else 0)
