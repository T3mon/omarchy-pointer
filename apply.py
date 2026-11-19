#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path(os.environ.get("HOME", str(Path.home())))
HYPR_DIR = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "hypr"
POINTER_LUA = HYPR_DIR / "pointer.lua"
HYPRLAND_LUA = HYPR_DIR / "hyprland.lua"
REQUIRE_LINE = 'require("hypr.pointer")'
STATE_PREFIX = "-- state: "
PLUGIN_ID = "t3mon.pointer"
BTN_MIDDLE = 274

SAFE_NAME = re.compile(r"^[A-Za-z0-9:._+-]{1,128}$")
ICON_DIRS = [
    HOME / ".local" / "share" / "icons",
    HOME / ".icons",
    Path("/usr/share/icons"),
]


def b(default):
    return ("bool", default)


def f(lo, hi, default):
    return ("float", lo, hi, default)


def i(lo, hi, default):
    return ("int", lo, hi, default)


def e(values, default):
    return ("enum", values, default)


POINTER = {
    "sensitivity": f(-1.0, 1.0, 0.0),
    "accelProfile": e(["adaptive", "flat"], "adaptive"),
    "naturalScroll": b(False),
    "scrollFactor": f(0.1, 2.0, 1.0),
    "leftHanded": b(False),
}
MOUSE = {
    **POINTER,
    "forceNoAccel": b(False),
    "buttonScroll": b(False),
    "buttonScrollLock": b(False),
}
MOUSE_DEVICE = {"custom": b(False), **POINTER}
TOUCHPAD = {
    **POINTER,
    "tapToClick": b(True),
    "disableWhileTyping": b(True),
    "clickfinger": b(False),
    "tapAndDrag": b(True),
    "dragLock": b(False),
    "middleEmulation": b(False),
    "tapButtonMap": e(["lrm", "lmr"], "lrm"),
    "scrollMethod": e(["2fg", "edge"], "2fg"),
    "drag3fg": e(["off", "3", "4"], "off"),
    "gestures": b(False),
    "gestureFingers": e(["3", "4"], "3"),
    "gestureInvert": b(True),
    "swipeDistance": i(100, 600, 300),
}
CURSOR = {
    "size": i(16, 96, 24),
    "theme": ("theme", "default"),
    "inactiveTimeout": i(0, 30, 0),
    "hideOnKeyPress": b(True),
    "hideOnTouch": b(True),
    "followMouse": e(["0", "1", "2", "3"], "1"),
    "warpToFocus": b(True),
    "warpOnWorkspace": b(True),
    "zoom": f(1.0, 3.0, 1.0),
    "resizeOnBorder": b(True),
}


def run(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, check=False, text=True, capture_output=True, timeout=5)


def quiet(argv: list[str]) -> None:
    try:
        run(argv)
    except (OSError, subprocess.TimeoutExpired):
        pass


def hypr_json(*args: str) -> object:
    try:
        proc = run(["hyprctl", "-j", *args])
    except (OSError, subprocess.TimeoutExpired):
        return {}
    if proc.returncode != 0 or not proc.stdout.strip():
        return {}
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}


def option(name: str, fallback=None):
    data = hypr_json("getoption", name)
    if not isinstance(data, dict):
        return fallback
    for key in ("bool", "float", "int"):
        if key in data:
            return data[key]
    value = data.get("str")
    return fallback if value is None or value == "[[EMPTY]]" else value


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def cursor_themes() -> list[str]:
    found = set()
    for base in ICON_DIRS:
        try:
            entries = list(base.iterdir())
        except OSError:
            continue
        for entry in entries:
            if (entry / "cursors").is_dir() or (entry / "hyprcursors").is_dir():
                if SAFE_NAME.match(entry.name) and entry.name != "default":
                    found.add(entry.name)
    return ["default", *sorted(found, key=str.lower)]


