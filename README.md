<h1 align="center">ember</h1>

<p align="center">
  <img src="https://img.shields.io/badge/DMS-1.7--beta-ffab4a?style=flat-square&labelColor=1b1a20" alt="DMS 1.7-beta">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-ffab4a?style=flat-square&labelColor=1b1a20" alt="license MIT"></a>
</p>

ember is a night light plugin for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS). it adds a moon to the bar, a small panel and a control center tile. it has three modes (always on, scheduled from sunset to sunrise, and off) and night and day temperature sliders from 2000K to 6500K that preview on screen while you drag them.

mode changes fade over 800ms by default. ember keeps no state of its own. it reads and writes the DMS night mode settings, so the gamma control tab, `dms ipc call night` and ember always show the same values.

## ✨ highlights

- 🌙 **three modes** (always on, scheduled from sunset to sunrise, and off) switch from the panel, the control center tile or a right click on the moon.
- 🌅 **smooth fades** warm or cool the screen over 800ms instead of snapping, and the length is a setting.
- 🎚 **a live preview** moves the screen with the night and day sliders while you drag, and saves the value 1200ms after you let go.
- 🌡 **a live readout** of the colour temperature sits next to the moon, and the moon shades towards amber as the screen warms.
- 🔗 **shared state** lives in the DMS night mode settings, so ember and the rest of DMS always agree.

## 📦 install

```sh
git clone https://github.com/z89/ember ~/.config/DankMaterialShell/plugins/ember
dms ipc call plugins enable ember
```

then add `ember` to a bar under settings, bar, widgets. no restart needed.

## 🌙 use

left click the moon to open the panel. right click switches between always on and scheduled, and so does the control center tile.

| mode | what the screen does |
| --- | --- |
| 🌙 always on | holds the night temperature all day |
| 🌅 scheduled | neutral by day, warm from sunset to sunrise |
| ⭕ off | no change |

the night and day sliders share one range, 2000K to 6500K in steps of 100K. the screen follows a slider while you drag it, and the current mode takes over again once you let go.

## ⚙️ settings

found on the plugin's settings page in DMS.

| setting | default | effect |
| --- | --- | --- |
| 🌡 show temperature | on | prints the live colour temperature next to the moon while night light is on |
| 🌅 fade | 800ms | how long a mode change takes, from 0 (instant) to 3000ms |
| 🎨 warm tint | on | shades the moon towards amber as the screen warms, instead of the accent colour |

only changes made through ember fade. the gamma control tab and `dms ipc call night` still switch instantly.

## ✅ requirements

- DMS 1.7 beta or newer, with the `gamma` capability.
- a compositor with `wlr-gamma-control`, such as hyprland, niri or sway.
- your coordinates set in DMS, for scheduled mode.

## 🩺 troubleshooting

if the night slider does nothing, ember is most likely in scheduled mode during the day. the night value only applies from sunset, so drag the slider to preview it or switch to always on.

if the panel reads gamma control unavailable and the mode switch is greyed out, the compositor has no gamma control or DMS was built without the `gamma` capability.

## 🧪 tests

`python3 tests/test_modes.py` runs ember's real mode and fade logic in qt with stand-ins for DMS, so no desktop or DMS daemon is needed. it needs qt 6's `qmltestrunner`.

## 📁 layout

```
EmberWidget.qml       bar moon, panel and control center tile
EmberSettings.qml     settings page
plugin.json           plugin manifest
tests/test_modes.py   python3 tests/test_modes.py
```

## 📄 license

MIT
