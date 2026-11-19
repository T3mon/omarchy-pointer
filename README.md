# Mouse & Touchpad

Omarchy bar widget that configures your mouse and your touchpad separately:
pointer speed, acceleration, scroll speed, natural scrolling, and primary
button for each, plus tap to click, pause while typing, two-finger click,
and three-finger drag for the touchpad.

Based on [wouldja/omarchy-mouse](https://github.com/wouldja/omarchy-mouse).

## Install

```sh
omarchy plugin add https://github.com/T3mon/omarchy-pointer.git --enable
```

Click the mouse icon to open the panel. When a touchpad is detected, a
**Mouse / Touchpad** switch at the top picks which device you are editing.
Scrolling over the icon nudges the pointer speed of the device last shown.

## How the settings stay separate

Hyprland's global `input` section applies to every pointer, so the plugin
splits them like this:

| Setting | Mouse | Touchpad |
|---|---|---|
| Pointer speed, acceleration, primary button | `input` | `hl.device` per touchpad (overrides `input`) |
| Scroll speed, natural scroll | `input` | `input.touchpad` |
| Tap, pause while typing, two-finger click, three-finger drag | | `input.touchpad` |

Touchpads are found with `hyprctl devices` (any pointer whose name contains
`touchpad` or `trackpad`).

## What it changes

Dragging a slider applies values live through `hyprctl eval`. Releasing it, or
any click, also writes:

- `~/.config/hypr/pointer.lua`: generated settings, with the panel state on its
  second line
- `~/.config/hypr/hyprland.lua`: adds `require("hypr.pointer")` after
  `require("hypr.input")` if missing (a `.bak.<pid>` copy is kept)

Because `pointer.lua` loads after `input.lua`, it wins over pointer settings
there. On first open, an existing `hl.device` block for your touchpad in
`~/.config/hypr/*.lua` is read so its speed is kept.

It never edits `/usr/share/omarchy` and never asks for elevated permissions.

## Remove

```sh
omarchy plugin remove t3mon.pointer
rm ~/.config/hypr/pointer.lua
```

Then delete the `require("hypr.pointer")` line from `~/.config/hypr/hyprland.lua`.

## Tests

```sh
node tests/model.test.js
python3 -I tests/test_apply.py
```

## License

MIT. Needs Omarchy (Quickshell), Hyprland, and Python 3.