def sanitize(raw: object, spec: dict, themes: list[str] | None = None) -> dict:
    src = raw if isinstance(raw, dict) else {}
    out = {}
    for key, rule in spec.items():
        kind = rule[0]
        default = rule[-1]
        value = src.get(key, default)
        if kind == "bool":
            out[key] = value if isinstance(value, bool) else default
        elif kind in ("float", "int"):
            try:
                number = float(value)
            except (TypeError, ValueError):
                number = default
            if number != number:
                number = default
            number = clamp(number, rule[1], rule[2])
            out[key] = int(round(number)) if kind == "int" else round(number, 2)
        elif kind == "enum":
            value = str(value)
            out[key] = value if value in rule[1] else default
        elif kind == "theme":
            value = str(value)
            out[key] = value if value in (themes or ["default"]) else default
    return out


def devices() -> tuple[list[str], list[str]]:
    payload = hypr_json("devices")
    mice = payload.get("mice") if isinstance(payload, dict) else None
    touchpads, others = [], []
    for mouse in mice or []:
        name = str(mouse.get("name") or "")
        if not SAFE_NAME.match(name):
            continue
        lowered = name.lower()
        target = touchpads if ("touchpad" in lowered or "trackpad" in lowered) else others
        if name not in target:
            target.append(name)
    return touchpads, others


def saved_state() -> dict | None:
    try:
        lines = POINTER_LUA.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    for line in lines[:5]:
        if line.startswith(STATE_PREFIX):
            try:
                parsed = json.loads(line[len(STATE_PREFIX):])
            except json.JSONDecodeError:
                return None
            return parsed if isinstance(parsed, dict) else None
    return None


def existing_device_overrides(names: list[str]) -> dict:
    found: dict = {}
    for path in sorted(HYPR_DIR.glob("*.lua")):
        if path == POINTER_LUA:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("--") or "hl.device" not in stripped:
                continue
            name = re.search(r'name\s*=\s*"([^"]+)"', stripped)
            if not name or name.group(1) not in names:
                continue
            entry = found.setdefault(name.group(1), {})
            sens = re.search(r"sensitivity\s*=\s*(-?[0-9.]+)", stripped)
            accel = re.search(r'accel_profile\s*=\s*"([^"]+)"', stripped)
            left = re.search(r"left_handed\s*=\s*(true|false)", stripped)
            natural = re.search(r"natural_scroll\s*=\s*(true|false)", stripped)
            if sens:
                entry["sensitivity"] = float(sens.group(1))
            if accel:
                entry["accelProfile"] = accel.group(1)
            if left:
                entry["leftHanded"] = left.group(1) == "true"
            if natural:
                entry["naturalScroll"] = natural.group(1) == "true"
    return found


def drag3fg_name(value) -> str:
    try:
        return {1: "3", 2: "4"}.get(int(value or 0), "off")
    except (TypeError, ValueError):
        return "off"


