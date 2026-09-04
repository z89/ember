<p align="center">
  <img src="assets/ember.svg" width="112" alt="ember">
</p>

<h1 align="center">ember</h1>

<p align="center">night light for <a href="https://github.com/AvengeMedia/DankMaterialShell">dankmaterialshell</a></p>

<p align="center">
  <a href="https://github.com/z89/ember/stargazers"><img src="https://img.shields.io/github/stars/z89/ember?style=flat-square&color=ffab4a&labelColor=1b1a20" alt="stars"></a>
  <a href="https://github.com/z89/ember/commits/main"><img src="https://img.shields.io/github/last-commit/z89/ember?style=flat-square&color=ffab4a&labelColor=1b1a20" alt="last commit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/z89/ember?style=flat-square&color=ffab4a&labelColor=1b1a20" alt="license"></a>
  <img src="https://img.shields.io/badge/dms-1.7%2B-ffab4a?style=flat-square&labelColor=1b1a20" alt="dms 1.7+">
</p>

a moon on the bar, a small panel, and the screen follows the slider while you drag it.

## install

```sh
git clone https://github.com/z89/ember ~/.config/DankMaterialShell/plugins/ember
dms ipc call plugins enable ember
```

then drop `ember` onto a bar under settings, bar, widgets. no restart needed.

## use

left click the moon for the panel. right click flips between always on and scheduled.

- **always on** holds the night temperature all day
- **scheduled** is neutral by day, warm from sunset to sunrise
- **off** does nothing

two sliders, night and day, 2000k to 6500k. drag one and the screen changes with it. let go and the current mode takes back over. like what you saw? go always on.

## needs

- dms 1.7 or newer with the `gamma` capability
- a compositor with `wlr-gamma-control` (hyprland, niri, sway)
- your coordinates set in dms, for scheduled mode

## notes

ember keeps no state of its own. it reads and writes dms's night mode settings, so the gamma control tab, `dms ipc call night` and ember always agree.

moved the night slider and nothing happened? scheduled mode, daytime. the daemon holds the day value until sunset. drag to preview, or go always on.

## license

mit
