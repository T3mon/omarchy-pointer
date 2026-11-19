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


def state(touchpads=("elan-touchpad",), mice=None, **sections):
    s = {
        "mouse": apply.sanitize(sections.get("mouse", {"sensitivity": -0.2, "accelProfile": "flat"}), apply.MOUSE),
        "touchpad": apply.sanitize(sections.get("touchpad", {"sensitivity": 0.4, "leftHanded": True, "drag3fg": "4"}), apply.TOUCHPAD),
        "cursor": apply.sanitize(sections.get("cursor", {}), apply.CURSOR, ["default", "Adwaita"]),
        "mice": {k: apply.sanitize(v, apply.MOUSE_DEVICE) for k, v in (mice or {}).items()},
        "connectedMice": list((mice or {}).keys()),
        "touchpads": list(touchpads),
        "themes": ["default", "Adwaita"],
    }
    return s


lua = apply.lua_config(state())
check("mouse speed is global", "    sensitivity = -0.20," in lua, True)
check("touchpad speed is per device", 'hl.device({ name = "elan-touchpad", sensitivity = 0.40, accel_profile = "adaptive", left_handed = true, scroll_method = "2fg" })' in lua, True)
check("four-finger drag maps to 2", "drag_3fg = 2," in lua, True)
check("no gesture by default", "hl.gesture" in lua, False)
check("cursor size env", 'hl.env("XCURSOR_SIZE", "24")' in lua, True)
check("default theme leaves env alone", "XCURSOR_THEME" in lua, False)

g = apply.lua_config(state(touchpad={"gestures": True, "gestureFingers": "4"}, cursor={"theme": "Adwaita", "size": 32}))
check("gesture written", 'hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })' in g, True)
check("theme env written", 'hl.env("XCURSOR_THEME", "Adwaita")' in g, True)
check("live eval skips gestures and env", any(x in apply.lua_config(state(touchpad={"gestures": True}), persistent=False) for x in ("hl.gesture", "hl.env")), False)
check("gesture needs a touchpad", "hl.gesture" in apply.lua_config(state(touchpads=(), touchpad={"gestures": True})), False)

btn = apply.lua_config(state(mouse={"buttonScroll": True, "buttonScrollLock": True}))
check("button scroll uses middle", 'scroll_method = "on_button_down",' in btn and "scroll_button = 274," in btn and "scroll_button_lock = true," in btn, True)
check("lock off without button scroll", "scroll_button_lock = false," in apply.lua_config(state(mouse={"buttonScrollLock": True})), True)

mice = {"logi": {"custom": True, "sensitivity": 0.8}, "other": {"custom": False}}
m = apply.lua_config(state(mice=mice))
check("custom mouse gets a block", 'hl.device({ name = "logi", sensitivity = 0.80' in m, True)
check("non-custom mouse has no persisted block", 'name = "other"' in m, False)
check("non-custom mouse mirrors globals live", 'hl.device({ name = "other", sensitivity = -0.20' in apply.lua_config(state(mice=mice), persistent=False), True)

evil = 'x", sensitivity = 1 }) os.execute("id") --'
check("unsafe device name rejected", apply.SAFE_NAME.match(evil), None)
check("unsafe name never reaches lua", "os.execute" in apply.lua_config(state(touchpads=[evil], mice={evil: {"custom": True}})), False)
check("unknown theme falls back", apply.sanitize({"theme": 'x"); os.exit()'}, apply.CURSOR, ["default"])["theme"], "default")
check("bad enum falls back", apply.sanitize({"followMouse": "9"}, apply.CURSOR)["followMouse"], "1")
check("sanitize clamps", apply.sanitize({"scrollFactor": 99}, apply.POINTER)["scrollFactor"], 2.0)
check("sanitize ignores nan", apply.sanitize({"sensitivity": "nan"}, apply.POINTER)["sensitivity"], 0.0)
check("int fields round", apply.sanitize({"size": 30.6}, apply.CURSOR)["size"], 31)

base = state(mice={"logi": {}})
merged = apply.merge_state({"mice": {"logi": {"custom": True}, "ghost": {"custom": True}}, "cursor": {"zoom": 2}}, base)
check("merge updates known mouse", merged["mice"]["logi"]["custom"], True)
check("merge ignores unknown mouse", "ghost" in merged["mice"], False)
check("merge does not touch input", base["cursor"]["zoom"], 1.0)

with tempfile.TemporaryDirectory() as tmp:
    hypr = Path(tmp)
    apply.HYPR_DIR = hypr
    apply.POINTER_LUA = hypr / "pointer.lua"
    apply.HYPRLAND_LUA = hypr / "hyprland.lua"
    apply.HYPRLAND_LUA.write_text('require("hypr.monitors")\nrequire("hypr.input")\nrequire("hypr.bindings")\n')
    apply.persist(state())
    text = apply.HYPRLAND_LUA.read_text()
    check("require lands after hypr.input", 'require("hypr.input")\nrequire("hypr.pointer")\n' in text, True)
    apply.persist(state())
    check("require added once", apply.HYPRLAND_LUA.read_text().count("hypr.pointer"), 1)
    saved = apply.saved_state()
    check("state round trips", saved["touchpad"]["sensitivity"], 0.4)
    check("connected devices are not persisted", "touchpads" in saved, False)

    (hypr / "input.lua").write_text('hl.device({ name = "pad-touchpad", sensitivity = 0.15, accel_profile = "flat" })\n-- hl.device({ name = "pad-touchpad", sensitivity = 0.9 })\n')
    check("existing override seeds", apply.existing_device_overrides(["pad-touchpad"]), {"pad-touchpad": {"sensitivity": 0.15, "accelProfile": "flat"}})

print(f"{failures} failure(s)" if failures else "all apply tests passed")
sys.exit(1 if failures else 0)