def live_state() -> dict:
    mouse = {
        "sensitivity": option("input:sensitivity", 0.0),
        "accelProfile": option("input:accel_profile", "adaptive") or "adaptive",
        "naturalScroll": option("input:natural_scroll", False),
        "scrollFactor": option("input:scroll_factor", 1.0),
        "leftHanded": option("input:left_handed", False),
        "forceNoAccel": option("input:force_no_accel", False),
        "buttonScroll": option("input:scroll_method", "") == "on_button_down",
        "buttonScrollLock": option("input:scroll_button_lock", False),
    }
    touchpad = {
        "sensitivity": mouse["sensitivity"],
        "accelProfile": mouse["accelProfile"],
        "leftHanded": mouse["leftHanded"],
        "naturalScroll": option("input:touchpad:natural_scroll", False),
        "scrollFactor": option("input:touchpad:scroll_factor", 1.0),
        "tapToClick": option("input:touchpad:tap-to-click", True),
        "disableWhileTyping": option("input:touchpad:disable_while_typing", True),
        "clickfinger": option("input:touchpad:clickfinger_behavior", False),
        "tapAndDrag": option("input:touchpad:tap-and-drag", True),
        "dragLock": bool(option("input:touchpad:drag_lock", 0)),
        "middleEmulation": option("input:touchpad:middle_button_emulation", False),
        "tapButtonMap": option("input:touchpad:tap_button_map", "") or "lrm",
        "drag3fg": drag3fg_name(option("input:touchpad:drag_3fg", 0)),
        "gestureInvert": option("gestures:workspace_swipe_invert", True),
        "swipeDistance": option("gestures:workspace_swipe_distance", 300),
    }
    cursor = {
        "size": os.environ.get("XCURSOR_SIZE") or 24,
        "theme": os.environ.get("XCURSOR_THEME") or "default",
        "inactiveTimeout": option("cursor:inactive_timeout", 0),
        "hideOnKeyPress": option("cursor:hide_on_key_press", True),
        "hideOnTouch": option("cursor:hide_on_touch", True),
        "followMouse": str(option("input:follow_mouse", 1)),
        "warpToFocus": not option("cursor:no_warps", False),
        "warpOnWorkspace": bool(option("cursor:warp_on_change_workspace", 1)),
        "zoom": option("cursor:zoom_factor", 1.0),
        "resizeOnBorder": option("general:resize_on_border", True),
    }
    return {"mouse": mouse, "touchpad": touchpad, "cursor": cursor, "mice": {}}


def current_state() -> dict:
    touchpads, mice = devices()
    themes = cursor_themes()
    base = live_state()
    overrides = existing_device_overrides(touchpads + mice)
    for name in touchpads:
        base["touchpad"].update(overrides.get(name, {}))
    for name in mice:
        if name in overrides:
            base["mice"][name] = {**base["mouse"], **overrides[name], "custom": True}
    saved = saved_state()
    if saved:
        for section in ("mouse", "touchpad", "cursor"):
            if isinstance(saved.get(section), dict):
                base[section].update(saved[section])
        if isinstance(saved.get("mice"), dict):
            base["mice"] = saved["mice"]
    saved_mice = base["mice"] if isinstance(base["mice"], dict) else {}
    mice_state = {}
    for name in sorted(set(mice) | {str(n) for n in saved_mice if SAFE_NAME.match(str(n))}):
        raw = saved_mice.get(name)
        mice_state[name] = sanitize({**base["mouse"], **(raw if isinstance(raw, dict) else {})}, MOUSE_DEVICE)
    return {
        "mouse": sanitize(base["mouse"], MOUSE),
        "touchpad": sanitize(base["touchpad"], TOUCHPAD),
        "cursor": sanitize(base["cursor"], CURSOR, themes),
        "mice": mice_state,
        "connectedMice": mice,
        "touchpads": touchpads,
        "themes": themes,
        "hasTouchpad": bool(touchpads),
    }


def merge_state(raw: dict, state: dict | None = None) -> dict:
    state = json.loads(json.dumps(state)) if state else current_state()
    for section, spec in (("mouse", MOUSE), ("touchpad", TOUCHPAD), ("cursor", CURSOR)):
        incoming = raw.get(section)
        if isinstance(incoming, dict):
            state[section] = sanitize({**state[section], **incoming}, spec, state["themes"])
    incoming_mice = raw.get("mice")
    if isinstance(incoming_mice, dict):
        for name, values in incoming_mice.items():
            if name in state["mice"] and isinstance(values, dict):
                state["mice"][name] = sanitize({**state["mice"][name], **values}, MOUSE_DEVICE)
    return state


def lb(value: bool) -> str:
    return "true" if value else "false"


def device_line(name: str, fields: dict) -> str:
    parts = [f'name = "{name}"']
    for key, value in fields.items():
        if isinstance(value, bool):
            parts.append(f"{key} = {lb(value)}")
        elif isinstance(value, float):
            parts.append(f"{key} = {value:.2f}")
        elif isinstance(value, int):
            parts.append(f"{key} = {value}")
        else:
            parts.append(f'{key} = "{value}"')
    return "hl.device({ " + ", ".join(parts) + " })"


