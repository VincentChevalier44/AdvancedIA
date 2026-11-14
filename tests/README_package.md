# AdvancedIA

**Human-like AI drivers for Assetto Corsa, powered by Custom Shaders Patch.**

- **Version in this package:** {VERSION}. What changed: [CHANGELOG.md](CHANGELOG.md).
- **Full user guide** (every setting, rule and log line): the README on GitHub, https://github.com/VincentChevalier44/AdvancedIA#readme
- **Author:** VincentChevalier44. MIT License (see `LICENSE`).

AdvancedIA is a Lua app for Assetto Corsa running on Custom Shaders Patch (CSP). It sits on top of the game's own AI
and makes the AI cars drive more like people: overtaking and defending, yielding, blue flags, mistakes, slipstream,
yellow flags, Safety Car, race rules and strategy, for track days, practice, qualifying and races.

## Requirements

- Assetto Corsa for PC with **Custom Shaders Patch** (Lua apps enabled).
- **Content Manager** recommended (the app reads the session type it writes to `race.ini`).
- Offline sessions only: in an online session the app sends no command.

## Installation

1. Close Assetto Corsa.
2. Drag this zip onto the Content Manager window and confirm, or extract it into the `assettocorsa` root folder.
3. Check the path: `assettocorsa/apps/lua/AdvancedIA/manifest.ini`.

## First launch

1. Start an offline session (Practice, Track day, Race weekend, Race or Hotlap).
2. Open the pause menu (Esc) or the setup screen: the AdvancedIA window opens there by itself. While you drive, only
   the in-game overlay is shown, and you can open a compact view of the window from AC's apps bar.
3. The built-in preset matching the session is applied automatically: nothing to set up. **FR** | **EN** at the top
   right of the window switches the language.
4. Races: add the Safety Car model (by default `ferrari_458_s3`) to the grid, or the app falls back to a VSC or FCY.

## Updating

At launch the app checks GitHub once for a newer release (nothing about you is sent). When one exists, an
**UPDATE** button appears in the window header: one click updates the app, your settings are kept. You can also
install a newer zip over this one.

## Reporting a problem

Please send, on Overtake or GitHub (https://github.com/VincentChevalier44/AdvancedIA/issues):
1. your log: `Documents\Assetto Corsa\logs\AdvancedIA.log`;
2. your CSP version;
3. the session type (track day, practice, qualifying, race, hotlap).
