# Mouse & Touchpad

Omarchy bar widget for pointer settings, with separate tabs for mice, the
touchpad, and the cursor.

- **Mouse**: speed, scroll speed, acceleration, primary button, natural
  scroll, raw input, middle-drag scrolling. Pick **All mice** or a single
  connected mouse and give it its own settings.
- **Touchpad**: its own speed, scroll speed, acceleration and primary button,
  plus tap to click, pause while typing, two-finger click, tap and drag, drag
  lock, middle click emulation, two-finger tap action, edge or two-finger
  scrolling, three/four-finger drag, and workspace swipe gestures.
- **Cursor**: size, theme, focus follows mouse, hide when idle, hide while
  typing or on touch, jump to focus, resize by dragging borders, and zoom.

Based on [wouldja/omarchy-mouse](https://github.com/wouldja/omarchy-mouse).

## Install

```sh
omarchy plugin add https://github.com/T3mon/omarchy-pointer.git --enable
```

Click the mouse icon to open the panel. When a touchpad is detected, a
**Mouse / Touchpad** switch at the top picks which device you are editing.
Scrolling over the icon nudges the pointer speed of the device last shown.

## How the settings stay separate

| Setting | Where it is written |
|---|---|
| All mice | `input` |
| One mouse with Own settings | `hl.device` for that mouse |
| Touchpad speed, acceleration, primary, scroll method | `hl.device` per touchpad |
| Touchpad scroll, tap, drag options | `input.touchpad` |
| Swipe gestures | `hl.gesture` and `gestures` |
| Cursor | `cursor`, `general`, `input.follow_mouse`, cursor env vars |

Touchpads are the pointers whose name contains `touchpad` or `trackpad`; every
other pointer from `hyprctl devices` is listed as a mouse.

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

Changing swipe gestures reloads Hyprland. Changing cursor size or theme also
runs `hyprctl setcursor` and updates the GNOME cursor settings for GTK apps.

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
