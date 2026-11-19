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

SAFE_DEVICE = re.compile(r"^[A-Za-z0-9:._+-]{1,128}$")

COMMON_DEFAULTS = {
    "sensitivity": 0.0,
    "accelProfile": "adaptive",
    "naturalScroll": False,
    "scrollFactor": 1.0,
    "leftHanded": False,
}
TOUCHPAD_DEFAULTS = {
    **COMMON_DEFAULTS,
    "tapToClick": True,
    "disableWhileTyping": True,
    "clickfinger": False,
    "drag3fg": False,
}
BOOL_KEYS = {
    "naturalScroll",
    "leftHanded",
    "tapToClick",
    "disableWhileTyping",
    "clickfinger",
    "drag3fg",
}


def run(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, check=False, text=True, capture_output=True, timeout=5)


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


def option(name: str, kind: str, fallback):
    data = hypr_json("getoption", name)
    if not isinstance(data, dict):
        return fallback
    if kind == "bool":
        if "bool" in data:
            return bool(data["bool"])
        if "int" in data:
            return bool(data["int"])
        return fallback
    if kind == "float":
        for key in ("float", "int"):
            if key in data:
                try:
                    return float(data[key])
                except (TypeError, ValueError):
                    return fallback
        return fallback
    value = data.get("str")
    return fallback if value in (None, "", "[[EMPTY]]") else str(value)


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def normalize_accel(value: object) -> str:
    return "flat" if str(value or "").strip().lower() == "flat" else "adaptive"


def touchpad_names() -> list[str]:
    payload = hypr_json("devices")
    mice = payload.get("mice") if isinstance(payload, dict) else None
    names = []
    for mouse in mice or []:
        name = str(mouse.get("name") or "")
        lowered = name.lower()
        if ("touchpad" in lowered or "trackpad" in lowered) and SAFE_DEVICE.match(name):
            if name not in names:
                names.append(name)
    return names


def sanitize(raw: object, defaults: dict) -> dict:
    out = dict(defaults)
    if not isinstance(raw, dict):
        return out
    for key, default in defaults.items():
        if key not in raw:
            continue
        value = raw[key]
        if key in BOOL_KEYS:
            out[key] = bool(value)
        elif key == "accelProfile":
            out[key] = normalize_accel(value)
        else:
            try:
                number = float(value)
            except (TypeError, ValueError):
                continue
            if number != number:
                continue
            out[key] = clamp(number, -1.0, 1.0) if key == "sensitivity" else clamp(number, 0.1, 2.0)
    return out


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


def existing_device_override(names: list[str]) -> dict:
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
            sens = re.search(r"sensitivity\s*=\s*(-?[0-9.]+)", stripped)
            accel = re.search(r'accel_profile\s*=\s*"([^"]+)"', stripped)
            left = re.search(r"left_handed\s*=\s*(true|false)", stripped)
            if sens:
                found["sensitivity"] = float(sens.group(1))
            if accel:
                found["accelProfile"] = accel.group(1)
            if left:
                found["leftHanded"] = left.group(1) == "true"
    return found


def live_state() -> dict:
    mouse = {
        "sensitivity": option("input:sensitivity", "float", 0.0),
        "accelProfile": option("input:accel_profile", "str", "adaptive"),
        "naturalScroll": option("input:natural_scroll", "bool", False),
        "scrollFactor": option("input:scroll_factor", "float", 1.0),
        "leftHanded": option("input:left_handed", "bool", False),
    }
    touchpad = {
        **{k: mouse[k] for k in ("sensitivity", "accelProfile", "leftHanded")},
        "naturalScroll": option("input:touchpad:natural_scroll", "bool", False),
        "scrollFactor": option("input:touchpad:scroll_factor", "float", 1.0),
        "tapToClick": option("input:touchpad:tap-to-click", "bool", True),
        "disableWhileTyping": option("input:touchpad:disable_while_typing", "bool", True),
        "clickfinger": option("input:touchpad:clickfinger_behavior", "bool", False),
        "drag3fg": option("input:touchpad:drag_3fg", "bool", False),
    }
    return {"mouse": mouse, "touchpad": touchpad}


def current_state() -> dict:
    names = touchpad_names()
    base = saved_state()
    if base is None:
        base = live_state()
        base["touchpad"].update(existing_device_override(names))
    return {
        "mouse": sanitize(base.get("mouse"), COMMON_DEFAULTS),
        "touchpad": sanitize(base.get("touchpad"), TOUCHPAD_DEFAULTS),
        "touchpads": names,
        "hasTouchpad": bool(names),
    }


def merge_state(raw: dict) -> dict:
    state = current_state()
    for section, defaults in (("mouse", COMMON_DEFAULTS), ("touchpad", TOUCHPAD_DEFAULTS)):
        incoming = raw.get(section)
        if isinstance(incoming, dict):
            state[section] = sanitize({**state[section], **incoming}, defaults)
    return state


def lua_bool(value: bool) -> str:
    return "true" if value else "false"


def lua_config(state: dict) -> str:
    m = state["mouse"]
    t = state["touchpad"]
    lines = [
        "hl.config({",
        "  input = {",
        f"    sensitivity = {m['sensitivity']:.2f},",
        f"    accel_profile = \"{m['accelProfile']}\",",
        f"    natural_scroll = {lua_bool(m['naturalScroll'])},",
        f"    scroll_factor = {m['scrollFactor']:.2f},",
        f"    left_handed = {lua_bool(m['leftHanded'])},",
        "    touchpad = {",
        f"      natural_scroll = {lua_bool(t['naturalScroll'])},",
        f"      scroll_factor = {t['scrollFactor']:.2f},",
        f"      tap_to_click = {lua_bool(t['tapToClick'])},",
        f"      disable_while_typing = {lua_bool(t['disableWhileTyping'])},",
        f"      clickfinger_behavior = {lua_bool(t['clickfinger'])},",
        f"      drag_3fg = {1 if t['drag3fg'] else 0},",
        "    },",
        "  },",
        "})",
    ]
    for name in state["touchpads"]:
        if not SAFE_DEVICE.match(name):
            continue
        lines.append(
            f'hl.device({{ name = "{name}", sensitivity = {t["sensitivity"]:.2f}, '
            f'accel_profile = "{t["accelProfile"]}", left_handed = {lua_bool(t["leftHanded"])} }})'
        )
    return "\n".join(lines)


def apply_live(state: dict) -> None:
    try:
        proc = run(["hyprctl", "eval", lua_config(state)])
    except (OSError, subprocess.TimeoutExpired) as exc:
        sys.stderr.write(f"hyprctl eval failed: {exc}\n")
        return
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr or proc.stdout or "hyprctl eval failed\n")


def persist(state: dict) -> None:
    HYPR_DIR.mkdir(parents=True, exist_ok=True)
    saved = {"mouse": state["mouse"], "touchpad": state["touchpad"]}
    body = (
        f"-- Generated by the Mouse & Touchpad panel ({PLUGIN_ID}). Change it from the panel.\n"
        + STATE_PREFIX
        + json.dumps(saved, separators=(",", ":"), sort_keys=True)
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
        state = merge_state(read_payload(sys.argv[2:]))
        if command == "lua":
            print(lua_config(state))
            return 0
        apply_live(state)
        if command == "apply":
            persist(state)
        emit(state)
        return 0
    sys.stderr.write(f"unknown command: {command}\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