def pointer_fields(values: dict) -> dict:
    return {
        "sensitivity": float(values["sensitivity"]),
        "accel_profile": values["accelProfile"],
        "natural_scroll": values["naturalScroll"],
        "scroll_factor": float(values["scrollFactor"]),
        "left_handed": values["leftHanded"],
    }


def lua_config(state: dict, persistent: bool = True) -> str:
    m, t, c = state["mouse"], state["touchpad"], state["cursor"]
    drag3 = {"off": 0, "3": 1, "4": 2}[t["drag3fg"]]
    lines = [
        "hl.config({",
        "  input = {",
        f"    sensitivity = {m['sensitivity']:.2f},",
        f"    accel_profile = \"{m['accelProfile']}\",",
        f"    natural_scroll = {lb(m['naturalScroll'])},",
        f"    scroll_factor = {m['scrollFactor']:.2f},",
        f"    left_handed = {lb(m['leftHanded'])},",
        f"    force_no_accel = {lb(m['forceNoAccel'])},",
        f"    scroll_method = \"{'on_button_down' if m['buttonScroll'] else ''}\",",
        f"    scroll_button = {BTN_MIDDLE if m['buttonScroll'] else 0},",
        f"    scroll_button_lock = {lb(m['buttonScroll'] and m['buttonScrollLock'])},",
        f"    follow_mouse = {c['followMouse']},",
        "    touchpad = {",
        f"      natural_scroll = {lb(t['naturalScroll'])},",
        f"      scroll_factor = {t['scrollFactor']:.2f},",
        f"      tap_to_click = {lb(t['tapToClick'])},",
        f"      disable_while_typing = {lb(t['disableWhileTyping'])},",
        f"      clickfinger_behavior = {lb(t['clickfinger'])},",
        f"      tap_and_drag = {lb(t['tapAndDrag'])},",
        f"      drag_lock = {1 if t['dragLock'] else 0},",
        f"      middle_button_emulation = {lb(t['middleEmulation'])},",
        f"      tap_button_map = \"{t['tapButtonMap']}\",",
        f"      drag_3fg = {drag3},",
        "    },",
        "  },",
        "  cursor = {",
        f"    inactive_timeout = {c['inactiveTimeout']},",
        f"    hide_on_key_press = {lb(c['hideOnKeyPress'])},",
        f"    hide_on_touch = {lb(c['hideOnTouch'])},",
        f"    no_warps = {lb(not c['warpToFocus'])},",
        f"    warp_on_change_workspace = {1 if c['warpOnWorkspace'] else 0},",
        f"    zoom_factor = {c['zoom']:.2f},",
        "  },",
        "  general = {",
        f"    resize_on_border = {lb(c['resizeOnBorder'])},",
        "  },",
        "  gestures = {",
        f"    workspace_swipe_invert = {lb(t['gestureInvert'])},",
        f"    workspace_swipe_distance = {t['swipeDistance']},",
        "  },",
        "})",
    ]
    for name in state["touchpads"]:
        if SAFE_NAME.match(name):
            lines.append(device_line(name, {
                "sensitivity": float(t["sensitivity"]),
                "accel_profile": t["accelProfile"],
                "left_handed": t["leftHanded"],
                "scroll_method": t["scrollMethod"],
            }))
    for name, values in state["mice"].items():
        if not SAFE_NAME.match(name):
            continue
        if values["custom"]:
            lines.append(device_line(name, pointer_fields(values)))
        elif not persistent and name in state["connectedMice"]:
            lines.append(device_line(name, pointer_fields(m)))
    if persistent:
        if t["gestures"] and state["touchpads"]:
            lines.append(f'hl.gesture({{ fingers = {t["gestureFingers"]}, direction = "horizontal", action = "workspace" }})')
        lines.append(f'hl.env("XCURSOR_SIZE", "{c["size"]}")')
        lines.append(f'hl.env("HYPRCURSOR_SIZE", "{c["size"]}")')
        if c["theme"] != "default":
            lines.append(f'hl.env("XCURSOR_THEME", "{c["theme"]}")')
    return "\n".join(lines)


