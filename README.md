<h1 align="center">ember</h1>

<p align="center">
  <a href="https://github.com/z89/ember/stargazers"><img src="https://img.shields.io/github/stars/z89/ember?style=flat-square&color=ffab4a&labelColor=1b1a20" alt="stars"></a>
  <a href="https://github.com/z89/ember/commits/main"><img src="https://img.shields.io/github/last-commit/z89/ember?style=flat-square&color=ffab4a&labelColor=1b1a20" alt="last commit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/z89/ember?style=flat-square&color=ffab4a&labelColor=1b1a20" alt="license"></a>
  <img src="https://img.shields.io/badge/dms-1.7%2B-ffab4a?style=flat-square&labelColor=1b1a20" alt="dms 1.7+">
  <img src="https://img.shields.io/badge/hyprland-0.56.2-ffab4a?style=flat-square&labelColor=1b1a20" alt="hyprland 0.56.2">
  <img src="https://img.shields.io/badge/arch%20linux-7.2.6-ffab4a?style=flat-square&labelColor=1b1a20" alt="arch linux, kernel 7.2.6">
</p>

ember is a DankMaterialShell plugin that puts night mode on the bar. it adds a small icon to the bar that shows the current colour temperature, and a panel with a mode switch and two sliders. the sliders change the screen as you drag them, so you can see what a temperature looks like before you keep it.

ember has no settings of its own. it reads and writes the night mode settings DMS already keeps, so the Gamma Control tab in DMS settings, the `dms ipc call night` command and ember always show the same values. changing something in one place updates the others.

## ✨ highlights

- 🌙 **three modes**: always on, scheduled, or off. always on holds the night temperature all day. scheduled keeps the screen neutral during the day and warms it between sunset and sunrise. off leaves the screen as it is.
- 🎚️ **live preview**: two sliders, one for night and one for day, both from 2000K to 6500K. the screen follows the slider while you drag it. the value is saved about a second after you let go.
- 🔥 **bar icon with a readout**: the icon changes with the mode, shows the current temperature next to it, and tints towards amber as the screen warms.
- 🖱️ **quick switching**: left click opens the panel. right click flips between always on and scheduled without opening anything.
- 🧩 **control centre tile**: the same toggle is available as a tile in the DMS control centre.
- 🔗 **shared state**: everything is stored in DMS's own night mode settings, so nothing can drift out of sync.

## 📦 install

```sh
git clone https://github.com/z89/ember ~/.config/DankMaterialShell/plugins/ember
dms ipc call plugins enable ember
```

then add `ember` to a bar under settings, bar, widgets. no shell restart is needed.

## 🎛️ how to use it

### the bar icon

the icon on the bar tells you what mode you are in:

- a filled moon means always on.
- a filled night light icon means scheduled.
- an outlined moon means off.

when night mode is on, the current temperature is printed next to the icon in kelvin. as the screen warms towards the night temperature, the icon shades from your accent colour towards amber.

left click the icon to open the panel. right click flips between always on and scheduled.

### the panel

the panel has a status line at the top that says what ember is doing right now: the mode, the current temperature, and when the next change is due. under that:

- **mode switch**: always on, scheduled, or off. a short line underneath explains what the selected mode does and, for scheduled, shows the sunset and sunrise times DMS is using.
- **night slider**: the temperature to use at night, or all day in always on mode. the default is 4500K.
- **day slider**: the temperature to use during the day in scheduled mode. the default is 6500K, which is neutral.

both sliders run from 2000K to 6500K in 100K steps, and they share the same range, so the same thumb position always means the same temperature.

### the live preview

while you drag either slider, ember sends the value straight to the screen. this lets you see what the temperature looks like before you keep it. once the slider has been still for a moment, the value is saved to DMS and the current mode takes over again.

what that means in practice:

- in always on mode, the night slider changes the screen and the screen stays there.
- in scheduled mode during the day, the night slider changes the screen while you drag, then the screen returns to the day temperature. the new night value is saved and used from sunset.
- in off mode, the sliders still save their values but there is no preview, because night mode is not running.

if you like what you saw while dragging and want to keep it, switch to always on.

### the control centre tile

ember also shows up as a tile in the DMS control centre. the tile shows the same status line as the panel and lights up when the screen is warm, meaning always on, or scheduled after sunset. tapping it flips between always on and scheduled, the same as right clicking the bar icon.

## ⚙️ settings

the plugin has two options under settings, plugins, ember. both are cosmetic.

| option | default | what it does |
|---|---|---|
| show temperature | on | print the live colour temperature next to the bar icon while night mode is on |
| warm tint | on | shade the icon towards amber as the screen warms. turn it off to keep the icon in the accent colour |

the temperatures and the schedule are not plugin settings. they live in DMS under settings, display, gamma control, and ember edits the same values.

## ✅ requirements

- DankMaterialShell 1.7 or newer with the `gamma` capability.
- a compositor that supports `wlr-gamma-control`, such as hyprland, niri or sway.
- your location set in DMS, so that scheduled mode knows when sunset and sunrise are.

## 🩺 troubleshooting

if the panel says **gamma control unavailable**, DMS cannot talk to the compositor's gamma protocol. check that your compositor supports `wlr-gamma-control` and that DMS is 1.7 or newer.

if you moved the night slider and the screen did not stay warm, you are probably in scheduled mode during the day. the preview shows the value while you drag, then DMS goes back to the day temperature until sunset. switch to always on if you want the night temperature right now.

if scheduled mode never warms the screen, check that DMS has your location. without coordinates it cannot work out sunset and sunrise.

if the sliders do nothing at all, night mode is off. switch to always on or scheduled first.

## 📄 license

mit
