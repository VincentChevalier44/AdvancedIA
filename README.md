<p align="center"><img src="docs/banner.jpg" width="100%" alt="AdvancedIA, more human, more racing: smarter opponents, more immersive offline racing. Human-like AI, overtaking and defence, flags and Safety Car, pit and weather strategy."></p>

# AdvancedIA

**Human-like AI drivers for Assetto Corsa, powered by Custom Shaders Patch.**

AdvancedIA is a Lua app for Assetto Corsa running on Custom Shaders Patch (CSP). Its HumanAI engine sits on top of the game's own AI and makes the AI cars drive more like people. On a track day they move aside for faster cars and spread out around the lap. In a race they respect blue flags, overtake and defend with intent, and flash their headlights at slower cars. They make the odd mistake, slow down for yellow flags, and follow Full Course Yellows, Virtual Safety Cars, a Safety Car and red flags. They make their mandatory pit stops, refuel and repair, and fit wet tyres when it rains. The app enforces the racing rules for you as well (delta time, penalties, DRS rules), and its in-game overlay tells you what is happening. It works in **offline sessions only**.

- **Current version:** Beta 1.50. See [CHANGELOG.md](CHANGELOG.md).
- **Interface:** English by default, French available (**FR** | **EN** buttons in the settings window).
- **Author:** VincentChevalier44. MIT License.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
  - [With Content Manager (recommended)](#with-content-manager-recommended)
  - [Manual installation](#manual-installation)
  - [First launch](#first-launch)
- [Updating](#updating)
  - [Moving from ACAdvancedIA (Beta 1.48 and older)](#moving-from-acadvancedia-beta-148-and-older)
- [Uninstalling and resetting the settings](#uninstalling-and-resetting-the-settings)
- [Features](#features)
  - [The settings window (Racing 26 interface)](#the-settings-window-racing-26-interface)
  - [Session profiles and automatic detection](#session-profiles-and-automatic-detection)
  - [Sections, built-in presets and first-install behaviour](#sections-built-in-presets-and-first-install-behaviour)
  - [General driving: level, aggression, caution and spreads](#general-driving-level-aggression-caution-and-spreads)
  - [Personality, focus and driving mistakes](#personality-focus-and-driving-mistakes)
  - [Yielding](#yielding)
  - [Blue flags](#blue-flags)
  - [Headlight flashes and horn](#headlight-flashes-and-horn)
  - [Overtaking, defending and slipstream](#overtaking-defending-and-slipstream)
  - [Lateral movement, lane holding and anti-weaving](#lateral-movement-lane-holding-and-anti-weaving)
  - [Race start](#race-start)
  - [Pit exit](#pit-exit)
  - [Accidents, yellow flags and recovery](#accidents-yellow-flags-and-recovery)
  - [Delta time, penalties and AI sanctions](#delta-time-penalties-and-ai-sanctions)
  - [Racing rules and rule sets](#racing-rules-and-rule-sets)
  - [Neutralisations: FCY, VSC and Safety Car](#neutralisations-fcy-vsc-and-safety-car)
  - [Red flag](#red-flag)
  - [DRS and Overtake Mode](#drs-and-overtake-mode)
  - [Pit stops: mandatory stops, tyres, fuel and repairs](#pit-stops-mandatory-stops-tyres-fuel-and-repairs)
  - [AI strategy, out-lap, tyre wear and failures](#ai-strategy-out-lap-tyre-wear-and-failures)
  - [Endurance and multi-class](#endurance-and-multi-class)
  - [Weather and tyres](#weather-and-tyres)
  - [Track-day traffic spacing](#track-day-traffic-spacing)
  - [AI distribution at session start and CSP AI flood](#ai-distribution-at-session-start-and-csp-ai-flood)
  - [Front radar and the other global options](#front-radar-and-the-other-global-options)
  - [In-game overlay](#in-game-overlay)
  - [Track light panels](#track-light-panels)
  - [Companion apps (SpotterEnginer bridge)](#companion-apps-spotterenginer-bridge)
  - [Beeps](#beeps)
  - [Custom presets](#custom-presets)
  - [Track zones and class patterns](#track-zones-and-class-patterns)
  - [Diagnostics tab](#diagnostics-tab)
  - [Safety guards and what the app never does](#safety-guards-and-what-the-app-never-does)
- [Settings overview](#settings-overview)
  - [Settings reference](#settings-reference)
- [Session log](#session-log)
- [Compatibility and known limitations](#compatibility-and-known-limitations)
- [Troubleshooting](#troubleshooting)
- [Development and tests](#development-and-tests)
- [Changelog, license and credits](#changelog-license-and-credits)

## Requirements

- **Assetto Corsa** for PC.
- **Custom Shaders Patch** installed and enabled, with Lua apps working (the app lives in `assettocorsa/apps/lua/`).
  - The manifest declares no minimum CSP version. The app was developed and checked against **CSP 0.3.0-preview675** (build 4210, see [docs/API_NOTES.md](docs/API_NOTES.md)).
  - The app checks every CSP function it uses while it runs. Anything missing is simply left unused, and the **DIAGNOSTICS** tab lists what is available.
  - If CSP is too old to draw the settings window, the window shows: *This CSP version lacks the drawing functions the settings window needs: please update CSP.*
- **Content Manager** (recommended).
  - The app reads the session type that Content Manager writes to `race.ini`. That is how it tells a Track day from a practice session, and practice from qualifying in a race weekend.
  - Without a readable `race.ini`, it uses the CSP session type, and practice sessions count as a Track day.
- **Offline sessions only.** In an online session (alt-online included) the app stands aside: no command is sent and the status reads *Online session: commands suspended*.
- The engine drives **up to 60 AI cars**. Cars in the pits, off track, or with invalid data are left out.

## Installation

The game loads the app from `assettocorsa/apps/lua/AdvancedIA/`. The folder name matters, because CSP stores the app's settings under that name.

### With Content Manager (recommended)

1. Close Assetto Corsa.
2. Download the package [`dist/AdvancedIA-Beta-1.50.zip`](dist/AdvancedIA-Beta-1.50.zip) (or the latest release on the [Releases page](https://github.com/VincentChevalier44/AdvancedIA/releases)) from this repository.
3. Drag the zip onto the Content Manager window and confirm the installation when Content Manager offers it.

The package already contains the right structure (`apps/lua/AdvancedIA/…`). Without Content Manager, you can also extract it straight into the `assettocorsa` root folder. It holds only what the game loads (entry point, manifest, icon, `src/`, `sounds/`, `tracks/`) plus the user notes. When a `.sha256` file is published next to it, use it to check the download.

### Manual installation

1. Close Assetto Corsa.
2. On this GitHub page, click **Code › Download ZIP**.
3. Extract the archive. It contains a folder named `AdvancedIA-main`.
4. Copy that folder into `assettocorsa/apps/lua/` and **rename it exactly `AdvancedIA`**.
5. Check the final path: `assettocorsa/apps/lua/AdvancedIA/manifest.ini`. With Steam this is usually `C:\Program Files (x86)\Steam\steamapps\common\assettocorsa\apps\lua\AdvancedIA\manifest.ini`.

The repository download also contains the test bench and the technical documents (`tests/`, `docs/`, French notes). The game never loads them, so they can stay.

### First launch

1. **Start an offline session** from Content Manager: Practice, Track day, Race weekend, Race or Hotlap.
2. **Open the pause menu (Esc) or the setup/pits screen.** The AdvancedIA settings window opens there by itself.
   - It closes as soon as you drive again. While you drive, only the **in-game overlay** is shown.
   - The app also has an icon among the setup screen's settings apps. Use it if the window does not appear.
   - The engine keeps running in the garage/setup screen, so a practice session goes on. Only the real pause freezes the commands.
3. **Language.** The interface is in English on a first installation. Click **FR** or **EN** at the top right of the window to switch.
   - The window, the tooltips, the overlay and the on-screen messages change at once, and the choice is saved.
   - The session log always stays in French.
4. **Find your way around.**
   - The window has four tabs: **HOME**, **SETTINGS**, **RACING RULES** and **DIAGNOSTICS**. The profile shown and edited is picked at the right of the tabs, on every tab.
   - The **SETTINGS** tab has a sidebar with four groups: **DRIVING**, **TRAFFIC**, **RACE & SAFETY** and **ADVANCED**. See [Settings overview](#settings-overview).
   - The window has no title bar. Drag an empty area to move it.
5. **What is active on a first installation:**
   - **Practice**, **Qualifying** and **Race** start with their recommended preset plus the **Base rules**, with racing rules on.
   - **Track day** stays fully native: no section is enabled, and the status reads *No section enabled: native AI*. Load **Nordschleife Touristenfahrten** on the **HOME** tab, or tick a section, to bring it to life. Until then, the AI distribution and the CSP AI flood handling are inactive too.
   - **Hotlap** has only the racing rules on: flag overlay, DRS beep, no AI to drive.
6. **The overlay** appears centred at the top of the screen.
   - Move it, resize it or change its look in **SETTINGS › ADVANCED › Overlay**.
   - While the app is active, it hides Assetto Corsa's own flags and its top message banner (CSP options **Hide race flags** and **Hide system messages**). Since Beta 1.47 they stay ticked, also with the game closed, so Content Manager shows them ticked; your values come back when you switch the app or the option off (see [CSP display options](#csp-display-options)). CSP may only apply them at the next game launch; **HOME › TO CHECK** says so.
7. **Track days on long circuits (7 km and more) with many AI.**
   - CSP's *AI flood* spawns the AI around you. The app switches it off for you, but CSP only reads that setting when the game starts.
   - So the first such session is still CSP's, and the full-track distribution applies from the **next launch**. The overlay announces it (**AI flood (CSP)**).
8. **Races.** The Safety Car is on by default in races. Add its model, by default the **Ferrari 458 Italia Stage 3** from the base game (`ferrari_458_s3`), to the grid in Content Manager. Without it, the app falls back to a VSC or an FCY.

## Updating

### Moving from ACAdvancedIA (Beta 1.48 and older)

Since Beta 1.49 the app is called **AdvancedIA**: its folder is `apps/lua/AdvancedIA`, its GitHub repository `VincentChevalier44/AdvancedIA`, its packages `AdvancedIA-Beta-X.zip`. The update button of ACAdvancedIA (Beta 1.48 and older) cannot move the app to the new folder, so **install Beta 1.49 once by hand**:

1. Close Assetto Corsa.
2. Back up, then **delete** the old folder `assettocorsa/apps/lua/ACAdvancedIA`. Both apps must never run together: while the old folder (its `manifest.ini`) is still there, AdvancedIA drives nothing and only shows this instruction, in its window and on screen.
3. Extract `AdvancedIA-Beta-1.50.zip` (or later) into the `assettocorsa` root folder (or drag it onto Content Manager). Check `assettocorsa/apps/lua/AdvancedIA/manifest.ini`.
4. **To keep your settings and custom presets**, before the first launch, rename `Documents/Assetto Corsa/cfg/extension/state/lua/app/ACAdvancedIA.ini` to `AdvancedIA.ini` (same folder). CSP stores each app's settings under its folder name. If you launched AdvancedIA first, close the game and replace `AdvancedIA.ini` with a copy of `ACAdvancedIA.ini`; the app reminds you under **HOME › TO CHECK** on that first launch.
5. Start the game and reopen the window from the app bar: as a new app, its window and overlay positions start from their defaults.

What keeps its old name on purpose: the CSP state file `Documents/Assetto Corsa/cfg/extension/state/ACAdvancedIA-cspgui.ini` (it holds your original **Hide race flags** / **Hide system messages** values, given back when you switch the options off), and the keys of the companion-app bridge (`ACAdvancedIA.Bridge.*`, a frozen format shared with SpotterEnginer). SpotterEnginer needs a version that knows the new folder name. The previous update work folder `state/ACAdvancedIA-update` is no longer used and can be deleted. From Beta 1.49 on, the update button works again, from the new repository.

**From the app (since Beta 1.33, reworked in Beta 1.35).** At launch, about ten seconds into the game, the app makes **one request** to GitHub (`api.github.com`) to read the latest published release; nothing about you or your installation is sent. When a newer version exists:
- **UPDATE · 1.36** appears in the header, right of the tabs, and *Update available* under **HOME › TO CHECK**, with an **Update** button (both greyed while you drive);
- **DIAGNOSTICS › UPDATES** shows the installed and available versions, the first lines of the release notes and **Read everything on GitHub**;
- in the pits, the overlay shows **UPDATE AVAILABLE** once per launch, for 6 seconds. Never on track.

One click on **Update**, stopped (paused, in a menu, or at your pit box at standstill):
1. downloads the release's SHA-256 digest, then its package, from the repository's release downloads only (no other address is followed);
2. checks the digest, the package contents (everything under `apps/lua/AdvancedIA/`, no path outside it, the updater itself included) and the version in its `manifest.ini`;
3. unpacks it into CSP's state folder, `Documents/Assetto Corsa/cfg/extension/state/AdvancedIA-update/next`, never into the app folder, and checks the unpacked copy;
4. then, on the first frame you are stopped (**READY · WHEN STOPPED** until then), copies the installed files that the update changes to `AdvancedIA-update/current` (since Beta 1.37, only the files whose content differs, so the stop is shorter), writes a marker, copies the changed files into the app folder in one go with CSP's live reload paused (`src/` first, `AdvancedIA.lua` next, `manifest.ini` last), keeps the version you had in `AdvancedIA-update/backup`, writes the session log, hands every AI back to AC and restarts the app.

Steps 1 to 3 can be cancelled and never touch the app folder. A failed copy in step 4 puts the installed version back at once (*Cannot write to the app folder: current version kept*; the log names the file). If that fails too, the block says *Recovery impossible*, names the marker file and does nothing more: restart the game, and reinstall manually if it persists. An install cut short by a crash or a power cut is finished at the next launch, before the app loads anything else: from the unpacked package when it is intact, otherwise by putting the starting version back; the app then restarts once. Two attempts at most, never a loop. **Roll back to Beta X** puts the previous version back the same way. **Check now** asks at most once a minute (greyed in between); GitHub's request limit is shown as such. Your settings, profiles and presets are kept: they live in CSP's storage, not in the app folder. Untick **Check for updates at launch** to never contact GitHub. With a CSP version that lacks the web, zip, copy or digest functions, the block says so: update manually as below. The download size is shown, but not its progress (CSP does not report it).

Each file is copied next to its destination under a temporary name, then renamed over it, so a crash never leaves a half-written file. Each kept version carries its file list, and **Roll back** is offered only for a complete one. A freshly installed version that does not start properly twice in a row (the engine and the window or the overlay running without error, since Beta 1.36) is rolled back automatically at the next launch. Your settings are kept after a roll back: a version reads settings written by a newer one, validating each setting it knows.

**Clean-up (since Beta 1.37).** At every launch, once the app has started properly and no install is pending or watched, the state folder is tidied: the unpacked package (`next/`), the working copy (`current/`), any other leftover file (`*.bak`, `*.tmp`, `*.new`) and empty folders are removed. `backup/` (the previous version, for **Roll back**), a pending marker and `failed.txt` are always kept. The log says `mise a jour: nettoyage (n fichiers)` when something was removed. Beta 1.36 left its unpacked package and a `boot.txt.bak` there: CSP's safe file replacement keeps the old content of a replaced file as `<file>.bak`, and the app rewrites `boot.txt` at the launch that counts the start. Both disappear at the first launch of Beta 1.37, and the app now deletes that `.bak` right after each write.

**Online**, the app drives nothing: checking and installing at your pit box only replace files and restart the app.

**Coming from Beta 1.33 or 1.34, install Beta 1.35 by hand** (below), game closed: their update button would unpack into the app folder, which CSP watches, without the protections above. Their `backup/` folder in the app folder is no longer used (you can delete it, game closed), and no roll back to Beta 1.34 is offered until the next update.

**Manually or with Content Manager:**

1. Close Assetto Corsa.
2. Install the new version:
   - **Content Manager:** install the new package over the old one (drag the new zip onto Content Manager).
   - **Manually:** delete `assettocorsa/apps/lua/AdvancedIA` and copy the new folder in its place, with the same name `AdvancedIA`.
3. Start the game. Your settings and custom presets are kept.

If you created your own zone files in `tracks/` (see [Track zones and class patterns](#track-zones-and-class-patterns)), back them up before replacing the folder or installing over it, then copy them back.

**Why nothing is lost:** the app keeps its settings in CSP's own storage (`ac.storage`), not in its folder. CSP writes them to `Documents/Assetto Corsa/cfg/extension/state/lua/app/AdvancedIA.ini`.

**Settings migrate automatically** between versions:
- Each version carries a data revision number. On the first start after an update, the app applies the one-off changes of every revision you skipped.
- Values you set yourself are kept. Values still on an old default follow the new default. For example:
  - Beta 1.24 changed the race start defaults: caution ×1.6 → ×1.3 and aggression ×0.6 → ×0.8.
  - Beta 1.20 widened the track-day spacing.
  - Beta 1.26 hides Assetto Corsa's original messages by default.
- What changed is written to the session log (`profils mis a jour …`) and shown under **HOME › TO CHECK** (*Updated to the current presets: …*).

Rolling back from the app keeps your settings since Beta 1.35. Before going back by hand to a version older than 1.35, back up `AdvancedIA.ini` (game closed): those versions reset settings written by a newer one. Read [CHANGELOG.md](CHANGELOG.md) for what changed and what to check in game.

## Uninstalling and resetting the settings

### Uninstalling

1. **If you used track days with an AI distribution other than Native,** restore CSP's AI flood first.
   - The app disables AI flood in your CSP user settings. Deleting the app does not turn it back on.
   - The simplest way: tick the **General** section, set **AI distribution at session start** to **Native (game)**, run a Track day session with AI, then restart the game. The app writes back the original values it saved before its first change.
   - Or edit the `[AI_FLOOD]` section of `Documents/Assetto Corsa/cfg/extension/new_behaviour.ini` by hand.
2. **If you kept the two CSP display options on** (Overlay section), untick them (or switch the app off with the on/off switch in the header) while the game runs: the app writes your original `gui.ini` values back at once. Closing the game does not give them back (Beta 1.47): after uninstalling, they stay ticked; untick them in Content Manager › **Custom Shaders Patch › GUI** if you want AC's own flags and messages back. Otherwise `Documents/Assetto Corsa/cfg/extension/state/ACAdvancedIA-cspgui.ini` holds them (the original file follows the `original` line).
3. Close Assetto Corsa and delete the folder `assettocorsa/apps/lua/AdvancedIA`. Keep a copy of your own `tracks/*.lua` zone files first if you want them later.
4. Optionally, delete what the app left in your Documents folder:
   - its settings and custom presets: `Documents/Assetto Corsa/cfg/extension/state/lua/app/AdvancedIA.ini`;
   - its session logs: `Documents/Assetto Corsa/logs/AdvancedIA.log` and `AdvancedIA.1.log` to `AdvancedIA.3.log`.

No track, car or `surfaces.ini` file is ever changed, so there is nothing else to undo.

### Stopping the app without uninstalling

- **APP ON** / **APP OFF** (header) switches the whole app on or off. When it is off, the AI are fully native again.
- **PANIC** (header) stops every command at once, until you click **RESUME**.
- Unticking a section's toggle switches that feature off for the profile shown. Its values are kept, and its settings stay visible, dimmed under a warning (since Beta 1.38).

### Resetting the settings

| What | Where | What is kept |
|---|---|---|
| One setting | Right-click the setting | Nothing: back to the profile default |
| One section | **RESET SECTION** at the top of the section | Display preferences, class patterns, values set by the rule set |
| A whole profile | **HOME › RESTORE DEFAULTS: <profile>** | Ticked sections, chosen championship rules, your preferences (panel, messages, HUD flag, DRS and delta beeps, volume) and class patterns |
| Racing rules of Practice, Qualifying and Race | **RACING RULES › RESET TO DEFAULTS** | The highlighted rule set is re-applied (or the closest one if you edited it). Your DRS beep and panel, volume, pit window message and Safety Car model are kept |
| Overlay | **SETTINGS › ADVANCED › Overlay › RESET SECTION**; **PUT BACK ON SCREEN** recentres it at 1.00x | Everything else |
| Global options | **SETTINGS › ADVANCED › Global options › RESET SECTION** | The measured lateral direction, personality seed, language and Safety Car |
| AI personalities | **Regenerate personalities** (Global options) | Draws a new seed |
| **Everything** (factory reset) | Close the game, delete `Documents/Assetto Corsa/cfg/extension/state/lua/app/AdvancedIA.ini`. If the app has switched CSP's AI flood off, restore it first (see [Uninstalling](#uninstalling)): the backup of your original AI flood values is kept in this file. Untick the two CSP display options first too (Overlay section): the app then gives back your `gui.ini` values | Nothing: the next start behaves like a first installation, and custom presets are deleted too |

## Features

### The settings window (Racing 26 interface)

Since Beta 1.35 the window uses the **Racing 26** design shared with SetupLab: a near-black background, anthracite panels with a cut corner, cyan for actions, and the racing colours of the flags.

- **Fonts bundled with the app** (`fonts/`, SIL Open Font License): Barlow for text, Barlow Condensed for labels, titles, buttons and tabs, JetBrains Mono for numbers. Without the font files the window falls back to Segoe UI and Consolas, and the session log says so once.
- **Header** (84 px, on every tab):
  - the brand, the version chip and, when a newer version is published, the one-click **UPDATE** button;
  - the track and the profile in use, how many AI cars the app drives and the engine state;
  - a state chip (**ACTIVE · RACE**, **PAUSED · RACE**, **SUSPENDED** in a replay or after the session, **APP OFF**, **PANIC**, **ONLINE**, **WAITING**, **NATIVE AI**), **FR | EN**, the **APP** switch and **PANIC / RESUME**;
  - slanted tabs (the racing-rules tab shows the rule set in use) and the profile selector, with a green dot on the profile in use; in a narrow window the profiles show as their first letter, never hidden.
- **HOME**: the session panel (profile in use, detection source, automatic profile switch), the built-in presets as tiles, live figures (AI driven, incidents, yellow zones, neutralisation, light panels), the **TO CHECK** list with a link to the section concerned, and the custom presets with their byte counter (64 bytes at most). A banner explains a disabled app, a panic, an online session or the wait for the first session, with a one-click action.
- **SETTINGS**: the sidebar lists the 15 sections in four groups, each with its switch and the number of settings changed from the profile defaults. A section shows its settings in **sub-groups** on two columns (one when the window is narrow). Sliders show the profile default as a grey mark; changed settings get a cyan diamond; a right click restores the default. Choices with up to three values are segments (a ‹ value › button when their labels do not fit), longer ones a ‹ value › button. An unticked section, **Global options** included, shows why its settings do not apply instead of the settings.
- **RACING RULES**: the three views (racing rules, mandatory stop, Safety Car) with their switches, then the championship rule sets with their main features and the reset. On a track-day or hotlap profile the mandatory-stop and Safety Car switches are greyed out and their views cannot be opened.
- **DIAGNOSTICS**: updates, sign calibration, headlight flashes (learnt field, with the last event id and count in its tooltip) and zones, the session log, CSP capabilities (two columns), the AI functions CSP exposes (names only), the AI table, performance tiles and the circular log with its level filter.
- **Window size**: 900 × 700 by default. Wider windows widen the columns while the text keeps its size; narrower ones scale the whole window down. Columns, lists, the sidebar and the logs scroll with the wheel.
- **CSP rendering**: flat colours only, no gradients, filters, letter spacing or animations; every state (rest, hover, pressed, disabled, selected) has its own colour. Tooltips stay the native ones, in the kit colours.

All numbers below are the shipped defaults unless stated otherwise. Every value can be changed in the settings. The complete list, with ranges and per-profile defaults, is in the [Settings reference](#settings-reference).

### Session profiles and automatic detection

The app has five independent profiles: **Track day**, **Practice**, **Qualifying**, **Race** and **Hotlap**. Each one keeps its own values and its own set of enabled sections.

With **Automatic profile** on (recommended), the profile follows the session declared in `race.ini`, for every Content Manager mode. It is chosen again at each new session of a weekend.

| Content Manager mode | Sessions | Profile used |
|---|---|---|
| Track day | "Track Day" session (declared as practice, or as qualifying by some Content Manager versions) | Track day |
| Practice | practice | Practice |
| Race weekend | practice → qualifying → race | Practice → Qualifying → Race |
| Race (quick race) | race | Race |
| Hotlap, time attack, drift, drag | no AI | Hotlap |

- Without a readable `race.ini`, the CSP session type is used, and practice sessions count as a Track day.
- **HOME › SESSION** shows the detected session, its source (race.ini or CSP) and the automatic profile, for example *Session detected: track day (race.ini) → automatic profile Track day*.
- **Clicking a profile button** (**TRACK DAY**, **PRACTICE**, **QUALI**, **RACE**, **HOTLAP**):
  - With **Automatic profile** on, the click only *shows* that profile so you can view or edit it. The detection still picks the profile used in game, and the window tells you which one is in use.
  - With **Automatic profile** off, the click chooses the profile used, until you tick **Automatic profile** again.
- **Track day**: Touristenfahrten-style traffic, standard yielding to the right, AI spacing. Never any penalties or championship rules.
- **Practice**: standalone or race-weekend practice. The AI yield to faster cars and drive at practice pace.
- **Qualifying**: slow AI move clearly out of the way of a flying lap.
- **Race**: no standard yielding. Blue flags, overtaking and defending, standing start, racing rules.
- **Hotlap**: sessions without AI (hotlap, time attack, drift, drag). By default only the racing rules are on, with the base rules: flag overlay and messages, DRS beep and badge. Penalties and championship rules do not apply. Track day settings are not affected by these sessions.

### Sections, built-in presets and first-install behaviour

**Sections are opt-in.**
- Each profile has 13 sections in the **SETTINGS** tab, plus the racing rules in their own tab. Each one has its own on/off toggle.
- Switching a section off keeps its values, but they stop applying. The tooltip of each toggle says what happens when it is off. For example, with **General** off the AI keep their native level, aggression and caution, with no differences between drivers.
- With no section enabled, the app sends no command at all (*No section enabled: native AI*).
- **Global options** off means conservative defaults for that profile: **Automatic** level mode, no grip bonus, front radar on, native awareness kept, default occupancy margins, default personality seed. To change any global option (for example to switch the front radar off), tick **Global options** for that profile first.

Built-in presets (**HOME › BUILT-IN PRESETS**).
- One click sets the profile concerned, and **ticks every section that acts in that session**: General, Headlights (AI-to-AI flashes included), Overtaking, Lines, Personality, Accidents, Racing rules, Classes / Endurance (multi-class on) and Weather. Multi-class only splits the grid when the pace gaps are large enough, so a one-class grid stays one class.
- On top of that, each preset ticks the sections of its own session:

| Preset | Applied to | Extra sections | Own values |
|---|---|---|---|
| **Nordschleife Touristenfahrten** | Track day | Yielding, Spacing | none |
| **Free practice** | Practice | Yielding | level 97%, aggression 40%, level spread 6%, lapses in focus on, chained overtakes |
| **Flying-lap qualifying** | Qualifying | Yielding | none |
| **Realistic race** | Race | Blue flags, Start | overtaking side **Automatic** |
| **Multi-class endurance** | Race (or Track day if that is the profile shown) | the Race or Track day base | Endurance layer, multi-class, lapses in focus. Applied to the Race profile, it also sets the **Endurance** rules for Practice, Qualifying and Race |

- Left unticked because they would do nothing: **Start** outside the race, **Spacing** outside the Track day, standard **Yielding** in the race, and **Global options**. In the race, the yielding offset, hold and confirmation values still serve blue flags, faster classes and overtakes, at their defaults.
- The **Blue flags** section is only ticked in the race. In practice and qualifying, being a lap down rarely means a real deficit.
- A preset keeps your preferences (flag panel, messages, HUD flag, DRS and delta beeps, beep volume) and your class patterns. They are also ignored when the app decides whether a preset still matches.
- Since Beta 1.29 a preset sets everything else in its profile, **championship rules included** (mandatory stop, Safety Car, rule set). A Practice, Qualifying or Race preset, built-in or custom, sets those rules for the whole weekend (Practice, Qualifying and Race), without ticking or unticking their Racing rules tab: loading **Realistic race** after adding a mandatory stop by hand removes it. A Track day preset leaves the race weekend as it is.
- Since Beta 1.29 a built-in preset button lights up only for the profile shown, after it was loaded for that profile (by you, or by the session preset below), and while the profile still matches it; since Beta 1.51 the championship rules (rule set, mandatory stop, Safety Car) are left out of that comparison. **RESTORE DEFAULTS: <profile>** switches the highlight off. Since Beta 1.38 a preset aimed at another profile than the one shown (Realistic race from Practice, Multi-class endurance from Qualifying) is applied to that profile without switching the profile shown: HOME says *Applied to the Race profile*, and its button lights up when you show that profile. **HOME** then reads *Preset recognised for this profile: …*, or *Last preset loaded: … — modified, or another profile selected*.
- The Nordschleife preset is not limited to the Nordschleife: use it at Le Mans or anywhere else.

**First installation** (no saved settings):
- **Practice**, **Qualifying** and **Race** start as if you had clicked **Base rules**: their recommended preset, then the base rules, with racing rules on.
- **Track day** stays without any command, probe or calibration until one of its sections is ticked. **Hotlap** has only its racing rules on.

**Built-in preset for the session detected** (Beta 1.51, **HOME › BUILT-IN PRESETS**, switch on by default).
- With the automatic profile, as soon as a new session is detected (track and session index), its built-in preset is applied and lit: Track day → **Nordschleife Touristenfahrten** (the Nordschleife included; the journal notes the track), Practice → **Free practice**, Qualifying → **Flying-lap qualifying**, Race → **Realistic race**. Hotlap gets none.
- Another built-in preset you chose for that profile (**Multi-class endurance** for the Race or the Track day) is kept and applied again; a custom preset you loaded into that profile is never replaced.
- Your championship rules (rule set, mandatory stop, Safety Car), preferences and class patterns are kept. Your own changes during the session stay until the next session; reloading the app in the same game launch does not apply the preset again. Journal: `preset_session: <name> (profil <P>)`.
- This reverses the Beta 1.29 rule. With the switch off, or with a manual profile, the old rule applies: once any preset has been loaded at least once, a profile you have **never set up** receives its recommended preset once, when it becomes active, and nothing lights up; a profile you have already set up is never touched.

### General driving: level, aggression, caution and spreads

Section **General** (sidebar **DRIVING**).

- **Level (%)**: the driving level imposed on the AI. 100% matches level 100 in Content Manager. Defaults: 95% on a Track day, 100% in Practice, Qualifying and Race.
  - Above 100%, the result depends on **Requested level mode** in the Global options.
  - The app writes a trial value of 1.05 and reads it back a moment later. Only if CSP keeps it above 1 is the native level used beyond 100%; the original value is restored after the check.
  - Otherwise, the **grip bonus** is used if you allowed it: `1.2 × (1 + 0.004 × points above 100)`, so 1.248 at 110%. Switching it off restores the base exactly.
  - Otherwise the level is capped at 100%.
- **Aggression (%)**: later braking and more determined attacks, with more contact. 100% equals 95% of the maximum native aggression, never more. Defaults: 55% / 45% / 80% (Track day / Practice and Qualifying / Race).
- **Caution**: the safety and braking margin behind another car (1 = native). The app then adjusts it to the situation: following, yielding, rain, start, incident. Defaults: 1.6 / 2.2 / 1.2.
- **Emulated braking zone (%)**: CSP exposes no AI braking distance, so the app emulates one through caution when an AI brakes or closes in on a car. 100% = native.
- **Level spread**, **Aggression spread**, **Caution spread (%)**: each AI gets a fixed, random offset around the base values. The result is a field of faster and slower, calmer and more aggressive, more and less careful drivers.
- The same section holds the session-start settings: **AI distribution at session start**, **Spread from (AI)**, **AI left in the pits at the start (%)**, **Start gap variation (%)**, **CSP AI flood range** and **Staggered pit exits**. See [AI distribution at session start and CSP AI flood](#ai-distribution-at-session-start-and-csp-ai-flood).

### Personality, focus and driving mistakes

Section **Personality** (sidebar **DRIVING**).

- **Deterministic personalities.** Each driver's reaction time, courtesy, patience, braking and level offsets come from the **Personality seed** (Global options). The same seed gives the same drivers again; **Regenerate personalities** draws new ones.
- **Reaction and awareness.**
  - Each driver gets a reaction delay (0.25–0.9 s on a Track day, 0.2–0.6 s elsewhere) between deciding to yield and starting to move.
  - Each also gets an awareness delay (0.6–2 s / 0.4–1.2 s) before noticing a faster car behind.
- **Pace map.** Every car learns its own usual pace at each point of the track, on a 400-cell map, lap after lap. The app uses it to judge whether a car is held up, and to build the delta reference.
- **Slow pace drift** (2% / 1%): the pace drifts slowly, over cycles of 1.5 to 4 minutes.
- **Line variation**: each driver's line varies slowly when no car is within 40 m, so the AI do not all drive exactly the same line. The anti-weaving limit never counts it.
- **Brief lapses in focus** (on by default for the Track day): now and then a driver loses a few per cent of pace for one to three seconds.
  - Interval 60–300 s on a Track day (120–600 s elsewhere); loss 6–12% (3–7%).
  - Never side by side, while defending or at the start of a yield.
- **Pace-based line** (Track day): the slowest drivers naturally run slightly over on the yield side, while the fastest keep the racing line.
- **AI driving mistakes (lock-ups, wheelspin)**, on in every session:
  - Wheel lock-ups under braking and wheelspin out of corners, triggered through CSP's native functions. They may end in an off, a spin or a crash, and therefore in a yellow flag, a neutralisation or a Safety Car.
  - Rate: 1 per hour per AI on a Track day, 0.5 elsewhere (a 20-AI grid makes about ten mistakes an hour, not all of them ending in a crash).
  - More frequent for a weaker driver, a tired one (Endurance layer), one in a lapse of focus, or in the rain.
  - Never under flags or within three minutes after a neutralisation, in the first minute of a race, on pit exit, side by side or within 40 m of you. Never more than once every three minutes for the same AI.
  - Each mistake is written to the log (`erreur de pilotage: …`).

### Yielding

Section **Yielding** (sidebar **TRAFFIC**). It applies on a Track day, in Practice and in Qualifying, but not in the Race (where only blue flags, a faster class or an accepted headlight flash make a car yield).

- **Standard yielding**: a slower AI moves aside for a clearly faster car behind, player or AI. **Yield side** is **Right** by default (**Left**, **Right** or **Automatic**). Automatic picks a free side from the position of the car behind, then keeps it for the whole manoeuvre.
- **Left and right are the driver's**, whatever sign the calibration measures (see [Lateral movement](#lateral-movement-lane-holding-and-anti-weaving)).
- **When to yield.**
  - The AI watches at least **Rear detection (m)** behind it (100 m on a Track day, 200 m in Practice and Qualifying). The real range grows with the speed difference, up to 400 m, and by 30% on a wet track.
  - It yields if the car behind is at least **Follower speed advantage (km/h)** faster (6 / 4) and will catch it within **Rear horizon (s)** (10 / 12).
  - The situation must hold for **Confirmation (s)** first.
- **How it yields.**
  - **Yield offset**: 0.65 of the half-width on a Track day, 0.8 in Practice and Qualifying. Reduced to as little as 40% in corners and restored on the exit, always within the real track width.
  - Slowdown while yielding: 6% / 8%.
  - The AI holds the position for at least 1 s, and stays aside after the pass (0.8–2.2 s on a Track day, 0.6–1.6 s in Practice and Qualifying) so the passing car can move back across.
  - With several cars in a train under a blue flag or ahead of a faster class, 1 s is added to let the whole train through.
- **Inviting a pass.** If the car behind stays within 25 m for more than 12 s while the AI yields, the AI slows down a further 10% to invite it past.
- **Letting an AI by yourself** (Beta 1.44). Move at least 2 m aside in front of an AI (within 40 m): it passes on the side you freed, with no speed advantage needed. In the race this works on straights only; in practice, qualifying and track day also in gentle corners (up to about 0.4 g), the part of the gap due to the bend itself being taken off. Outside the race, simply slowing down clearly below the AI's own pace there is enough too: it passes you even at a crawl, is never written off after a failed attempt, and the courtesy rule (no counter-attack right after you passed it) no longer holds it back.
- **Timeout.** After **Maximum yield duration (s)** (25 s), the AI returns to its line and ignores that car for 10 s.
- **Reaction to pressure.** A car sitting within 15 m behind at a similar speed (8 km/h difference at most) is let through after **Pressure duration (s)** (4 s on a Track day, 3 s in Practice and Qualifying).
- **Queues on a track day** (Beta 1.21):
  - An AI right behind the car ahead (less than 60 m) no longer yields to a car only slightly faster, nor to pressure, nor to an AI's headlight flash. Doing so would slow the whole queue without letting anyone through.
  - It yields as soon as the track ahead is clear, or to a car at least 15 km/h faster.
  - Your own headlight flash is always honoured.
- **Flying laps in Practice and Qualifying** (Beta 1.51, **Practice and qualifying: flying laps first**, on by default in Practice and Qualifying, never in the Race or on a Track day). As in F1, every car (you included) is either on a flying lap or not: out-lap from the pit exit to the line (one more lap if the line comes less than 30 s after the pit exit), cool-down or aborted lap (below 75% of the fleet's pace there, corrected by the car's own long pace, for 4 s; until the line), in-lap, damaged car.
  - An AI that is not on a flying lap moves aside for the closest flying car behind it within 3 s that is closing in (or within 30 m), like under a blue flag: even with a car ahead of it, a slower car closer behind does not hide the flying one, and the flying AI takes the gap at once.
  - It never attacks a flying car ahead of it (unless invited or that car is abnormally slow), and an AI on a flying lap does not do standard yielding for a car that is not.
  - An AI leaving the pits waits at the end of the pit lane while a flying car reaches the merge (see [Pit exit](#pit-exit)).
  - You too: on your out-lap or a cool-down lap, the message **Flying lap — <driver> is coming on a flying lap: let them by** warns you when a flying AI is within 3 s behind you (once per AI every 30 s).
  - Journal: `cede a <name> en tour lance`, `tour lance: <name> arrive derriere le joueur`, and in the minute summary `tours lances : cessions N (abouties, perdues), attaques retenues, retenues a la jonction, avis au joueur`.
- **Letting an AI past you** (every session, race included):
  - Move at least 2 m off its line on a straight, without overtaking yourself.
  - The AI following within 40 m pulls out on the side you free, even at equal speed, and does not hand the place straight back.

### Blue flags

Section **Blue flags** (sidebar **TRAFFIC**). It is ticked by the **Realistic race** preset. It is never active on a Track day.

- An AI about to be lapped moves aside to let the lapping car (player or AI) through, with a limited loss of pace (a fixed 8% reduction).
- **Blue flag range (m)**: 150 m in the race. It is multiplied by 1.5 for a backmarker two or more laps down, and for a faster class.
- **Side under blue flag**: **Automatic** (from the position of the lapping car, then the free side), **Left** or **Right**.
- **Equal speed** (Beta 1.24): when you sit within 40 m behind an AI you are lapping, the blue flag stays waved even if you are not faster. The AI keeps its line through the corners and moves over at the exit.
- The log notes each blue flag: `drapeau bleu: X laisse passer le joueur…` (*lets the player by*). If it has not let you by after 3 s, the log gives the reason, gap and speed.
- Under yellow, a neutralisation or a red flag, yielding is forbidden.
- A blue flag only concerns cars a lap down. A slower car on the same lap is simply overtaken.

### Headlight flashes and horn

Section **Headlights** (sidebar **TRAFFIC**).

- **No fighting with you outside the race** (Track day, Practice, Qualifying; since Beta 1.29). When you pass an AI, it does not try to pass you back for 20 s, unless you slow down sharply (25 km/h slower). While you are right behind it, alongside, or just ahead after passing it (within 30 m), it eases its aggressiveness. In the race, the AI fights as usual and may defend.
- **Your headlight flashes.**
  - Teach the app your car's flash signal once: **DIAGNOSTICS › Learn headlight flashes (6 s)**, then give several short flashes.
  - Unlearned, ordinary yielding still works. **Horn counts as a flash** (off by default) is the alternative.
- **Headlight flashes** mode: **Never**, **Lapped cars** or **Always**.
  - The default is **Always** on a Track day and in Practice and Qualifying, **Lapped cars** in the Race.
  - Outside the race, an accepted flash makes the AI yield.
  - In the race, **Lapped cars** only targets AI you are lapping, while **Always** counts as a request to pass for every car.
- **Acceptance.**
  - Beyond 60 m you must be at least **Speed advantage for a flash (km/h)** faster (12 / 8 / 15), and able to reach the AI before its yield would end (**Maximum yield duration (s)** minus 5 s). Otherwise it would move over for nothing, give up and then ignore you.
  - Within 60 m, **Close-range advantage (km/h)** is enough (−5 / −5 / 6). Outside the race, stuck right behind at the same speed, your flash is understood: it means “let me by”.
  - Up to Beta 1.28: 30 m and 5 / 4 / 6 km/h, without the catch-up condition. Since Beta 1.29 the advantage is judged for as long as the request lives, so a flash refused from further back is understood as soon as you close in.
  - **Flash range (m)** is 200 m on a Track day, in Practice and in Qualifying, and 150 m in the Race (120 / 150 / 100 m up to Beta 1.28). Values still at the old defaults follow the new ones, in your profiles and custom presets.
  - A request stays valid for **Request lifetime (s)** (8 s).
  - An AI may miss the first flash (**First flash missed (%)**, 10% / 5% / 10%). A second flash within 4 s is always seen and makes the request urgent.
  - Up to three AI ahead of you react to the same flash, nearest first, 0.5 s apart, to clear a short train.
- **AI-to-AI headlight flashes** (on by default):
  - An AI held up behind a slower car gives it a visible double flash, and that car yields as it would to your flash.
  - In the race, only to lap a car or for a faster class (an LMP1 behind an LMP3, for example). Never between cars fighting for position.
  - Flashes are debounced and rate-limited, and a request reaches at most three cars.

### Overtaking, defending and slipstream

Section **Overtaking** (sidebar **TRAFFIC**).

- **Overtaking** (app-driven).
  - The AI prepares, pulls out, runs side by side, then moves back across with a margin: two car lengths plus **Clearance after overtaking (m)** (18 / 20 / 10). An occupied side is always respected.
  - With the section off, the AI only overtake their native way.
- **Overtaking side.**
  - **Opposite to yield side** (consistent on a track day), **Automatic**, **Left** or **Right**. The free side always has priority.
  - **Automatic** works out the side, in the race, from the position of the car ahead and the next corner; elsewhere it is the side opposite to yielding. **Realistic race** sets **Automatic**.
  - The Track day, Practice and Qualifying defaults are **Left**, matching yielding to the right.
- **When to overtake.**
  - A slower car within **Forward detection (m)** (60 / 50 / 50 m) that the AI will catch within 6 s, with at least **Speed advantage to overtake (km/h)** (8 / 10 / 3). The advantage is adjusted to the driver's confidence, and halved against a slower class.
  - **Held up**: below 93–95% of its own usual pace at that point for **Held-up confirmation (s)**, the AI tries even without a large speed difference.
  - In the race, the AI pulls out at **Pull-out distance (m)** plus **Pull-out gain (s)** × speed, at most 22 m (at 180 km/h: 8 + 12.5 m).
- **Completing and aborting.**
  - **Chain overtakes** passes a second slower car in the same move if the lane stays clear.
  - **Pause after overtaking (s)** lets the AI settle before the next attempt.
  - An overtake is aborted when the side closes, the target is faster, a fast car arrives behind, the AI stops closing in, or a yellow flag comes out.
  - Since Beta 1.26, a target lost from sight for a moment (wheels off the track) no longer cancels the move (1 s tolerance).
- **Slipstream**: on a fast straight (over 150 km/h) behind a car, the AI lowers its caution after 1 s to use the tow.
- **Defending** (race only).
  - Against a close attacker (within **Defending distance (m)**, 12 m), an AI may cover its line once per attacker and per lap. The probability is tied to its confidence.
  - The move is a single one of at most **Maximum defending offset** (0.35 of the half-width), at least 8 s apart (**Pause between defences (s)**).
  - Never against a car lapping it or from a faster class, never weaving and never under braking.
  - A defence ends as soon as the cars overlap, and an AI never moves towards a car alongside it.

**Breaking the tow, dirty air and the last laps (Beta 1.42)** (sidebar **Overtaking**, subgroups *Slipstream and dirty air* and *End of race*):
- **Breaking the tow** (race): on a long straight (relearnt each session from the AI's own laps, braking zones excluded; nothing on the race's first lap), a leader followed in its slipstream by a direct rival (same lap, same class) makes one move away from the follower, never towards the overtaking side forced by **Overtaking side**, and no move at all if the follower is already clearly on that side. It returns to its line before the braking zone, and ends the move as soon as the follower pulls out. Never when the follower is more than 12 km/h faster, already overtaking or is you; never under a flag, under braking, with a car alongside, near the pit exit (100 m before to 500 m after it), in front of a car that laps it or of another class, and never without room in the anti-weaving budget. Breaking the tow and a defence never both happen on the same straight.
- **Dirty air**: in a corner, within the set distance behind another car and in its wake, the AI lifts the throttle slightly (at most the set percentage) and its usual line variation becomes faster micro-corrections, never towards an occupied side and never counted as a change of side. Off in track day by default.
- **Last-laps urgency** (race): in each car's own last laps (held until it finishes; a timed race includes the lap after the time ends), with a direct rival close ahead or behind, aggression rises step by step (still capped, never above the base under braking or in corners) and the defence triggers from further away. No extra aggression with a lapped car, another class or you just ahead, no defence boost against you, never under a flag.

### Lateral movement, lane holding and anti-weaving

Section **Lines** (sidebar **DRIVING**).

- **How lateral moves are made.**
  - Every lateral move (yield, overtake, defence, avoidance) follows **Lateral movement speed**, **Lateral acceleration** and **Lateral smoothing (s)**, within **Maximum offset** (0.85 / 0.85 / 0.8 of the half-width) and the real track width.
  - Manoeuvres only start where the track is straight enough (**Straight threshold**, with **Yaw rate reference (rad/s)**).
- **Side occupancy always comes first.** If a car occupies the side an AI was moving towards, the AI returns to its line at **Release factor** times the normal speed (2×). Returns to the centre are checked for occupancy too.
- **Anti-zigzag cap**: a manoeuvre changes side (left, line, right) at most 6 times a minute, then the AI drives straight for 20 s. Since Beta 1.29 the side counted is the one the manoeuvre aims for, not the target narrowed by the track width in a corner (up to Beta 1.28, about nine triggers out of ten came from that narrowing and cut yields and overtakes).
- **Caution kept in braking zones and corners** (since Beta 1.31): slipstream, overtaking and following lower an AI's caution on the straights. As soon as the AI brakes itself, or in a corner, its caution is never below its usual level and its aggressiveness never above it; caution comes back within a fraction of a second instead of being carried into the braking zone.
- **Braking added by the app** (front radar) is not the driver's braking: since Beta 1.30 it no longer stops an AI from pulling out to overtake. The AI's own braking still does.
- **No change of direction under braking** (common racing rule): no lateral manoeuvre starts or continues with the brake pedal beyond 20%, except avoidance and recovery.
- **Anti-weaving.**
  - An AI may change its targeted side (left, line, right) at most six times a minute to manoeuvre. Beyond that, it goes 20 s without manoeuvres, and a single warning is logged.
  - Avoidance of a stopped car, recovery after contact and emergency release are never limited.
  - Following an offset that shrinks in a corner on the same side does not count, and neither does the slow line variation.
- **Left/right reference.**
  - The app follows the CSP SDK convention (offset +1 = right) whatever the sign measured in game.
  - In Assetto Corsa, **DIAGNOSTICS** normally reads *Offset / side sign: -1 / -1*. That is expected.
  - The calibration waits for two isolated AI lined up on a straight with enough width. It makes a native +0.5 offset for three seconds, then returns to zero once the side is free.
  - No behavioural offset is sent until the sign is confirmed. If the measurement fails, it is retried every 60 s, or rerun with **Rerun sign calibration**.
  - Beta 1.25 restored the -1 / -1 sign on installations where it had been lost (*sens lateral retabli* in the log).
- **Track zones**: no-manoeuvre zones can be defined per track. See [Track zones and class patterns](#track-zones-and-class-patterns).

### Race start

Section **Start** (sidebar **DRIVING**). Race only; ticked by **Realistic race**.

- **Start delay (s)** (2 s since Beta 1.49, 1 s before): for this time after the start, the app commands no lateral move, yielding, overtaking or avoidance. The AI follow their native line.
- **Full throttle to the first corner** (Beta 1.25):
  - On the straight there is no start caution and no following caution, so the AI stay close to the car ahead.
  - **Caution at the start** (×1.3) and **Aggression at the start** (×0.8) apply only under braking and in corners, so at the first corner. They relax gradually over **Settling time after the start (s)** (25 s).
  - No overtaking or yielding is commanded during that settling time.
- **Careful first lap (start and restarts)** (Beta 1.47, on in the race profile): at the start and at every restart,
  each AI drives its first lap carefully. Gaps are counted in time (same behaviour for F1, GT and road cars); every
  braking zone of the lap is anticipated (braking points learnt from the leading cars, braking of the car ahead); the
  radar lifts off before it brakes (a full brake only for a contact less than 0.4 s away); no defence, tow-breaking or
  dirty air; overtakes only on a real straight with a real advantage; avoidance only of a stopped or very slow car;
  aggression and overall caution capped. It ends at the AI's first crossing of the line, when the pack has spread
  around it, or after 3 minutes, then it is released over 3 s.
  - **On a straight** (Beta 1.50: driver not braking, car straight, outside the anticipation window of a braking point,
    closing slower than 60 km/h): the AI keeps its foot down in the slipstream. No time-gap caution and no radar caution
    there; the radar lifts only when contact is less than 0.6 s away and no lane is free alongside, by a graded amount,
    and never when the car behind is closer to hitting it than it is to hitting the car ahead. AC's own following brake
    does not make a straight a corner approach; only a free brake marks the pack's first braking point. Each radar lift
    or brake of the start says why in the log.
- **Hold the grid lane at the start** (off by default):
  - Each AI records its position on the grid. After the green light, while a car runs alongside it (and while braking), it keeps that lane instead of cutting across its neighbours towards the racing line.
  - It then joins the line gradually, never towards an occupied side.
- **The front radar** stays very gentle at the start: it only brakes when contact is imminent (less than 0.8 s away).
- **Log lines.** The log measures each start: `depart: peloton a … km/h en moyenne apres … s, … freinage(s) du radar au lancement` (*field speed after the start delay, number of radar brake applications*). It also writes a start report with the lane hold, multipliers, blue flags, radar and each AI's tyres.

### Pit exit

- For 15 s after leaving the pit lane, an AI with a car ahead within 80 m (you included) may only close in slowly: 7.5 to 15 km/h of closing speed depending on its confidence, reducing with distance and negative under 12 m. It also brakes earlier.
- It makes no manoeuvre for the first few seconds, and its lateral offsets stay limited near the pit lane.
- Inside the pit lane itself, no line, speed or level command is sent: the native pit limiter applies.
- Since Beta 1.41, the app learns where the pit lane joins the track. Cars moving near the end of the pit lane are seen by the AI on track (forward radar, avoidance); a car stopped in the pit lane, you included, is not.
- **Track day (since Beta 1.41), Practice and Qualifying (since Beta 1.51):** an AI driving out, past its own pit box, waits at the end of the pit lane (10 s at most) while a car on track will reach the merge within about 5 s. In Practice and Qualifying only a car on a flying lap is waited for (see Yielding, *Flying laps*). It uses the same native stop as the hold in the pit box. The first exit of each session teaches the merge point and is not covered.

### Accidents, yellow flags and recovery

Section **Accidents** (sidebar **RACE & SAFETY**).

**Incident detection** (player included):
- A car counts as stopped below 10 km/h for more than 2 s. A spin is confirmed over 0.6 s, and wrong-way driving after 2 s.
- An incident ends after 2 s of normal driving, so a slide that settles stays a single incident. A car off track for more than two minutes counts as cleared.
- A stationary grid is never an incident, but a clash at the first corner is.
- A car moving off at the start of a session or leaving the pits only becomes a stopped incident once it has driven. In a queue behind a slow car, only the head of the queue counts.

**Avoidance** (**Avoid stopped or crashed cars**):
- An AI approaching a stopped, very slow, spinning or crashed car slows down and goes round it on the free side. With no clear lane, it slows hard behind it.
- A slow car (below **Obstacle speed (km/h)**, 25 km/h, for 2 s) is only avoided if the AI arrives at least 15 km/h faster, or if it is an incident. In a traffic jam the AI simply follows.
- Defaults: detection 150 m, level −25%, caution ×1.5, avoidance offset 0.6. A car sideways on the track is avoided even outside the "same direction" neighbourhood. Avoidance is never subject to the anti-weaving limit.

**After a crash:**
- **Recovery after contact**: after a hit (a sharp loss of speed close to a car), the AI drives more calmly for 4 s. If it is almost stopped, it waits before moving off.
- **Crashed AI stop** (off track only; on the track itself the AI moves off at once):
  - After a heavy deceleration with contact, an off or a spin, the AI stays still for 3 to 8 s, like a driver collecting their thoughts.
  - It then waits until no car at speed is within 120 m behind (at most 10 s more).

**Yellow flags** (**Yellow flags (incident zone)**):
- **Zone.** It runs from 300 m before to 50 m after the incident and is held 10 s after it clears. Overtaking is forbidden from 150 m before the zone, for the AI and for you.
- **Double waved yellow** (incident on the track):
  - A zone delta applies: the reference time is 15% slower than the usual pace, which is the F1 reference for a double yellow. With the Endurance rules it becomes a **Slow Zone** at a fixed 80 km/h.
  - The delta is reset at the zone entry, including when an overlapping single-yellow zone leads into it.
- Single yellow (incident off the track): slightly reduced pace, with no delta.
- **What the AI do in a zone.**
  - They follow the same reference as you, with a small margin of their own (2–6%). They brake on the approach at a bounded deceleration (**Approach deceleration (m/s²)**, 5 m/s²) and queue behind the car ahead.
  - No overtaking, no yielding, no blue flag and no defending. A manoeuvre in progress completes, unless the cars are side by side.
  - Where no pace is known yet (first lap), a fallback speed applies (50 km/h).
- **For you.**
  - The overlay and the on-screen messages warn you. Assetto Corsa's small native yellow flag on the HUD is optional (**AC native yellow flag on the HUD**, off by default), and it never covers a blue, white, black or chequered flag.
  - On an equipped track, the trackside light panels turn yellow too (see [Track light panels](#track-light-panels)).
  - **Your car is never speed-limited**: the delta time judges your pace.

**Recovering stopped cars** (Beta 1.24, consistent with the racing rules):
- **Alone on the track under a local yellow** (no rule can follow from it): the AI is returned to its pit box after 8 s, or after 3 s if it is broken (suspension, engine or gearbox out of use).
- **While race control decides**, it stays put: 20 s, or the major-incident delay plus 5 s. That covers three cases:
  - a neutralisation is chosen for the major incident (VSC, FCY, Safety Car);
  - several cars are involved on the track (red flag or Safety Car escalation possible);
  - a neutralisation is already in progress.
- **Off track** (gravel, wall): returned after 30 s (20 s under a neutralisation), never while it is waiting to rejoin. Since Beta 1.29 these 30 s count the time without moving more than 15 m, so a car spinning its wheels and rocking on the spot in a gravel trap is recovered too.
- An AI still rolling and making progress, even at walking pace, is never recovered: it rejoins or drives to the pits.
- A recovery is not counted as a pit stop, except under a red flag where every car goes in. AC resets the car on its return to the pits, which also clears its damage.

### Delta time, penalties and AI sanctions

**Delta time** (used under VSC, FCY, Safety Car until you reach the queue, red flag until the pit lane, and double waved yellow):
- The delta compares your time with a reference: your usual pace at each point (the faster of your own and your class's), slower by a percentage that depends on the situation. The defaults are:

| Situation | Reference slower by | Fallback where no pace is known |
|---|---|---|
| Double waved yellow | +15% | 50 km/h |
| VSC | +30% | — |
| FCY (base rules) | +50% | 80 km/h |
| FCY (GT and Endurance rules) | +150% (≈ 80 km/h) | 80 km/h |
| Red flag | +60% | 80 km/h |

- It starts at +1 s when the flag is triggered and never exceeds +3 s, so there is no credit for flooring it afterwards.
- It always allows braking at the approach deceleration from your speed at the signal, after a 2.5 s reaction: braking normally from 250 km/h is never penalised.
- It is judged at each mini-sector (about every 250 m) and at the exit of a double yellow zone. Going a bit faster, then slower, evens out, as with the F1 delta. It is not an 80 km/h limiter.
- The overlay shows it large: green when positive, flashing red when negative. **Delta: beeps** adds F1-style beeps.

**Player penalties** (**Player penalties under flags**; Practice, Qualifying and Race, never on a Track day or in Hotlap):
- **Negative delta**: crossing a mini-sector, or the exit of a double yellow, with a delta below −0.50 s (**Delta: mini-sector tolerance (s)**).
- **Overtaking under flags**: in a yellow zone or the 150 m before it, under a neutralisation or under a red flag.
  - Not counted: passing a car that has crashed or only just moved off again, is stopped or very slow, in the pits, off track, or serving a sanction. Places gained through the pit lane do not count either.
  - An overtake already side by side when the flag comes out may be completed.
- **Giving the place back.**
  - An overtake made within 10 s of the flag (while braking) is forgiven if you give the place back, even after the flag has ended. The overlay shows *GIVE THE POSITION BACK TO … (… s)*, with at least 5 s to do it.
  - The AI you passed does not queue behind you; it comes back past. Retaking a place an AI gives back to you is not an overtake.
  - Any car passed illegally, AI or you, may retake its place without sanction while the flag lasts.
- **After the Safety Car**: no overtaking until you cross the line.
- **Red flag**: restarting outside the pits is penalised.
- **Mandatory stops**: a stop missing when the window closes is penalised.
- **The sanction.**
  - AC adds no time to the classification, so the penalty is a native **throttle cut** (5 s, **Penalty: throttle cut (s)**). It is announced on screen and on the overlay, and logged. It needs race settings that allow AC's throttle-cut penalty.
  - Beyond **Offences allowed before disqualification** (5), you are disqualified with AC's black flag. The overlay shows your count, and its black flag says *Disqualified: 6 offences*.

**AI sanctions** (**AI sanctions under flags**; Practice, Qualifying and Race):
- An AI that overtakes under yellow, a neutralisation or a red flag lifts off for a few seconds. There is at most one sanction every 20 s, and a car that went off track during the pass does not count.
- When a neutralisation or a red flag starts, an AI that passes during the braking lifts off clearly to give the place back. It is only sanctioned if it keeps the place.
- Beyond the allowed number of infringements, the AI is disqualified, returned to its pit box and parked until the end of the session.

**AI sanctions (Beta 1.42)** (sidebar **AI sanctions**; everything in Race; in Practice and Qualifying only track limits, wrong way and notices; never on a Track day or in Hotlap; never you, whom AC sanctions itself). AC cannot give its own penalties to an AI nor change its results: everything below is applied by the app, and time penalties exist only in the app's **corrected classification**.
- **Track limits** (three wheels or more off for 0.3 s, at 40 km/h or more, without a spin, not under a yellow flag, not while the app itself moves the car aside): in Practice and Qualifying the lap is invalidated in the app (journal and Diagnostic; AC's lap times and grid do not change), and the next lap too in the last sector. In the race: warnings (3 by default), then a time penalty for each further off; these time penalties never lead to a black flag. A place where three different AI go off within 5 minutes is the AI line itself leaving the limits: it is ignored, the warnings already given there are taken back, and it is forgotten after 30 minutes without an off.
- **Corner cut with a time gain** (race): an AI that gains 0.3 s or more on its learnt pace gets a throttle cut (5 s by default), lowered gradually to 35 % (never to zero), only on a straight (lateral acceleration at most 2 m/s²), without braking, above 80 km/h, not in the 3 s after rejoining or leaving the pits, never with a car behind closer than 30 m or 4 s at its closing speed (then not before 50 m), never under a flag. With no safe moment for 90 s it becomes a time penalty.
- **Procedural offences** (race): jump start at the app's standing start (a held movement of 0.5 s, counted once), pit-lane speeding, crossing the pit-exit line. Penalty: drive-through (default), stop-and-go (a drive-through when the app cannot hold a car at its box) or time penalty.
- **Serving**: the AI is called in once the race has run 30 s, with the pits open and no red flag or neutralisation, never while another stop is wanted (rule, strategy or weather stop: the penalty waits for it), and within the shared pit-call limit. The penalty pass has no tyres, no repairs, no fuel and no wait (stop-and-go: the stop time) and is neither a mandatory stop nor counted as a stop, and does not restart the maximum-stint clock; AC's AI still stops briefly at its box. Not served within the set laps (the lap of the notice and laps without a chance to serve do not count): black flag; if no AI at all has entered the pits after two laps of calls (a track whose pit lane the AI never take), a time penalty instead. Too few laps left to serve: added to the result.
- **Black flag**: wrong way for 5 s at 20 km/h or more (not off the track nor during a spin), an ignored penalty, or too many penalties. The AI is brought back to its pit box and parked there; it is never parked on the track.
- **Give the place back** (race): an AI that passes a car of the same lap while off the track, or within 3 s of rejoining, lifts off to let it back past within 15 s (never below that car's speed minus 25 km/h nor 70 % of its own pace); otherwise a time penalty. Cancelled under a yellow, red or neutralisation, or if that car pits, crashes, is lapped, has a blue flag or crawls.
- **Corrected classification**: the places of AC's finished cars are redistributed in corrected order (time added); Diagnostic block « AI RACE », the journal line `classement corrige` (written when it changes) and the race recap line « Corrected classification: P<n> » when your place changes. Nothing is shown when nobody has a time penalty.
- **Notices**: penalties, throttle cuts and places owed on the overlay (one every 6 s at most; black flags always, with priority). Since Beta 1.43 each one has its own overlay panel: a badge with its code (DT, SG, +N, CUT, POS; the black flag square for a black flag), the driver's name, the sanction and its reason, and a label on the session line. It takes the band only when none of your flags is shown; otherwise it is written on the session line.
- Unticking the section or the switch of a penalty's source during a session cancels what is under way.

### Racing rules and rule sets

Tab **RACING RULES**.

**Choosing the rules.**
- At the top left, **Racing rules on** switches the rules on or off for the profile shown.
- Under **CHAMPIONSHIP RULES** there are five rule sets, applied together to the **Practice**, **Qualifying** and **Race** profiles: **Base rules**, **F1 2025**, **F1 2026**, **GT** and **Endurance**. The Track day and Hotlap profiles are never changed by a rule set; while one of them is shown, the highlight shows the Race profile's rule set. Since Beta 1.29, **Mandatory stop in the race** and **Safety Car** stay off there and ignore clicks, since they only act in the race: set them from the Practice, Qualifying or Race view.
- The values were checked against the 2025 and 2026 F1 Sporting Regulations, WEC 2026 and the 2026 GT World Challenge regulations.
- Since Beta 1.29 the session presets set the rules too: **Free practice**, **Flying-lap qualifying** and **Realistic race** bring the **Base rules** for the whole weekend, and a custom Practice, Qualifying or Race preset brings its own. **Multi-class endurance** applied to the Race profile sets the **Endurance** rules. Up to Beta 1.28, session presets kept the chosen rules.

| Rule | Base | F1 2025 | F1 2026 | GT | Endurance |
|---|---|---|---|---|---|
| No change of direction under braking | yes | yes | yes | yes | yes |
| Double waved yellow (incident on track) | delta +15% | delta +15% | delta +15% | delta +15% | Slow Zone 80 km/h |
| Neutralisation after a major incident (car stopped 15 s on track) | local yellow zone | VSC (delta +30%, end announced 12 s before the green) | VSC (same) | FCY (delta +150%, ≈ 80 km/h) | FCY (delta +150%) |
| Safety Car if the incident escalates (on by default in the race) | yes, from the local yellow zone | yes, after the VSC | yes, after the VSC | yes, after the FCY | yes, after the FCY |
| Pit lane closed under neutralisation | no | no | no | no (open under FCY, SRO rules) | under FCY and for 3 Safety Car laps |
| Red flag on a pile-up (3 cars), real restart (also in practice and qualifying) | yes | yes, tyres changed | yes, tyres changed | yes, no work on the cars | yes, no work on the cars |
| Restart after a red flag in the race (since Beta 1.34) | rolling (RS) | standing (SS) from the grid | standing (SS) | rolling (RS) | rolling (RS) |
| DRS one leader lap after the start, a Safety Car or a red flag; off in the rain and under flags | yes | yes | active aero with no wait | yes | yes |
| Mandatory stop in the race | off | on, different dry compound, before 95% (waived if the race turns wet) | same | on, between 25 and 35 min of a one-hour race (42–58%), no minimum time | none imposed; stints of 50 min max |
| Repairs at every stop in the race (3 s plus damage, 60 s max) | yes | yes | yes | yes | yes |
| Fuel at enforced stops | refuel at the stop | race fuel from the start (refuelling banned since 2010) | same | race fuel from the start (no refuelling in GT World Challenge Sprint) | refuel at the stop |
| Overtake Mode (within 1 s at the detection point, end of lap) | — | — | +2% level on the straights of the next lap | — | — |
| Emulated BoP, Pro-Am ratings | — | — | — | yes | yes |
| Slower class with a predictable line | — | — | — | — | yes |

**Rules that always apply** while the racing rules are on: one defence per straight, never a move towards a car alongside (one car width), and the defence ends as soon as the cars overlap.

**Race-only rules.** Neutralisations, mandatory stops and Overtake Mode only apply in the race. The other rules apply in every profile where the racing rules are on (red flags: Practice, Qualifying and Race).

Emulated BoP (**BoP: pace evened out within each class**): within each class, the AI level slowly converges towards the class median pace, by at most ±2%, updated every minute. Car weight and power are never changed.

Pro-Am ratings (**Pro-Am driver ratings (Bronze to Platinum)**): each AI gets a rating (Platinum, Gold, Silver or Bronze) that stays the same all weekend. Lower ratings are up to 4% slower and slightly more careful.

**The two independent switches.**
- **Mandatory stop in the race** and **Safety Car** sit under **Racing rules on**. They are set for Practice, Qualifying and Race at once, and show the Race profile's state.
- Clicking a row's **title** shows its settings on the right without changing anything. Only its pill toggles the option.
- Each rule set gives them their starting state. Changing them keeps the rule set highlighted.

**RESET TO DEFAULTS** re-applies the highlighted rule set (or the closest one if you edited it), switches included. Your preferences and the Safety Car model are kept.

The 50-minute Endurance stint is an approximation: the WEC limits stints through the BoP energy allowance.

### Neutralisations: FCY, VSC and Safety Car

Race only. A car stopped on the track for longer than **Major incident: car stopped on track (s)** (15 s) is a major incident and triggers the neutralisation set under **Neutralisation after a major incident**:

- **Local yellow zone** (base rules): the yellow zone only.
- **FCY: whole track**: the whole circuit runs to the FCY delta, with no overtaking.
- **VSC: reduced pace**: the whole circuit runs to the VSC delta. The end is announced 12 s before the green (**VSC ENDING**).
- **Safety Car**: the Safety Car comes out straight away, if a car is chosen and on the grid (otherwise FCY).

A neutralisation lasts at least 30 s after the last major incident (**Minimum neutralisation time (s)**). After an FCY or a VSC, racing resumes immediately, with no DRS wait. The panel and messages announce each phase: *Full Course Yellow*, *Virtual Safety Car*, *Green flag*…

Safety Car escalation (**Safety Car if the incident escalates**, on by default in the race with every rule set):
- The set neutralisation responds first. If the incident escalates, the Safety Car is deployed instead, as race control would decide. Escalation means at least 2 cars stopped on track at the same time, or a car stopped for 30 s longer than the major-incident delay (a long recovery).
- With the local yellow zone (base rules), the Safety Car comes out directly when the incident escalates.
- The red flag (3 cars) still takes priority.

**The Safety Car car.**
- **Choosing the model.** Under **RACING RULES › Safety Car** you can pick the model from the car database (**Filter the car database**, **Pick from the car database**, listed as "name (folder)") or type its folder. The default is the **Ferrari 458 Italia Stage 3** from the base game (`ferrari_458_s3`).
- **It must be on the grid.** AC cannot add a car during a session, so add it to the grid in Content Manager. The Racing rules tab warns you during a race if it is missing. Without it, the VSC or FCY carries on.
- **Held when not needed.** It is returned to its pit box in every session and held there by AC's own pit wait (start delay and brake counter, renewed every second; Beta 1.50), never parked without a driver, so that it can drive out by itself when released. If it leaves its box, it is brought back (at most every 10 s); after two such escapes it is parked without a driver as before. Spare Safety Cars stay parked without a driver.
- **Several cars of that model** (Content Manager's random "Manual" grid):
  - The one in a livery whose name contains "safety" (for example `Safety_Car`) is the Safety Car. Failing that, the first one is, and the app gives it that livery.
  - The others stay parked in the pits and never race, but they appear in the driver list and classification because AC loaded them. A "Custom" grid in Content Manager lets you add just one without reducing the number of opponents.
  - Safeguard: while you have not picked the model yourself, several Ferrari 458 S3 on the grid are competitors, and only one in a safety livery becomes the Safety Car.
- **One-make race** (the model is the whole grid's, or yours): no competitor is removed. Only a car in the safety livery becomes the Safety Car; otherwise the app falls back to FCY.
- **Livery.** A livery applied by the app is given back when the car stops being the Safety Car, and when the app unloads.

**A Safety Car period.**
1. **Called.** The field goes under the FCY delta (never faster than the Safety Car minus 30 km/h) while the car stays parked 10 s.
2. **Out of the pits** (Beta 1.50). Released in its box, it drives down the pit lane and joins the track by itself. When the pit exit is known it is released once the leader is about 20 s from it, so that it emerges just ahead of the leader (at most 90 s after the call); otherwise right after the call time. Log: `voiture de securite: liberee, sort par la voie des stands`, `sortie de son stand`, `sortie en piste devant <name>`, then `en tete de la file` once the queue has formed. After a red flag it leaves first and the AI follow 3 s later, in the frozen order; you are told to wait until then.
   - **Fallback: placed on track** (Beta 1.48), if it has not left its box within 10 s or the pit lane within 45 s, never within your sight (at least 800 m ahead of you, 300 m behind). AC's AI never drove the Safety Car out of its pit box, so the app places it on the track through CSP (the same method as spreading the AI on a track day), 200 m ahead of the leader, on a point with no car within 80 m. The FCY continues until it is on track. If it cannot be placed within 15 s, the neutralisation continues as an FCY (logged).
3. **On track.** It runs at 80 km/h while the first car behind it is more than 120 m back, then at **Safety Car speed (km/h)** (120 km/h). The AI catch it up at its speed plus 40 km/h, then run in single file without overtaking.
4. **In this lap.** Once the incident is cleared and it has been out for at least 60 s, the overlay announces *Safety Car in this lap*.
5. **Green.** The green flag comes when it enters the pit lane (`voiture de securite: rentree a son stand` once in its box). There is **no overtaking until the line**, then it is held in its box again. If it misses the pit entry and crosses the line, the green comes there and it is sent back to its box, but only once out of your sight (it keeps driving towards the pit entry for at most 60 s).
6. **Fallbacks.** If it stops on the track during its intervention, it is returned to its pit box and the neutralisation continues as an FCY. After a VSC, your delta restarts at +1 s when the Safety Car takes over.

**Status:** the Safety Car's exit from its pit box was reworked in Beta 1.25 and has not yet been confirmed in game (log line `voiture de securite: sortie de son stand apres … s`). Treat it as experimental.

### Red flag

**Red flag on a serious accident (practice, qualifying, race)**, on by default.

**In the race:**
- **Trigger** (Beta 1.47, only when the track is really blocked). At least 3 cars (**Red flag: cars stopped on track**) stopped for 10 s **because of an incident**: damage, a spin, stopped off the racing line or off the track, or stopped alone on the track. Cars that only wait undamaged in the queue behind the accident, on the racing line, never count. And the track must be blocked: where those cars stand, they leave no 2.5 m passage across the width of the track. Otherwise the race goes on under yellow flags, VSC or Safety Car as before, and the journal says why (`pas de drapeau rouge: 5 voitures arretees dont 4 dans la file`). A car still spinning does not count, and neither does yours.
- **The AI.** All AI return to their pit box at the red-flag delta (+60%, 80 km/h fallback) without overtaking, and stay there. An AI stopped on the track is recovered to its pit box.
- **You.** Enter the pit lane too, within the delta. The overlay shows **RED FLAG**, flashing, with the *PIT: RETURN TO THE PIT LANE* pill.
  - The restart waits for you, at most until the maximum delay. Refusing to come in holds the AI until that delay.
  - Restarting outside the pits is penalised.
- **The restart** comes once every AI is at its pit box (Beta 1.48: not just in the pit lane), the track is clear and the minimum suspension (60 s, **Red flag: minimum suspension (s)**) has passed. At the latest, it comes after one and a quarter laps at the return speed plus the pit lane (about 8 minutes at Spa).
- **A real restart** (F1, WEC, GT):
  - **The order is frozen at the red flag** (Beta 1.48), you included: the classification at that moment, not the order in which cars reach the pits. It sets the pit exit, the grid of a standing restart, the overlay and the overtaking rule below.
  - The cars leave their boxes in that order, one every 2 s, each only once the car before it has left its box and passed its own (at most 20 s of waiting, 45 s behind you). The log notes `sortie des stands: X attend Y`.
  - **The Safety Car is placed on the track** for the restart lap: 200 m after the pit exit when the app knows where the pit lane rejoins (the AI wait in their boxes until it is placed), otherwise 250 m ahead of the first car out. If it cannot be placed within 15 s, the restart lap runs under VSC (F1 rules) or FCY. Without a Safety Car, it runs under VSC with the F1 rules, or under FCY otherwise.
  - **The overlay shows your restart position**: in the pits a **RESTART P7** box with *Stay in the pits · restart P7 behind …*, then *Wait: … leaves before you* and *Go: P7 behind …*; on track a green *P7 · BEHIND D. FERRO* pill, or an amber *RETAKE P7: PASS … (ALLOWED)* pill. The session line shows the frozen position.
  - **Retaking your place is not an overtake under the flag**: passing a car classed behind you in the frozen order is allowed (for the AI too) during the pit exit, the restart lap and until the line. Passing a car classed ahead of you, or the Safety Car, is still penalised.
  - There is no overtaking during the restart lap, nor until the line after the green (after a standing start, overtaking is allowed from the lights out, since Beta 1.36).
  - Since Beta 1.34, **Restart after a red flag** chooses how the race restarts (the overlay announces it during the restart lap):
    - **Rolling start (RS) behind the Safety Car** (base, GT and Endurance rules): the green comes when the Safety Car pits, as above.
    - **Standing start (SS) from the grid** (F1 2025 and F1 2026 rules): after the restart lap, every car drives to its grid slot, in race order with the slots closed up. A car in the pit lane starts from the pit lane. The AI slow down along the approach (speed cap from the distance to the slot, assist brake in the last metres), take the column of their slot and are held there. The overlay tells you your slot and the distance to it (*Go to your grid slot: P4 · 380 m*, to the metre below 20 m, then **IN POSITION** or **SLOT PASSED**). With the VSC or FCY, the restart lap ends when the leader completes it. Once everyone is in place (or after 2 minutes, whoever is still out is held where they are), five lights come on in the overlay, one per second, and go out after a random hold; every AI leaves at once, with the race-start protections (caution, aggression, front radar, lane holding). Moving forwards once you are in your slot and stopped, before lights out, is a **jump start**, penalised like the other infringements (throttle cut, counted towards disqualification) once you are past the line, never on the grid; starting from the pit lane is never a jump start. The trackside light panels stay yellow during the grid and the lights, then green.
    - The grid slots are the track's `AC_START` nodes when CSP gives them and they make sense (before the line, within 400 m, in order, on the track), otherwise computed: 6 m before the line, 8 m apart, alternating columns. Nobody is ever teleported, so laps stay exact. Without the CSP functions it needs (stop counter, speed cap, lateral offset) or a measured lateral direction, the restart stays rolling and the log says why.
    - A new incident during the grid or the lights cancels the standing start: the holds are released and the usual yellow flags take over.
  - **Overtaking allowed after the restart** (Safety Car view): **at the control line** (default, the usual rule) or **as soon as the Safety Car pits**, for a red-flag restart lap and for an ordinary Safety Car deployment.
- **Work in the pits.** With the F1 rules, tyres are changed under the red flag and the stop counts (**Red flag: tyres changed in the pits (stop counts)**), even before the pit window opens (Beta 1.48). With the GT and Endurance rules, no work is done, also for a car that entered the pit lane under the red flag and reaches its box after the restart. With a compulsory compound change, your own stop counts only if you changed compound.
- **DRS** is disabled until one lap after the restart.
- **Limitation:** AC cannot suspend a race, so its race clock keeps running during the suspension.

**In Practice and Qualifying**, the session is suspended the same way: every AI returns to its box at reduced speed. It then resumes at the green flag with no restart lap, the AI leaving the pits one at a time. Never on a Track day.

### DRS and Overtake Mode

- **Player DRS: beep and panel** (on by default):
  - For a DRS-equipped car, a beep sounds when your DRS becomes available, in hotlap too. The overlay shows a **DRS** badge until you open the flap (white outline when available, solid when open).
  - It does not come back under braking in the same zone.
  - Availability is AC's own (the track's DRS zones, within one second at the detection point). The app never opens your DRS for you.
- **DRS: racing rules (rain, flags, start, Safety Car, red flag)** (on by default in Practice, Qualifying and Race):
  - DRS is disabled for every car, you included, in the rain and under flags (neutralisation, red flag, the car's own yellow zone).
  - In the race it is also disabled for the leader's first laps after the start, after a Safety Car and after a red flag (**DRS: leader laps before enabling**, 1 lap; F1 2026: 0), never after a VSC or an FCY. The app measures the leader's laps on track.
  - Practice and qualifying: rain and flags only. Never on a Track day.
  - The overlay shows the reason: *DRS disabled under flags*, *DRS DISABLED: WET TRACK*, *DRS ENABLED IN … LAP(S)*.
- **AI DRS: opened in the zones** (on by default): AI whose car has DRS open it in the zones as you do, when CSP reports it available, on a straight and not braking. It closes under braking. The log summary counts the openings.
- **F1 2026:**
  - Active aero (Straight Mode) is rendered through AC's DRS on cars that have one, with no wait.
  - **Overtake Mode** is emulated for the AI only, through their level: an AI within 1 s of the car ahead at the detection point (end of the lap) gets +2% level on the straights of the next lap. It is disabled in the rain, under flags, and after the start or a restart until the leader reaches the detection point. AC does not give this boost to the player.
- GT3 and WEC cars have no DRS in reality: the DRS rules only concern cars that have one.

### Pit stops: mandatory stops, tyres, fuel and repairs

The settings are under **RACING RULES › Mandatory stop in the race**. They are the Race profile's settings, the only profile where they apply.

**Mandatory stop in the race** (off by default; on with the F1 and GT rules). Since Beta 1.51 it is simply on or off: one stop is required, and everyone, AI and player, then makes as many stops as their strategy needs (settings saved with 2 or 3 stops become one):
- **The window.** It opens and closes at a percentage of the race (**Window opens (% of race)** 25%, **Window closes (% of race)** 75% by default). The race is measured in leader laps, or in time for a timed race.
  - A window that closes at 100% never closes.
  - A window declared by CSP (server, race mode) is used first.
- **The AI.** Each one stops at its own moment in the window, with at most three called in at once.
  - Only stops made with the window open count, and reloading the app mid-race does not make them stop again.
  - A recovery to the pits and the Safety Car do not count as stops, except under a red flag.
- **You.** The overlay reminds you when the window opens and towards its end. A stop missing when the window closes means a penalty (throttle cut, counted as an infringement).
- **F1 rules.** **Change dry compound (F1)**: a different dry compound at the stop. It is no longer mandatory if the race turns wet.
- **Pit lane closed** (**Pit lane closed under neutralisation**; GT and Endurance rules):
  - No AI is called in, and a stop made with the pit lane closed does not count.
  - A tyre change for rain is still allowed. The overlay shows **PIT LANE CLOSED**.
- **Maximum stint (min, 0 = free)**: beyond it, the AI is called in, except in the last 5% of the race. Endurance rules: 50 min.
- **Minimum stop time (s, 0 = free)**: useful to mimic refuelling or a driver change.

**Tyres** (**New tyres at every stop (pit rules active)**): at every pit visit in the race, as soon as a pit rule is active, the app fits new tyres. They are wet tyres if the weather requires them, otherwise another dry compound (F1 rule) or a fresh set.

**Repairs** (**Repairs at every stop in the race (bodywork, suspension, engine)**, on with every rule set):
- Whenever a damaged AI visits its pit box (a rules stop or a native fuel stop), bodywork, suspension and engine are repaired.
- It stays there for the repair time: 3 s plus according to the damage, 60 s at most. Under a red flag, repairs follow the rule set's work rule.

**Fuel** (**Fuel at enforced stops**; mandatory stop, maximum stint, weather tyre change, red flag):
- **Refuel at the stop**: just what is needed until the next planned stop or the finish, plus a reserve (base and Endurance rules).
- **Race fuel from the start**: before the start, the AI gets fuel for the whole race (within its tank) and no longer refuels, unless that is not enough to finish (F1 and GT rules).
- **Left to AC**: the app does not touch the fuel.
- **How it is measured.** Consumption is measured lap by lap on each car and remembered per car model and track for the next race; until then, AC's estimate is used. While consumption is unknown, or if fuel use is off in the session, nothing is imposed.
- **Safety net.** Each request also tells AC after how many laps to make an emergency stop, so an AI never runs dry.
- The player is never concerned. The log notes the amount requested and the fuel before and after the stop.

### AI strategy, out-lap, tyre wear and failures

New in Beta 1.42 (sidebar **AI strategy**, Race only; out-lap and tyre wear in **Weather**):
- **Individual pit strategy**: each AI is its own strategist, cautious to bold (drawn per session around **Average risk taking**, spread by **Spread between strategists**). It plans its stops from its own tyre wear per lap, its fuel and the laps left, through the usual pit request; a mandatory stop is aligned on the planned stop when that falls later in the window, and refuelling covers the next stint plus the margin. Near the finish the last stint is stretched instead of stopping: no stop when the fuel reaches the flag with the usual reserve and the tyres last to their wear limit, at most two laps (one to three, with the risk taking) past the set wear. Under a new neutralisation, strategists close to their stop pit.
- **Undercut and overcut**: a bold strategist a few laps from its stop undercuts the rival just ahead; a cautious one covers the rival behind that pits (never with fresh tyres); one with good tyres stays out two laps when the rival ahead pits. Never in reaction to a car serving a penalty, a disqualified car or a car pitting with a failure.
- **Out-lap warm-up**: after a real stop at its box (never after a penalty pass, a recovery to the pits, a red-flag recall or at the race start), an AI drives its out-lap a few percent slower until the line or warm tyres, then gets its level back smoothly. It acts through the AI level, so it needs the **General** section ticked (as does the level part of a failure; the throttle part of a failure works either way).
- **Lock-ups and tyre wear**: worn, asymmetric front tyres make lock-ups more frequent at the end of a stint; each lock-up adds a small flat spot (virtual km) to the more worn front tyre, bounded per stint (reset when new tyres are fitted).
- **Tyre wear is used only once its scale is checked in game**: the app waits until it has seen a fresh tyre (low wear) and the wear rising. Until then, and if the values stay implausible (`usure des pneus non fiable ici`), there is no stop for tyres and no wear-linked lock-ups; fuel and the stop rules still apply.
- **Safety of the plan**: whether a stop is needed is decided on the raw fuel and tyre capacity; margins only place a stop that is needed. No tyre stop and a fuel reserve of 0.1 lap in the last 2 laps; critical fuel (under 1.5 laps, cannot finish) is called even with the pits closed or the call limit reached, but never before the after-stop check; strategy stops fit new tyres when **New tyres at every stop** is ticked (none forced in the wet when the app does not manage the weather); a stop that changed nothing (tyres or fuel) is not asked again; one call limit is shared with the stop rules and the penalty passes, a call is never withdrawn (a request not yet called is withdrawn when the plan no longer needs it); a non-critical stop waits for the mandatory window to open; a neutralised lap does not teach fuel use.
- **Progressive failures** (rare): a fluid leak, overheating, a slow puncture or a battery drain lowers the pace gradually (up to **Failure: maximum pace loss**); the AI heads to the pits, is repaired in 8 to 20 s, then gets its pace back. Never parked on the track, never on the first lap nor in the last 10 % of the race, at most once per AI per session.

### Endurance and multi-class

Section **Classes / Endurance** (sidebar **RACE & SAFETY**).

- **Endurance layer** (Track day and Race profiles):
  - The pace varies from one stint to the next (**Variation between stints (%)**, 3%), drawn at each stop.
  - It drops slightly over a stint (**Degradation over a stint (%)**, 1%, reached after 40 min, reset in the pits).
  - Extra caution for 8 s on pit exit.
  - Lapses in focus become more frequent after 1 h 30 without an incident (fatigue).
  - **HOME › TO CHECK** suggests it for sessions longer than one hour.
- **Multi-class**:
  - The AI are split into classes by pace: a new class opens at a gap of **Gap between classes (%)** (8%), with four classes at most.
  - A slower class yields to a faster one (**Class speed advantage (km/h)**, 4 km/h), which overtakes it more easily. Faster classes get a longer blue-flag range.
  - Without a large enough gap the grid stays one class, and an AI still learning its pace is compared with no class.
  - **Class patterns** take priority over the automatic split (see [Track zones and class patterns](#track-zones-and-class-patterns)).
- **Slower class: predictable line** (Endurance rules): an AI of a slower class caught by a faster class holds its line instead of moving aside. It is up to the faster car to overtake cleanly.
- On a Track day, endurance keeps its logic without a classification. Lap-based rules apply in qualifying and the race.

### Weather and tyres

Section **Weather** (sidebar **RACE & SAFETY**). It is independent of Endurance and ticked by every built-in preset.

- **Detection.** The app watches rain, track wetness and standing water. 15 s of confirmation and separate thresholds avoid constant changes, and a still-wet track keeps the wet strategy even if the sky clears.
- **Adapt pace to the weather**: on a wet track, the AI lower their level (by up to 10%) and their aggression, increase their caution and watch further behind them (+30% rear range).
- **Manage dry and wet tyres**.
  - The compounds come from each car's CSP catalogue (dry, intermediate, wet).
  - In the rain the AI fit intermediates, or wets if the rain is heavy, at their stop. They go back to dry tyres when the track dries out.
  - A dry compound already fitted is kept. An AI leaving wet tyres gets one of its car's own dry compounds.
  - Before a race start, on the grid, and in the first 15 s of any session for a stationary AI, the right compound for the conditions is fitted at once, instead of a stop on lap 1.
  - Otherwise the app requests a pit stop, and only changes the compound at the stop. The request stays active in the pit lane until the change, and is only lifted after the exit: in CSP, a "false" request also blocks the pits for a moment.
  - While the native wet-tyre state already matches the decision, CSP's native wet strategy is not forced.
- **Rain compensation without wet tyres (%)** (15%, 0–30%): with no wet compound available and no native wet tyre confirmed, the app adds a bounded grip assist, scaled by the conditions.
  - It is not a universal wet-tyre model, and Rain FX stays active.
  - No extra bonus is added when CSP already reports native wet tyres.
- **On-screen message on a weather change** announces the pace and tyre adaptation.
- The section shows the track wetness, the number of AI on wet tyres or compensated, and the tyre lists read. A profile in use without the Weather section gets a warning on **HOME**.

### Track-day traffic spacing

Section **Spacing** (sidebar **TRAFFIC**). Track day profile only, ticked by **Nordschleife Touristenfahrten**.

- **Counting.** The app counts the AI present and those currently on track, leaving out the player, remote cars, cars in the pits or off track, and invalid data.
- **The target gap** combines three parts:
  - a gap tied to pace (**Base gap (s)**, 2.5 s at the car's speed, plus 15 m);
  - a distance that grows with the number of cars (**Distance added per AI (m)**, 2.8 m per AI);
  - a deterministic variation per car (**Gap variation (%)**, ±45%).
- **Limits.** 50 AI get larger targets than 9 AI on a long enough track. On a short circuit, the available length caps the target while keeping the variation.
- **How a car is held back.**
  - When an AI follows too closely, the app lowers a speed cap (`setAITopSpeed`) gradually, at most 4 km/h per second, by up to **Maximum speed reduction (%)** (14%).
  - The cap is based on the car's highest free speed on a straight since leaving the pits, never a cornering speed. It never goes below the target, so the AI accelerates freely back up to it after a corner.
  - The corrections come in 6 s episodes, staggered between cars, followed by 12 s free. They are suspended below 60 km/h.
- **What spacing never does.** No car is ever teleported and no forced braking is used to space cars. Beta 1.26: a faster AI is never held back behind a clearly slower car on a straight; it catches it and overtakes.
- **Release.** The cap is lifted once the gap opens, during a priority manoeuvre, outside the Track day profile and when the section is switched off. The restore uses the SDK's "unlimited" value, because CSP offers no way to read the original cap, so a cap set by another app cannot be restored exactly.
- The app never holds AI in their pit box on a Track day: Content Manager already places them on track.

### AI distribution at session start and CSP AI flood

New in Beta 1.26. Settings in the **General** section of the profile shown.

**AI distribution at session start** (Track day, Practice, Qualifying; never in the race, where cars start from the grid):
- **On the whole track** (Track day default).
  - Each AI is placed directly on track, on its line, with gaps drawn at random as in real traffic (**Start gap variation (%)**, 100%; 0 = regular intervals). That can be a few cars almost nose to tail and others more than 2 km apart.
  - Cars are never less than 15 m apart, and 300 m are left free on each side of you.
  - **AI left in the pits at the start (%)** (25%, about 7 or 8 AI out of 30) stay in the pits and leave on their own, as on a real track day.
  - The app first cancels AC's native wait, lets CSP align the car on its line, then launches it at 50 km/h along its axis. An AI only counts as placed once it reaches its spot.
  - The log reports `repartition des IA: … IA posees en piste sur … prevues` (*placed on track out of planned*). Three seconds later it gives `… IA roulent normalement, … en difficulte` (*driving normally / in trouble*).
- **Staggered pit exits** (Practice and Qualifying default).
  - The AI leave the pits one after the other, in a random order, **Staggered pit exits, practice and qualifying** seconds apart (10 s per AI, 0 = free).
  - With many cars the gap shrinks, never below 2 s, so that all are out within 3 minutes at most, or within a quarter of a short session.
  - On a Track day in this mode, the gap follows the circuit length, with all cars out within 10 minutes.
  - Only AC's native start wait is used, so no car is parked. An AI that leaves its box before its turn has its wait cancelled at once, and all waits are cancelled if the app is switched off or unloaded.
  - The log notes the draw (`sorties des stands etalees …`), then each AI's planned turn and actual exit.
- **Native (game)**: the game's own start.
- **When it applies.** It needs at least **Spread from (AI)** AI (10 by default) at the start of the session (first 60 s); below that, the game's start is kept. It never runs online.

**CSP AI flood** (Track day, circuits of 7 km and more):
- **Why.** CSP's AI flood makes the AI appear and disappear around the player, within 1 km by default. While it is active, neither distribution nor spacing is possible.
- **What the app does.** It manages the `[AI_FLOOD]` section of your CSP user settings (`Documents/Assetto Corsa/cfg/extension/new_behaviour.ini`). Only the keys it manages change; the rest of the file is kept as it is.
  - With at least **Spread from (AI)** AI, it switches AI flood **off**.
  - Below that number, it switches AI flood **on**, with the chosen **CSP AI flood range, below the threshold (km)** (1 km = CSP's own setting, up to 5 km). The effect is not guaranteed beyond 2 km, the limit of CSP's settings page.
  - With **Native (game)**, it writes back the original values, saved before its first change.
- **Next launch.** CSP reads this setting when the game starts, so a change takes effect at the **next launch**.
- **Leftover.** CSP's safe file replacement used to leave `new_behaviour.ini.bak` next to the file; the app deletes it after each write (since Beta 1.38) and, since Beta 1.39, at launch when an older version left one.
  - The overlay announces it (**AI flood (CSP)**, for example *turned off for 45 AI: relaunch from Content Manager to spread them over the whole track*), and the log notes it.
  - If AI flood was active when the game started, that session's AI are placed by CSP and the app does not try to distribute them.
- **In the log at each launch:** `AI flood de CSP au lancement: actif|inactif (circuits d au moins 7.0 km)` (*active or inactive at launch, minimum track length*).

### Front radar and the other global options

Section **Global options** (sidebar **ADVANCED**). These values are shared by all profiles. Each profile only applies them if its **Global options** section is on; otherwise it uses the defaults below.

- **Front radar (light extra braking)** (on by default since Beta 1.24, from the starting grid, never in the pits):
  - An AI about to hit the car ahead in its lane (you or an AI) first lifts off, with contact less than 2.5 s away.
  - With contact less than 1.2 s away, it adds light braking: at most 45%, built up over about 0.3 s and released progressively.
  - It is never a stab of the brakes nor a sideways move. The brake only adds to the AI's own, and its throttle, steering, clutch, gear and handbrake stay its own.
  - At the race start it only brakes below 0.8 s to contact. A slipstream or a slow approach does not trigger it.
  - To switch it off, tick **Global options** and set the radar to **OFF**.
- **Requested level mode**: **Automatic**, **Native if confirmed**, **Grip bonus allowed** or **Cap at 100%**. It decides how a level above 100% is applied (see [General driving](#general-driving-level-aggression-caution-and-spreads)).
- **Allow the grip bonus** (off): lets the grip bonus emulate a level above 100%. It changes the AI cars' grip, so switch it on knowingly. **Grip bonus per level point** is 0.004 (0.4% per point).
- **Override native AI awareness** (off): when the app imposes a lateral offset, the AI ignore their native avoidance and strictly follow the target. More precise, but it removes a native safeguard.
- **Detailed log** (off): records every AI state change in the event log.
- Lateral occupancy:
  - **Occupancy: lateral threshold (m)** (0.3): below this offset, a nearby car is in the same lane.
  - **Occupancy: lateral reach (m)** (5.5): beyond it, a car no longer occupies the side.
  - **Occupancy: margin (m)** (6): longitudinal margin added to the car lengths.
  - **Occupancy: speed gain (s)** (0.8): extra margin per m/s of closing speed.
- **Personality seed** and **Regenerate personalities**: see [Personality](#personality-focus-and-driving-mistakes).

### In-game overlay

Since Beta 1.25, the app draws its own overlay, like SuperHUD's, instead of a CSP app window. It replaces the former "AdvancedIA Drapeaux" window. Set it in **SETTINGS › ADVANCED › Overlay**; its settings are shared by every session. The flag band is switched on per profile by **AdvancedIA flag panel while driving** (Accidents section, on by default). With it off, the band only shows the game's own flags and penalties. The session line and AC messages keep following their own Overlay settings.

Position and size (**POSITION AND SIZE**):
- **UNLOCK · MOVE · SIZE**: drag the overlay to move it, pull its bottom right corner to resize it, and right-click it to lock it again. **LOCK THE POSITION** locks it from the window.
- **PUT BACK ON SCREEN**: back to the automatic position (centred at the top of the screen) at size 1.00x.
- **Size**: 0.50x to 2.50x (1.00x = 600 px wide). The overlay keeps its proportions at every size.

Appearance (**APPEARANCE**):
- **Background**: **OPAQUE**, **DIMMED** or **TRANSPARENT**.
- **Background opacity**: 86% by default; at 0% only the flag, texts and delta remain.
- **Content opacity**: 30–100%.
- **Display**:
  - **Only with information** (default): the overlay appears for a flag, a penalty, DRS or the delta.
  - **Always**: it stays on screen, showing **TRACK CLEAR** when there is nothing to report.
- **Information: display time**: how long non-urgent information stays (green flag, start, DRS available, last lap, chequered flag, slippery surface). 0 = **While they last**. Flags always stay as long as they are active.

Content (**CONTENT**):
- **Session info (position, lap, time, best lap, fuel, stop)**: a permanent top line with **POS**, **LAP** (lap of the total) or **LEFT** (time left), **BEST**, **STOP** (mandatory stop done or to do) and **FUEL** (fuel left in laps, orange below two laps).
- **Flag explanations**: under the instruction, an explanation of what is happening. For a yellow flag: *A car is in trouble ahead, near the track (spin, off, stopped)…*. For a double yellow: *A car is stopped or sideways on the track…*. Also for the Safety Car, VSC, FCY, red and blue flags, slippery track and the last lap.
- **End of race summary**: at the finish, **RACE OVER**, the chequered flag and a summary, also written to the log (`fin de course: …`). It contains:
  - congratulations for your place (victory, podium, top 5, top 10…);
  - finishing and starting positions, places gained or lost;
  - your best lap compared with the whole field (*the fastest of the race!*);
  - overtakes made on track and times you were overtaken (excluding pit stops and recovered cars), and the number of laps.
- Lap line message: when you cross the line, the band shows the next lap (**LAP 4/8**), the last lap and the best one, or *new best lap!*.

Assetto Corsa displays (**ASSETTO CORSA DISPLAYS**):
- **Replace the AC session box (lap, time, RACE OVER)** (on): hides AC's original session box at the top of the screen while the session line replaces it. It is restored when the app unloads.
- **Show AC messages on the overlay** (on): AC's messages (assists, warnings, invalidated lap) are shown on the overlay's top line for as long as they last.
- **Hide the original AC messages** (on by default since Beta 1.26).
  - At launch, the app checks that hidden messages still reach the overlay. If not, hiding lifts itself until the next launch, and the log says so.
- **Hide AC system messages (CSP option)** (on, Beta 1.40): CSP's **Hide system messages** while the overlay takes over the messages; it hides AC's top banner for assists and similar messages. AC's red cut and penalty banners (*CUT DETECTED: LAP WILL NOT COUNT*, *PENALTY, SLOW DOWN FOR … SECONDS*, drive-through, disqualification) stay drawn by AC even with this option: CSP offers no way to hide them (Beta 1.40 sessions). Since Beta 1.41 the overlay no longer shows them again, so they are never seen twice; they are still written to the session log. See [CSP display options](#csp-display-options).
- **Hide AC's own flags (CSP option)** (on, Beta 1.40): CSP's **Hide race flags** while the app is active and its flag panel (**App flag panel while driving**) stays ticked in the profile in use.
- A status line under these two switches says whether CSP applies them now, at the next launch, or not at all.
- Other AC HUD elements (fuel, starting lights, damage, leaderboard, proximity, mirror, wrong way, ping) stay: the overlay does not fully replace them.
- **Click-through when locked** (on), **Hide in replays** (on), **Hide in the pits** (off).

<a id="csp-display-options"></a>**CSP display options** (Beta 1.40, kept ticked since Beta 1.47):
- **Where.** `[HIDE]` section of your CSP user settings, `Documents/Assetto Corsa/cfg/extension/gui.ini` (the file Content Manager writes for **Custom Shaders Patch › GUI**). Only `HIDE_SYSTEM_MESSAGES` and `HIDE_RACE_FLAGS` change; the rest of the file stays as it is.
- **Never your own choice.** An option you ticked yourself before the app did is left alone. An option the app ticked stays ticked while the app is active: unticking it in Content Manager is undone at the next launch, so use the app's switch instead.
- **Saved first.** The original file and values go to `Documents/Assetto Corsa/cfg/extension/state/ACAdvancedIA-cspgui.ini` before the first write, so they survive a crash. **Ticked for good (Beta 1.47).** The options stay ticked when the game closes, when the app unloads, during **PANIC** and after a crash, so Content Manager shows them ticked. The app gives your values back, byte for byte when nothing else changed the file, only when hiding stops: you switch the option off, you switch the app off (APP button), you turn off the app's flag panel in the profile in use (flags), or the overlay stops taking over AC's messages (messages).
- **When it applies.** If CSP re-reads `gui.ini` during the session (log `options CSP: gui.ini relu par CSP en cours de partie`), at once. Otherwise at the next game launch (`… effet au prochain lancement du jeu`).
- **Red on the light panels** waits until CSP has applied **Hide race flags**, never on the file alone. Otherwise the red value would show as AC's black flag.
- **Safety.** At most 8 writes of `gui.ini` per game session, and no `.bak` left behind. If hidden messages stop reaching the overlay, **Hide system messages** is given back and the window says so; tick the switch again to retry.
- **In the log:** lines starting with `options CSP:`.

**Reading the band:**
- **Left side.** An accent bar in the flag's colour, then the flag with its code:
  - **SC**, **VSC**, **FCY**;
  - **!** for a single yellow, **!!** for a double yellow;
  - **P** for a mandatory stop;
  - yellow and red stripes for a slippery surface;
  - chequered, black, and the black-and-white penalty flag;
  - since Beta 1.32: white for a slow vehicle ahead, the black-and-white flag for a warning, black with an orange disc for a damaged car;
  - or the **DRS** badge.
- **Middle.** The title in bold, then a short one-line instruction, for example *Ref. +30% · stay in the green*, *Yellow in 200 m · slow down* or *Drive-through · 2 lap(s) to serve it*.
- **Right side.** The **delta time**, large: green when positive, flashing red when negative. The app version sits in a corner.
- **Pills,** shown only when they apply: penalty, *GIVE THE POSITION BACK TO …* with the seconds left, *PIT: RETURN TO THE PIT LANE* under a red flag, the gap of the car lapping you (*… s BEHIND*), **PIT LANE CLOSED**, *No overtaking*, and DRS disabled with its reason.
- **Flashing is kept for what is urgent**: red and blue flags, a negative delta, an overtake committed under flags, a penalty, a place to give back, a call to the pits. A new flag also flashes for a few seconds.

**The game's own flags and penalties** (black flag, drive-through with the laps left, return to the pits, throttle cut, chequered flag, last lap, blue, yellow) are always shown on the overlay, even with the panel off or the app stopped. AC still applies its own penalties.

**FIA signals added in Beta 1.32** (none of them forbids overtaking):
- **SLOW VEHICLE** (white flag): a car on the track ahead of you, within 300 m, has been going below half its usual pace at that spot for 3 s (below the obstacle speed while its pace is not known yet). Not a car already in an incident (that is a yellow flag), in the pit lane or just out of it, nor the grid. Overtaking it is allowed. Only with the app's yellow flags on. Logged (`vehicule lent devant le joueur: …`).
- **WARNING** (black-and-white flag):
  - you overtook under a flag and the place is still to give back once the flag has ended (under the flag itself, the flag stays shown with the *GIVE THE POSITION BACK* pill);
  - your last tolerated infringement: the next one disqualifies you. Shown for 10 s as soon as no flag is up, dropped if you are disqualified. Logged (`avertissement du joueur: …`).
- **CAR DAMAGED** (black flag with an orange disc): for 20 s when your car gets notable mechanical damage: suspension (0.2 of 1), engine (life down to 600 of 1000), gearbox (0.4 of 1), heavy bodywork damage (impacts adding up to 100 km/h) or a blown tyre. Read once a second, never with mechanical damage off, never in the pit lane; a repair re-arms it. Logged (`voiture du joueur endommagee: …`).

### Track light panels

Since Beta 1.32, on a track whose CSP configuration lights its trackside light panels (marshal posts, LED boards) from the player's flag, the app lights them with its own flags. Offline only.

Since Beta 1.37 the panels have their own section, **SETTINGS › RACE & SAFETY › Track light panels**, set per profile like the other sections and ticked by default in every profile:
- **Active for:** one chip per profile (**TRACK DAY · PRACTICE · QUALI · RACE · HOTLAP**), cyan when the section is ticked for that profile; a click ticks or unticks it, like the section's switch. This section never counts as one that drives the AI: with only this section ticked, the app drives no AI.
- **Circuit status:** equipped or not, with the file where the panels were found, and the colour shown right now. On a track that is not equipped, colours and durations stay adjustable, with no effect there.
- **Colours:** yellow (always on: yellow flag, Safety Car, VSC, FCY), red, blue, white (very slow vehicle ahead), orange (slippery track), green (end of zone, of neutralisation and restart). A colour turned off gives way to the next one by priority; red turned off shows yellow.
- **Durations:** **Green duration (s)**, 0–15, 5 by default (0: no green; the end of a yellow zone keeps three fifths of it, 3 s by default); **Delay before a less important colour (s)**, 0.5–5, 1.5 by default.
- **The legend** of the six colours and, when AC's own flags are shown, the warning that red appears as yellow.
- Beta 1.32 to 1.36 had a single switch, shared by every profile, in the Overlay section. When updating, your choice is kept: if you had turned it off, the section is unticked in every profile. The Overlay section now links to this one.

- **How it works.** CSP track configurations light their panels from the player's race flag (`INPUT=FLAG_TYPE`). The app sets that flag (`physics.overrideRacingFlag`), so all the panels of the track show the same colour at once. It hands the flag back to AC as soon as there is nothing to show, and on every exit (stop, panic, session change, unload, reload).
- **Equipped tracks.** On the first frame at a track, the app reads its configuration, and never writes it:
  - the track's own `extension/ext_config.ini`, its layout's, and the files they include (since Beta 1.41 found as CSP does: from the including file's folder, `..` allowed, `common/…` in CSP's track configurations, `extension/…` from the Assetto Corsa folder; only inside the track's folder or CSP's configuration; 64 files and 8 MB at most);
  - CSP's own `extension/config/tracks/<track>.ini` and `loaded/<track>.ini`.
  - A track counts as equipped when an active section lights up on a condition read from `FLAG_TYPE` (defined there, in an included file, or in CSP's shared `common/conditions.ini`). CSP's choice between the track's file and its own is not known to the app: the window says *found in its configuration*.
  - On the author's installation, 25 of 46 tracks are equipped (76 of 151 layouts, Beta 1.41), for example Spa, Monaco, Le Mans, Bahrain, COTA, Suzuka, Zandvoort, the 2026 layouts of Melbourne, Monza and Silverstone, and Imola and the Nordschleife through CSP's own configurations. It depends on each track's version and configuration.
  - Elsewhere, this section never changes the AC flag.
- **Colours**, by priority (each track's configuration sets the exact colours):

| Panels | When |
| --- | --- |
| Red | Red flag, only when AC's own flags are hidden in CSP (**Hide race flags**): the red value is AC's black flag in its own display. Otherwise yellow. |
| Yellow | A yellow zone ahead of you, Safety Car, VSC, FCY, the relaunch lap after a red flag |
| White | A slow vehicle ahead of you |
| Orange | Slippery track (rain starting, 30 s) |
| Blue | A car lapping you is behind you (race) |
| Green | At the end of a neutralisation and at a restart (5 s by default), at the end of a yellow zone (3 s by default); see **Green duration (s)** |
| AC's own | Nothing to report, your last lap in a lap race (AC's white flag), the finish (AC's chequered flag) |

- **AC's own flags are never covered** when they are up: blue, white, black or chequered; over AC's yellow, only yellow or red. While the app shows a colour, AC's own flags come back when it ends.
- **Changes.** A more important colour is shown at once; a less important one, or handing back to AC, after **Delay before a less important colour (s)**, 1.5 s by default (track configurations ignore shorter states). The track check and every change are logged (`panneaux lumineux du circuit: …`).
- **AC's own display.** If AC's flags are shown (not hidden in CSP), its flag icon also shows the yellow, blue and green of the panels; the window says so. The **AC native yellow flag on the HUD** preference still applies on a track that is not equipped, or with the section unticked for the profile in use (it is greyed otherwise).
- **Fixed in Beta 1.34.** In your Imola session on Beta 1.32, the panels never lit: AC keeps its own start flag up for a long time (the whole session in hotlap), and the app refused to write over it, without a word in the log. The start flag no longer blocks the panels. Every wanted colour that cannot be written is now logged once with its cause (`panneaux lumineux du circuit: jaune voulu, non ecrit (drapeau natif 12)`, `capacite missing`, `echec: …`), and every change of AC's own flag is logged (`drapeau d AC: 1 (depart)`). The track configuration is now also read when no section is ticked.
- **Not confirmed in game yet.** The SDK marks the slippery (3) and slow vehicle (6) values as *does not work yet* for AC's own display; whether the panels show them, and red (5), is to be checked in game.

### Companion apps (SpotterEnginer bridge)

AdvancedIA can share its live state with a companion app, today **SpotterEnginer** (voice spotter and race engineer).

- **Only when SpotterEnginer is installed**: at launch the app checks once for `apps/lua/SpotterEnginer/manifest.ini`. If it is absent, nothing is opened or computed and the journal says `pont des apps compagnes: SpotterEnginer absent, pont inactif`; AdvancedIA behaves exactly as without the bridge.
- **When it is installed**: two shared structures are opened with `ac.connect` (`ACAdvancedIA.Bridge.Hello` and `ACAdvancedIA.Bridge.Data.v1`, layout in `src/bridge_layout.lua`, identical in both apps) and the engine state is copied into them every frame, read only: flags and neutralisations, the delta, the player's penalties, the pit window, the AI sanctions and stops. Journal: `pont des apps compagnes: ouvert (version 1)`.
- **Announcements** (`messageId`, `messageKind`, `messageValue`, `messageExtra`, `messageTitle`, `messageText`): one per event, in the app's language. Silent kinds (never a message at the top of the screen; re-sent on the next frame if another announcement takes their frame): `pitCompound`, `pitPlanSame`, `pitNotCounted`, `pitValidated` (F1 compound change, Beta 1.49), `pitPlanOk` (strategy fixed after a « same compound » warning; value = fitted compound index, extra = planned one; Beta 1.50); `scOut` (Safety Car on track, sent in the same frame as `safetyPhase` becoming `out`; value = AC index (0-based) of the first car behind it, -1 if none, extra = gap in m), `scLeading` (queue formed behind it; value = AC index of the first car, extra = gap in m), `restartPlace` (race, at the red flag and when you leave the pit lane on the relaunch lap; value = your frozen place (1-based), extra = AC index of the car to follow, -1 in P1), `restartRetake` (a car classed behind you is ahead; value = its AC index, extra = your place) (Beta 1.50). Shown kind `fastCar` (Practice and Qualifying, Beta 1.51: a flying AI is coming while you are on an out-lap or cool-down lap; value = its AC index, extra = gap in s). The text names the driver. The internal Safety Car phase `exit` (released, in the pit lane) is published as `call`, as `place` is.
- **Isolation**: the bridge never writes into the engine, the commands or the settings; an error in it closes the bridge alone (`pont des apps compagnes coupe: …`), and it is closed when the app unloads, so the reader sees AdvancedIA as absent at once.

### Beeps

- **Delta: beeps**: F1-style beeps, closer and closer together as the delta nears zero, and very fast when it is negative.
- **Player DRS: beep and panel**: a beep when your DRS becomes available (see [DRS](#drs-and-overtake-mode)).
- **Beeps (DRS and delta): volume (%)**: 25–400%, 200% by default, on top of the game's master volume. It is the same in the cockpit and exterior views; above 100% the sound may clip slightly.
- The sounds are `sounds/delta-beep.wav` and `sounds/drs-available-beep.wav`.

### Custom presets

- On **HOME › CUSTOM PRESETS**, type a name and click **SAVE**. This saves the profile shown (values, enabled sections) and the global options.
- Click the preset's button (name · profile) to load it back, including after a restart. Saving under an existing name replaces that preset.
- **Delete** removes it permanently. The current settings stay applied.
- Limits: 16 presets, and names of at most 64 bytes in UTF-8 (an accented letter counts as two). Saved text is never executed.
- A custom preset is highlighted when the profile matches it exactly.
- Custom presets live in the same CSP storage as the settings, so they survive updates.

### Track zones and class patterns

**No-manoeuvre zones** (optional, per track):
- In **DIAGNOSTICS › Track zones**, drive to the start of a narrow section and click **Mark start**, then **Mark end (no manoeuvres)** at its end. No yielding or overtaking is commanded there.
- **COPY** copies the zones to the clipboard. Paste them into `tracks/<trackId>.lua` in the app folder; no track file is ever changed. The format is:

```lua
return { zones = {
  { from=0.123, to=0.131, noYield=true, noOvertake=true,
    maxOffset=0.4, note="Narrow section" },
} }
```

- The loader never executes the file's Lua. It uses a dedicated data grammar with only the allowed fields, at most 64 zones and 64 KiB. A range that crosses zero is accepted.
- Observed pit positions add a cautious limit around their progress. No zone is shipped for any track.

**Class patterns** (**Classes / Endurance › CLASS PATTERNS**):
- Each pattern is part of the car folder name followed by its class, for example `lmp1:1,lmp3:2,gt3:3`. Enter them in eight separate rows (**Edit the eight pairs**) or in compact form.
- Class 1 is the fastest, 4 the slowest.
- Patterns are literal, case-insensitive substrings of at most 32 characters `[a-zA-Z0-9_-]`. They take priority over the automatic split by pace, and are never executed.

### Diagnostics tab

**DIAGNOSTICS**, left column:
- CSP version, track and spline length.
- **Track light panels**: equipped track or not, and the colour shown (*Disabled* when the section is unticked for the profile in use).
- **Sign calibration**: its state, *Offset / side sign*, and **Rerun sign calibration**.
- **Headlight flashes**: the learned signal, and **Learn headlight flashes (6 s)**.
- **Track zones**: **Mark start**, **Mark end (no manoeuvres)**, **COPY**, and the zone count.
- **UPDATES** (since Beta 1.33), at the top: installed and available versions, the state (for example *You have the latest version (checked at 14:32)*, *Downloading Beta 1.36 (1.0 MB)…*, *Beta 1.36 ready: it installs as soon as you stop*, *GitHub unreachable: check the connection*, *GitHub refuses for now (request limit)*), the first lines of the release notes with **Read everything on GitHub**, **Update** (greyed while you drive; **Cancel** until the copy starts; **Try again** after an error), **Check for updates at launch**, then **Check now** (once a minute at most) and **Roll back to Beta X** side by side.
- **SESSION LOG**: **Write the session log to disk**, with the log's path and size.
- **CSP capabilities**: one row per CSP function the app uses, with its state (*Available, not used yet*, *Call succeeded*, *Missing*, *Disabled after three failures*). Below it: the level mode, the braking-zone and grip notes, and **Exposed AI functions**.

**DIAGNOSTICS**, right column:
- **AI CARS DRIVEN**: one row per AI with **CAR**, **STATE**, **OFFSET**, **LVL / AGG. / CAUT.** and **GAP**. Hover a row for the reason of its state, for example *Overtake aborted: side closed*.
- **Performance**: the AI loop's mean and maximum cost per frame, excluding UI drawing, plus cars, engine errors, API errors and rejected data.
- **Event log**: the last 200 events, with a **FILTER** of **ALL**, **ERROR**, **WARN**, **INFO** or **DEBUG**.

Each area scrolls with the mouse wheel.

### Safety guards and what the app never does

**The app suspends its commands** (and shows why under the status in the header) in these cases:

| Status | Meaning |
|---|---|
| *Online session: commands suspended* | Online, including alt-online |
| *Replay: commands suspended* | Replay |
| *Paused* | Real pause; the garage/setup menu keeps the engine running |
| *Session over* | The session has ended |
| *No AI spline: commands suspended* | No usable AI line on this track |
| *Panic: commands stopped* | **PANIC** pressed |
| *Disabled* | **APP OFF** |
| *Abnormal time step* | A frame took abnormally long |
| *CSP physics access unavailable* | CSP's `physics.allowed()` is false; the app never bypasses a CSP restriction |
| *No section enabled: native AI* | Nothing ticked in this profile |

**Restoring the game.**
- **Panic, switching off or unloading** sets the lateral offset back to zero and restores the original level and aggression.
  - The return to the centre waits for a safe situation if it would cross a car, or if the car is in the pits.
  - CSP offers no way to read the original caution or grip, so they are restored to 1 and to the SDK base of 1.2.
- **On unload**, everything is restored at once, even in pause, in the pits or off track: level, aggression, caution, grip, speed cap, brake, wet tyres, pit request, forced stop, parked Safety Car, player flag, AC session box and messages.
- **In a replay**, AC does not simulate the cars, so nothing can be commanded to them. An unload during a replay leaves the values in place until the app is next loaded in the same session, which restores them through a temporary recovery store.
- The lateral offset is never judged from replay positions.

**Errors.**
- Three consecutive failures disable a CSP function.
- An error on one car isolates that car for 5 s; three failed attempts in a row exclude it until the next session.
- A display error is logged once and never stops the engine.

**What the app never does:**
- It never drives **your** car: no steering, throttle or braking. The front radar only acts on AI. The only things it can do to your car are AC's own native penalties (throttle cut, black flag), disabling DRS under the racing rules, and AC's native yellow HUD flag if you ask for it.
- It never changes a track, car or `surfaces.ini` file, and needs no script installed on the tracks.
- It contacts no server but GitHub: one request per launch to `api.github.com` (turn it off with **Check for updates at launch**), and the release files on `github.com` only when you click **Update**. It only writes inside its own folder (`backup/`) when updating.
- **The only CSP settings it changes** are two display options of `[HIDE]` in `Documents/Assetto Corsa/cfg/extension/gui.ini` while it is active (Beta 1.40, see [CSP display options](#csp-display-options)), and the `[AI_FLOOD]` section of `Documents/Assetto Corsa/cfg/extension/new_behaviour.ini`, on Track days with an AI distribution other than **Native (game)**. It saves the original values first and writes them back in **Native (game)** mode. Otherwise it writes only its own CSP state file and its session log.
- It never teleports or force-brakes cars to space them. It does return stopped, disqualified or parked AI to their pit box, and it places AI on track at the session start when **On the whole track** is chosen.
- It never drives Traffic Planner's kinematic cars, nor anything in alt-online modes.
- It never tries to arbitrate another AI app. Known windows of other AI controllers only raise a warning (*Another AI app detected*).
- It never executes text it stores or loads: preset names, class patterns and zone files are parsed as data.

## Settings overview

The settings window uses the same visual style as SuperHUD: a dark background, with blue marking what is active.
- It has no title bar: drag an empty area to move it.
- It follows the pause menu and the app's icon, and scales with its width (900 × 700 by default).
- Changes made from the menu are saved at once, without having to drive again.
- Changing a setting in the garage brings the AI's ongoing manoeuvres back to their base line, with an occupancy check.

### Header

- **ADVANCEDIA** with the version.
- Status line: **ACTIVE** or **INACTIVE** with the profile in use, and below it the reason for a stop (see [Safety guards](#safety-guards-and-what-the-app-never-does)).
- **APP ON** / **APP OFF**, **PANIC** / **RESUME**.
- **FR** | **EN** language buttons.

### Tabs

| Tab | Contents |
|---|---|
| **HOME** | **PROFILE SHOWN AND EDITED** (**TRACK DAY**, **PRACTICE**, **QUALI**, **RACE**, **HOTLAP**), **Automatic profile**, **SESSION** (detected session and its source), **BUILT-IN PRESETS**, the recognised preset, **RESTORE DEFAULTS: <profile>**. On the right: **LIVE STATUS** (AI cars driven by the app, incidents, yellow zones, neutralisation), **TO CHECK** (warnings) and **CUSTOM PRESETS**. The page scrolls with the mouse wheel |
| **SETTINGS** | The sidebar of sections (below). On the right, the chosen section: its title, profile buttons, description, live status lines, **RESET SECTION**, then its settings in two columns |
| **RACING RULES** | On the left: **Racing rules on**, **Mandatory stop in the race**, **Safety Car**, then **CHAMPIONSHIP RULES** (**Base rules**, **F1 2025**, **F1 2026**, **GT**, **Endurance**; *Applied together to Practice, Qualifying and Race*) and **RESET TO DEFAULTS**. On the right, the settings of the selected row |
| **DIAGNOSTICS** | See [Diagnostics tab](#diagnostics-tab) |

### Sidebar of the SETTINGS tab

Each entry except **Overlay** has its own on/off pill for the profile shown.

| Group | Sidebar entry | Section title | What it covers |
|---|---|---|---|
| **DRIVING** | **General** | **General settings** | Level, aggression, caution, braking zone, spreads, AI distribution at session start, CSP AI flood range, staggered pit exits |
| | **Personality** | **Personality and focus** | Reactions, awareness, pace drift, line variation, lapses in focus, pace-based line, driving mistakes |
| | **Lines** | **Lateral movement** | Lateral speed, acceleration, smoothing, maximum offset, straight threshold, anti-weaving pause, release factor |
| | **Start** | **Race start** | Start delay, start caution and aggression, settling time, grid lane hold |
| **TRAFFIC** | **Yielding** | **Yielding** | Standard yielding, side, offsets, detection, holds, invitation, pressure |
| | **Blue flags** | **Blue flags** | Blue flags, range, side |
| | **Headlights** | **Headlight flashes** | Your flashes, AI-to-AI flashes, horn |
| | **Overtaking** | **Overtaking and defending** | Overtaking, side, margins, chaining, held-up logic, pull-out, slipstream, defending |
| | **Spacing** | **Traffic spacing** | Track-day spacing |
| **RACE & SAFETY** | **Accidents** | **Accidents and incidents** | Avoidance, crashed AI stop, yellow flags, double yellow, player flags, messages and beeps, penalties and sanctions |
| | **Track light panels** | **Track light panels** | Circuit status, colours sent to the panels, durations, profiles it is active for |
| | **Classes / Endurance** | **Endurance and classes** | Endurance layer, multi-class, class patterns |
| | **Weather** | **Weather and tyres** | Pace and tyres in the rain, rain compensation |
| **ADVANCED** | **Global options** | **Global settings** | Level mode, grip bonus, front radar, native awareness, detailed log, occupancy, personality seed |
| | **Overlay** | **In-game overlay** | Position, size, look and content of the overlay, AC displays taken over |

### Using the controls

- **Slider**: drag it, or use the **−** and **+** buttons for one step.
- **Choice**: click to cycle through the values (**▸**).
- **Switch**: **ON** / **OFF**.
- **Right-click** a setting to set it back to the default of the profile shown.
- The mouse wheel scrolls a long section.
- **Tooltips.** Every control has one, in the chosen language: what it does, the default for the profile and the range. The decimal mark is a point in English and a comma in French.
- **Settings that do nothing in a profile are hidden**, with a note instead:
  - penalties on a Track day and in Hotlap;
  - the Endurance layer in Practice and Qualifying;
  - the AI distribution in the Race and in Hotlap;
  - the CSP AI flood range outside the Track day.
- The **Mandatory stop in the race** and **Safety Car** views of **RACING RULES** always show the Race profile's settings, the only profile where they act.

### Settings reference

- **Columns.** Practice and Qualifying share the same defaults; Hotlap uses the Track day defaults. "n/a" means the setting is hidden in that profile.
- **Racing rules values** are the profile defaults, which are the **Base rules**. The other rule sets change them, as shown in [Racing rules and rule sets](#racing-rules-and-rule-sets).
- **Sections.** A value only applies when its section is ticked for the profile.
- **Lateral offsets** are fractions of the track half-width.

#### General settings (sidebar: **General**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Level (%)** | 40 – 110 | 95 | 100 | 100 |
| **Aggression (%)** | 0 – 100 | 55 | 45 | 80 |
| **Caution** | 0.5 – 8 | 1.6 | 2.2 | 1.2 |
| **Emulated braking zone (%)** | 50 – 150 | 100 | 100 | 100 |
| **Level spread (%)** | 0 – 20 | 8 | 3 | 2 |
| **Aggression spread (%)** | 0 – 30 | 12 | 8 | 10 |
| **Caution spread (%)** | 0 – 30 | 12 | 8 | 8 |
| **Staggered pit exits, practice and qualifying (s per AI, 0 = free)** | 0 – 30 | 0 | 10 | 0 |
| **AI distribution at session start** | Native (game) / Staggered pit exits / On the whole track | On the whole track | Staggered pit exits | n/a |
| **Spread from (AI)** | 2 – 60 | 10 | 10 | n/a |
| **AI left in the pits at the start (%)** | 0 – 50 | 25 | 25 | n/a |
| **Start gap variation (%)** | 0 – 100 | 100 | 100 | n/a |
| **CSP AI flood range, below the threshold (km)** | 1 – 5 | 1 | n/a | n/a |

#### Personality and focus (sidebar: **Personality**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Minimum reaction (s)** | 0.1 – 2 | 0.25 | 0.2 | 0.2 |
| **Maximum reaction (s)** | 0.1 – 2 | 0.9 | 0.6 | 0.6 |
| **Minimum awareness delay (s)** | 0.2 – 5 | 0.6 | 0.4 | 0.4 |
| **Maximum awareness delay (s)** | 0.2 – 5 | 2 | 1.2 | 1.2 |
| **Slow pace drift (%)** | 0 – 6 | 2 | 1 | 1 |
| **Line variation** | 0 – 0.15 | 0.05 | 0.03 | 0.02 |
| **Brief lapses in focus** | on / off | on | off | off |
| **Minimum interval (s)** | 20 – 900 | 60 | 120 | 120 |
| **Maximum interval (s)** | 20 – 900 | 300 | 600 | 600 |
| **Minimum duration (s)** | 0.5 – 8 | 1.5 | 1 | 1 |
| **Maximum duration (s)** | 0.5 – 8 | 3 | 2 | 2 |
| **Minimum pace loss (%)** | 0 – 25 | 6 | 3 | 3 |
| **Maximum pace loss (%)** | 0 – 25 | 12 | 7 | 7 |
| **Pace-based line** | on / off | on | off | off |
| **Maximum line bias** | 0 – 0.4 | 0.25 | 0.25 | 0.25 |
| **AI driving mistakes (lock-ups, wheelspin)** | on / off | on | on | on |
| **Mistakes: rate (per hour per AI)** | 0 – 6 | 1 | 0.5 | 0.5 |

#### Lateral movement (sidebar: **Lines**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Lateral movement speed** | 0.1 – 1 | 0.3 | 0.3 | 0.45 |
| **Lateral acceleration** | 0.5 – 4 | 1.5 | 1.5 | 2 |
| **Lateral smoothing (s)** | 0.05 – 1 | 0.25 | 0.25 | 0.2 |
| **Maximum offset** | 0.3 – 0.95 | 0.85 | 0.85 | 0.8 |
| **Straight threshold** | 0 – 1 | 0.35 | 0.35 | 0.5 |
| **Yaw rate reference (rad/s)** | 0.2 – 1.2 | 0.5 | 0.5 | 0.5 |
| **Pause between direction changes (s)** | 0.3 – 5 | 1.2 | 1.2 | 1 |
| **Release factor** | 1 – 4 | 2 | 2 | 2 |

#### Race start (sidebar: **Start**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Start delay (s)** | 0 – 30 | 0 | 0 | 2 |
| **Caution at the start** | 1 – 3 | 1 | 1 | 1.3 |
| **Aggression at the start** | 0.2 – 1 | 1 | 1 | 0.8 |
| **Settling time after the start (s)** | 2 – 30 | 12 | 12 | 25 |
| **Hold the grid lane at the start** | on / off | off | off | off |
| **Careful first lap (start and restarts)** | on / off | off | off | on |

#### Yielding (sidebar: **Yielding**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Standard yielding** | on / off | on | on | off |
| **Yield side** | Left / Right / Automatic | Right | Right | Right |
| **Yield offset** | 0.2 – 0.95 | 0.65 | 0.8 | 0.6 |
| **Rear detection (m)** | 30 – 400 | 100 | 200 | 80 |
| **Follower speed advantage (km/h)** | 1 – 30 | 6 | 4 | 6 |
| **Rear horizon (s)** | 3 – 30 | 10 | 12 | 8 |
| **Confirmation (s)** | 0.1 – 2 | 0.6 | 0.4 | 0.5 |
| **Minimum hold (s)** | 0.3 – 5 | 1 | 1 | 1 |
| **Hold after the pass, min. (s)** | 0.2 – 6 | 0.8 | 0.6 | 0.8 |
| **Hold after the pass, max. (s)** | 0.2 – 6 | 2.2 | 1.6 | 1.8 |
| **Slowdown while yielding (%)** | 0 – 20 | 6 | 8 | 6 |
| **Extra slowdown to invite a pass (%)** | 0 – 25 | 10 | 10 | 10 |
| **Maximum yield duration (s)** | 8 – 60 | 25 | 25 | 25 |
| **Reaction to pressure** | on / off | on | on | off |
| **Pressure distance (m)** | 5 – 30 | 15 | 15 | 15 |
| **Pressure duration (s)** | 1 – 15 | 4 | 3 | 4 |

#### Blue flags (sidebar: **Blue flags**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Blue flags** | on / off | off | on | on |
| **Blue flag range (m)** | 50 – 400 | 150 | 200 | 150 |
| **Side under blue flag** | Automatic / Left / Right | Automatic | Automatic | Automatic |

#### Headlight flashes (sidebar: **Headlights**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Headlight flashes** | Never / Lapped cars / Always | Always | Always | Lapped cars |
| **Flash range (m)** | 40 – 250 | 200 | 200 | 150 |
| **Speed advantage for a flash (km/h)** | 3 – 40 | 12 | 8 | 15 |
| **Close-range advantage (km/h)** | −10 – 15 | −5 | −5 | 6 |
| **Request lifetime (s)** | 3 – 20 | 8 | 8 | 8 |
| **First flash missed (%)** | 0 – 40 | 10 | 5 | 10 |
| **Cars reacting** | 1 – 3 | 3 | 3 | 3 |
| **Horn counts as a flash** | on / off | off | off | off |
| **AI-to-AI headlight flashes** | on / off | on | on | on |

#### Overtaking and defending (sidebar: **Overtaking**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Overtaking** | on / off | on | on | on |
| **Overtaking side** | Opposite to yield side / Automatic / Left / Right | Left | Left | Left |
| **Overtaking offset** | 0.2 – 0.95 | 0.7 | 0.65 | 0.6 |
| **Forward detection (m)** | 20 – 200 | 60 | 50 | 50 |
| **Speed advantage to overtake (km/h)** | 1 – 30 | 8 | 10 | 3 |
| **Forward horizon (s)** | 2 – 20 | 6 | 6 | 6 |
| **Clearance after overtaking (m)** | 8 – 40 | 18 | 20 | 10 |
| **Pause after overtaking (s)** | 0 – 10 | 2 | 3 | 1 |
| **Chain overtakes** | on / off | on | off | on |
| **Held-up confirmation (s)** | 0.5 – 10 | 2 | 3 | 1.2 |
| **Held-up pace threshold** | 0.8 – 0.99 | 0.93 | 0.93 | 0.95 |
| **Pull-out distance (m)** | 4 – 15 | 8 | 8 | 8 |
| **Pull-out gain (s)** | 0 – 0.5 | 0.25 | 0.25 | 0.25 |
| **Slipstream** | on / off | on | on | on |
| **Defending** | on / off | on | on | on |
| **Maximum defending offset** | 0.1 – 0.5 | 0.35 | 0.35 | 0.35 |
| **Pause between defences (s)** | 2 – 30 | 8 | 8 | 8 |
| **Defending distance (m)** | 5 – 25 | 12 | 12 | 12 |
| **Break the tow on straights** | on / off | n/a | n/a | on |
| **Tow to break: distance (m)** | 10 – 60 | n/a | n/a | 30 |
| **Minimum straight (m)** | 200 – 1500 | n/a | n/a | 400 |
| **Dirty air behind a car** | on / off | off | on | on |
| **Dirty air: distance (m)** | 5 – 40 | 20 | 20 | 20 |
| **Dirty air: throttle lift in corners (%)** | 0 – 10 | 3 | 3 | 3 |
| **Last-laps urgency** | on / off | n/a | n/a | on |
| **Last laps concerned** | 1 – 10 | n/a | n/a | 3 |
| **Extra aggression (%)** | 0 – 50 | n/a | n/a | 15 |
| **Stronger defence (%)** | 0 – 100 | n/a | n/a | 40 |

#### Traffic spacing (sidebar: **Spacing**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Base gap (s)** | 0.5 – 5 | 2.5 | 2.5 | 2.5 |
| **Distance added per AI (m)** | 0.5 – 5 | 2.8 | 2.8 | 2.8 |
| **Gap variation (%)** | 0 – 50 | 45 | 45 | 45 |
| **Maximum speed reduction (%)** | 2 – 20 | 14 | 14 | 14 |

#### Accidents and incidents (sidebar: **Accidents**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Avoid stopped or crashed cars** | on / off | on | on | on |
| **Obstacle speed (km/h)** | 5 – 50 | 25 | 25 | 25 |
| **Obstacle detection (m)** | 50 – 300 | 150 | 150 | 150 |
| **Level drop near an obstacle (%)** | 0 – 50 | 25 | 25 | 25 |
| **Caution near an obstacle** | 1 – 3 | 1.5 | 1.5 | 1.5 |
| **Avoidance offset** | 0.3 – 0.9 | 0.6 | 0.6 | 0.6 |
| **Recovery after contact** | on / off | on | on | on |
| **Crashed AI stop** | on / off | on | on | on |
| **Minimum stop (s)** | 1 – 15 | 3 | 3 | 3 |
| **Maximum stop (s)** | 1 – 30 | 8 | 8 | 8 |
| **Clear track behind to rejoin (m)** | 30 – 300 | 120 | 120 | 120 |
| **Yellow flags (incident zone)** | on / off | on | on | on |
| **Zone start before the incident (m)** | 50 – 800 | 300 | 300 | 300 |
| **Zone end after the incident (m)** | 0 – 300 | 50 | 50 | 50 |
| **Hold after clearing (s)** | 0 – 60 | 10 | 10 | 10 |
| **Approach deceleration (m/s²)** | 2 – 10 | 5 | 5 | 5 |
| **Double yellow: reference time slower by (%)** | 5 – 200 | 15 | 15 | 15 |
| **Double yellow: Slow Zone speed (km/h, 0 = delta time)** | 0 – 150 | 0 | 0 | 0 |
| **Double yellow: fallback speed, unknown pace (km/h)** | 30 – 200 | 50 | 50 | 50 |
| **AC native yellow flag on the HUD** | on / off | off | off | off |
| **AdvancedIA flag panel while driving** | on / off | on | on | on |
| **On-screen incident messages** | on / off | on | on | on |
| **Delta: beeps** | on / off | on | on | on |
| **Player penalties under flags** | on / off | n/a | on | on |
| **Delta: mini-sector tolerance (s)** | 0 – 1 | n/a | 0.5 | 0.5 |
| **Penalty: throttle cut (s)** | 2 – 15 | n/a | 5 | 5 |
| **Offences allowed before disqualification** | 1 – 20 | n/a | 5 | 5 |
| **AI sanctions under flags** | on / off | n/a | on | on |

#### AI strategy (sidebar: **AI strategy**, Race only)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Individual pit-stop strategy** | on / off | n/a | n/a | on |
| **Tyre wear before stopping (%)** | 30 – 95 | n/a | n/a | 75 |
| **Fuel margin (laps)** | 0 – 3 | n/a | n/a | 1 |
| **Undercut and overcut (reacting to rivals’ stops)** | on / off | n/a | n/a | on |
| **Average risk taking (%)** | 0 – 100 | n/a | n/a | 50 |
| **Spread between strategists (%)** | 0 – 100 | n/a | n/a | 60 |
| **Progressive mechanical failures** | on / off | n/a | n/a | on |
| **Failures: rate (per hour and per AI)** | 0 – 2 | n/a | n/a | 0.05 |
| **Failure: maximum pace loss (%)** | 3 – 30 | n/a | n/a | 12 |

#### AI sanctions (sidebar: **AI sanctions**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Track limits (at least three wheels off)** | on / off | n/a | on | on |
| **Warnings before a penalty (race)** | 0 – 5 | n/a | n/a | 3 |
| **Corner cut with a time gain: throttle cut** | on / off | n/a | n/a | on |
| **Throttle cut (s)** | 2 – 15 | n/a | n/a | 5 |
| **Jump start** | on / off | n/a | n/a | on |
| **Pit-lane speeding** | on / off | n/a | n/a | on |
| **Pit-exit line crossed** | on / off | n/a | n/a | on |
| **Penalty for procedural offences** | Drive-through / Stop-and-go / Time penalty (added to the result) | n/a | n/a | Drive-through |
| **Wrong way: black flag** | on / off | n/a | on | on |
| **Wrong way tolerated (s)** | 2 – 15 | n/a | 5 | 5 |
| **Laps to serve a penalty (then black flag)** | 1 – 5 | n/a | n/a | 3 |
| **Stop-and-go: stop (s)** | 5 – 30 | n/a | n/a | 10 |
| **Time penalty (s)** | 1 – 30 | n/a | n/a | 5 |
| **Unserved penalty added to the result** | on / off | n/a | n/a | on |
| **Give the place back after an off-track overtake** | on / off | n/a | n/a | on |
| **Time to give the place back (s)** | 5 – 30 | n/a | n/a | 15 |
| **AI sanction notices on screen** | on / off | n/a | on | on |

#### Endurance and classes (sidebar: **Classes / Endurance**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Endurance layer** | on / off | off | n/a | off |
| **Multi-class** | on / off | off | off | off |
| **Gap between classes (%)** | 3 – 25 | 8 | 8 | 8 |
| **Class speed advantage (km/h)** | 1 – 15 | 4 | 4 | 4 |
| **Variation between stints (%)** | 0 – 8 | 3 | n/a | 3 |
| **Degradation over a stint (%)** | 0 – 5 | 1 | n/a | 1 |

#### Weather and tyres (sidebar: **Weather**)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Adapt pace to the weather** | on / off | on | on | on |
| **Manage dry and wet tyres** | on / off | on | on | on |
| **On-screen message on a weather change** | on / off | on | on | on |
| **Rain compensation without wet tyres (%)** | 0 – 30 | 15 | 15 | 15 |
| **Out-lap: tyre warm-up** | on / off | off | on | on |
| **Out-lap: level lowered by (%)** | 0 – 15 | 7 | 7 | 7 |
| **Lock-ups linked to tyre wear** | on / off | off | on | on |
| **Lock-ups: gain at the end of a stint** | 0 – 3 | 1.5 | 1.5 | 1.5 |
| **Flat spot: wear added per lock-up (km)** | 0 – 5 | 1 | 1 | 1 |

#### Track light panels (sidebar: **Track light panels**)

Ticked by default in every profile, Hotlap included. See [Track light panels](#track-light-panels).

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Yellow · yellow flag, Safety Car, VSC, FCY** | always on | on | on | on |
| **Red · red flag** | on / off | on | on | on |
| **Blue · blue flag shown to you** | on / off | on | on | on |
| **White · very slow vehicle ahead** | on / off | on | on | on |
| **Orange · slippery track** | on / off | on | on | on |
| **Green · end of zone, neutralisation and restart** | on / off | on | on | on |
| **Green duration (s)** | 0 – 15 (0: no green) | 5 | 5 | 5 |
| **Delay before a less important colour (s)** | 0.5 – 5 | 1.5 | 1.5 | 1.5 |

#### Racing rules: **Racing rules on** view

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **No change of direction under braking** | on / off | on | on | on |
| **Neutralisation after a major incident** | Local yellow zone / FCY: whole track / VSC: reduced pace / Safety Car | Local yellow zone | Local yellow zone | Local yellow zone |
| **Major incident: car stopped on track (s)** | 5 – 60 | 15 | 15 | 15 |
| **FCY: fallback speed, unknown pace (km/h)** | 40 – 150 | 80 | 80 | 80 |
| **FCY: reference time slower by (%)** | 10 – 150 | 50 | 50 | 50 |
| **VSC: reference time slower by (%)** | 10 – 80 | 30 | 30 | 30 |
| **Minimum neutralisation time (s)** | 10 – 180 | 30 | 30 | 30 |
| **Red flag on a serious accident (practice, qualifying, race)** | on / off | on | on | on |
| **Red flag: cars stopped on track** | 2 – 10 | 3 | 3 | 3 |
| **Red flag: fallback speed, unknown pace (km/h)** | 40 – 150 | 80 | 80 | 80 |
| **Red flag: reference time slower by (%)** | 10 – 200 | 60 | 60 | 60 |
| **Red flag: minimum suspension (s)** | 20 – 600 | 60 | 60 | 60 |
| **Red flag: tyres changed in the pits (stop counts)** | on / off | off | off | off |
| **Restart after a red flag** | Rolling start (RS) behind the Safety Car / Standing start (SS) from the grid | rolling | rolling | rolling |
| **Overtake Mode (F1 2026, within one second at detection)** | on / off | off | off | off |
| **Overtake Mode: detection gap (s)** | 0.3 – 2 | 1 | 1 | 1 |
| **Overtake Mode: level gain (%)** | 0 – 5 | 2 | 2 | 2 |
| **Player DRS: beep and panel** | on / off | on | on | on |
| **DRS: racing rules (rain, flags, start, Safety Car, red flag)** | on / off | off | on | on |
| **DRS: leader laps before enabling (start, SC, red flag)** | 0 – 5 | 1 | 1 | 1 |
| **AI DRS: opened in the zones** | on / off | on | on | on |
| **Beeps (DRS and delta): volume (%)** | 25 – 400 | 200 | 200 | 200 |
| **BoP: pace evened out within each class** | on / off | off | off | off |
| **BoP: maximum correction (%)** | 0 – 5 | 2 | 2 | 2 |
| **Pro-Am driver ratings (Bronze to Platinum)** | on / off | off | off | off |
| **Slower class: predictable line** | on / off | off | off | off |

#### Racing rules: **Mandatory stop in the race** view (Race profile)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Mandatory stops in the race** | 0 – 3 | 0 | 0 | 0 |
| **Window opens (% of race)** | 5 – 95 | 25 | 25 | 25 |
| **Window closes (% of race)** | 5 – 100 | 75 | 75 | 75 |
| **New tyres at every stop (pit rules active)** | on / off | on | on | on |
| **Repairs at every stop in the race (bodywork, suspension, engine)** | on / off | on | on | on |
| **Change dry compound (F1)** | on / off | off | off | off |
| **Minimum stop time (s, 0 = free)** | 0 – 120 | 0 | 0 | 0 |
| **Maximum stint (min, 0 = free)** | 0 – 240 | 0 | 0 | 0 |
| **Fuel at enforced stops** | Refuel at the stop / Race fuel from the start / Left to AC | Refuel at the stop | Refuel at the stop | Refuel at the stop |
| **Pit lane closed under neutralisation** | Always open / Closed under FCY / Closed under FCY and for 3 Safety Car laps | Always open | Always open | Always open |
| **Pit window opening message** | on / off | on | on | on |

#### Racing rules: **Safety Car** view (Race profile)

| Setting | Range | Track day | Practice / Qualifying | Race |
|---|---|---|---|---|
| **Safety Car speed (km/h)** | 60 – 250 | 120 | 120 | 120 |
| **Safety Car if the incident escalates** | on / off | off | on | on |
| **Overtaking allowed after the restart** | At the control line / As soon as the Safety Car pits | at the line | at the line | at the line |

#### Global settings (sidebar: **Global options**, shared by all profiles)

| Setting | Range | Default |
|---|---|---|
| **Requested level mode** | **Automatic** / **Native if confirmed** / **Grip bonus allowed** / **Cap at 100%** | **Automatic** |
| **Allow the grip bonus** | on / off | off |
| **Front radar (light extra braking)** | on / off | on |
| **Override native AI awareness** | on / off | off |
| **Detailed log** | on / off | off |
| **Occupancy: lateral threshold (m)** | 0.1 – 1 | 0.3 |
| **Occupancy: lateral reach (m)** | 2 – 8 | 5.5 |
| **Occupancy: margin (m)** | 2 – 15 | 6 |
| **Occupancy: speed gain (s)** | 0 – 2 | 0.8 |
| **Grip bonus per level point** | 0 – 0.01 | 0.004 |
| **Personality seed** (**Regenerate personalities**) | 0 – 2147483647 | 19731019 |

#### In-game overlay (sidebar: **Overlay**, shared by all sessions)

| Setting | Range | Default |
|---|---|---|
| **UNLOCK · MOVE · SIZE** / **LOCK THE POSITION** | locked / unlocked | locked |
| **PUT BACK ON SCREEN** | button | centred at the top, 1.00x |
| **Size** | 0.50x – 2.50x | 1.00x |
| **Background** | **OPAQUE** / **DIMMED** / **TRANSPARENT** | **OPAQUE** |
| **Background opacity** | 0 – 100% | 86% |
| **Display** | **Only with information** / **Always** | **Only with information** |
| **Information: display time** | 0 (**While they last**) – 60 s | **While they last** |
| **Content opacity** | 30 – 100% | 100% |
| **Session info (position, lap, time, best lap, fuel, stop)** | on / off | on |
| **Flag explanations** | on / off | on |
| **End of race summary** | on / off | on |
| **Replace the AC session box (lap, time, RACE OVER)** | on / off | on |
| **Show AC messages on the overlay** | on / off | on |
| **Hide the original AC messages** | on / off | on |
| **Hide AC system messages (CSP option)** | on / off | on |
| **Hide AC's own flags (CSP option)** | on / off | on |
| **Click-through when locked** | on / off | on |
| **Hide in replays** | on / off | on |
| **Hide in the pits** | on / off | off |

## Session log

**Where it is.** Every launch of the game writes `Documents/Assetto Corsa/logs/AdvancedIA.log`. **DIAGNOSTICS › SESSION LOG** shows its exact path and size.

**Rotation and size.**
- Reloading the app within the same launch carries on in the same file.
- At each new launch the previous files shift: the three previous launches are kept as `AdvancedIA.1.log` (the most recent) to `AdvancedIA.3.log`.
- The file is capped at 4 MB per launch.
- **Write the session log to disk** (Diagnostics, on by default) switches it off. **Detailed log** (Global options) adds every AI state change.

**What it contains.**
- New lines are added every two seconds and at shutdown. Each one has the real date and time, the engine time in seconds, the level (INFO, WARN, ERROR), the car index (-1 when no car is concerned) and the event.
- Events cover the session and profile, incidents and yellow zones, crashed AI, neutralisations, the Safety Car, pit stops, tyres, fuel and repairs, headlight flashes between AI, contacts, blue flags, the weather, your flags and penalties, lost CSP capabilities and errors.
- A summary is written every minute: the AI states at that moment, plus the counters of the past minute (overtakes attempted, completed and aborted with their reasons, yields, yields where nobody passed, defences, avoidances, contacts, recoveries after a contact, flashes, anti-weaving blocks, incidents, stopped AI, AI tyres, AI DRS openings).

**The log is written in French**, even with the English interface, and without accents. The most useful lines to search for:

| Line starts with | Meaning |
|---|---|
| `=== AdvancedIA Beta … : lancement` | Start of a game launch, with the app version |
| `compilateur JIT:` | Whether the enlarged JIT cache is in use (all cars driven in one protected call) or not (one by one) |
| `AI flood de CSP au lancement:` | CSP AI flood state as loaded by CSP at this launch (`actif` / `inactif`) and its minimum track length |
| `session:` | Detected session: index, CSP type, race.ini type, `(Track Day)`, track, number of cars, spline length |
| `profil:` | Profile in use (`J` Track day, `P` Practice, `Q` Qualifying, `C` Race, `H` Hotlap), `(automatique)` or `(manuel)` |
| `onglets:` … `; regles:` | Sections ticked in this profile, and the rule set recognised (`base`, `F1`, `F1_2026`, `GT`, `Endurance`, `personnalisees` = custom, `decochees` = off) |
| `sens lateral:` | Lateral direction. `-1 / -1` is expected; `0 / 0 (en attente de mesure, aucun deplacement lateral)` means no lateral move is written yet |
| `repartition des IA` | AI distribution at session start: plan, cars placed (`posees en piste sur … prevues`), check after 3 s (`roulent normalement` / `en difficulte`); since Beta 1.28 each car in trouble is named with its model and the reason (`aux stands` in the pits, `hors piste` off track, `lente` slow, `glissade` sliding) |
| `depassement` / `depassement fini` | Since Beta 1.31: each overtaking attempt the app starts (`depassement: A -> B (trigger, gap, speed difference)`; trigger `rapprochement` closing, `retenue` held up, `invitation`, `cession` the car ahead yields, `cible lente` an abnormally slow AI ahead, since Beta 1.41) and how it ended (`reussi`, `cible plus rapide`, `cote ferme`, `sans rapprochement`, `suiveur rapide`, `cible perdue`, `drapeau jaune`…; since Beta 1.41 also `rendue a AC` handed back to AC: pits, off track or not driven, `cede a son suiveur` yielded to its follower, `evitement d un obstacle`, `contact, reprise au calme`, `tete-a-queue`), after how long and the minimum gap. Since Beta 1.41, after a `cible plus rapide` the app leaves that target alone for 45 s, then 180 s, then 600 s, except for a real closing move or an abnormally slow target |
| `tete-a-queue, contexte` | Since Beta 1.31: what the app was commanding an AI just before it spun: state and for how long, time since its last manoeuvre, lateral offset, caution and aggressiveness against their usual values, level, slipstream, app braking |
| `drapeau d AC:` | Since Beta 1.34: every change of AC's own race flag while the app does not set it (`1 (depart)`, `2 (jaune)`, `12 (bleu)`…), to check the track light panels in game |
| `capacite <name>: echec (…)` / `capacite <name>: coupee apres 3 echecs` | Since Beta 1.34: the first failure of a CSP function the app uses, with CSP's error text, and when the app stops using it after three failures (once per launch) |
| `relance:` / `grille:` / `feux:` | Since Beta 1.34: how a race restarts after a red flag (`relance: depart arrete (SS)`, `relance arretee indisponible (<reason>): depart lance`), the grid (`grille: formation, 12 voitures, 24 places (AC_START)` or `places calculees`, `grille: delai maximal`), the lights (`feux: allumage`, `feux eteints apres 6.4 s: depart`), `faux depart du joueur`, `depart arrete annule: nouvel incident` |
| `panneaux lumineux du circuit:` | Since Beta 1.32: light panels found in the track configuration or not (`detectes (extension\ext_config.ini)`, `non detectes`; since Beta 1.41 followed by how many files were read and how many includes were not read: not found, outside the track and CSP folders, beyond the limit), then each colour the app shows on them and why (`jaune (drapeau jaune)`, `bleu (drapeau bleu)`, `rendus a AC`); since Beta 1.47, `drapeau 5 de l app encore affiche apres restitution, restitution renvoyee` when CSP keeps showing the app's last flag after handing it back, then (WARN) `… remplace par le drapeau de depart d AC` after 3 restores |
| `vehicule lent devant le joueur` | Since Beta 1.32: white flag; the slow car, its speed and how far ahead of you |
| `avertissement du joueur` | Since Beta 1.32: your last tolerated infringement (black-and-white flag) |
| `voiture du joueur endommagee` | Since Beta 1.32: black flag with an orange disc, with the damage read |
| `mise a jour` | Since Beta 1.33: the launch check (`mise a jour disponible: Beta … (publiee le …, … octets)`, `… est la derniere version`, `aucune version publiee sur GitHub`), each install step (download, `empreinte verifiee, sauvegarde de la …`, `installation de la …`, `… installee, commandes des IA rendues a AC et redemarrage de l app`), refusals and errors (`refusee en conduite`, `echec reseau (statut …)`, `empreinte SHA-256 differente`, `contenu du paquet refuse`, `ecriture impossible`, with `version actuelle conservee`), rollback, recovery at launch (`installation interrompue (…), sauvegarde remise en place`) and, after the restart, `mise a jour reussie: A -> B` |
| `invitation du joueur non suivie` | Since Beta 1.30: you moved aside right in front of an AI (at least 2 m, within 40 m) and it has not started to pass after 3 s. The line gives the distance, the lateral gap, the speed difference, both yaw rates and the reason (yellow flag, braking, corner, rest after a manoeuvre, anti-zigzag cap, car alongside, too slow, `joueur plus rapide` you were pulling away, `virage` a corner tighter than 0.4 g outside the race since Beta 1.44…) |
| `appel de phares du joueur` | Since Beta 1.29: each of your headlight flashes, with the AI targeted within the flash range, the nearest one (distance, your speed advantage), how many saw it and how many understood it; `cede sur appel de phares du joueur` is logged when an AI yields to it |
| `IA anormalement lente` | Since Beta 1.41: the AI at the head of a slow queue, running below 60% of its own usual pace at that spot (its class's learned pace corrected by its usual relative pace, `habituelle de l IA`; a slow road car among GT cars is never reported), for 20 s with a car stuck behind it (within 60 m). After 5 s it is an obstacle the cars behind drive around (line `IA lente a contourner:`). Damaged (suspension 0.2 or body 150) and slow for 30 s: `endommagee …, ramenee a son stand (le deplacement la repare)` (track day, practice, qualifying: brought back to its pit, the move repairs it) or `arret aux stands demande` (race: pit stop requested; once per session when the Rules tab is unticked). While the AI's own usual pace is still unknown (its first 20 s of free driving), the line is written from its class pace as in Beta 1.39 (`habituelle de l IA inconnue, diagnostic seulement`) and nothing is commanded. The line gives the driver, the car model, the speed, the class pace, the cars queued behind, the AI state, whether the app commands it, any speed limit the app imposes, the damage (body, suspension, engine, gearbox), its position, its pedals and the app's brake and pit request. The end line gives the real reason: `roule de nouveau normalement` (back to its pace) or `ne retient plus le trafic … (rentree aux stands, hors piste, roule au pas, plus aucune voiture derriere…)` |
| `IA lente a contourner` | Since Beta 1.41: the moment an abnormally slow AI becomes an obstacle for the cars behind (its speed, its usual pace, the cars queued behind) |
| `sorties des stands etalees` / `sortie des stands:` | Staggered pit exits: the draw, then each AI's planned turn and actual exit (`attente annulee` = left early) |
| `AI flood de CSP:` | The app changed CSP's AI flood (`desactive` = off, `active` = on, `reglage d origine rendu` = original restored), effective at the next launch |
| `resume:` | Summary every minute. Since Beta 1.41: `abouties` counts only yields where a follower really passed, `cessions sans passage` the others, `contacts` real contacts between cars (once per pair every 10 s) and `reprises au calme` the recoveries after a contact |
| `cout par image mesure par:` | Since Beta 1.41: the clock used for the cost per frame shown in the summary (`compteur Windows`, `os.preciseClock`, or `os.clock (1 ms)`, whose maximum is rounded to the millisecond) |
| `jonction des stands:` | Since Beta 1.41: the pit exit merge point learned from the first car leaving the pit lane (`relevee a … m`), each AI held at the end of the pit lane while a car on track arrives (`X attend Y (a la jonction dans … s, … m avant elle)`) and its release (`repart apres … s (piste libre / attente maximale)`, 10 s at most). The hold is for track day only |
| `depart: peloton a` | Race start measurement: field speed after the start delay, radar brake applications |
| `incident:` / `neutralisation:` / `drapeau rouge:` | Incidents, neutralisations (FCY, VSC, Safety Car, with the reason) and red flags |
| `voiture de securite:` | Safety Car phases: parked, released, `sortie de son stand apres … s`, `en piste`, `rentre ce tour` |
| `drapeau bleu:` | Blue flags given to you |
| `contact:` | Contacts between cars (at most 3 lines per second between AI; always those involving you) |
| `erreur de pilotage:` | An AI driving mistake |
| `pneus poses:` / `reparations` / `carburant` | Tyres fitted (compound and previous one), repairs made, fuel requested and fuel before/after the stop |
| `penalite du joueur:` / `disqualification du joueur:` | Your penalties and disqualification |
| `messages d AC:` | Whether hiding AC's original messages works at this launch |
| `profils mis a jour` / `premiere installation` | Settings migrated after an update / first installation defaults |
| `capacite CSP desactivee apres trois echecs:` | A CSP function was disabled after three failures |
| `fin de course:` | Your end-of-race summary |

**Sharing it when reporting an issue:**
1. Reproduce the problem, then note the approximate time (each log line carries the real clock time).
2. Close the game, or at least end the session, so the last lines are written. If you have restarted the game since, the session you want is in `AdvancedIA.1.log` (or `.2`, `.3`).
3. Open an issue on this repository and attach the log file (zip it if it is large). Add:
   - the app version, your CSP version (shown in **DIAGNOSTICS**), the track, the cars;
   - the Content Manager mode and session type, the number of AI;
   - what you expected and what happened.

**Lines added in Beta 1.42**:

| Line | Meaning |
|---|---|
| `strategie: X plan n arret(s), prochain vers le tour l (pneus\|carburant), risque r %` | X's plan to the finish and what limits its stint. |
| `strategie: X arret demande (cause)` / `strategie: X reste dehors (overcut sur Y)` | The strategist calls X in (tyres, fuel, undercut, covering an undercut, neutralisation, failure), or keeps it out. |
| `tour de sortie: X pneus a chauffer (niveau -x %)` | X's out-lap after a stop, slightly slower. |
| `usure: X blocage, pneu … +km km (usure w %, asymetrie a %)` | A lock-up added a flat spot to that tyre. |
| `panne: X kind (perte x % sur t s), retour aux stands` / `panne: X reparee aux stands` | A progressive failure, and its repair. |
| `aspiration: X casse l aspiration de Y (gap m, ligne droite len m)` | A leader breaks a direct rival's tow with one move. |
| `usure des pneus: echelle verifiee sur X (a % a b % en n tour(s))` / `usure des pneus non fiable ici (X : w % apres n tours) : ni arret pour les pneus, ni blocages lies a l usure` | Tyre wear scale checked in game, or judged unreliable on this car/track. |
| `strategie: X arret retenu jusqu a l ouverture de la fenetre obligatoire` | A non-critical stop waits for the mandatory window. |
| `strategie: X pneus non changes a l arret (usure w %) : plus d arret pour les pneus` / `strategie: X pas de carburant ajoute a l arret : plus d arret pour le carburant` | A stop changed nothing: that cause is not asked again. |
| `resume: … \| aspiration cassee n (finies n), air sale n` | Minute summary, written only when not zero. |
| `fin de course: n derniers tours, agressivite +x %, defense +y %` | Last-laps urgency has started (once per session). |
| `tour invalide IA: X (secteur n[, dernier secteur : tour suivant aussi])` | Practice or qualifying: X's lap invalidated by the app. |
| `limites de piste IA: X avertissement k / n` / `… zone ignoree a m m …` / `… X, sanction annulee (zone ignoree)` | Track-limit warning; a place where the AI line leaves the limits; a warning taken back. |
| `sanction IA: X penalite de temps +s s (reason), total +s s` | Time penalty in the corrected classification. |
| `sanction IA: X coupure des gaz s s (virage coupe, gain g s)` | Throttle cut for a corner cut with a gain. |
| `sanction IA: X drive-through\|stop-and-go (reason), a purger en n tours` / `sanction IA purgee: X …` | Penalty to serve in the pits, and served. |
| `sanction IA: X drapeau noir (contresens\|penalite non purgee\|trop d infractions)` | Black flag: the AI is parked at its box. |
| `stands IA: X a v km/h dans la voie (limite l km/h)` / `stands IA: X sortie de la voie m m avant la jonction` | Pit-lane speeding; pit-exit line crossed. |
| `passage de penalite a l emplacement: X, non compte comme arret` | A penalty pass at the box: not a stop. |
| `place a rendre IA: X doit rendre la place a Y (s s)` / `place rendue IA: …` / `… annulee (cause)` | Place to give back after an off-track overtake. |
| `faux depart IA: X, m m, v km/h, s s avant l extinction` | AI jump start at the app's standing start. |
| `classement corrige (le classement d AC reste inchange): …` | The app's corrected classification (only with a time penalty). |

Summary counters: `tow` and `tow_end` (tows broken and ended), `dirtyAir` (dirty-air episodes).

## Compatibility and known limitations

**What the app drives.**
- The classic physical AI opponents exposed by CSP (`ac.getCar`), in offline sessions.
- Traffic Planner's kinematic cars and alt-online modes are not driven. Earlier links to Traffic Planner were removed.
- There is no dependency on or integration with RARE. Pure is not a code dependency either: weather data comes from CSP. Real-world testing with Pure is still listed as open in [docs/VALIDATION.md](docs/VALIDATION.md).
- **Other AI apps**: known windows of other AI controllers raise a warning (*Another AI app detected*). Their presence does not prove they actually drive the AI, and the app does not try to arbitrate their commands.
- **CSP access**: what the app can do is whatever `physics.allowed()` grants. It never bypasses a CSP restriction.
- Tracks need no script and no file is changed. Per-track no-manoeuvre zones are optional.

**Known limitations.**
- **AI turn signals cannot be driven from an app** in CSP 0.3.0-preview675: `ac.setTurningLights` only drives the player's car, and the per-car control has no indicator field.
- **Red flag and penalties.**
  - AC has no native red flag; AdvancedIA shows its own on the overlay. AC cannot suspend a race, so its clock keeps running during a red flag.
  - AC adds no time to the classification, so penalties are native throttle cuts (no drive-through or stop-and-go imposed by the app). They need race settings that allow that penalty.
- **FCY and Slow Zone** are judged on the delta time (average over each mini-sector of about 250 m), as with the F1 delta. They are not an 80 km/h limiter.
- **F1 2026**:
  - Active aero is rendered through AC's DRS on cars that have one, with no wait.
  - Overtake Mode is emulated for the AI only, through their level.
  - Parc fermé, track limits and the pit exit line remain AC's.
- **DRS** is disabled and restored by the app according to the rules (`physics.allowCarDRS`), and opened for the AI in the zones (`physics.setCarDRS`). GT3 and WEC cars have no DRS in reality.
- **AI driving mistakes.** CSP does not document the exact effect of the wheelspin "severity" (`physics.setAITractionMistake`). Its value (1.4) and the default rate are still to be confirmed in game.
- **The braking zone is emulated** through caution: the CSP SDK exposes no AI braking distance, and `setAIBrakeHint` is not a distance API.
- **A level above 100%** depends on CSP accepting it natively. Otherwise the grip bonus (opt-in) or the 100% cap applies.
- **The Safety Car must be on the Content Manager grid.** Extra copies of its model appear in the driver list and classification, even though they never race. Its exit from the pit box (reworked in Beta 1.25) is not yet confirmed in game.
- **The spacing speed cap** is restored to "unlimited": a cap set by another app cannot be restored exactly. How quickly the distances converge depends on the native driving and remains to be observed in game.
- **CSP AI flood changes** only take effect at the next launch of the game.
- **Several CSP functions have only been verified offline** (HUD flag, forced stop, AI headlight flashes, parked car, return to pits, among others). See [docs/VALIDATION.md](docs/VALIDATION.md).
- **Performance.**
  - The app enlarges the JIT compiler cache of its virtual machine and then drives all cars in one protected call. If CSP does not expose that option, it drives them one by one, as before (`compilateur JIT` line in the log).
  - The offline benchmark of Beta 1.26 measured 0.21 ms per frame for 30 AI and 0.55 ms for 60 AI. That bench does not replace an in-game measurement, and the version number is no FPS or physics guarantee.
- **Language.** The session log is written in French (without accents), whatever the interface language; the documentation is in English.

## Troubleshooting

**The settings window does not appear.**
- It only shows in the pause menu (Esc) or the setup/pits screen, and closes itself while you drive.
- Check that the folder is exactly `assettocorsa/apps/lua/AdvancedIA` (with `manifest.ini` directly inside, not `AdvancedIA-main` or a nested folder), and that CSP is enabled.
- The app also has an icon among the setup screen's settings apps.

**The status says "No section enabled: native AI".** The profile in use has no section ticked. This is normal on a Track day after a first installation. Load a built-in preset on **HOME** (for example **Nordschleife Touristenfahrten**) or tick sections in **SETTINGS**.

**The AI never move aside, pull out or avoid anything.**
- Check **DIAGNOSTICS › Sign calibration**: *Offset / side sign* should read **-1 / -1**. The log line `sens lateral:` gives the same information.
- With `0 / 0`, no lateral move is written until two isolated AI on a straight allow the measurement. Click **Rerun sign calibration** on a long straight.
- Also check that the sections concerned (**Yielding**, **Overtaking**, **Accidents**, **Lines**) are ticked for the profile in use.

**On a track day, all the AI are bunched around me, or appear and disappear.**
- That is CSP's AI flood (tracks of 7 km and more). The app switches it off from 10 AI, but CSP only reads the setting at launch: **restart the game from Content Manager**.
- Check the log lines `AI flood de CSP au lancement:` and `repartition des IA`.
- **AI distribution at session start** must be **On the whole track**, with the Track day profile active and at least one section ticked.

**The AI on a track day hold each other up in queues.**
- Tick **Spacing** (or load **Nordschleife Touristenfahrten**).
- An AI right behind another only yields to a car at least 15 km/h faster; your own headlight flash is always honoured.

**An AI I am lapping will not let me by.** Blue flags only act in a race with the **Blue flags** section ticked (it is in **Realistic race**). Sit within 40 m behind it: since Beta 1.24 the blue flag stays waved even at equal speed, and the AI moves over at a corner exit. A slower car on the same lap is not shown a blue flag; overtake it.

**My headlight flashes are ignored.** Learn them first (**DIAGNOSTICS › Learn headlight flashes (6 s)**), or use **Horn counts as a flash**. Then check the **Headlight flashes** mode (**Lapped cars** in the race by default) and the speed advantage required.

**AC's own flags appear on top of the overlay.** The app ticks CSP's **Hide race flags** for you (**Hide AC's own flags (CSP option)**, Overlay section); CSP may only apply it at the next game launch. If the status line says the options cannot be changed, tick "Hide race flags in the top left corner" yourself (Content Manager › Custom Shaders Patch › GUI).

**The overlay is off screen or the wrong size.** **SETTINGS › ADVANCED › Overlay › PUT BACK ON SCREEN**.

**AC messages appear twice, or not at all.**
- **Hide the original AC messages** and **Hide AC system messages (CSP option)** (Overlay section) hide the original display; both are on by default. AC's red cut and penalty banners (*CUT DETECTED*, *PENALTY…*) cannot be hidden through CSP: AC keeps drawing them, and since Beta 1.41 the overlay does not duplicate them (log `messages d AC: penalites et coupes laissees a l affichage d AC`).
- If hiding would also remove them from the overlay, the app lifts it until the next launch (log line `messages d AC:`).

**The Safety Car never comes out.**
- Its model must be on the grid (by default the **Ferrari 458 Italia Stage 3**, `ferrari_458_s3`). The Racing rules tab warns you during the race when it is missing.
- **Safety Car** must be on in **RACING RULES**.
- Without it, the VSC or FCY carries on.

**I am never penalised.**
- Penalties never apply on a Track day or in Hotlap.
- Check **Player penalties under flags** (Accidents section, which must be ticked) and that your race settings allow AC's throttle-cut penalty.

**Practice takes long before all the AI are out.** **Staggered pit exits** sends them out one by one. Set **Staggered pit exits, practice and qualifying** to 0, or **AI distribution at session start** to **Native (game)**.

**The AI do not change tyres in the rain.** Tick **Weather** for the profile and check **Manage dry and wet tyres**. Cars whose catalogue has no wet compound get the bounded **Rain compensation without wet tyres (%)** instead.

**A mandatory stop was not counted.** Stops made with the pit lane closed, or outside the window, do not count. A recovery to the pits does not count either, except under a red flag.

**I want the original AI back right now.** **PANIC**, or **APP OFF**.

**I changed many things and want a clean start.** See [Resetting the settings](#resetting-the-settings).

## Development and tests

### Project structure

```
AdvancedIA.lua        entry point: per-frame update, settings window, IN_GAME overlay callback, restore on unload
manifest.ini            CSP app manifest (name, version, settings window, overlay callback)
icon.png                app icon (64×64; the 512×512 original is docs/icon-512.png)
src/                    the HumanAI engine and its interface
  snapshot.lua            reads the game state (the only module reading ac/physics, with applier)
  applier.lua             writes the commands to CSP, storage, session log, restore (the only writer)
  engine.lua              orchestration of a frame: profiles, guards, traffic, incidents, pits, weather, overlay data
  director.lua            per-car state machine (drive, yield, overtake, defend, avoid, recover)
  perception.lua          neighbours and side occupancy
  persona.lua             deterministic driver personalities
  traffic.lua             track-day spacing, AI distribution at session start, staggered pit exits
  flood.lua               CSP AI flood settings ([AI_FLOOD] of new_behaviour.ini), pure text handling
  cspgui.lua              CSP display options held by the app ([HIDE] of gui.ini), pure text handling
  incidents.lua           incidents, yellow flags, neutralisations, Safety Car, red flag
  penalties.lua           player penalties and AI sanctions
  delta.lua               delta time
  pits.lua                mandatory stops, tyres, fuel, repairs
  weather.lua             rain detection and tyre decisions
  classes.lua             laps, classes, multi-class
  mistakes.lua            AI driving mistakes
  flash.lua               headlight flash detection and learning
  calibration.lua         left/right sign calibration
  caps.lua                CSP capability detection and failure handling
  zones.lua               no-manoeuvre zone data grammar
  hudinfo.lua, panel.lua  overlay decisions (session line, lap line, recap, flags), no drawing
  lights.lua              track light panels, slow vehicle ahead, player damage, track configuration parsing (files read by applier.lua)
  ui.lua, widgets.lua     settings window and overlay drawing
  config.lua              every setting: range, per-profile defaults, rule sets, presets, migrations
  presets.lua             custom presets
  lang.lua, lang_en.lua   French and English interface texts
  tips.lua, tips_en.lua   French and English tooltips
  locale.lua, journal.lua, util.lua
sounds/                 delta-beep.wav, drs-available-beep.wav
tracks/                 optional per-track zone files (<trackId>.lua); none shipped
tests/                  offline test bench (Python + LuaJIT through lupa); never loaded by the game
docs/                   audits, CSP API notes, measurements, validation status, official icon (icon-512.png) and banner (banner.jpg)
HumanAI_PDR_v1.0.md     product design requirements; the test bench checks its 78 catalogued cases
CHANGELOG.md            changes, newest first
COMPATIBILITY.md, AUDIT.md   compatibility notes and the original adversarial review
dist/                   release package (dist/AdvancedIA-Beta-1.27.zip)
```

Only `src/snapshot.lua` and `src/applier.lua` touch `ac`/`physics` directly. Everything else is pure decision code, which is what makes the offline bench possible.

### Setting up the bench

You need Python 3 and the two packages pinned in `tests/requirements.txt` (`lupa==2.8`, `luaparser==4.2.0`). Install them into `tests/_vendor`, which the scripts add to their import path. From the repository (app) root:

```sh
python -m pip install --target tests/_vendor -r tests/requirements.txt
```

The scripts locate the app folder from their own path, so run them from the root as `python tests/<script>.py`. They never modify game files.

### The suites

| Script | What it does | Output |
|---|---|---|
| `python tests/lint.py` | Static analysis of every Lua file with luaparser: forbidden globals, unused locals, duplicate definitions, and every field read from CSP structures checked against the installed SDK (`tests/sdk-fields.json`), since a missing field raises an error in game | `tests/lint-results.txt` |
| `python tests/test_pdr.py` | Compiles every source file with LuaJIT, then runs the scenario suites (`tests/scenarios.lua`, `tests/extended.lua`). It checks that all 78 cases catalogued in `HumanAI_PDR_v1.0.md` exist. Prints `PASS`/`FAIL` per check and a total | `tests/results.json` |
| `python tests/integration.py` | Runs the real entry point `AdvancedIA.lua` against a simulated host (`tests/integration_cases.lua`). It also checks the manifest (callbacks, flags, version equal to `src/config.lua`). Set `INT_FILTER` to run matching cases only | `tests/integration-results.json` |
| `python tests/golden.py` | Reference fingerprints of three scenes: track day with 30 AI, ruled race with 30 and with 60 AI. Run it in two versions and compare the files: a pure clean-up must leave them identical | `tests/golden-results.txt` |
| `python tests/audit.py` | Traceable inventory of every setting and function with its runtime consumers (it makes no claim about CSP physics) | `docs/PARAMETER_AUDIT.md`, `docs/PARAMETER_AUDIT.json` |
| `python tests/performance.py [--frames N] [--profile]` | Reproducible cost of the engine core with 9, 30 and 60 AI (default 20,000 frames after warm-up; the release uses `--frames 30000`). `--profile` adds the top stacks | `tests/performance-current-results.json` |
| `python tests/run_soak.py` | Endurance run: 1,728,000 frames (eight hours at 60 Hz with 40 AI), memory tracked, then a 30-AI benchmark. Fails if the memory or time criteria are not met | `tests/soak-results.json` |
| `python tests/mutate.py [app folder]` | Mutation testing. Each important rule is altered in a throw-away copy, and the named test (`INT:` = integration case) must fail on the mutant. Prints `DÉTECTÉE` / `NON DÉTECTÉE` per mutation and `TOUTES DÉTECTÉES` at the end. Long: hundreds of mutations, each copying the app with `tests/_vendor` | console |
| `python tests/report.py` | Factual release report; open criteria are never turned into successes. Reads the scenario, integration and soak results; the soak must come from the current version | `docs/MESURES.md`, `docs/RELEASE_STATUS.json` |
| `python tests/package.py` | Reproducible distribution archive. It holds only what the game loads (entry point, manifest, icon, `src/`, `sounds/`, `tracks/`) plus the user notes, under `apps/lua/AdvancedIA/`. Older packages in `dist/` are removed | `dist/AdvancedIA-<version>.zip` and `.sha256` |

`tests/devtools.py` holds the maintainer's tools (tree comparison, installation with the game closed and a backup). Its paths are specific to the author's machine.

**Recommended order:** `lint`, `test_pdr`, `integration`, `audit`, `mutate`, `run_soak`, `performance --frames 30000`, `report`, `package`. The report only accepts soak and performance results obtained on the current sources.

**Rewritten files.** `audit.py`, `report.py`, `golden.py` and the other suites rewrite tracked result files in `docs/` and `tests/`. Commit them only when you mean to.

**Never run the performance, soak or mutation suites while the game is running**: they are CPU-heavy, and measurements are only valid with the game closed.

The kinematic bench does not replace an in-game validation of collisions or of the real cost of CSP calls. The open in-game checks are listed in [docs/VALIDATION.md](docs/VALIDATION.md) and [docs/MESURES.md](docs/MESURES.md).

## Changelog, license and credits

- **Changelog:** [CHANGELOG.md](CHANGELOG.md), newest first. Each entry lists what changed, why (often from the author's own sessions and logs), and the verification run (checks, integration cases, mutations, soak, benchmark).
- **License:** MIT. See [LICENSE](LICENSE).
- **Author:** VincentChevalier44 (Vincent Chevalier / LHK Informatique).
- **Credits.**
  - Built on the Custom Shaders Patch Lua SDK. The CSP function signatures come from the local SDK and the CSP documentation.
  - No code from any other AI controller is imported.
  - The settings window and the overlay follow the visual style of SuperHUD. There is no affiliation.