def apply_live(state: dict) -> None:
    try:
        proc = run(["hyprctl", "eval", lua_config(state, persistent=False)])
    except (OSError, subprocess.TimeoutExpired) as exc:
        sys.stderr.write(f"hyprctl eval failed: {exc}\n")
        return
    if proc.returncode != 0 or proc.stdout.strip().lower().startswith("error"):
        sys.stderr.write(proc.stderr or proc.stdout or "hyprctl eval failed\n")


def apply_cursor(state: dict) -> None:
    c = state["cursor"]
    quiet(["hyprctl", "setcursor", c["theme"], str(c["size"])])
    quiet(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(c["size"])])
    quiet(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", c["theme"]])


def persisted_view(state: dict) -> dict:
    return {key: state[key] for key in ("mouse", "touchpad", "cursor", "mice")}


def persist(state: dict) -> None:
    HYPR_DIR.mkdir(parents=True, exist_ok=True)
    body = (
        f"-- Generated by the Mouse & Touchpad panel ({PLUGIN_ID}). Change it from the panel.\n"
        + STATE_PREFIX
        + json.dumps(persisted_view(state), separators=(",", ":"), sort_keys=True)
        + "\n"
        + lua_config(state)
        + "\n"
    )
    tmp = POINTER_LUA.with_suffix(".lua.tmp")
    tmp.write_text(body, encoding="utf-8")
    tmp.replace(POINTER_LUA)
    ensure_require()


def ensure_require() -> None:
    if not HYPRLAND_LUA.exists():
        return
    text = HYPRLAND_LUA.read_text(encoding="utf-8")
    if REQUIRE_LINE in text or "require('hypr.pointer')" in text:
        return
    backup = HYPRLAND_LUA.with_name(f"hyprland.lua.bak.{os.getpid()}")
    backup.write_text(text, encoding="utf-8")
    needle = 'require("hypr.input")'
    if needle in text:
        text = text.replace(needle, needle + "\n" + REQUIRE_LINE, 1)
    else:
        text = text.rstrip("\n") + "\n\n" + REQUIRE_LINE + "\n"
    tmp = HYPRLAND_LUA.with_suffix(".lua.tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(HYPRLAND_LUA)


def gesture_key(state: dict) -> tuple:
    t = state["touchpad"]
    return (t["gestures"], t["gestureFingers"])


def cursor_key(state: dict) -> tuple:
    return (state["cursor"]["size"], state["cursor"]["theme"])


def apply(state: dict, before: dict) -> None:
    apply_live(state)
    persist(state)
    if cursor_key(state) != cursor_key(before):
        apply_cursor(state)
    if gesture_key(state) != gesture_key(before):
        quiet(["hyprctl", "reload"])


def read_payload(args: list[str]) -> dict:
    raw = (" ".join(args) if args else sys.stdin.read()).strip()
    if not raw:
        return {}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid json: {exc}") from exc
    if not isinstance(parsed, dict):
        raise SystemExit("payload must be a json object")
    return parsed


def emit(state: dict) -> None:
    json.dump(state, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        sys.stderr.write("usage: apply.py get | live [json] | apply [json] | lua [json]\n")
        return 2
    command = sys.argv[1]
    if command == "get":
        emit(current_state())
        return 0
    if command in ("live", "apply", "lua"):
        payload = read_payload(sys.argv[2:])
        before = current_state()
        state = merge_state(payload, before)
        if command == "lua":
            print(lua_config(state))
        elif command == "live":
            apply_live(state)
            emit(state)
        else:
            apply(state, before)
            emit(state)
        return 0
    sys.stderr.write(f"unknown command: {command}\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
