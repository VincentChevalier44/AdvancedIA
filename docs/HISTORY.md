# Changelog archive

Beta 1.39 and older, then the 1.x.y versions and the release candidates, newest first. The current changelog
is [CHANGELOG.md](../CHANGELOG.md). The audit pages these entries name (`AUDIT.md`, `docs/AUDIT_*.md`,
`COMPATIBILITY.md`) were removed in Beta 1.52; the git history keeps them.

## Beta 1.39 — 3 November 2026

A 2.2-second freeze of the settings window fixed, and the last gaps of the fidelity review of Beta 1.38 closed; delivered through the in-app update.

- **Freeze fixed (seen in game with 347 installed cars):** the **Safety Car** view read the name of every car of `content/cars` (`ui/ui_car.json`) in one frame (CSP logged *Slow script … 2156 ms*). The car base is now read a little at every frame (at most 24 files, never more than 4 ms of reading, at least one), with *Reading the car base… n / N* in place of the rows; it is read once per session and filtered in memory.
- **Slow frames in the session log:** a frame of the window or of the overlay longer than 50 ms (500 ms for the first frame of each, while its fonts load) is logged once per place (`WARN interface lente: regles/safety, 85 ms`; tab, section or Racing-rules view; at most eight lines), so the next session pinpoints any remaining freeze.
- **CSP AI flood setting:** a `new_behaviour.ini.bak` left in `Documents/Assetto Corsa/cfg/extension` by versions before Beta 1.38 is deleted at launch (that file only) and logged once (`nettoyage: new_behaviour.ini.bak efface`).
- **Overlay:** pills in capitals; the blue-flag gap in a blue box to the right of the title (*0.8 S BEHIND*), with no pill row; the **PIT: RETURN TO THE PIT LANE** reminder under the mandatory stop too; the app's black flag says *Disqualified: 6 offences*; the offence-count pill in solid amber and *… you passed a car!* in solid red, dark text; the **Delta** label green or pale red like its value; *FUEL 14,2 t* in French; no explanation line under the start lights and the update notice.
- **Window:** the circuit's display name in the header (*Spa-Francorchamps / Race*; Diagnostics keeps the identifier); the class pattern rows open by default; the *Messages hidden* note moved into the switch's tooltip; **Lock the position** neutral while unlocked; the duplicated paragraph of the Safety Car view removed; the veil of an unticked section covers its settings list (and the circuit status of the track light panels) only, never the Personalities block, the legend, the patterns or the car base; **Personalities** across the full width under the two columns of Global options.
- **HOME:** after a built-in preset applied to another profile, the line stays *No active preset* (MainApplique), with *Preset applied to the Race profile*.
- **Diagnostics:** short titles **Headlights** and **Zones**; *CSP 0.2.11 · track spa · spline 7004 m* with the values highlighted; the calibration line *Offset / side sign -1 / -1* (the state is in the chip, its long text in the tooltip); the last flash event in the field's tooltip; the track-light-panels line removed (HOME tile and its section); *…/logs/ACAdvancedIA.log · 48 212 bytes*; capabilities **27** / 29; the grip note shortened, the braking-zone note in the tooltip.
- **Updates block:** release notes shown again while downloading; no message line when a version is available; with no published version, **Check now** is the full-width outline button in place of the action.
- **Texts:** *Applied together to Practice, Qualifying and Race.*; no parenthesis in the Track day and Hotlap note; *·* instead of *|* in the mandatory-stop line; *Not equipped* before the first session; in English *offences* everywhere (*Offences allowed before disqualification*), *rolling start (RS)*, *Installation interrupted: Beta 1.38 restored at launch*.

**Verification**: 449 checks; 121 integration cases; 1,124 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.38; 8-hour soak with 0 errors (memory between 8.7 and 9.9 MB, peak frame 0.82 ms); engine bench with 30 AI, median of five alternating runs: 0.207 ms (Beta 1.38: 0.222 ms). The interface is not in the engine bench; a test reads 347 cars from a slow fake disk (3 ms a file) without a frame over 0.25 s.

## Beta 1.38 — 3 November 2026

The window and the overlay brought to the level of the final mockup (a fidelity review of Beta 1.37 found about forty visible gaps), delivered through the in-app update.

- **Sections:** an unticked section now shows its settings **dimmed under its warning** (*Section off for this profile…*), as in the mockup, instead of the warning alone; they stay adjustable and apply once the section is ticked. Descriptions are the mockup's; the count of changed settings follows them in cyan. **Global options** is the pane title; the grip bonus slider sits right under its switch; **New draw**; *default: …* on the level mode, overlay background and display.
- **Built-in presets (your choice):** a preset aimed at another profile (Race from Practice, Multi-class endurance from Qualifying…) is applied to that profile **without switching the profile shown**; HOME says *Applied to the Race profile* and no tile lights up until you show that profile. **RESTORE DEFAULTS: <profile>** (**RESTAURER <profil>** in French), *No active preset*, *Detected: race · source race.ini*; an invalid preset name gets a red frame and the mockup's message.
- **Choices and values:** short labels in the boxes (*Lapped*, *Refuel*, *Under FCY*…; tooltips keep the long ones); 0 reads *free* (pit-exit spread, minimum stop, maximum stint) or *delta* (Slow Zone); overlay values without units in the box (*Background opacity (%)*, size **1×**).
- **Track light panels:** switch in the title row, **Active for** chips in full cyan, colours and durations in one column, the red note only when red is off, legend with the green duration, *Panels right now: yellow · VSC* (also on the HOME tile), the mockup's red-flag warning.
- **Safety Car view:** five-phase strip (Parked, Called, On track, In this lap, In the pits), amber steps 1–2, filter and model side by side, the car base as rows (name, folder) — eight shown, the others counted.
- **Racing rules:** rule sets name their restart (*RS restart*, *SS restart*); Overtake Mode gap and gain and the BoP correction are dimmed while their switch is off; **Mandatory stop** pane title.
- **Header and HOME:** guard line *Ready · race (race.ini) → profile Race (auto)*, a dot in the state chip, a warning triangle on **PANIC**, a **Got it** button that hides the online banner until the state changes, the update alert on one row (button on the right), *· shown once* after a successful update.
- **Diagnostics:** short buttons (**Learn · 6 s**, **Start**, **End**, **Copy zones**, **Rerun**), short capability names, *AI functions exposed by CSP*, **ms** after the times, *CSP 0.2.11 · track spa · spline 7004 m*; update notes hidden while checking or installing, **Check now** in front when nothing is published, the mockup's interrupted-install text.
- **Overlay:** best-lap purple (#B26CFF) for a new best lap and the BEST value of the session line, the app logo at the head of that line, *START · Green light: the race is on*, *Five lights on · go at lights out*, the offence count under **WARNING** and **PIT: RETURN TO THE PIT LANE** under **CAR DAMAGED**, the version in the update flag on a tinted background, a DRS badge with a light fill and no frame, the dimmed background at half the opacity, *CARB.* for fuel in French, no version text in the corner; one-line instructions and explanations aligned with the mockup.
- **Scroll bars** can be dragged (cyan while dragging); the class pattern rows (**Edit row by row**) show the rows in use plus **+ Add a row**.
- **CSP AI flood setting:** CSP's safe file replacement left `new_behaviour.ini.bak` in `Documents/Assetto Corsa/cfg/extension` after each write; the app now deletes it.

**Verification**: 449 checks; 117 integration cases; 1,100 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.37; 8-hour soak with 0 errors (final sources: memory between 7.9 and 9.0 MB, peak frame 0.68 ms; an earlier 1.38 run gave 8.6 to 9.8 MB and 2.39 ms, and Beta 1.37 run the same afternoon 8.4 to 9.6 MB and 2.19 ms; the memory and peak criteria are still not met, as before); engine bench with 30 AI, median of five alternating runs: 0.220 ms (Beta 1.37: 0.231 ms). The interface is not in the engine bench; the new drawing code caches its texts and tables, rebuilt only when a value or the language changes.

## Beta 1.37 — 3 November 2026

The clean, final version after the first real update from the app (1.35 → 1.36), with the track light panels in their own settings section.

- **Track light panels, own section:** **SETTINGS › RACE & SAFETY › Track light panels**, per profile, ticked by default in every profile (the Beta 1.36 behaviour):
  - **Active for** chips for the five profiles, the circuit status and the colour shown now, moved from the Overlay section (which now links to it);
  - a switch per colour: yellow always on; red off shows yellow (red still needs AC's flags hidden); blue, white, orange and green off give way to the next colour;
  - **Green duration (s)**, 0–15, 5 by default (0: no green), and **Delay before a less important colour (s)**, 0.5–5, 1.5 by default;
  - built-in presets tick it; the former global switch is migrated (turned off, the section is unticked in every profile); it never counts as a section that drives the AI;
  - the greyed **AC native yellow flag on the HUD**, the home tile, its warning (now linking to this section) and the Diagnostics line follow the section of the profile concerned;
  - with the default values, the panels behave exactly as in Beta 1.36.
- **Update from the app:**
  - the state folder is tidied at every launch once the app has started properly and nothing is pending: the unpacked package, the working copy, stray `*.bak`, `*.tmp` and `*.new` files and empty folders go; `backup/`, a pending marker and `failed.txt` stay. Logged once: `mise a jour: nettoyage (n fichiers)`. The leftovers of the 1.35 → 1.36 update (`next/`, `boot.txt.bak`) disappear at the first launch;
  - `boot.txt.bak` came from CSP's safe file replacement, which keeps the old content as `<file>.bak`; the app now deletes it after each write;
  - the copy of the installed version before an update only takes the files whose content changes (the manifest always), which shortens the stop; the log gives their number and the time taken.
- **Housekeeping:** documentation brought up to date (Updating, Track light panels, settings reference, interface notes).

**Verification**: 448 checks; 115 integration cases; 1,076 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.36; 8-hour soak without errors on the final sources (memory between 8.1 and 9.3 MB, peak frame 0.83 ms; Beta 1.36 the same day: 8.5 to 9.7 MB, 0.89 ms; memory and peak criteria still not met, as before; earlier runs showed isolated peaks of a few ms on both versions, machine noise), one hour of regulated racing at 0.23 ms on average (Beta 1.36 the same day: 0.27); benchmark (median of five alternating runs) 30 AI 0.24 ms (Beta 1.36: 0.23), 60 AI 0.62 ms (Beta 1.36: 0.63).

## Beta 1.36 — 3 November 2026

The fixes from the third adversarial review of Beta 1.35 (no blocker, no major finding), and the version that carries the **first real update from the app** (1.35 → 1.36).

- **Standing start:**
  - overtaking is allowed **from the lights out**, as at a real standing start (the "until the line" rule stays for rolling starts and Safety Car restarts), so the AI are no longer sanctioned for passing between the grid and the line;
  - a jump-start penalty is never served while you are stopped on the grid, even after a stall: after 30 s it waits until you move off or cross the line;
  - beyond 25 m past your slot, the overlay says **SLOT PASSED · 60 m** (up to 500 m behind) instead of almost a lap ahead;
  - at the lights out, only the AI held near their slot start from its column; a car released far from its slot by the two-minute timeout, or a car in the pits, gets no sudden lateral step.
- **Track light panels:** red and the neutralisations (VSC, FCY, Safety Car) now come before your own penalty, so the panels no longer go dark while the app cuts your throttle under the Safety Car. Only a disqualification hands the panels back to AC for the rest of the session. CSP's **Hide race flags** setting is read when red is written, so turning it on during a session takes effect at once.
- **Update from the app:**
  - if `src/update.lua` cannot be read, the app now loads without the updater (log: `mise a jour: module illisible`) instead of stopping;
  - a freshly installed version is confirmed only once the engine **and** the window or the overlay have run without error, so a version whose interface fails on every frame is rolled back automatically at the next launch; an install finished by the launch-time recovery is watched the same way;
  - no **RESTARTING** chip stays in the header after a roll back or a recovered install;
  - empty folders are removed with their files, so the previous version is always kept by renaming its folder, never by the slower file-by-file copy, however many updates follow.
- **Interface:**
  - the Racing Rules reset button keeps its own label after a settings section was reset;
  - the state chip says **NO AI · <profile>** when the session has no AI to drive, never **ACTIVE**;
  - the overlay layout and position reuse their tables and points (Beta 1.35 still created about eight tables per frame there), and clip areas no longer create a table;
  - the start lights follow the configured number of lights.
- **Housekeeping:** a dead table removed from the journal; the slow-vehicle log timer follows the 24-hour clock wrap; README and API notes corrected (the backup copy happens at the final, stopped step; the file-watching pause is re-asserted before each changed file).
- **Online:** the app drives nothing online; checking and installing an update while stopped at your pit box only replace files and restart the app, so they stay allowed.

**Verification**: 444 checks; 113 integration cases; 1,052 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.35; 8-hour soak without errors (memory between 7.7 and 8.7 MB; memory and peak criteria still not met, as before), one hour of regulated racing at 0.24 ms on average; benchmark (median of five alternating runs) 30 AI 0.22 ms (Beta 1.35: 0.23), 60 AI 0.60 ms (Beta 1.35: 0.62).

## Beta 1.35 — 3 November 2026

The new interface from Vincent's final mockup (*ACAdvancedIA — Refonte UI*), merged with Beta 1.34, a full review of the window and the overlay, and a safer update from the app.

**Interface**
- **Fonts bundled with the app**: Barlow, Barlow Condensed and JetBrains Mono (SIL Open Font License, in `fonts/` with their licences). Segoe UI and Consolas when the files are missing, noted once in the session log, even when only the overlay is shown.
- **Header on every tab**: brand and version chip, one-click update button (greyed while you drive), track and profile, AI driven and engine state, state chip, **FR | EN**, **APP** switch, **PANIC / RESUME**, slanted tabs and the profile selector. The selector never disappears: in a narrow window the profiles show as their first letter.
- **State chip**: **ACTIVE · RACE** while the app drives, **PAUSED · RACE** while the game is paused (live figures kept), **SUSPENDED** in a replay, after the session, on a track without an AI line, on abnormal frames or when CSP refuses the AI functions. It never says *active* when nothing is driven.
- **HOME** in two scrolling columns: session panel, built-in presets as tiles, live figures including the light panels, **TO CHECK** with links to the section concerned, custom presets (long names shrink to fit) with a 64-byte counter, and a banner for a disabled app, a panic, an online session or the first session. After an update, the report has a **Notes ›** link.
- **SETTINGS**: sidebar with the section switches and the number of changed settings; every section in sub-groups on two columns; default marks on the sliders, cyan diamonds on changed settings, segments for choices with up to three values (a ‹ value › button when their labels do not fit). **Global options** unticked now show the inactive-section message like every other section, instead of settings that looked editable. **Assetto Corsa native yellow on the HUD** is greyed out on an equipped track while the track light panels are on.
- **RACING RULES**: views with their switches, rule sets, Safety Car model card and deployment steps; the message of another tab is cleared when you change tabs.
- **DIAGNOSTICS**: update block with all its states, the last headlight flash event (id / count) and the track light panels line again, capabilities on two columns, AI table, performance tiles, log level as a segment.
- **Overlay**: cut-corner background, accent bar in the flag colour, letter badges (SC, VSC, RS, SS), the Beta 1.34 restart panels (rolling and standing start, five start lights, **GO**, **JUMP START**), and every text in the app fonts.
- Switching language redraws every cached text (values, defaults, update messages) at once.
- **Lighter drawing**: one font push per change of role instead of one per text, measured texts and control identifiers kept between frames, fewer tables and points created per frame in the overlay (none since Beta 1.36), the rule set and preset signatures computed once per change. A drawing error now closes its fonts and clips in the same frame.

**Updating from the app, reworked**
- Nothing is unpacked or staged in the app folder any more (CSP reloads an app whose files change): the package goes to CSP's state folder (`Documents/Assetto Corsa/cfg/extension/state/ACAdvancedIA-update`), where the installed version is also copied before anything changes.
- The click downloads, checks and unpacks; the copy into the app folder waits for you to be stopped (pause, menu, or at your pit box at standstill: the pit lane at speed no longer counts) and is done in one go, CSP's live reload paused, `src/` first, `ACAdvancedIA.lua` next, `manifest.ini` last. Files are copied, never moved (the app folder and Documents are often on different drives).
- A failed copy puts the installed version back at once and names the file. If even that fails, the window says so with the marker file and stops there.
- An install cut short by a crash is finished (or undone) at the next launch, before any other module loads, then the app restarts once. Two attempts at most, never a loop, and the app is never left frozen.
- GitHub's request limit (403, 429) is shown as such; **Check now** asks at most once a minute (greyed in between); a cancelled download can no longer be revived by a late answer; release notes are cut without splitting a character; the previous version for **Roll back** is read from the backup itself; a restart that does not happen is reported after 10 seconds.
- **Second review of the updater:**
  - every file is first copied next to its destination under a temporary name, then renamed over it, so a crash never leaves a half-written file;
  - each kept version (`current`, `backup`) carries its file list; **Roll back** is offered only for a complete version, and the old backup is replaced by renaming folders, never by moving files one by one;
  - a freshly installed version that fails to start twice in a row is rolled back automatically at the next launch, and the log says so;
  - **your settings are kept after a roll back**: a version now reads settings written by a newer one (each known setting is validated) instead of falling back to the defaults;
  - the marker is read back after it is written, and the app restarts only once it is really gone (never a restart loop, even with a read-only marker);
  - the downloaded size must match the release, every module the new version loads must be in the package, and the unpacked files must equal the package;
  - the check and the download give up after a timeout; a download ready to install expires if you drive off; **Roll back** runs on the next frame, not inside the window drawing;
  - each failure is logged with its detail, and a recovery outcome is also written to CSP's own log.
- **Install Beta 1.35 by hand, game closed** (Content Manager or a folder copy, see README › Updating): do **not** use the update button of Beta 1.33 or 1.34. Their updater still unpacks into the app folder, which CSP watches, and has none of the protections below. Their `backup/` folder in the app folder is no longer used (delete it with the game closed if you like), so no roll back to Beta 1.34 is offered until the next update.

**Race restarts and light panels (second review of the engine)** — these also fix the installed Beta 1.34:
- **Standing start:** with the F1 rules and no Safety Car model, the restart lap under VSC or FCY used to end on a timer, wherever the field was; cars more than half a lap from their slot, or past the line, were then held where they stood. The restart lap now ends when the leader completes it, the distance to a slot is measured forwards, and a car counts as past its slot only within 25 m.
- **Jump start:** watched only once you are in your slot and stopped, forwards only, never when you start from the pit lane; the penalty is served once you are past the line (150 m, at the latest 30 s after lights out), never while stopped on the grid. Without player penalties, no JUMP START panel.
- **Formation:** the AI expected on the grid are counted every frame (a car in the pits, invalid or disqualified no longer makes everyone wait 2 minutes); no pit stop is requested during the formation and the lights; your distance shows to the metre below 20 m, then **IN POSITION** or **SLOT PASSED**; with no slot, *Start from the pit lane*, never *P0*.
- **After lights out:** the race-start protections (caution, aggression, front radar, lane holding) apply to a standing restart too, and each AI steers on from its slot's column without a jump.
- **Track light panels:** green at lights out and at a Safety Car restart (no more white SLOW VEHICLE while the field is slow behind the Safety Car or on the grid, nor for 10 s after a green); AC's penalty or your disqualification hands the flag back to AC; a pause no longer hands the panels back for a moment; AC's Hide race flags is re-read when red is about to be written.
- **Smaller fixes:** the track's grid nodes are never modified (a second red flag used computed slots while saying AC_START), side-by-side grids are accepted and a fallback says why; lights timing as intended; no AI pass sanction during the formation; restoring the flag to AC is logged; the slow-vehicle log line at most every 10 s; timers kept across the 24-hour time wrap; a capability failing during the final hand-back is logged.
- **Lighter engine:** the lateral occupancy skips cars too far away to count (same results), and the fuel key is built only when fuel is requested.

**Verification**: 439 checks; 109 integration cases; 1,035 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.34; 8-hour soak without errors (memory between 8.6 and 9.6 MB; memory and peak criteria still not met, as before), one hour of regulated racing at 0.27 ms on average; benchmark (median of three alternating runs) 30 AI 0.21 ms (Beta 1.34: 0.22), 60 AI 0.54 ms (Beta 1.34: 0.58).

## Beta 1.34 — 3 November 2026

Rolling and standing restarts after a red flag, and the fix for the track light panels that never lit in your Imola session.

- **Track light panels fixed.** In your Imola session on Beta 1.32 the track was detected, you were under a yellow flag, yet no colour was ever written and the log said nothing. AC keeps its own start flag (green) up for a long time, the whole session in hotlap, and the app only wrote over *no flag* or AC's yellow. The start flag no longer blocks the panels; AC's blue, white, black, penalty and chequered flags are still never covered.
- **Diagnostics so this cannot stay silent again:**
  - a wanted colour that is not written is logged once, with its cause (AC's own flag, a missing capability, CSP's error);
  - every change of AC's own race flag is logged (`drapeau d AC: 1 (depart)`);
  - the first failure of each CSP function the app calls through its capability table (AI and player commands) is logged with CSP's error text, and so is the moment the app stops using it after three failures. Until now a failing function left no trace.
  - The track configuration is now read even when no section is ticked, so the window no longer says it was not read yet.
- **Restart after a red flag** (racing rules, red flag group): **rolling start (RS)** behind the Safety Car, or **standing start (SS)** from the grid.
  - F1 2025 and F1 2026 use the standing start; the base, GT and Endurance rules the rolling start.
  - Standing start: after the restart lap, every car drives to its grid slot in race order (slots closed up; a car in the pits starts from the pit lane) and is held there; five lights in the overlay, a random hold, then lights out and everyone leaves at once. Nobody is teleported, so laps stay exact. The grid comes from the track's `AC_START` nodes, or is computed in front of the line.
  - Moving before lights out is a jump start, penalised like the other infringements.
  - Without what it needs (CSP functions, measured lateral direction, track length) the restart stays rolling, with the reason in the log. A new incident during the grid cancels it.
  - The overlay announces the restart during the restart lap (**ROLLING START**, **STANDING START**), shows your slot and the distance to it, the five lights, **GO** and **JUMP START**. The light panels stay yellow during the grid and the lights, then green.
- **Overtaking allowed after the restart** (Safety Car view): at the control line (default) or as soon as the Safety Car pits, for a red-flag restart and an ordinary Safety Car deployment alike.
- The update check compares the published version once per release instead of every frame.
- Not confirmed in game yet: the panels with the start flag fix, the `AC_START` grid slots (whether CSP finds them), the AI stopping in their slots, and laps and positions after a standing start.

**Verification**: 421 checks; 101 integration cases; 913 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.33; 8-hour soak without errors (memory between 7.9 and 8.9 MB); benchmark (median of three alternating runs) 30 AI 0.21 ms (Beta 1.33: 0.21), 60 AI 0.57 ms (Beta 1.33: 0.57).

## Beta 1.33 — 2 November 2026

Updating from inside the game, at your request: the app checks GitHub at launch and installs a new version in one click.

- **Check at launch.** About ten seconds into the game, one request to GitHub (`api.github.com`) reads the latest published release. **DIAGNOSTICS › UPDATES › Check for updates at launch** (on by default) turns it off; **Check now** asks on demand.
- **One-click update** from the header (**UPDATE · 1.34**), **HOME › TO CHECK** or **DIAGNOSTICS › UPDATES**, only when stopped (in the pits, paused or in a menu):
  - the release's SHA-256 digest and package come from the repository's release downloads only; the digest, the package contents (all under `apps/lua/ACAdvancedIA/`, the updater itself included) and its manifest version are checked before anything is written;
  - the installed version is backed up to `backup/previous.zip`, the package is unpacked into `backup/next`, then each changed file is moved into place, `manifest.ini` last;
  - the session log is written, every AI is handed back to AC and the app restarts. After the restart: *Update complete: Beta 1.33 → Beta 1.34*.
- **Nothing breaks on failure.** Any error before the install keeps the current version; a failed install puts the backup back at once; an install cut short by a crash or a power cut is finished or undone at the next launch, and the app drives nothing until then. **Roll back to Beta X** puts the previous version back. Settings, profiles and presets are kept.
- **Overlay:** in the pits, **UPDATE AVAILABLE** once per launch for 6 s; never while driving.
- **Logged:** check result, each install step, refusals and errors (`mise a jour …`).
- Not confirmed in game yet: the first real update will be Beta 1.33 → 1.34. The download size is shown, not its progress (CSP does not report it).

**Verification**: 412 checks; 99 integration cases; 862 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.32; 8-hour soak without errors (memory between 7.8 and 8.7 MB); benchmark 30 AI 0.23 ms (Beta 1.32: 0.27), 60 AI 0.63 ms (Beta 1.32: 0.65).

## Beta 1.32 — 2 November 2026

The track's light panels now show the app's flags, and the overlay gains the FIA signals it was missing, at your request.

- **Track light panels.** On a track whose CSP configuration lights its trackside light panels from the player's flag, the app lights them with its own flags. **SETTINGS › ADVANCED › Overlay › Track light panels**, on by default.
  - Red under a red flag, only with AC's flags hidden in CSP (the same value is AC's black flag in its own display; yellow otherwise). Yellow for a yellow zone ahead of you, the Safety Car, VSC, FCY and the relaunch lap. White for a slow vehicle ahead, orange for a slippery track, blue when a car laps you, green for 5 s when a neutralisation or a yellow ends.
  - Nothing to show, your last lap or the finish: the flag goes back to AC. AC's own flags are never covered (blue, white, black, chequered; over AC's yellow, only yellow or red). A less important colour waits 1.5 s, so the panels never flicker.
  - The track configuration is read once per track, never written. On your installation, 18 of your 41 tracks are equipped (59 of 132 layouts), among them Spa, Monaco, Le Mans, Bahrain, COTA, Suzuka and Zandvoort, and **Imola and the Nordschleife** through CSP's own configurations. Elsewhere, nothing changes.
  - Logged: the track check and each colour with its reason (`panneaux lumineux du circuit: …`).
  - With AC's flags shown, AC's own flag icon also shows the yellow, blue and green: the window says so.
- **New overlay flags** (FIA), none of which forbids overtaking:
  - **SLOW VEHICLE** (white flag): a car ahead of you, within 300 m, has been below half its usual pace there for 3 s. A car in an incident still gets the yellow flag.
  - **WARNING** (black-and-white flag): a place to give back once the flag has ended (until now the reminder disappeared with the flag), and your last tolerated infringement before disqualification.
  - **CAR DAMAGED** (black flag with an orange disc): for 20 s when your car gets notable mechanical damage (suspension, engine, gearbox, heavy bodywork damage, blown tyre).
- **The app's own flag is never read back as one of AC's**: with the panels lit red, AC's black flag (same value) is not shown on the overlay.
- Not confirmed in game yet: red, slippery and slow vehicle on the panels (the SDK marks the last two *does not work yet* for AC's own display). Rolling and standing restarts (RS / SS) come next.

**Verification**: 396 checks; 94 integration cases; 816 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.31 except the new final-warning log line (identical once that line is removed); 8-hour soak without errors (memory between 8.9 and 10.1 MB); benchmark 30 AI 0.23 ms (Beta 1.31: 0.21), 60 AI 0.62 ms (Beta 1.31: 0.57). The real detection code was run on the 132 layouts of the 41 installed tracks. The memory and benchmark gaps with Beta 1.31 are within run-to-run variation: memory varies with the JIT compiler's traces (without the JIT, 3.20 MB against 3.18 MB, flat over the run), and alternating runs on the same machine give 30 AI 0.233 / 0.226 ms and 60 AI 0.611 / 0.604 ms, the same with the light panel work switched off (0.239 and 0.592 ms).

## Beta 1.31 — 2 November 2026

Overtakes between AI and the repeated spins at the same corners (your Imola sessions: Acque Minerali around 2,850–2,940 m and Rivazza around 4,130 m, in Beta 1.28 to 1.30 alike). Your test confirmed the Beta 1.30 fix: an AI behind you passed normally once you moved aside.

- **Caution kept in braking zones and corners.** Slipstream, overtaking and following lower an AI's caution on the straights (down to 0.6 to 0.7 of its usual value), and overtaking raises its aggressiveness. That lowered caution, smoothed over 0.4 s, was carried into the next braking zone, which at Imola are downhill ones. Now, as soon as the AI brakes itself or is in a corner, its caution is never below its usual level and its aggressiveness never above it; caution comes back within a fraction of a second.
- **Overtakes started on real closing only.** In your sessions, 12 of 14 attempts (and most of the day's 822) were given up because the car ahead pulled away: they started on a passing speed difference (corner exit, earlier braking). An attempt triggered only by closing now waits until the AI has really gained 4 m on the car ahead (tracked continuously, corners included); being held up, an invitation and a car that yields still start it at once.
- **Diagnostics in the log**, to check both fixes on your next sessions:
  - each attempt and how it ended (`depassement`, `depassement fini`);
  - what the app was commanding an AI just before a spin (`tete-a-queue, contexte`);
  - in the minute summary, real passes between AI (two cars within 20 m swapping places), how many followed an app manoeuvre, and AI passing you.
- Not confirmed in game yet. Your own spin at 2,858 m shows that Acque Minerali is tricky in itself; the context line will tell whether the app plays a part.
- **Official icon**: a racing helmet with cyan light lines, as the app icon in the game (`icon.png`, 64×64) and in 512×512 for GitHub and Overtake (`docs/icon-512.png`).
- **Official banner** at the top of the README (`docs/banner.jpg`).

**Verification**: 387 checks; 91 integration cases; 774 mutations, all detected; clean lint, parameter audit; 8-hour soak without errors (memory between 7.5 and 8.4 MB); benchmark 30 AI 0.24 ms (Beta 1.30: 0.25), 60 AI 0.63 ms (Beta 1.30: 0.77).

## Beta 1.30 — 2 November 2026

Fix from your Imola practice session: an AI arriving fast behind you slowed down until it stopped, although you had moved aside to let it by.

- **Braking added by the app no longer blocks overtaking.** You were still partly in the AI's lane, so the front radar added light braking (the log shows it 6 m behind you, 18 km/h faster). The app counted that braking as the driver's: the rule “no change of line under braking” then stopped the AI from pulling out, the pass could not start, and the AI dropped to your speed behind you. The braking read on the pedal is the higher of the AI's own and the app's (CSP API); only braking above what the app adds now counts as the driver's. The AI's real braking still forbids any change of line.
- **Invitation not taken explained in the log** (`invitation du joueur non suivie`). If you move aside right in front of an AI (at least 2 m, within 40 m) and it has not started to pass after 3 s, the log says why. Your session recorded no invitation at all; the next log will show the reason if it happens again.

**Verification**: 383 checks; 91 integration cases; 761 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.29; 8-hour soak without errors (memory between 7.4 and 8.4 MB); benchmark 30 AI 0.23 ms (Beta 1.29: 0.23), 60 AI 0.59 ms (Beta 1.29: 0.64).

## Beta 1.29 — 2 November 2026

Presets now set the whole profile, and your headlight flashes are understood earlier, at your request. Your Imola practice session and a review of all of the day's logs brought three driving fixes.

- **Anti-zigzag cap counted wrongly** (found by reviewing the 2 November logs: 630 triggers in four sessions). The cap counts how often a manoeuvre changes side (at most 6 a minute, then 20 s of rest in a straight line). It looked at the target after the track-width bound; in a corner that bound drops to almost nothing, so a yield or an overtake held on the same side counted as a return to the line and then a new start. That was 1225 of the 3780 recorded changes (38%); only about 47 of the 630 triggers were real zigzags. Each trigger cut the yield or overtake under way and blocked new ones for 20 s. The cap now counts the side the manoeuvre aims for; a real zigzag is still capped.
- **No fighting with you outside the race** (your practice session): when you pass an AI, it does not try to pass you back for 20 s, unless you slow down sharply (25 km/h slower). While you are right behind it, alongside, or just ahead after passing it (within 30 m), it eases its aggressiveness, so the game's AI no longer forces its way into the corner. The app's own defending already only acted in the race. The race is unchanged.
- **AI stuck in a gravel trap** (your practice session: a car stayed in the gravel for more than a lap under yellow): it kept spinning its wheels and moving back and forth on the spot, sometimes above the 5 km/h stop threshold, so the 30 s recovery timer kept restarting. An off-track incident now counts the time spent without moving more than 15 m: after 30 s the car is taken back to its pit. A car that drives slowly out of the gravel is left alone, and a crashed car still waits for a clear track before rejoining.
- **Presets include the championship rules**: a built-in or custom preset now sets its profile's rules too (mandatory stop, Safety Car, rule set). This reverses the 1.4.0 behaviour (“rules independent of session presets”).
  - A Practice, Qualifying or Race preset sets those rules for the whole weekend, without ticking or unticking the Racing rules tab. **Free practice**, **Flying-lap qualifying** and **Realistic race** bring the Base rules: a mandatory stop added by hand is removed.
  - **Multi-class endurance** in the Race still brings the Endurance rules. A Track day preset leaves the race weekend as it is.
  - A profile you never configured receives the weekend rules and keeps them when its recommended preset is applied.
- **Track day and Hotlap**: **Mandatory stop in the race** and **Safety Car** are shown off and ignore clicks there, since they only act in the race. Their settings are reached from the Practice, Qualifying or Race view.
- **No pre-selected built-in preset**: a built-in preset button lights up only for the profile shown, after you click it for that profile, and while the profile still matches it. In Practice, **Nordschleife Touristenfahrten** no longer lights up because the Track day profile carries it. A recommended preset applied on its own lights nothing and is no longer reported as *Last preset loaded*; **Restore defaults** switches the highlight off.
- **Headlight flashes**:
  - Why the AI only reacted when you were very close (found in the code; the logs had no line for yields to your flashes): it wanted you at least 12 km/h faster, or 5 km/h faster within 30 m. Stuck behind at the same speed, your flash was never understood.
  - Close range is now 60 m, and **Close-range advantage (km/h)** defaults to −5 km/h outside the race (was 5 / 4; 6 in the race, unchanged): stuck behind an AI at the same speed, your flash is understood.
  - **Flash range (m)** goes to 200 m on a Track day, in Practice and in Qualifying, and to 150 m in the Race (was 120 / 150 / 100 m). Beyond 60 m you must also be able to reach the AI before its yield would end (maximum yield duration minus 5 s): an AI that moved over too early would give up and then ignore you.
  - The advantage is judged for as long as the request lives (8 s): a flash refused from further back is understood as soon as you close in.
  - Values still at the old defaults follow the new ones, in your profiles and custom presets; values you set stay as they are.
  - The log records each of your flashes (`appel de phares du joueur`) and each yield to it (`cede sur appel de phares du joueur`).

**Verification**: 382 checks; 91 integration cases; 757 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.28; 8-hour soak without errors (memory between 7.8 and 8.7 MB); benchmark 30 AI 0.18 ms (Beta 1.28: 0.19), 60 AI 0.49 ms (Beta 1.28: 0.50).

## Beta 1.28 — 2 November 2026

Diagnostics after your Nordschleife 24h track day (60 cars), where a Porsche running at about 100 km/h held up a long queue. The log did not record which car was slow or why, so this version adds the lines needed to find the cause; the driving itself is unchanged.

- **Abnormally slow AI** (log line `IA anormalement lente`): an AI on track, outside the pits and yellow zones, running below 60% of its class's learned pace at that spot for 20 s with a car stuck behind it (within 60 m) is reported once, with its model, speed, class pace, queue, state, the app's command and speed limit, and its damage (read while it is slow). A second line closes the episode. Nothing is commanded: the fix will follow the cause found.
- **AI distribution check**: 3 s after placement, each car in trouble is now named with its model and the reason (in the pits, off track, slow or sliding).

**Verification**: 375 checks; 90 integration cases; 722 mutations, all detected; clean lint, parameter audit; 8-hour soak without errors (memory between 7.4 and 8.3 MB); benchmark 30 AI 0.19 ms (Beta 1.27: 0.21), 60 AI 0.55 ms (Beta 1.27: 0.55).

## Beta 1.27 — 2 November 2026

Race start defaults taken from your custom preset “Course Test”, which you found more realistic.

- **Race profile, Start section**: **Start delay (s)** 1 s (was 12 s), **Settling time after the start (s)** 25 s (was 12 s), **Hold the grid lane at the start** off (was on). **Caution at the start** ×1.3 and **Aggression at the start** ×0.8 are unchanged.
- The built-in **Race** preset (and the Endurance preset in the Race profile) uses the same values.
- Existing installations: Race-profile values still at the old defaults (12 s, 12 s, lane hold on) follow the new ones, each value on its own; values you have tuned stay as they are (settings revision 16, logged as `C:depart` in the profile update line).
- Two tooltips brought up to date: “On the whole track” places the AI with varied gaps and keeps a share in the pits; the flag panel is the in-game overlay (unlock it in **SETTINGS** › **Overlay** to move and resize it).
- Documentation translated into English for the public GitHub repository; COMPATIBILITE.md becomes COMPATIBILITY.md.

**Verification**: 374 checks; 90 integration cases; 716 mutations, all detected; clean lint, parameter audit; 8-hour soak without errors (memory between 7.4 and 8.2 MB); benchmark 30 AI 0.20 ms (Beta 1.26: 0.21), 60 AI 0.53 ms (Beta 1.26: 0.57). The reference scenes are identical to Beta 1.26.

## Beta 1.26 — 30 October 2026

Based on your track days at the Nürburgring (45 and 60 cars).

- **Traffic jams on track days: CSP's AI flood handled by the app.** On circuits of 7 km and more, AI flood keeps all the AI cars alive within 1 km of you; the spacing settings could do nothing about it. From 10 AI cars, the app turns it off (the user's CSP setting); below that, it keeps it with the chosen range (1 to 5 km). CSP reads this setting at launch: the effect comes at the next launch, announced on the overlay.
- **AI cars spread over the whole circuit from the start** (settings of the General tab): placed on track with varied gaps (from a few tens of metres to more than 2 km, never less than 15 m), keeping clear of 300 m around you, aligned by CSP and launched at 50 km/h; 25% stay in the pits and come out on their own. Confirmed in game: 45 AI cars placed out of 45, 0 in trouble. In practice and qualifying, optional (staggered pit exits by default); never in the race.
- **Faster AI cars**: never held back by spacing behind a clearly slower car on a straight; they catch it and pass it.
- **More persistent overtakes**: a target lost from sight for a moment (wheels off track) no longer makes the AI abandon the manoeuvre (1 s tolerance).
- **AC's original messages hidden by default**, shown on the overlay instead; if hiding them also removed them from the overlay, the hiding lifts itself until the next launch (log).
- **Limitation**: Content Manager's “Override limits” option (“Outrepasser les limites”, under Drive) is a Content Manager setting, out of reach of an in-game app.

**Verification**: 373 checks; 90 integration cases; 716 mutations, all detected; clean lint, parameter audit; 8-hour soak without errors (memory between 7.2 and 7.9 MB); benchmark 30 AI 0.21 ms (Beta 1.25: 0.22), 60 AI 0.55 ms (Beta 1.25: 0.59). The reference scenes change slightly (lost targets held on to: fewer anti-zigzag caps triggered).

## Beta 1.25 — 30 October 2026

Based on your Spa race (27 cars) and your requests about the overlay.

- **AI lateral movement restored: the most important change in this version.** The log of your starts showed `signe 0` (sign 0). The lateral sign measured by the app (-1 / -1, Assetto Corsa's convention) disappeared between 10:01 and 11:15 on 26 October, right after Beta 1.9 was installed; your settings backups show it. The measurement then only made one attempt per session, rarely possible in a pack. Since then, the app had written no lateral movement at all: no yielding, no move out to overtake, no avoidance of a crashed car, no blue flag, no grid lane hold at the start. The sign is restored to -1 / -1 (noted in the log) and the measurement is retried every 60 s to confirm it. **Everything you judged consistent over the last few days ran without these movements**: the AI cars will once again move aside, pull out and avoid. If you dislike a behaviour, untick its tab (Yielding, Overtaking, Lines, Start) to get the previous driving back.
- **Safety Car that would not leave its pit box**: called twice during your race, then released, it stayed parked and switched to FCY after 90 s. Once released, it is now woken up, its departure is immediate, no forced braking or stop is requested of it, and these commands are repeated every 2 s as long as it stays in its pit box. The log notes `voiture de securite: sortie de son stand apres … s` (Safety Car: left its pit box after … s). This exit has never yet been observed in game.
- **Flat out to the first corner at the start**: on the straight, no more start caution or following caution; the AI cars stay glued to the car ahead, and the radar only brakes for a truly imminent contact (less than 0.8 s). Start caution and start aggression only apply under braking and in corners, so at the first corner, and relax slowly at its exit. Your log showed about twenty radar braking events in ten seconds on the start straight, 5–9 m from the car ahead; that was the cause of the slowdown. A new log line measures each start: `depart: peloton a … km/h en moyenne apres 12 s, … freinage(s) du radar au lancement` (start: pack at … km/h on average after 12 s, … radar braking event(s) at launch). Grid lane hold at the start finally works, with its offset cautiously capped.
- **Own in-game overlay** (**Overlay** section of the settings): free position and size (unlock, drag, bottom right corner, right-click to lock), put back on screen, opaque, dimmed or transparent background, background and content opacity, click-through, hidden in replays or in the pits. The old “ACAdvancedIA Drapeaux” window disappears: simply reopen the game, and the overlay appears centred at the top of the screen.
- **Assetto Corsa displays taken over**:
  - a session line at the top of the overlay: position, lap out of the total or time left, best lap, mandatory stop, fuel in laps;
  - when crossing the line: next lap, last lap and best lap;
  - AC's session box at the top of the screen (2/3, 2/8, RACE OVER) is hidden and replaced;
  - AC messages (aids, warnings) are shown on the overlay; their original display stays visible by default, so it may appear twice, and each new message is noted in the log so you can then decide which ones to hide.
- **Flag explanations**: below the instruction, what is happening. Yellow flag: a car in trouble near the track. Double yellow: a car stopped or sideways on the track. Also for the Safety Car, the VSC, the FCY, the red flag and the blue flag.
- **End of the race**: “RACE OVER”, chequered flag and summary:
  - congratulations according to your position (victory, podium, top 5, top 10…);
  - finishing position, starting position and places gained or lost;
  - best lap, compared with the whole field (“the fastest of the race!”);
  - on-track overtakes and times you were overtaken (excluding pit stops and recovered cars);
  - number of laps.

  It is also noted in the log.

**Verification**: 367 checks; 88 integration cases; 688 mutations, all detected; clean lint, parameter audit. The driving statistics of the reference scenes are identical to Beta 1.24; they run with a known lateral sign, so without revealing the absence of movement in game. Soak without errors; core at 30 AI 0.22 ms per frame against 0.23 ms in Beta 1.24, at 60 AI 0.69 ms against 0.53 ms.

## Beta 1.24 — 30 October 2026

Based on your Spa race (27 cars) and your remarks.

- **Per-section reset**: each section of the settings (Personality, Lines, General, Start, Accidents, Global options…) has a **RESET SECTION** button. Its settings go back to the default values of the profile shown, like a right-click on each one. Your display preferences, the class patterns and the settings fixed by the rule set are kept. For the global options, the button never touches the measured lateral sign or the Safety Car. The Racing Rules tab keeps its own button.
- **Front radar, on by default** (formerly “Additional braking”, experimental and off until now): in every session and from the grid, an AI car about to hit the car ahead in its lane, you or an AI car, first **lifts off** within 2.5 s of the contact. Within 1.2 s, it adds **light braking** of 45% at most, built up over 0.3 s and released gradually. There is never a stab of the brakes or a change of line, and the brake is only added to the AI's own. A slipstream or a slow approach changes nothing: on the reference scenes, as many overtakes as before (136 against 137). This setting targets the AI cars that ran into the back of you at the first corner. It can be turned off in Global options.
- **Blue flags in the race**: an AI car holding you up while you were lapping it **never let you by** if you were running at its speed, glued behind it. It took at least 3 km/h of speed advantage, whereas a car being held up runs at precisely the same pace. Now, glued within 40 m, the blue flag stays waved. It still keeps its line in the corners and moves aside at the exit. In practice and qualifying, nothing changes: an extra lap there only means more time spent on track. The log notes each blue flag: `drapeau bleu: X laisse passer le joueur` (blue flag: X lets the player by), or `… sans le laisser passer (raison, écart, vitesse)` (… without letting them by (reason, gap, speed)) after 3 s. Under a yellow flag, neutralisation or red flag, yielding remains forbidden and nothing is noted. Reminder: the blue flag only concerns cars a lap down. A slower car on the same lap is overtaken.
- **Less timid race start**: start caution goes from ×1.6 to ×1.3 and aggression from ×0.6 to ×0.8 (Start tab). The middle of the pack lifted off well before La Source. Values left at the old defaults follow; the ones you had set stay.
- **Stationary cars, consistent with the flags**: recovery never bypasses race control.
  - An AI car stopped **alone** in the middle of the track under a local yellow flag (no rule can follow from it) is brought back to its pit box after **8 s** instead of 20, or **3 s** if it is **broken** (suspension, engine or gearbox out of action).
  - It stays for the time of the decision, with the Beta 1.23 delays (20 s, or the major incident plus 5 s), in three cases: a **neutralisation** is chosen for the major incident (VSC, FCY, Safety Car, which is therefore always declared first), **several cars** are involved on track (the red flag and the escalation to the Safety Car keep their window), or a neutralisation is in progress.
  - Off track (gravel trap, wall), it is brought back after **30 s** instead of 90, never while it is waiting to set off again.
  - An AI car that is still moving, even at walking pace, is never recovered: it sets off again or returns to the pits.
  - Under a red flag, nothing changes.
- **Pit stops**: a recovery (car brought back to its pit box by the app, even if AC reports the pit box one frame later) and the Safety Car no longer count as a pit stop, nor for the mandatory stop. Under a red flag, where all cars come in, the count stays that of Beta 1.23.
- **Tyres**: two cars on your grid (WHK Macca V8 1.2) received compound 15 at every stop, `Grip Formule 1 - Super tendre` (Formula 1 grip - super soft). This car offers 16 dry compounds, in four grip families (original, F3, F2, F1). Drawing a dry compound now only takes the first of each name (original hard, medium, soft, super soft). The `pneus poses` (tyres fitted) lines now give the name of the compound fitted and of the previous one. Probable link with their repeated stops at the same spot: to be confirmed in the next log.
- **Start and contact log**: at the start, a line gives:
  - grid lane hold (AI cars measured, offset, held, known track width, lateral sign);
  - the multipliers, blue flags and the radar;
  - each AI car's tyres.

  Each contact between cars is also noted (`contact: X touche l arriere de Y` (contact: X hits the rear of Y), or on the side, with the speed difference): at most 3 lines per second between AI cars, so that a pile-up does not drown the incident lines, and always the ones that involve you. Grid lane hold at the start never appeared in your logs; the next race will tell why.
- **Major incident tooltip** (Rules tab): it states that the car is only brought back to its pit box after this delay plus 5 s.

**Verification**: 362 checks; 85 integration cases; 641 mutations, all detected; clean lint, parameter audit. The engine fingerprints change, as expected (radar on by default, start), with driving statistics almost identical to Beta 1.23. Soak without errors; core at 30 AI 0.183 ms per frame against 0.157 ms in Beta 1.23, at 60 AI 0.498 ms against 0.445 ms.

## Beta 1.23 — 30 October 2026

Your tests of Beta 1.22 (Spa, 48 cars) confirmed in game the staggered pit exit (actual exits 1 to 3 s after the planned turn) and the repairs (bodywork repaired at the stop in the race). Two fixes, at your request:

- **Staggered pit exit capped**: with 47 AI cars 10 s apart, the last one only came out after 7 min 42 s. Now, all of them are out within **3 min at most**, or within a quarter of the session if it is shorter (short qualifying sessions): with many cars, the gap shrinks automatically (about 4 s with 47 cars, never below 2 s, never beyond your setting). The log shows the gap used: `sorties des stands etalees (essais): 47 IA, 3.9 s d ecart, la derniere dans 180 s` (staggered pit exits (practice): 47 AI, 3.9 s apart, the last one in 180 s).
- **Repair log**: a `reparations` (repairs) line only if something was actually repaired. The `carrosserie 0 km/h, moteur 1000` (bodywork 0 km/h, engine 1000) lines came from slight wear read on entering the pit box, which AC had already repaired at the stop; the app then wrote nothing.

**Verification**: 352 checks; 84 integration cases; 598 mutations, all detected; engine fingerprints identical to Beta 1.22; clean lint, parameter audit. Soak without errors; core at 30 AI 0.165 ms per frame against 0.173 ms in Beta 1.22, at 60 AI 0.479 ms against 0.469 ms.

## Beta 1.22 — 29 October 2026

Your test of Beta 1.21 (track day on the Nordschleife, 22:03 and 22:07): cars well spaced, but all crawling on track. The cause, confirmed by your remark (“the cars, when they set off, are already on the track”) and by the log: on loading, AC places the AI cars in their pit boxes; the app wrote their exit wait there and parked them, then Content Manager placed them on track for the track day. They then carried out on track the wait received in the pits: stopped or at walking pace (`arret` (stop) incidents at 0-10 km/h between 600 and 1,800 m), brought back to the pits by the app after 20 s, then parked again. Fixes:

- **Track day: no AI car held back or parked any more** by the app at the start of the session. Content Manager places the cars (already spaced). The “Staggered pit exits” setting of the Spacing tab is removed.
- **Staggered pit exits in practice and qualifying** (your request), with many cars: at least 10 AI cars in their pit boxes at the start of the session. Each one waits for its turn, in a random order, about 10 s after the previous one (“Staggered pit exits, practice and qualifying” setting of the General tab, 0 = free exit). Safe by design: only AC's native wait (no car parked); **cancelled at once** if an AI car leaves its pit box before its turn, whatever the reason, and cancelled for all of them if the app is turned off or unloaded: an AI car can never again stop on track because of this wait. The log notes the draw, then for each AI car its planned turn and its actual exit (`attente annulee` (wait cancelled) if it left earlier). Never in the race (grid start).
- **Parked Safety Car, reserves and disqualified AI cars**: brought back to their pit box every time they leave it (at most every 10 s), and no longer just once. Your Safety Car had been found outside its pit box.
- Kept from Beta 1.21: **no cascading yields in a queue** (no yields in your two sessions, against 12 AI cars out of 19 at the same time in Beta 1.20).

**Verification**: 351 checks; 84 integration cases; 593 mutations, all detected; engine fingerprints identical to Beta 1.21; clean lint, parameter audit. Soak without errors; core at 30 AI 0.178 ms per frame against 0.187 ms in Beta 1.21, at 60 AI 0.468 ms against 0.480 ms. The native wait (`setAITimeToStart`) in practice and qualifying has not yet been seen in game: the log of actual exits will show it.

## Beta 1.21 — 29 October 2026

Your test of Beta 1.20 (track day on the Nordschleife, 19 AI, 21:23): the cars still glued to one another, crawling. The log showed two causes, now fixed:

- **The AI cars did not stay in their pit boxes**: the exit draw had been made (`sorties des stands etalees: 19 IA, la derniere dans 182 s` (staggered pit exits: 19 AI, the last one in 182 s)), but 18 AI cars were on track after 60 s. Beta 1.20 held them back with AC's stop counter, which only brakes a car (it does stop a crashed AI car on track) and does not prevent it from leaving its pit box. Now, each AI car stays **parked without a driver** in its pit box (the mechanism used for the Safety Car's reserves), with **AC's native wait** before setting off, until its turn. The log notes for each AI car `sortie des stands: tour prevu a X s, sortie a Y s` (pit exit: turn planned at X s, left at Y s): this will show in game whether the exits really follow the draw.
- **Cascading yields in the queue**: up to 12 AI cars out of 19 were yielding at the same time. In a train of identical cars, each had a car glued behind it (“pressure”) or barely faster, moved aside and slowed down without being able to let it by, and the whole queue slowed down. Now, as with yielding between classes: an AI car glued to the car ahead (less than 60 m) only yields to a clearly faster car (15 km/h and more); with a clear track ahead, it yields as before. The player's headlight flash is still always honoured.

**Verification**: 351 checks; 82 integration cases; 593 mutations, all detected; engine fingerprints identical to Beta 1.20 (ordinary spaced traffic does not change); clean lint, parameter audit. Soak without errors; core at 30 AI 0.163 ms per frame against 0.174 ms in Beta 1.20, at 60 AI 0.442 ms against 0.441 ms. CSP functions used for the staggered exit: `setAINoInput` (already used to park the Safety Car) and `setAITimeToStart` (new); neither has yet been seen in game in the pit box at the start of a session, hence the log of actual exits.

## Beta 1.20 — 29 October 2026

- **Wider track day spacing** (your report: 14 identical cars at 100% running one behind the other). Two causes: your first session was detected as qualifying (fixed in Beta 1.19), and the AI cars left the pits in single file. Now:
  - **randomly staggered pit exits** at the start of each session (and at each restart): the AI cars still in their pit boxes each leave in turn, in a random order, about 10 s after one another (at least 4 s), held in their pit box by AC's stop counter (the mechanism of the staggered exit after a red flag). New “Staggered pit exits (s per AI)” setting in the Spacing tab, 0 for a free exit. The log notes `sorties des stands etalees: N IA, la derniere dans X s` (staggered pit exits: N AI, the last one in X s);
  - **larger and more varied target gaps**: base interval 2.5 s (instead of 1.2 s), variation ±45% from one AI car to another (instead of ±35%), speed reduction up to 14% (instead of 10%) when an AI car follows too closely. Update: your settings left at the old defaults take the new ones; a setting you had changed is kept.
- **Repairs at race stops**: each time a damaged AI car stops in its pit box (stop required by the rules, or native stop for fuel), bodywork, suspension and engine are repaired, and it stays there for the time of the repair (3 s plus more depending on the damage, 60 s at most). On by default with all rule sets (“Repairs at every stop” setting under “Mandatory stop in the race”). The log notes the damage repaired and whether AC was already repairing it itself.
- **Endurance** (your request): the rule set explicitly includes **free refuelling over the course of the race** (at the end of each 50-min stint, just what is needed for the next stint, and a native stop as soon as the tank requires it: the number of stops is not fixed), **new tyres** and **repairs** at every stop; all the other Endurance rules are kept (FCY, Slow Zone, pit lane closed, maximum stint, BoP, Pro-Am). Still no mandatory stop imposed.

**Verification**: 350 checks; 82 integration cases; 586 mutations, all detected; engine fingerprints identical to Beta 1.19 for the race and rules scenes, only the track day scene changes (intended spacing); clean lint, parameter audit. Soak without errors; core at 30 AI 0.177 ms per frame against 0.172 ms in Beta 1.19, at 60 AI 0.475 ms against 0.467 ms. CSP functions new to the app, never yet tried in game: `setCarBodyDamage`, `setSuspensionDamage`, `setCarEngineLife` (protected: a missing or failing function is simply ignored; damage read under protection); under a red flag, repairs follow the rule for work in the pits, like tyres.

## Beta 1.19 — 29 October 2026

- **Left column of the Racing Rules tab** (your request): the “Racing rules on”, “Mandatory stop in the race” and “Safety Car” rows work like the list of the Settings tab. Clicking the **title** shows its settings on the right and highlights it, without changing anything; only the **pill** turns the option on or off.
- **Settings filed under their title**: pit stops (number, window, tyres, minimum time, maximum stint, fuel, pit lane closed) now only appear under “Mandatory stop in the race”, and the Safety Car's speed, escalation and model only under “Safety Car”. These two views set the Race profile, the only one where they apply, whatever the profile shown. The neutralisation (yellow zone, FCY, VSC or Safety Car) and the major incident delay stay in “Racing rules on”.
- **Options independent of the rule sets**: mandatory stop and Safety Car combine with any rule set (base, F1 2025, F1 2026, GT, Endurance), which stays highlighted; each rule set gives their initial state.
- **Safety Car on by default in the race**, with all rule sets (your request). With the base rules (local yellow zone), it comes out directly when the incident escalates. **Default model: Ferrari 458 Italia Stage 3** from the base game (`ferrari_458_s3`); another one can be chosen under the “Safety Car” title. It must be on the grid in Content Manager (AC cannot create a car during a session): in the race, the left column reports its absence. Update: the Safety Car is turned on for your Practice, Qualifying and Race, and the Ferrari becomes the model if none was chosen. Safeguard: since the 458 S3 is common as an AI car, as long as you have not chosen the model yourself, several 458 S3s on the grid are competitors and none is removed (only the one in the safety car livery becomes the Safety Car). A model already chosen before the update remains yours, with the Beta 1.4 behaviour. Without a Safety Car on the grid, the local yellow zone stays a local yellow zone.
- **RESET TO DEFAULTS button** at the bottom of the column: values of the highlighted rule set (or of the closest one if it was adjusted on the right), mandatory stop and Safety Car included, for Practice, Qualifying and Race; your preferences (DRS beeps and panel, volume, pit window message) and the Safety Car model are kept.
- **Track day detection fixed** (your report): your last track day on the Nordschleife was declared by Content Manager as a “qualifying” type (`TYPE=2`, whereas your 66 archived track days were of the practice type); the app chose the Qualifying profile, hence no traffic spacing and yields between identical AI cars. A “Track Day” session now always gives the Track day profile (restart the session; if you chose a profile by hand, tick “Automatic profile” again). The other modes are still detected as before (practice, qualifying, race, quick race, hotlap). The test bench now names each simulated session according to its type, like Content Manager.

**Verification**: 346 checks; 81 integration cases; 560 mutations, all detected; engine fingerprints identical to Beta 1.18; clean lint, parameter audit. Soak without errors; core at 30 AI 0.190 ms per frame against 0.212 ms in Beta 1.18, at 60 AI 0.515 ms against 0.482 ms.

## Beta 1.18 — 29 October 2026

- **Mandatory stop in the race and Safety Car toggles** (your request), in the left column of the Racing Rules tab, under “Racing rules on”. They act together on Practice, Qualifying and Race, like the rule sets, and show the state of the Race profile. Each rule set sets them automatically:

  | Rule set | Mandatory stop | Safety Car |
  |---|---|---|
  | Base rules | no | no |
  | F1 2025, F1 2026 | yes (1 stop) | yes, after the VSC |
  | GT | yes (1 stop) | yes, after the FCY |
  | Endurance | no (maximum stint of 50 min, your choice) | yes, after the FCY |

  Mandatory stop turned on: the number of stops set on the right is kept (at least one).
- **Safety Car as an escalation** (your choice): in the race, the rule set's VSC or FCY first responds to the major incident; if the incident escalates, the Safety Car is deployed in its place: at least 2 cars immobilised on track at the same time, or a car immobilised 30 s longer than the major incident delay (long recovery). It is called (pack on the FCY delta for 10 s), leaves the pits, comes in on the following lap once the track is clear, green flag as it enters the pit lane and no overtaking until the line. After a VSC, your delta restarts at +1 s; if the Safety Car is unavailable, the FCY carries on. New “Safety Car if the incident escalates” setting (Common rules section). A Safety Car must be chosen and present on the grid: the left column reminds you of this, as well as of the two cases where the toggle changes nothing (local yellow zone; neutralisation already set to “Safety Car”).
- **Update of your settings**: a profile or custom preset still on the F1 2025, F1 2026, GT or Endurance rules receives the escalation (reported under “To check” on the Home tab); customised rules stay as they are. If a Safety Car is chosen and on the grid, your next races may therefore see it come out after a VSC or an FCY.
- The left column of the Racing Rules tab scrolls with the mouse wheel when the window is short.

**Verification**: 344 checks; 80 integration cases; 540 mutations, all detected; engine fingerprints identical (no Safety Car in their scenarios); clean lint, parameter audit. Soak without errors; core at 30 AI 0.199 ms per frame against 0.184 ms in Beta 1.17, at 60 AI 0.516 ms against 0.504 ms.

## Beta 1.17 — 29 October 2026

- **New Racing Rules tab** (your request), between **Settings** and **Diagnostics**: the Rules section leaves the list of the Settings tab and gets a whole tab of its own. On the left, the toggle that turns the rules on or off for the profile shown (it was in the list of sections) and the championship rule sets (base, F1 2025, F1 2026, GT, Endurance), one below the other, applied together to Practice, Qualifying and Race. On the right, as in the Settings tab: title, choice of the profile shown, description and all the rules settings on two columns (neutralisations, Safety Car, red flag, pit stops, Formula 1 2026, DRS and beeps, GT, Endurance). In English: **RACING RULES**.
- Tooltips and texts that referred to “the Rules tab” now refer to the Racing Rules tab, in French as in English.

Settings, profiles and AI behaviour unchanged (engine fingerprints identical).

**Verification**: 341 checks; 79 integration cases, including one dedicated to the Racing Rules tab (tab order, section removed from Settings, toggle specific to the profile shown and saved, rule sets, editable settings, French name); 516 mutations, all detected; clean lint, parameter audit. Soak without errors; core at 30 AI 0.190 ms per frame against 0.172 ms in Beta 1.16, at 60 AI 0.480 ms against 0.465 ms.

## Beta 1.16 — 29 October 2026

- **Interface in English or French** (your request): small **FR | EN** selector in the header of the settings window, just to the right of **PANIC**. Everything the app displays changes language at once: settings window (tabs, sections, setting labels, choices, status, points to check, diagnostics), tooltips, flag panel while driving (titles, instructions, pills) and on-screen messages. British English with FIA and motorsport vocabulary: Safety Car, Virtual Safety Car, Full Course Yellow, double waved yellow, Slow Zone, delta time, mini-sector, pit lane, pit box, pit window, mandatory stop, stint, refuelling, tyres, compound, chequered flag, drive-through, blue flag, backmarker, slipstream, yielding… Numbers with a decimal point in English, with a decimal comma in French.
- **English on first install**; an existing installation, like yours, stays in French on update. The choice is saved and restored on loading; it is not part of the custom presets.
- Staying in French: the session log (file and event log in Diagnostics), which is used to analyse your sessions, and the name of the “ACAdvancedIA Drapeaux” window in CSP's list of apps (fixed by the manifest, kept so as not to lose its position).
- Buttons whose label is too long for the chosen language: smaller font before the text is cut.
- Red flag tooltip corrected: it also applies in practice and qualifying (behaviour unchanged since Beta 1.12).

AI behaviour unchanged (engine fingerprints identical to Beta 1.15).

**Verification**: 341 checks; 78 integration cases, including a pass through every tooltip in English then in French; 511 mutations, all detected; parity of the two languages (same keys, same formats, same numerical values in each tooltip); clean lint, parameter audit. Soak without errors; core at 30 AI 0.170 ms per frame against 0.163 ms in Beta 1.15, at 60 AI 0.457 ms against 0.438 ms.

## Beta 1.15 — 26 October 2026

- **Hotlap** (your request): by default, only the Rules tab is ticked, with the base rules: flag panel and messages, DRS beep and badge through the normal path (no AI car to drive). A Hotlap profile still empty and never set (Beta 1.10 to 1.14) receives it on update; a Hotlap profile you have set is kept as it is.
- First install still recognised: a profile counts as set if it has been set, or if its tabs differ from its default (the Hotlap's Rules tab does not count as a setting).

AI behaviour unchanged.

**Verification**: 336 checks; 76 integration cases; 489 mutations, all detected; clean lint, parameter audit. Soak without errors; core at 30 AI 0.203 ms per frame against 0.167 ms in Beta 1.14, at 60 AI 0.538 ms against 0.522 ms.

## Beta 1.14 — 26 October 2026

- **Flag overlay as a compact banner** (your choice): flag, bold title and short instruction on one line, delta on the right, version in small type; a thin row of pills only if there are any. Short instructions written for each flag (“Ref. +30% · stay in the green”, “Yellow in 200 m · slow down”…). Blinking reserved for urgent items: red, blue, negative delta, overtake made under a flag, penalty, place to give back, call to the pits.
- **Overlay settings** (Accidents section, common to all sessions): background opacity down to transparent; display only with information or always (“TRACK CLEAR”); display time of non-urgent information (green, start, DRS, last lap, chequered flag, slippery track); flags always stay as long as they are active.
- **More compact settings window** (your request): 900 × 700 by default instead of 1000 × 780, the content following the width; a wider window is brought back to this size only once, on first opening, then the size you choose is respected.
- **DRS**: the badge clears as soon as you open the wing, without coming back under braking in the same zone; the beep sounds again in hotlap (Hotlap profile with no tab ticked), according to the “Player DRS: beep and panel” preference.

AI behaviour unchanged.

**Verification**: 335 checks; 76 integration cases; 485 mutations, all detected; clean lint, parameter audit. Soak without errors; core at 30 AI 0.191 ms per frame against 0.171 ms in Beta 1.13, at 60 AI 0.559 ms against 0.463 ms.

## Beta 1.13 — 26 October 2026

Search for anomalies in AI behaviour in a closed-loop simulator (20 AI, each preset, five minutes: the cars really follow the commanded offset and level, AC's AI is emulated).

- **AI car held up behind a slower one** (race especially): a clearly faster AI car could stay behind for a minute without trying anything. It only knew it was held up at the places where it had already driven alone; caught in traffic, and with AC's AI matching the car ahead, no speed difference appeared. Its free pace is now estimated elsewhere from its class's median pace at that place, multiplied by its relative pace learned where it drove alone (never without this learned pace). Simulation: longest hold-up reduced from 54 s to 5 s in the race, from 82 s to 5 s in endurance; successful overtakes 47 instead of 42; no contact; no more lateral back-and-forth movements.
- **Flags and warnings audited**: all flags, announcements and pills have their title, their instruction and their announcement. Fixed: in practice and qualifying, the red flag announced “Race suspended” and the restart “racing resumes”: it is now “Session suspended” and “session resumes” (panel and message). Black flag: correct instruction whether the disqualification comes from the app or the game; white flag: “Last lap”. New lifecycle test: in the five profiles and with the app off, every AC flag appears with its title and the panel clears as soon as it drops (the start flag clears on its own).
- **Courtesy between drivers measured**: alongside, at least 0.56 m of free space (never less than 0.5 m); when cutting back in after an overtake, at least 8.7 m ahead of the car passed (no cutting back in at less than 5 m).
- Checked without fault: no contact between cars, no zigzagging (about one back-and-forth per minute per AI car, due to manoeuvres and the personal line), plausible queued yields on track days (released after 25 s at the latest), brief, compliant defences (a single move, ending as soon as the attacker is alongside).

**Verification**: 334 checks; 74 integration cases; 475 mutations, all detected; clean lint, parameter audit. Soak without errors; core at 30 AI 0.184 ms per frame against 0.205 ms in Beta 1.12, at 60 AI 0.526 ms against 0.481 ms.

## Beta 1.12 — 26 October 2026

Surgical audit of the presets and their rules (your requests and your choices in the questionnaire).

- **Fuel at enforced stops**: new setting (Rules tab). Refuel at the stop: the AI car takes on just what is needed until the next planned stop or the finish. Race fuel from the start: the AI car starts with the fuel for the whole race and no longer refuels, unless it is not enough to finish. Left to AC. F1 2025, F1 2026 and GT Sprint: race fuel from the start (refuelling forbidden); Endurance and base rules: refuelling. Consumption measured lap by lap (kept per model and circuit for the next race), otherwise AC's estimate; nothing imposed as long as it is unknown; an AC backup stop stays scheduled (never running dry); never the player; everything is handed back to AC on switch-off.
- **Tyres** checked per rule: F1 two dry compounds (except in a wet race), tyres changed under a red flag; GT and Endurance: a new set at every stop, nothing under a red flag.
- **Red flag in practice and qualifying**: session suspended, all AI cars return to the pits, then resumption at the green flag without a restart lap, staggered pit exits. Never on a track day.
- **AI driving mistakes in all sessions**: track day 1 per hour per AI car, practice, qualifying and race 0.5; never at the start, under a flag or near you. The profiles where they were unticked by the old default are ticked (an explicit choice to untick them in the race is kept).
- **Practice**: chained overtakes, as on a track day (the audit spotted it: the qualifying value was applied).
- **Hotlap chosen by hand**: kept after a restart (it reverted to Track day).
- **Hotlap, your feedback**: AC's start flag, raised for the whole session in hotlap, stayed displayed in green in the panel; it is now only shown for 5 s. The panel also shows the player's DRS badge (available, open) when the app drives nothing (hotlap, no tab ticked), and the log notes each change in DRS availability. DRS itself is still decided by AC (each zone activates when passing its detection point): CSP only allows forbidding it, never allowing it earlier.
- **Permanent audit**: a test checks in the engine, for each built-in preset, yielding and its side, overtaking and its side, headlight flashes, chaining, penalties, blue flags, the red flag, spacing, the start, multi-class, the Endurance layer, mistakes, and for each rule set fuel and tyres.

Driving behaviour unchanged (reference scenario statistics identical to Beta 1.11); fingerprints of the rules-enabled race changed by the fuel requests.

**Verification**: 332 checks; 74 integration cases; 469 mutations, all detected; clean lint, parameter audit. Soak without errors; core at 30 AI 0.216 ms per frame against 0.221 ms in Beta 1.11, at 60 AI 0.584 ms against 0.540 ms.

## Beta 1.11 — 26 October 2026

- **AC flags in the panel** (your request): the ACAdvancedIA panel shows all the game's flags and penalties: black flag, drive-through with the laps left to serve it, return to the pits, throttle cut, chequered flag, last lap, the game's blue and yellow. They stay displayed even with the panel unticked or the app stopped (session over, panic, no tab ticked). Penalties are still applied by AC; only their display moves to the panel. Black flag framed in white, black-and-white diagonal penalty flag as in AC, chequered flag drawn.
- **Original flags hidden**: CSP option “Hide race flags in the top left corner” ticked at install (gui.ini backed up first). If it is unticked, the Home tab reports it under “To check”.

AI behaviour unchanged (fingerprints identical to Beta 1.10).

**Verification**: 324 checks; 74 integration cases; 450 mutations, all detected; clean lint, parameter audit. Soak without errors; core at 30 AI 0.182 ms per frame against 0.179 ms in Beta 1.10, at 60 AI 0.534 ms against 0.496 ms.

## Beta 1.10 — 26 October 2026

- **Hotlap profile** (your request): fifth profile, chosen automatically in hotlap, time attack, drift and drag (sessions without AI). Its settings are its own: the Track day profile is no longer modified by these sessions. Neutral by default; penalties and championship rules not applicable, as on a track day.
- **Interface without duplicates** (your requests): three tabs instead of four. The Presets tab is removed: the built-in presets and your custom presets (save, load, delete) are on the Home tab, the championship rules stay at the top of Settings › Rules. The separate diagnostics window is removed: all its content is in the Diagnostics tab (controls at the top, then CSP capabilities; table of AI cars driven, performance and filterable log on the right). The “ACTIVE TAB” button disappears: the toggle in the list does the same thing. The technical notes (level mode, braking zone) are now only in Diagnostics.
- **No more title bar** (no cross or arrow) on the settings window and the flag panel: you move them by dragging an empty area; the settings window follows the pause menu and the app icon.
- **Safety Car** at the top of the Rules section, just after the common rules (where the neutralisation is chosen).
- **Theme everywhere**: the flag panel while driving takes the windows' palette (common neutral tints), rounded corners, an accent bar on the left and the bold title; its tested layout stays the same.
- Profile buttons with short labels (TRACK DAY, PRACTICE, QUALI, RACE, HOTLAP): no more truncated labels.

AI behaviour unchanged (fingerprints identical to Beta 1.9).

**Verification**: 323 checks; 73 integration cases, including the tooltips of every control in the three tabs; 444 mutations, all detected; clean lint, parameter audit. Soak without errors; core at 30 AI 0.191 ms per frame against 0.210 ms in Beta 1.9, at 60 AI 0.546 ms against 0.532 ms.

## Beta 1.9 — 26 October 2026

New interface, full adversarial review of the code and championship rules checked against the regulations.

- **New settings window**: header with the engine status and the APP ON and PANIC buttons, Home, Settings, Presets and Diagnostics tabs. The fourteen sections are listed on the left with their toggle; the settings are shown on two columns: sliders to drag with − and +, right-click for the profile's default value, mouse wheel for long sections. Each control keeps its tooltip.
- **AI car left offset after a side-by-side**: when the target moved back ahead, or stayed just behind at the same pace, the AI car kept its overtaking position indefinitely (no exit planned after the side-by-side). It now moves back in after 4 s without progress; a slow overtake that is progressing is never cut short.
- **Avoidance**: a spinning car sliding towards the chosen side makes the AI re-evaluate the side, never towards it.
- **Defending**: it no longer starts if the anti-zigzag cap would refuse it; this refusal blocked yielding to blue flags for 20 s.
- **Under a yellow flag**: an abandoned overtake no longer immediately sets off again towards another car (abandon counted twice).
- **Penalties**:
  - Illegally passed by an AI car, you can take your place back without a penalty, even if that AI car had just been sanctioned or if AI sanctions are off (you were being penalised).
  - An AI car that overtakes by cutting the track under a yellow flag is sanctioned as it would be on the track.
  - AI cars no longer queue behind a car serving a sanction.
- **Championship rules** (2026 regulations checked: FIA F1, SRO GT World Challenge, FIA WEC): in GT, the pit lane stays open under FCY (SRO, art. 39.4). The other values turned out to comply (DRS after one lap in F1 2025, active wing from the first lap in 2026, pit lane closed under FCY and for three Safety Car laps in WEC, GT window from 25 to 35 min). The double yellow's +15% and the VSC's +30% are presented as the app's values: the FIA does not publish any.
- **Custom presets** saved before Beta 1.8: they now receive the relaxed delta and the race's lane hold, like the profiles (a single shared migration).
- **Track day**: “Restore” and the built-in preset also reset its rules settings to default.
- The pit window message is a preference kept by the rule sets; Personality tab unticked: driving mistakes off; reaction time text corrected (2.5 s).
- Updates to your settings reported in the log and on the Home tab.

Reference scenarios (without physical contacts): on the track day, anti-zigzag cap triggers from 5 to 2 and returns after overtaking from 131 to 140; in the race with 60 AI, triggers from 19 to 15 and `cible plus rapide` (target faster) abandons from 11 to 7.

**Verification**: 321 checks, including the new ones, which fail without their fix; 73 integration cases, including coverage of the tooltips of every control drawn, setting each parameter through the interface, and sixteen custom presets in the window; 435 mutations, all detected; clean lint, parameter audit. Soak without errors; core at 30 AI 0.213 ms per frame against 0.194 ms in Beta 1.8, at 60 AI 0.619 ms against 0.542 ms (alternating measurements, game closed).

## Beta 1.8 — 22 October 2026

Your answers to the questionnaire: retaking a place without a sanction, relaxed delta time, holding the lane into the first corner.

- **Hold the grid lane at the start** (race, Start tab, ticked by default): on the grid, each AI car records its position relative to the racing line; after the green light, it keeps that position while a car is running alongside it and while braking, instead of immediately rejoining the line by cutting across its neighbours; it then rejoins the line gradually, never towards an occupied side. A 0.3 m margin keeps it away from its neighbour. The log notes the position recorded and the deviation measured on the way back: the first race will tell whether the scale of AC's offset is the right one.
- **Retaking a place without a sanction**: a car illegally overtaken under a flag (by you or by an AI) can take its place back without being sanctioned while the flag lasts (seen at Spa: Gryc sanctioned for re-passing you 0.9 s after your throttle cut).
- **Relaxed delta time**: 0.50 s tolerance per mini-sector (0.10 s before; a setting you had changed is kept) and 2.5 s of reaction to the signal (1 s before). Your two penalties at Spa (−1.41 s when the Safety Car was called, −1.57 s under double yellow) correspond, according to the simulation (250 km/h, braking at the approach deceleration), to lifting off 2 to 3 s after the signal: they would no longer be given; lifting off clearly later is still penalised.

- **Diagnosing the `direction_limit` warnings** (log only, driving unchanged): each side change logged carries the intended target before the width bound, and `fige` (frozen) when the target was frozen at the offset of the moment. On a track day at Spa (Beta 1.7), 68 warnings in 12 minutes, mostly yields alternating `YIELD_HOLD>+0` and `YIELD_HOLD>-1`: each trigger cancels the yield or the overtake for 20 s. Probable but unconfirmed cause: the width bound collapsing in corners where the racing line runs along an edge. A fix was tried and then withdrawn, for lack of proof: on the simulator, it increased the number of warnings. Your next session will settle it.

Reference scenarios: track day identical to Beta 1.7; in the race, overtaking and yielding statistics identical, fingerprints changed only by the penalty rules (lane hold only comes into play at a standing start, absent from these scenarios).

**Verification**: 310 checks, including the new ones, which fail on Beta 1.7; 72 integration cases (lane hold end to end, in both of AC's reference frames); 413 mutations, all detected; clean lint, parameter audit. Soak without errors (8 h of track day, one hour of configured race); core at 30 AI 0.157 ms per frame against 0.154 ms in Beta 1.7, at 60 AI 0.430 ms against 0.412 ms (same machine, alternating measurements, game closed).

## Beta 1.7 — 22 October 2026

Analysis of the Spa race (10 laps): AI cars stopped in the middle of the track, queues behind a slow car or one moving aside. Beta 1.6 was not installed on its own: 1.7 contains it.

- **Pass after a yield, in the race too**: an AI that yields (blue flag, headlight flash) is overtaken immediately by the car following it, on the side it frees, with no speed advantage required; likewise when you move clearly aside on a straight (this invitation only existed outside races). Previously, the car behind stayed in line, the yield expired and the flashing started again (Kaisanlahti flashed Kemp a dozen times without ever getting past).
- **Manoeuvres cancelled just after they started**: a yield or an overtake no longer starts if the anti-zigzag cap would immediately refuse its change of side (log: `cede` then `direction_limit` within the same second).
- **Attacks abandoned for nothing**: in the race, an AI no longer gives up overtaking because a car on the same lap is coming up fast behind it (it simply brakes later); only if that car is lapping it or comes from a faster class.
- **AI cars stopped in the middle of the track**: holding a crashed AI now only applies off track; an AI stopped in the middle of the track is returned to its pit box after 20 s (90 s before, without neutralisation: Kuikka 92 s at 4,592 m).
- **Off-track hold not working**: the car taken out of driving control was marked “to be restored”, and the commanded stop was lifted every frame; it now holds. Long-standing bug.
- **Log**: the per-minute summary lists the AI cars not managed and their reason (pits, off track, finished…); passes after a yield are counted separately.

On the reference scenarios (without physical contacts: a trend, not the in-game result), anti-zigzag cap triggers divided by 2 to 4, no abandonment because of a same-lap follower in the race, completed manoeuvres slightly up.

**Verification**: 306 checks, including the new ones, which fail on Beta 1.6; 71 integration cases; 387 mutations, all detected; clean lint, parameter audit. Soak without errors (8 h of track day, one hour of configured race); core at 30 AI 0.173 ms per frame against 0.163 ms in Beta 1.6, at 60 AI 0.482 ms against 0.459 ms (same machine, alternating measurements, game closed).

## Beta 1.6 — 22 October 2026

Continued analysis of the game logs (Spa, Imola) and of your requests.

- **Race start, first corner**: the start caution (distance kept behind the car ahead) and start aggression only applied after the 12 s start delay, so after La Source at Spa. They now apply from the grid, in full until the end of the delay, then return to normal during the settling time, as test R01 of the specification requires (“caution ↑” during the delay). The field arrives more spread out and calmer at the first braking point; AC's AI remains sole master of its line on corner entry.
- **Safety Car released then parked again every frame** after a restarted race, as soon as the lights went out (log: `garee sans pilote` (parked without a driver) every 5 s for 100 s). Long-standing bug: a parked car was marked “to be restored” on a session change, a restoration that could never succeed. It now stays under the parking order.
- **First installation**: Practice, Qualifying and Race start out as if “Base rules” had been clicked (recommended preset then base rules, Rules tab ticked); Track day stays without any commands. An existing installation is never changed.
- **Crashed AI held twice**: an impact detected during its hold (end of a slide) caused it to be held again at the very moment it was released (`repart apres 3.2 s` (rejoins after 3.2 s) then `arretee 5.0 s` (stopped 5.0 s)). It is now held only once per accident.
- **Log**: each session states the ticked tabs and the rule set actually active; each `direction_limit` warning details the side changes counted (AI state, target side, age) and then the refused change, so that the manoeuvre that keeps repeating can be fixed next (at Imola, almost all the AI cars in practice).
- Validation: numbers of checks and cases recalculated from the results (297 checks announced in Beta 1.5 when there were 298).

**Verification**: 302 checks, including the new ones, which fail on Beta 1.5 (and the Safety Car integration case: 600 releases in 10 s on Beta 1.5, none in Beta 1.6); 71 integration cases; 376 mutations, all detected; clean lint, parameter audit. Engine outputs bit-for-bit identical to Beta 1.5 on the three reference scenarios, log texts aside. Soak without errors (8 h of track day, one hour of configured race); core at 30 AI 0.176 ms per frame against 0.173 ms in Beta 1.5, at 60 AI 0.468 ms against 0.461 ms (same machine, alternating measurements, game closed).

## Beta 1.5 — 22 October 2026

Fixes for issues seen in a race (Spa, 32 cars, grid placed before the line).

- **False blue flag at the start**: the game's lap counter only counts completed laps, and crossing the line at the start completes none. A car still before the line therefore seemed to be a lap ahead of the one that had just crossed it: blue flag shown to the player on the first straight, AI cars moving over at the start to let a car from behind through, an AI believed lapped by the player. Now, a car that has completed no lap laps nobody. Long-standing bug, already present in Beta 1.3.
- **Safety Car stuck in the pit lane**: once released, it was still there at the end of the one-minute minimum; the app thought it had come in at the end of the lap and gave the green immediately, in the middle of the track, so the ban on overtaking until the line lasted almost a lap (two sanctions resulted from it in the race analysed). It is now announced as “in this lap” (`rentre ce tour`) only once it is on track, and the green comes when it enters the pit lane, at the end of the lap; still in the pit lane 90 s after its release (estimated delay, to be confirmed in game), it is declared unavailable and the neutralisation ends as an FCY. The log records the time it takes to reach the track (`en piste apres … s` (on track after … s)).

**Verification**: 298 checks, including those for the start (for each of the three effects) and for the Safety Car, which fail on Beta 1.4; 70 integration cases; 366 mutations, all detected; clean lint, parameter audit. Engine outputs bit-for-bit identical to Beta 1.4 on the three reference scenarios: none of the roughly 960,000 lap-gap calculations changes there. Soak without errors (8 h of track day, one hour of configured race); core at 30 AI 0.166 ms per frame against 0.167 ms in Beta 1.4, at 60 AI 0.429 ms against 0.458 ms (same machine, alternating measurements). Still to be seen in game: the start without a blue flag and the Safety Car's exit time.

## Beta 1.4 — 21 October 2026

Full adversarial audit (five independent reviewers: rules and penalties, AI and writes into the game, configuration and dead code, performance, real regulations), each finding reproduced on the bench before being fixed, then covered by a test that fails on Beta 1.3.

**Rules checked against the regulations** (F1 2025 and 2026, WEC 2026, GT World Challenge 2026, Appendix H of the Sporting Code) and the driver's decisions:

- **Five rule sets**: Base, **F1 2025** (DRS), **F1 2026** (Overtake Mode, movable wing with no waiting), GT, Endurance. The old “Formula 1” set mixed DRS (until 2025) and Overtake Mode (2026), which never coexisted.
- **Double yellow** at sector time +15% (the F1 benchmark) instead of +70%; **Slow Zone** at a fixed 80 km/h with the Endurance rules (Le Mans, WEC).
- **GT and Endurance FCY** at the equivalent of 80 km/h (delta +150%), like the fixed 80 km/h of the WEC and the GT World Challenge, instead of +50%.
- **VSC ending** announced (“VSC ENDING”), green flag about a dozen seconds later, delta still judged; a new incident cancels it.
- **Restart behind the Safety Car**: no overtaking until crossing the line, for you as for the AI cars (F1, WEC and GT require it; previously, from the green).
- **Red flag, real resumption**: AI cars released from the pits in classification order, restart lap behind the Safety Car (without it: under VSC or FCY), without overtaking, then until the line. F1: tyres changed under the red flag, the stop counts; GT and Endurance: no intervention.
- **Pit lane closed** under FCY (GT and Endurance) and for three Safety Car laps (Endurance): no AI called in, a stop made with the pit lane closed does not count; “PIT LANE CLOSED” pill.
- **DRS**: one-lap wait only after the start, a Safety Car or a red flag (no longer after a VSC or an FCY, article 22.1 of the F1 regulations); also disabled under AC's native yellow flag.
- **F1 2026 Overtake Mode**: detection once per lap, at the end of the lap, within one second; gain on the straights of the following lap; disabled in the rain, under flags and before the leader passes the detection point after the start or a restart.
- **Stops**: F1 with no real window (stop before 95% of the race, no longer mandatory if the race turns wet); GT Sprint between 25 and 35 minutes in an hour (42 to 58%), with no minimum time (the 50 s of Beta 1.3 do not exist in Sprint).

**Bugs fixed** (found by the audit, all reproduced):

- **Rules tab unticked**: DRS stayed disabled by the rules and opened for the AI cars (settings not neutralised); the delta beeps and their volume went back to their default.
- **Disabled DRS never given back** when the app was turned off with no car followed, or reloaded turned off after an abrupt stop.
- **Safety Car and spares parked on the grid** after “Restart” or when going from qualifying to the race (return to the pit box done only once per process); kept parked during the cool-down lap; a car in the pit lane is returned to its pit box, never parked across the lane.
- **One-make race**: a Safety Car model left set parked the whole grid; no competitor is removed any more.
- **Giving the place back**: retaking a place that an AI gives back was punished (player and AI alike); the overtaken car stayed in line behind the one that owed it the place, which could never give it back (a slowing spiral down to 30 km/h under FCY, then a sanction); firmer lift-off; a pending overtake is no longer forgotten on leaving the zone; an off-track AI keeps the neutralisation regime; the red pill turns green again once the place is given back.
- **Double zone reached from a single zone**: no delta was measured.
- **Messages**: the “restarted outside the pits” penalty and the DRS announcement were erased by the green flag of the same frame; a cancelled red flag (rules unticked) penalised the player outside the pits.
- **Safety Car stopped** on track: returned to its pit box, the neutralisation continues as an FCY (previously, the field was stuck behind it for up to five minutes).
- **Driving mistakes** lost for an AI not under command; never in the first minute of a race, even without the Start tab.
- **AI DRS** closed immediately under braking (up to a second of delay).
- **Player penalty** lost if its native write failed: retried.
- **Safety Car livery** applied by the app: given back to the car that no longer is the Safety Car, and on unload.
- **Custom presets** from Beta 1.0 and 1.1: DRS by the rules and driving mistakes read as off; profile defaults.
- Panel: “+0.00” is no longer red; empty name in “GIVE THE POSITION BACK”; permanent flashing after 24 h of engine time.

**Migration**: profiles and presets still on a Beta 1.3 rule set receive its Beta 1.4 version (“Formula 1” becomes “F1 2025”); elsewhere, only the double yellow leaves the old default, and a value set by the driver is kept.

**Performance** (measured, outputs bit-for-bit identical over 72,000 reference frames): larger JIT compiler cache (the engine recompiled all its code every one to two minutes) and cars driven in a single protected call when this cache is accepted; AI sanctions skipped when there is no flag; fleet pace in a single pass; CSP vectors read only once; built-in preset signatures memoised; panel with no closure created and no layout rebuilt every frame.

**Clean-up**: distribution zip reduced to the app and its documentation; old packages and outdated bench results removed; leftovers of the km/h limits (speed limit sign, constants, tooltip and validation texts) removed; global settings that were never read removed; the same migration rule is no longer written twice; the parameter audit no longer counts tooltips as consumers.

**Verification**: 296 checks (including a test that fails on Beta 1.3 for each bug fixed), 70 integration cases, 359 mutations, all detected, clean lint, parameter audit; soak without errors (8 h of track day, one hour of configured race); core at 30 AI 0.162 ms per frame against 0.273 ms in Beta 1.3, at 60 AI 0.437 ms against 0.644 ms (same machine, alternating measurements), if CSP accepts the larger JIT cache (`compilateur JIT` line of the log); otherwise, roughly the cost of Beta 1.3 despite the new rules (30 AI: 0.25 to 0.27 ms against 0.26 to 0.29 ms). Engine outputs bit-for-bit identical before and after the performance layer (72,000 frames, cars one by one and in a single call). Still to be seen in game: CSP accepting the JIT cache, the new rules and the livery skin.

**Not adopted** (documented): graduated penalties through native drive-throughs or stop-and-gos (never checked in game, they invalidate the lap), place given back for any overtake under flags, wave-by, Code 60, DTM set, “slippery surface” flag kept for four laps, VSC at +35% (your choice: +30%).

## Beta 1.3 — 21 October 2026

- **Safety Car livery** (seen in game, Content Manager “Manual” grid: the Mercedes picked did not have the safety car livery, liveries being drawn at random). Among the cars of the model, the one wearing a “safety” livery (`Safety_Car`) serves as the Safety Car; if none wears it, the app applies that livery to the chosen car (CSP skin, once, written to the log).
- Reminder: the other cars of this model stay parked in the pits and never race, but AC has loaded them: they appear in the driver list and the classification. A “Custom” grid with a single Mercedes keeps all the opponents.
- Verification: 274 checks, 63 integration cases, 285 mutations, all detected, clean lint; soak without errors (including one hour of configured race); benchmark 30 AI 0.239 ms, 60 AI 0.603 ms. The CSP livery skin is still to be seen in game.

## Beta 1.2 — 21 October 2026

Seen in game on Beta 1.1: an FCY triggered at over 250 km/h earned the player a penalty. The log shows an **overtaking** penalty 1.7 s after the FCY (an AI was braking harder), not a speeding one. Eight AI cars were also sanctioned just after a yellow zone, two of them for overtaking the player. Complete overhaul, based on how an F1 steering wheel works:

- **Delta time** instead of km/h limits, for you as for the AI cars. Reference time: your usual pace at each point (the faster of yours and your class's; the AI cars' as long as yours is not known; fallback speed on the very first lap), slower by a percentage: **VSC +30%**, **FCY +50%** (also while the Safety Car is being called, never faster than the Safety Car minus 30 km/h), **Safety Car** on track: FCY delta until the queue, **red flag +60%** until the pit lane, **double waved yellow +70%**, reset at the zone entry. Penalty on crossing a mini-sector (roughly every 250 m) in the negative beyond 0.10 s. Start at +1 s, cap at +3 s, braking from your speed at the signal always tolerated: the case seen (250 km/h, 1 s of reaction, braking at 5 m/s²) is tested with and without learned pace.
- **Double or single yellow**: incident on track, double yellow (zone delta); off track, single yellow (slow down, no overtaking).
- **Place to give back**: an overtake made during the transition (10 s after the flag) is forgotten if the place is given back, otherwise sanctioned when the deadline expires. “GIVE THE POSITION BACK” pill. The AI cars too, when a neutralisation or a red flag is triggered: they lift off to give the place back.
- **AI cars in line under any flag** (yellow zone and its approach included): never faster than the car ahead, beyond a slight closing up; never queuing behind a crashed or very slow car. Fixes the series of sanctions seen after a yellow zone.
- **Panel**: large delta time in green or flashing red, delta beeps (new sound, higher-pitched than the DRS one), flashing “RED FLAG” and “PIT” pill, flashing blue with the gap of the car lapping you, **slippery surface** flag (yellow and red stripes) when the rain starts, “!!” for the double yellow.
- **DRS rules** for all cars (player and AI), like race control in F1: not allowed during the leader's first lap after the start and after each restart, laps measured by the app on the track (F1 rule since 2024; two laps before that; DTM did not allow it on the first lap), disabled in the rain and under flags. On-screen messages and the reason on the panel. Practice and qualifying: rain and flags only; never on a track day.
- **AI DRS**: opened in the zones when it is available, on straights and when not braking, closed again under braking; openings counted every minute in the log.
- **AI driving mistakes**: wheel lock-up under braking or wheelspin on corner exit (native CSP functions), more frequent for a weaker, tired or distracted driver or in the rain; adjustable (0.5 per hour per AI by default); never under a flag or just after, at the start, at pit exit, side by side or near you.
- Settings: “VSC / FCY / Red flag / Double yellow: reference time slower by (%)”, “Delta: mini-sector tolerance”, “Delta: beeps”, “DRS: racing rules”, “DRS: leader laps before enabling”, “AI DRS”, “AI driving mistakes” and their rate. The old speeds become fallback speeds (unknown pace); “VSC reduction” and “speed tolerance” are gone.
- **Safety Car and Content Manager's “Manual” grid** (seen in game: half the opponents were Mercedes safety cars, the opponents being drawn at random from the candidates): the first car of the model serves as the Safety Car, all the others stay parked in the pits in every session and never race (previously: none parked, FCY fallback). “Custom” grid: a single one, with no opponents lost.
- Verification: 273 checks, 62 integration cases, 281 mutations, all detected, clean lint; soak without errors, including one simulated hour of configured race (6 neutralisations, average cost 0.205 ms at 30 AI); benchmark 30 AI 0.239 ms, 60 AI 0.593 ms. Panel checked on a mock-up taken from its real layout; beeps, `allowCarDRS`, `setCarDRS` and driving mistakes are still to be seen in game.

## Beta 1.1 — 21 October 2026

- **Safety Car not found in the list** (seen in game: “Aston Martin Vantage safety car 2021” missing). The list only showed folder names (this car is stored in `aston_vantage2018`) and only the first 63 out of 342. It now presents **all** installed cars under the name displayed by Content Manager followed by the folder, sorted by name; the filter searches both; the chosen car is also displayed under its name.
- Verification: 259 checks, 60 integration cases, 229 mutations, all detected, clean lint; soak without errors; benchmark 30 AI 0.234 ms, 60 AI 0.633 ms; car database checked on a real folder of 343 cars.

## Beta 1.0 — 21 October 2026

- **New numbering**: 1.8.0, validated in game by the driver, becomes **Beta 1.0**; the previous versions keep their old number below.
- **Version shown at the top of every window**: settings, diagnostics and the flag panel while driving.
- **Flag panel redesigned** to be read at a glance: banner in the flag's colour and version at the top; flag with its symbol (SC, VSC, FCY, “!”, P) or DRS badge; instruction in large type; **speed limit sign** (white circle with a red ring) and **your speed in large type**, green at or below the limit, orange above it but still in time to brake, flashing red beyond what is allowed (the colour follows the penalty rule exactly); “No overtaking” (green, red after an overtake), “DRS disabled” and penalty pills. TrueType text at the intended size; layout tested without overlap from 360 × 80 to 900 × 220. Same flags, same priorities and same texts as before.
- **Driver's decisions** (questionnaire of 21 October):
  - **red flag**: you too must return to the pit lane; the restart waits for you (at most until the maximum delay) and restarting outside the pits is penalised;
  - **VSC**: target speed shown on the panel (your learned pace at that point, reduced as for the AI cars), penalty beyond a 10% margin and only where your pace is known; your pace is no longer learned under flags;
  - **mandatory stops**: yours are counted, recalled on the panel when the window opens and towards its end, and a stop still missing when it closes is penalised;
  - **neutralisations** (FCY, VSC, red flag): an AI never drives faster than the car ahead once it has joined the queue, as behind the Safety Car;
  - **Safety Car**: the model must be unique on the grid; if several cars are that model, none is parked and the Rules tab says so.
- Verification: 259 checks (including the 78 from the PDR), 59 integration cases, 223 mutations, all detected (`tests/mutate.py`), clean lint; 8 simulated hours of soak without errors; benchmark with the game closed at the level of 1.8.0 (30 AI 0.211 ms, 60 AI 0.572 ms). The panel rendering was checked on a mock-up taken from its real layout; it is still to be seen in game.

## 1.8.0 — 21 October 2026

- **AI that stayed behind you on a track day** (reported in game by the driver, reproduced on the bench; see also the class fix further down, which prevented an AI still learning from overtaking you). To overtake, an AI had to arrive clearly faster than you or know it was held below the pace learned at that point; an AI that had been following you for a long time had never driven freely at that point and never overtook at equal speed, even when you moved aside. Now, **invitation to pass**: outside races, when you move at least 2 m off the line of the AI following you (within 40 m), on a straight and without overtaking another car yourself, for more than half a second, it pulls out on the side you free, with no speed advantage required and even if the setting imposes an overtaking side. It does not hand the place back to you right away if you follow it closely (20 s). Moved aside by up to 6 m, outside its lane, you invite it too; in a train, the following AI cars are invited in turn. Bench: at equal speed, overtake started in under 2.5 s (never in 1.7.2); no invitation in a long curve, when you are overtaking, in a race or with no offset.
- **Flag and DRS at the same time** (seen in game: in a DRS zone under a yellow flag, only the DRS was displayed). The panel also shows AC's native yellow flag (a slow or stopped car that it reports without an app incident); a flag always keeps priority, with a red “DRS disabled under flags” line if DRS is available, and the DRS beep never sounds under a flag (it sounds at the end of the flag if the zone is still active).
- **Pit exit without contact** (seen in game: as soon as the limiter ended, the AI cars charged into the car ahead). For 15 s after leaving the pit lane, an AI with a car ahead within 80 m (including you) can only close in on it with a small speed difference (7.5 to 15 km/h depending on its confidence), which shrinks with distance and turns negative under 12 m; it also brakes earlier (caution ×1.5). Lateral offsets stay restrained near the pit lane, to respect the exit line as closely as possible.
- **Adversarial review of the driving**:
  - a car glued behind its target is no longer mistaken for a car alongside: the AI waiting to pull out (race) no longer skips this wait in the middle of a corner;
  - no pulling out under braking (PDR §10.2.4), nor towards a target already occupying that side;
  - an overtake pulled out with no closing in at all for 8 s is abandoned instead of staying pulled out indefinitely; the wait behind the target in a race is capped at 20 s;
  - obstacle avoidance: never towards an offset obstacle (opposite side closed: the AI slows down), side kept throughout the avoidance (no more weaving);
  - a crashed car close in space but elsewhere on the layout (bridge, crossing) no longer triggers avoidance;
  - defence interrupted under braking even when the Rules tab is unticked;
  - contact detection by yaw removed: it could never trigger (behaviour unchanged).
- **Adversarial review of the sanctions and the race**:
  - **speed under a yellow flag**: the faster you arrived in a zone, the longer the braking delay granted (13 s at 250 km/h, for a zone crossed in 5 s): any arrival above about 150 km/h escaped the penalty. Now your speed is judged like the AI cars': the limit at the start of the zone, plus what the approach deceleration (5 m/s²) allows you to shed over the remaining distance. The approach panel appears early enough to brake this way from your speed (about 205 m at 150 km/h, 680 m at 280 km/h) and shows the distance to the **start of the zone** (“Yellow zone in 240 m”; before: the distance to the incident, 300 m further on); zone reported too late (incident just ahead): a delay to slow down from your speed;
  - no overtaking for the player too from 150 m before the zone, as for the AI cars (the panel's “No overtaking” line appears at that moment; speed, for its part, is judged from the approach panel); under a neutralisation, a slower yellow zone applies;
  - FCY limit while the Safety Car is called or still in the pit lane (before, never checked);
  - no more sanctions for an AI or the player overtaking a car that has gone off track, nor for places gained through the pit lane;
  - an AI serving a sanction (lifting off, now gradual: never sudden braking in front of the overtaken car) or the player with the throttle cut can be overtaken, without a chain reaction; so can a crashed car that has just rejoined, for as long as the zone is held; a single sanction per AI every 20 s, as for the player;
  - Safety Car still in the pit lane: the 80 km/h limit stays displayed (it applies); no yellow zone for the player in the pit lane; AC's native yellow flag without a “No overtaking” line (never judged);
  - a crashed car that stayed off track for a long time becomes an incident again if it comes back onto the track without driving off;
  - disqualified AI: no longer counted in the mandatory stops; an AI that has finished no longer holds a pit call slot;
  - log: a real stop is no longer also counted as a discarded stop; tyres outside any category counted as `inconnus` (unknown); overtakes with no closing in and invitations by the player counted;
  - panel infringement counter updated when the number allowed changes.
- **Adversarial review of the settings, the interface and the writes**:
  - Safety Car parked in the pits in every session as soon as its model is chosen (before, only in the profile set to “Safety Car”: in practice and qualifying, it drove like an ordinary AI);
  - Accidents tab unticked, Rules ticked: the flag panel and the messages keep your choice (before, they came back switched on);
  - built-in preset: your preferences (panel, messages, HUD flag, DRS and beep volume) and your class patterns are kept, like the championship rules (before, loading “Multi-class endurance” erased the patterns it needs);
  - custom presets: saved before 1.6.0, they loaded with penalties off in race, practice and qualifying (a 1.7 preset whose two penalties had been deliberately unticked finds them ticked again: untick them and save it again); an invalid value is now replaced by its default value and logged instead of making the preset disappear;
  - settings with no effect hidden and reset to their default value: penalties on a track day, stint variation and degradation in practice and qualifying; unticking “Automatic profile” keeps the current profile (before, it went back to the last profile chosen by hand, for example track day in the middle of a race); “Restore this profile” keeps the preferences and class patterns; Safety Car choice visible as long as a model is selected; the Start tab no longer delays avoidance outside races; penalty messages subject to the “On-screen incident messages” option; “Last preset loaded” shows the button's name;
  - writes: neutral values (player flag, parked car, pit stop request, brake, speed, grip, original level) given back even after a series of failures of the capability; black flag lifted on unload, on disabling and on a session change, never during a recalibration, and imposed again after an app reload; stops and sanctions saved on their own timer and on unload; disqualifications and infringements kept across an app reload (before, a disqualified AI drove off again);
  - log: an app reload continues the same file (before, three reloads erased the real previous launches); the size limit really stops the writing;
  - flag panel: a display error no longer switches the panel off for the whole session; fonts always restored; unplayed beep released;
  - bench: errors caught on shutdown, on restoration, on a session change and in the interface now make the tests fail;
  - **classes**: an AI still learning its pace (start of session, pit exit, traffic) was taken for a slower class as soon as the others, player included, were classified: it yielded and no longer overtook anyone, not even on invitation. Classes are now only compared between classified cars;
  - overtaking corridor: it follows the lateral reach set in the global options;
  - clean-up: fields never read removed, comments and tooltips aligned with the code, documentation (windows, rule sets, order of the measurements, review history, SDK notes), package (lint SDK fields, current results only), mutation bench shipped (`tests/mutate.py`);
  - speed judged from the approach panel (moved earlier depending on speed), no overtaking only within 150 m of the zone and inside it, as for the AI cars;
  - tooltips and documentation updated (DRS badge, messages, Accidents and Rules tabs, preset name in bytes, replay, tyre change in the pit lane).
- Verification: 257 checks (including the 78 from the PDR), 58 integration cases, 209 mutations, all detected (`tests/mutate.py`), clean lint, no errors caught; 8 simulated hours of soak without errors, stable memory; benchmark with the game closed: 30 AI 0.193 ms, 60 AI 0.554 ms. The new features are still to be checked in game ([VALIDATION.md](VALIDATION.md)).

## 1.7.2 — 20 October 2026

Includes 1.7.1, which was not installed separately (louder DRS beep, 200% by default at the driver's request; DRS badge distinct from the green flag).

- **No more tyre back-and-forth in the rain** (seen in the 1.7.0 logs at Spa: 178 `W -> I` changes in a few minutes for AI cars parked in the pits). The app fitted intermediates in moderate rain, CSP's rain logic immediately put the wet tyres back on, and so on. In the rain, an AI on intermediates or wet tyres now keeps them; the app only steps in on the wrong category (dry tyres in the rain, wet tyres in the dry), as requested: in the dry, one of the dry compounds; in the rain, intermediates or wets.
- 1.7.0 logs (Spa, track day, 20 to 24 cars): no false stopped-car incidents or avoidance in traffic jams, against 251 incidents in 3 minutes on the Nordschleife in 1.5.1.

## 1.7.1 — 20 October 2026

- **Louder DRS beep** (reported twice in game by the driver: audible but too quiet). The file is already almost at maximum (peak at -3 dB); the cause was CSP, which by default reduces an app sound heard from the cockpit to 25%. The beep is now at the same level whatever the camera, on the game's main channel (only the master volume applies), at 200% by default: eight times louder than in 1.7.0 in cockpit view. “DRS: beep volume (%)” setting in the Rules tab, from 25 to 400%.
- **DRS badge distinct from the green flag** (seen in game): instead of the green square, a dashboard-style “DRS” badge: white frame and white lettering when DRS is available, solid white light and black lettering when it is open.
- `src/applier.lua` gets its original line endings back.

## 1.7.0 — 20 October 2026

**Escalating sanctions under a yellow flag** (driver's request):
- each infringement is counted per driver for the session: speeding or overtaking for you, overtaking for an AI (in a yellow zone, under neutralisation or a red flag; overtaking a crashed, stopped, very slow, pitting or off-track car is still allowed);
- up to the number of infringements allowed (5 by default, adjustable): throttle cut for you, a few seconds lifting off for an AI (its speed is limited to 70% of its speed at that moment);
- beyond that, disqualification: AC's native black flag for you; for an AI, return to its pit box and car parked until the end of the session (retirement), announced on screen with its name;
- the flag panel shows your counter on the “No overtaking” line (for example “infringements: 3 / 5”), and the log details each sanction;
- “AI sanctions under yellow flags” option in the Accidents tab: ticked in practice, qualifying and race, never on a track day.

**Wet tyres in the dry, cause found**: the 1.5.1 logs show that, on the Nordschleife on a track day and in practice, AI cars appear in the pits on intermediate tyres on a dry track. The app changed them, but only when stopped in the pit box and once per second: the AI cars that left right away kept their intermediates until the next stop (3 to 8 cars out of 40 to 61 in the summaries). The right compound is now fitted as soon as the AI is in the pit lane, even while moving.

**Verification**: 235 checks, 57 integration cases, 140 mutations, all detected (including those for the sanctions, the DRS, the overtaking indicator and the tyres in the pit lane); cost per frame unchanged (0.20 ms at 30 AI, 0.54 ms at 60 AI). The 1.7.0 soak finished without errors (1,728,000 frames, 40 AI): mean at 30 AI 0.218 ms, P99 0.395 ms, raw maximum 1.8 ms; memory between 3.24 and 3.53 MB outside garbage collector passes, with no trend.

## 1.6.0 — 20 October 2026

Full review requested by the driver: four independent adversarial reviews (race management, reading from and writing to the game, driving engine, settings and interface), each finding checked in the code before fixing, a test that fails on 1.5.1 for each fix and a mutation that proves it.

**New: player penalties under yellow flags** (requested by the driver, Accidents tab, practice, qualifying and race, never on a track day):
- speeding above the displayed limit plus the tolerance (5 km/h), for more than 2 s, in a yellow zone, under FCY, with the Safety Car called or under a red flag, after allowing time to brake from your speed at the moment the limit applies (an incident just ahead of you puts the yellow zone around you: at 200 km/h, about 9 s; at least 10 s at the start of a neutralisation);
- overtaking under a yellow flag, neutralisation or red flag, except a crashed, stopped or very slow car, or one in the pits or off track; an overtake already side by side when the flag applies may be completed;
- AC does not add time to the classification: the closest native penalty is applied, a throttle cut (5 s, adjustable), only once per infringement, announced on screen, shown in red on the panel and written to the log.

**New: flag panel** (requested by the driver):
- “No overtaking” line under the instruction of each flag that forbids it: green, then red as soon as you have passed a car under that flag, even at the right speed; it returns to normal when the flag ends (also on a track day, without a penalty);
- your car's DRS: a beep (your `sounds/drs-available-beep.wav` file) when DRS becomes available, and a “DRS AVAILABLE” then “DRS OPEN” panel while the zone is active. Availability is AC's own (the track's DRS zones, the one-second rule); the app does not operate the DRS. Flags keep priority. “Player DRS: beep and panel” option in the Rules tab, outside the F1, GT... rule sets;
- default window size raised to 620 × 150 for these lines (a size already set is kept).

**Incidents and neutralisations**
- Traffic jams: the 1.5.0 log (Nordschleife, 35 cars, 4 minutes) counted 262 “stationary incidents”, 133 yellow flags for the player and up to 115 avoidances per minute. It was the field moving at 10 to 25 km/h behind the start. Now:
  - a car only counts as “stopped” below 10 km/h;
  - it only becomes a stationary incident after it has been moving: no more false incidents at the start of a track day or at the pit exit;
  - in a queue, only the car at the head of the queue is an incident;
  - an AI only steers around a slow car if it comes up on it at least 15 km/h faster, or if that car is an incident. In a traffic jam, it follows instead of dodging (clarification of PDR §10.8).
- Major incident (neutralisation, red flag): only a car that is truly stationary, no longer a car moving at walking pace.
- A neutralisation lasts at most 10 minutes; an AI in an incident, stationary on track, is brought back to its pit box after 20 s of neutralisation, and after 90 s outside a neutralisation (Accidents tab). A car waiting in a queue or that has not yet moved never is.
- Log: every minute, the stops dismissed by these rules (queue, start or pits, car at walking pace) and the traffic jams followed without avoidance; each penalty names the zone and the incident involved, the limit and your entry speed, or the car passed; each recovery gives its reason and how long the car was stationary.
- Safety Car: a new major incident during its in lap keeps it on track.
- VSC: the pace reference is frozen at the start of the VSC (no more spiral down towards 30 km/h when the usual pace is not known); the usual pace is no longer learned under a yellow flag or under a spacing limit.
- Only one on-screen message per frame: the most important one wins.
- Accidents tab unticked and Rules ticked: neutralisations and the red flag are still shown to the player (panel and messages).
- Player's blue flag kept as long as the passing car stays right behind.

**AI driving**
- Avoidance: a car alongside no longer prevents avoiding an obstacle on the free side; avoidance ends as soon as the target moves off at speed again; the obstacle search targets the nearest one and no longer overwrites the tracked target.
- Return to the line and manoeuvre endings aim for the offset that can actually be reached (unknown track width, narrow zone, maximum offset): no more AI stuck in “return” for the whole session.
- Overtaking: a car alongside no longer skips the wait before pulling out; pulling out on a straight only (PDR §10.2.4).
- Lapped car behind two leaders in a close fight (less than 2 s, less than 4 km/h apart): it stays behind (PDR §10.17.4).
- Defending: never during the anti-weaving rest, never under braking.
- Caution no longer rises when overtaking or in the slipstream; emergency release never held back, even with a factor of 1; consistent patience.
- A car rejoining the track right alongside counts towards side occupancy.
- Blocked-yield counter reset outside free driving.

**Writes to the game and restoration**
- Restoration attempted even after a series of write failures; each unloading step is protected; brake also released in the pit lane; native yellow flag handed back to AC even with no tracked car (app disabled, reload).
- Drawing error in the settings windows: logged once, the engine carries on.
- Timers realigned on a clock rollback; tyres fitted at a new car's first stop; original rain strategy never re-read from the value the app has just restored; remembered stops forgotten when the session restarts.
- Pit calls limited without ever withdrawing the call of an AI already on its way.

**Settings and interface**
- “Restore this profile” keeps the ticked tabs and the chosen racing rules, as the tooltip said.
- Rule buttons on a first install: each profile also receives its recommended preset (before, it only kept the Rules tab).
- Integer settings (reactions, red flag cars, stops, penalty) rounded and displayed without decimals.
- Overtake aborted by a yellow flag counted separately in the log.
- Tooltips and documentation corrected (tyres at every stop, Endurance preset, red flag, HUD flag, blue flags by laps).
- Dead code removed (strings, constants, unreachable headlight-flash band), two duplicated restorations factored out.

**Verification**: the realistic wiring simulation (each parameter on a closed circuit with corners, stops, accidents and rain) shows that dependent settings take effect once their parent is enabled; neutralisation now also works in the simulation (before, the queue triggered the red flag).

## 1.5.1 — 20 October 2026

Urgent fix, found by the full adversarial review requested by the driver.

- **Angle normalisation restored** (1.5.0 regression): the text-wrapping function added for the flag panel had the same name as the one that brings an angle back into [-π, π[, and replaced it. Each time a car's heading crossed ±180° (at least once per lap), the yaw rate read jumped sharply, the corner factor dropped to zero for about a second, and the slip could reach 360°: manoeuvres held back, cars at speed taken for obstacles, false spins and possible yellow zones. The two functions now have distinct names.
- **Flag panel, layout** (spotted in game on a screenshot): the title was hidden by the CSP window's title bar. The content now starts from the visible area below that bar, the block is centred vertically, the instruction is wrapped at the window's actual width, and the title switches to the normal font if the window is short.
- **Transparent flag window** (requested by the driver): its title bar and frame are no longer shown while driving, only when the mouse hovers over it to move it; with no flag, nothing is visible.
- **Live player speed** (requested by the driver): under a speed instruction (yellow zone, FCY, Safety Car called, red flag), the panel shows “Your speed: 63 km/h”; instruction and speed in red above the limit, in green at or below the limit.
- **Wet tyres in the dry on track days and in practice** (spotted by the driver): the 1.4.0 fix only applied on the grid before a race start. In the first fifteen seconds of any session, a stationary AI now receives, on the spot, the compound suited to the weather (in the dry: a dry compound; in the rain: intermediates or wets).
- **Log, tyre diagnostics**: weather read at the launch of each session and at each profile change (wetness, rain, water, the app's decision, and whether the current profile manages tyres: without the Weather tab ticked, the app never touches the tyres), breakdown of the AI tyres in each summary (dry, intermediate, wet, unknown), and each compound change made by the app with its names (for example `W -> M (sec)`, “sec” meaning dry). If some AI still run on wets in the dry, the log will say whether the app believes the track is wet or whether the compound came from elsewhere.
- **Code check**: a module or local function defined twice at the same level is now rejected (the cause of the regression).
- Tests: game reading on a heading that crosses ±180° (continuous yaw rate, zero slip), failing on 1.5.0; panel placement below the title bar, tall and short window; speed colour above and at the limit; tyres adapted on spawning at the start of a track day, weather and tyre log, unticked Weather tab reported. 187 checks, 50 integration cases, 68 mutations all detected. Eight-hour simulated soak without errors, stable memory (3.05 to 3.30 MB excluding garbage collector passes).

## 1.5.0 — 20 October 2026

Clearly visible flags and a red flag, following the driver's choices (“panel only”, “full procedure”). AC does not allow its original flags to be redrawn, and its red flag (SessionSuspended) does not work in CSP.

- **ACAdvancedIA flag panel**: new driving window “ACAdvancedIA Drapeaux” (Flags), with no background, movable, opened automatically when a flag appears (if the driver closes it, it stays closed until the next flag). Large coloured flag and instruction: red; Safety Car (called, on track, in this lap); FCY or VSC; yellow with the distance to the incident rounded to 10 m and the maximum speed, or “incident zone”; blue when a faster car is lapping you (race); green at the restart. Nothing is drawn without a flag. Classic drawing functions only (no DirectWrite); a drawing error is logged once and never stops the engine.
- **AC's native yellow flag no longer forced**: “AC native yellow flag on the HUD” option off by default; one-off migration of the profiles and custom presets saved before 1.5.0.
- **Red flag (race)**: when at least three cars are stationary on track at the same time (stopped for 5 s, below 5 km/h; a spinning car still moving does not count; player excluded; adjustable from 2 to 10), the race is suspended. Any neutralisation in progress is lifted (Safety Car recalled), all AI at 80 km/h at most without overtaking, brought back to their pit box and held there; an AI stopped on track for 8 s (below 5 km/h) is recovered to its pit box, never an AI moving at walking pace. Green flag once all the AI are in, the track is clear and the minimum suspension (60 s) has elapsed; at the latest after a lap and a quarter at the return speed, plus the pit lane and the minimum suspension (about 8 minutes at Spa, 5 to 30 minutes depending on the track). A stop under the red flag does not count as a mandatory stop. A forced restart does not trigger a new red flag on the same stuck cars. AC's race clock keeps running.
- Tests: 186 checks and 50 integration cases; 62 targeted mutations all detected, including 17 on flags. The soak does not trigger a red flag: these paths are covered by the checks and the integration cases.

## 1.4.0 — 20 October 2026

Interface, championship rules and tyres, at the driver's request and based on the log of the Nordschleife session (13 cars, 1.3.6).

- **Clear highlight of the chosen item**: the selected tab stays highlighted (blue, white text) while it is shown, like the recognised profile, presets and rules. CSP's “active” flag alone only lightened the background slightly.
- **Tooltips everywhere, in French**: every setting (135), every global option (11), every tab, checkbox, button, list and field, in both windows. Each tooltip explains the function based on the code that applies it (where it acts, in which profile, effect of a higher or lower value), then gives the profile's default value and the range. Lines wrapped by hand, decimal comma, texts prepared only once.
- **Selectable championship rules**: the Base, Formula 1, GT and Endurance buttons are always visible in the Rules tab, even when it is unticked. In Track day, the highlight shows the rules of the Race profile, the ones the buttons set; previously, the chosen button never lit up in this profile.
- **Rules independent of session presets**: loading Realistic race, Free practice or Qualifying keeps the chosen rules, and a preset stays recognised whatever the rules. Multi-class endurance in the race applies the Endurance rules (FCY, Slow Zone 80 km/h, BoP, Pro-Am). A preset button lights up when the profile it sets carries that preset.
- **Profile shown separate from the profile in use**: with the automatic profile, clicking Track day, Practice, Qualifying or Race shows that profile to view or adjust it, without unticking detection. The 20 October log showed three launches left on `J (manuel)` (manual) after a single click. Without the automatic profile, the click always chooses the profile used.
- **Suitable tyres from the grid**: before the green light, stationary on the grid, an AI that started on a wet compound on a dry track (or a dry compound in the rain) immediately receives the suitable compound, instead of stopping on the first lap. In the dry, a dry compound already chosen is kept; otherwise each AI receives its own compound among the car's dry compounds (hard, medium, soft, super soft...). In the rain: intermediates, or wets if the rain is heavy. The log records each change made on the grid.
- Tests: 181 checks and 48 integration cases; 45 targeted mutations all detected, including 14 on the interface and tyres; tooltip coverage checked control by control on the four profiles and the fourteen tabs.

## 1.3.7 — 20 October 2026

Following the fifth session log (practice at Spa, 20 cars, 1.3.6): 20 yields started, none completed; 14 overtakes attempted, none successful; some fifty `direction_limit` warnings; two AI cut off by the cap at the very moment they were yielding after a headlight flash.

- **Yields interrupted in corners** (defect present since 1.0.0): in a corner, the yield and overtaking offset shrinks (PDR, 40% at the tightest) then recovers on the exit, and yaw noise makes it vary slightly on a straight. The anti-weaving cap counted each of these variations as a change of direction; after about 7 s, it cut the yield and the AI went back to its line. On the bench, with yaw smoothed as in game, 1.3.6 interrupted every yield in a corner or with noise; 1.3.7 completes them all.
- **New definition of a change of direction** (PDR §7.5): a change of the targeted side (left, line, right). Following a target that varies on the same side is neither counted nor held back by the delay between directions; a real back-and-forth from one side to the other stays capped (test unchanged). Small corrections on a straight unchanged on the bench (12 to 16 cm peak to peak, as in 1.3.6).
- **`manoeuvres interrompues par blocage` counter** (manoeuvres interrupted by the anti-weaving block) in the log summary: yields and overtakes cut off by the cap, which were counted neither as successful nor as aborted.
- The bench overtakes in corners already succeeded in 1.3.6: their low success rate in the pack is not explained by this defect; the new counter will settle it.
- Tests: 180 checks and 44 integration cases; 31 targeted mutations all detected; three of the four new tests fail on 1.3.6 (the fourth, overtaking in corners, is a guard); line variation test strengthened (maximum variation).

## 1.3.6 — 20 October 2026

Following the fourth session log (race at Spa, 25 cars, pile-up at the chicane, 1.3.5):

- **Safety: avoidance takes precedence over the anti-weaving rest** (defect present since 1.0.0). A resting AI coming up on a stopped car switched every frame between avoidance and normal driving (964 entries into avoidance in one minute during the pile-up) and was pulled back towards the centre, and so towards the obstacle: 0.37 offset instead of 0.60 on the bench. In line with PDR §7.5, avoidance, recovery and emergency release are no longer held back or counted by the cap, and the rest no longer interrupts them.
- **Slow incident**: a car that stays below 25 km/h after a spin remains the same incident until it moves off again (observed: spin then stop counted as two incidents).
- **Detailed aborts** in the log counters: side closed, faster target, fast follower, target lost, yellow flag.
- Tests: 176 checks and 44 integration cases; 29 targeted mutations all detected; the two new tests fail on 1.3.5.

## 1.3.5 — 20 October 2026

Following the third session log (race at Spa, 10 cars, 1.3.4): over three minutes, 8 overtakes attempted, 0 successful, 15 aborted.

- **Overtake completed once side by side** (PDR §10.2.4, deviation present since 1.0.0): aborting is no longer allowed once the cars are side by side; the AI completes its overtake, even if the corridor closes or a fast car comes up behind. Only exception: the target gets back ahead and pulls away.
- **“The target is getting away” only for a target still ahead**: an AI that had got ahead of a car a few km/h slower was no longer “losing ground”, but the abort still triggered; with a 5 km/h difference, the overtake was aborted with a 13.7 m lead, just before it was confirmed, and the AI moved back in too early.
- **No return to hold while moving back in** (PDR §10.2.4): an AI moving back in alongside a car simply waits (lateral occupancy keeps priority) instead of going back into overtake hold, which produced repeated aborts for a single overtake.
- Tests: 174 checks and 44 integration cases; 26 targeted mutations all detected; the two new tests fail on 1.3.4. Bench: overtakes with 5, 10 and 20 km/h differences all completed.

## 1.3.4 — 20 October 2026

Following the second session log (race at Spa, 10 cars, 1.3.3: 5 anti-weaving blocks instead of 69, visible overtakes):

- **Stabilised end of incident**: an incident is only declared over after 2 s of normal driving. A slide that settles down (observed on René Mairesse: three incidents in 3 s) remains a single incident, and the major-incident timer that triggers a neutralisation is no longer reset. The yellow zone is therefore lifted 2 s later than in 1.3.3.
- **Per-minute counters in the log summary**: overtakes attempted, successful and aborted, yields started and completed, defences, avoidances, contacts, AI-to-AI headlight flashes, anti-weaving blocks, incidents and crashed AI stopped; reset at each summary.
- Tests: 172 checks and 44 integration cases; 23 targeted mutations all detected; the two new tests fail on 1.3.3.

## 1.3.3 — 20 October 2026

Fixes from the first session log (race at Spa, 10 cars):

- **AI frozen by their own line variation** (defect present since 1.0.1): the PDR's anti-weaving cap (six changes of direction per minute, then 20 s without manoeuvres) counted every reversal of the slow line variation in free driving. An AI alone on a straight was thus blocked 65% of the time, unable to overtake, yield or defend; the log showed 69 `direction_limit` warnings in four minutes. Only manoeuvres (yield, overtake, defence, avoidance, recovery and their returns) now count; line variation and the return to the line during the enforced rest are no longer changes of direction. The warning is written once per trigger.
- **False `zones_rejected:syntax` alert** on any track without a zones file: a missing file is no longer reported.
- Log summary: `cout non mesure` (cost not measured) when the native timer is unavailable in game, instead of 0.000 ms.
- Tests: 170 checks and 44 integration cases; 21 targeted mutations all detected; the three new tests fail on 1.3.2. The behaviour deliberately differs from 1.2.0 on the line in free driving (see VALIDATION.md).

## 1.3.2 — 20 October 2026

- **Session log on disk**: `Documents/Assetto Corsa/logs/ACAdvancedIA.log`, one file per game launch (the three previous ones as `.1.log` to `.3.log`), 4 MB at most. Timestamped lines: session (type, track, cars), chosen profile, incidents (cause, on or off track, position, driver) and their end, crashed AI stopped then moving off again, neutralisations and Safety Car phases, green flag, player flag, pit window and pit stops, tyres fitted, AI-to-AI headlight flashes and the resulting yields, weather, disabled CSP capabilities, errors; summary every minute (managed AI by state, incidents, measured cost). Switch and file path in the diagnostics window, on by default.
- Tests: 167 checks and 44 integration cases; 18 targeted mutations all detected.

## 1.3.1 — 20 October 2026

- **Safety Car deployed in two stages**: on a major incident, it is first **called** (field under FCY at 80 km/h, it stays parked for 10 s), then released; while it drives down the pit lane, the field stays under FCY. It therefore joins a field that has already slowed down rather than traffic still at full speed. It comes out even if the crashed car is still on track.
- Tests: Safety Car cycle extended; 16 targeted mutations all detected.

## 1.3.0 — 20 October 2026

- **Presets**: each built-in preset ticks all the tabs that act in its session (Accidents, Racing rules, Classes and Weather included); multi-class on everywhere; overtaking **Automatic** in the race; values specific to Practice (level 97%, aggression 40%, spread 6%, lapses in focus). Warning if the active profile ignores the weather.
- **Profile update**: a profile identical to a 1.2.0 built-in preset receives its 1.3.0 version once; a modified profile stays as it is, its obstacle avoidance following its keys in the Accidents tab. Data schema unchanged (version 3): 1.2.0 ignores the new keys.
- **Accidents tab**: detection of cars that are stopped, spinning (confirmed over 0.6 s) or facing the wrong way, player included; speed-limited yellow zone (50 km/h by default, approach with bounded deceleration) with no overtaking, yielding, defending or blue flag; avoidance of a car sideways across the track; brief stop of crashed AI, then moving off only with the track clear behind; yellow flag on the player's native HUD and on-screen messages.
- **Racing rules tab**: no change of direction under braking; FCY, VSC or Safety Car neutralisation on a major incident; mandatory stops, minimum stop time and maximum stint in the race; F1 Overtake Mode; emulated BoP and Pro-Am ratings; predictable slow class; F1, GT and Endurance rule sets applied to Practice, Qualifying and Race.
- **Safety Car** (experimental): model chosen from the `content/cars` database, present on the grid, parked in the pits, deployed on a major incident, single file, back in at the green flag. FCY fallback if the car is missing.
- **Pit stops**: a single request for weather and rules, without ever cancelling a native stop; new tyres or another dry compound at the stop; mandatory stops counted within the window and kept across a reload.
- **AI-to-AI headlight flashes**: a visible double flash from an AI held below its pace; the car ahead yields (in the race: only to a higher class, or when it is a lap down). The extra brake now also preserves KERS (neutral value `Skip`).
- **Weather change**: on-screen message.
- **Robustness**: new CSP reads isolated in their own protection; lint checking every field read against the installed SDK.
- Tests: 166 checks and 43 integration cases; 13 targeted mutations all detected; frame-by-frame equivalence with 1.2.0 when the new features are disabled (4 profiles, 20 AI, 0 differences).

## 1.2.0 — 20 October 2026

- **Practice profile**: fourth profile, with its settings, its button, its storage and the built-in “Free practice” preset (qualifying sections, without Spacing or blue flags). Qualifying's prepared values; Endurance layer unavailable, as in qualifying.
- **Content Manager mode detection**: the name of the session declared in `race.ini` tells Track day (“Track Day”, found in 49 archived launches) apart from practice (single Practice, practice in a Weekend). Track day → Track day; Practice → Practice; Weekend → Practice, then Qualifying, then Race; Race → Race.
- **Automatic mode kept**: loading a preset, built-in or custom, sets its profile without unticking “Automatic profile”. A message shows the profile set when it differs from the current session. The profile buttons remain an explicit manual choice.
- A Practice profile that has never been set up receives the “Free practice” preset once when detection activates it, as soon as a preset has already been used.
- Tests: detection of the four modes, preset loaded in automatic mode, weekend Practice → Qualifying → Race. Each fails on 1.1.0.

## 1.1.0 — 19 October 2026

Fixes from the adversarial review of 1.0.1 (`docs/AUDIT_V1_1.md`, removed in Beta 1.52 and kept in the git history).

- **Left/right**: the interface sides now follow the SDK convention (+1 = right) whatever the calibrated sign. In AC's frame of reference, calibration gives -1; “Yield to the right” then sent the AI to the left, and “Overtake on the left” made it pass on the right. Signs already calibrated remain valid; no recalibration is needed.
- **Reload**: the recovered original levels and aggressions are no longer overwritten by the modified values on the first frame, nor dropped if no section is active.
- **Unloading**: full restoration even when paused or in a replay, including in the pits and off track; the offset remains subject to occupancy.
- **Spacing**: the limit no longer drops below the target under braking or on corner exit. The reference is the highest uncapped speed on a straight, never that of a corner. During an episode, the limit is never below the leader's speed minus the reduction, including just after a pit exit or a settings change. The maximum measured difference goes from 48.8 to 12.8 km/h.
- **Weather**: the pit request stays active in the pit lane until the compound change and is only cleared after the exit. On a dry track, CSP's native rain strategy is no longer forced.
- **Setup/garage menu**: the engine is no longer frozen there, because in practice the session carries on while the player is in the garage. Only the real pause freezes the commands. Changing a setting in the garage brings manoeuvres in progress back to their base line, with an occupancy check. To be confirmed in game.
- **110% mode**: the read-back no longer mistakes the level written in the same frame, or a level between 1.000 and 1.010, for clipping.
- **Qualifying**: new built-in preset. A profile that has never been set up receives its recommended preset once when detection activates it (J Nordschleife, Q Qualifying, C Realistic race), as soon as a preset has already been used. Profiles that have been set up are never modified, and a first install stays neutral.
- **Detection**: preset recognised by its content for the active profile (J/Q/C weekend), detected session shown with its source (race.ini or CSP). `race.ini` is re-read on a session change instead of every second.
- **Extra brake**: steering, pedals, gear and MGU-H mode receive their documented neutral value; the brake is released as soon as the car is no longer controlled.
- **Miscellaneous**: session restart at the same index resynchronised, headlight learning kept on a settings change, stable player state, fixed order of the global sliders.
- Tests: 6 checks and 10 integration cases added, including a simulated host in AC's direct frame of reference. Each fails on 1.0.1 and passes on 1.1.0.

## 1.0.1 — 19 October 2026

- Endurance layer decoupled from classes, lapses in focus and sign calibration; stint traits renewed only with the layer; wet detection for yielding tied to weather adaptation.

## 1.0.0 — 19 October 2026

- Fix for AI crawling along on Track day: end of the cumulative reduction and of the cascade through the leader; bounded spacing regulation with free phases.
- Neighbour sorting shared per frame, selection by rank, one square root per occupancy check, precomputed section keys and UI controls indexed by group. Collision protection rate kept.
- Independent Weather tab, enabled by the built-in presets: dry/wet tyres, intermediates, CSP priority, compound change only at a pit stop, bounded compensation when there is no real or native wet tyre. Another dry compound chosen by the native strategy is preserved.
- Migration of profiles and presets to schema 3, keeping the activations. Recovery of the rain/pit commands on reload, including when a driving restoration is waiting for the pit exit.
- Overtake abort delay separated from lateral blocking; C setter signatures respected and tested through FFI pointers.
- Removal of obsolete fields, redundant reads/imports and copies of measurement scenarios; version centralised in the manifest. Legacy code moved out of the active folder.
- Final report in docs/AUDIT_V1.md. The CPU and memory results and the strict criteria still open are published unfiltered in docs/MESURES.md.

## 1.0.0-rc.4 — 19 October 2026

- Defaults of the three profiles: yield to the right, overtake on the left, slipstream and defending ticked in the prepared values. Sections stay disabled on first start; the built-in presets apply these defaults when loaded.
- Fix for drop-down list indices: Automatic and every other choice can be selected and persist.
- Unticked sub-options kept in the effective parameters; UI identifiers distinct from tab names.
- Automatic yielding takes the free side into account; side setting under blue flag respected in Qualifying.
- Detailed log actually optional and included in custom presets; continuous slipstream time, reset on an interruption.
- Identities checked during probe/calibration; offset restoration kept pending after a failure; brake-only command recognised; quarantine path using the effective options.
- Headlight reaction limit shown from 1 to 3, consistent with the propagation.
- Persistent deletion of custom presets with a dedicated button, without changing the current settings. Freed slots can be reused; long names and the delete button fit the panel width.
- Audit of 95 profile parameters, 11 global options and 166 functions in the 18 active files. Full walk through the fields via the interface, tests of extremes and disabled behaviours, new eight-hour soak. Detailed report in docs/AUDIT_RC4.md; measurements and limits in docs/MESURES.md.

## 1.0.0-rc.3 — 19 October 2026

Fix for the panel missing in setup, reported by the user's 19:54 screenshot. Window opening is now synchronised from `script.update`, even with no HUD or window open. Removal of the SIM_CALLBACKS/UI_CALLBACKS registrations from the manifest to keep a single engine call per frame. Windows declared SETUP in the SETTINGS group, with setup background, and content always hidden while driving. New integration check going through the real automatic callback.

Full loading of the built-in presets: values, recommended sections and active sub-options are applied together, with ticked boxes and highlighting. Nordschleife notably enables Yielding and Spacing; Realistic race enables Blue flags; Endurance adds its layer and the classes. First start stays neutral and custom presets restore their saved activations.

## 1.0.0-rc.2 — 19 October 2026

- Automatic profile re-evaluated after a manual choice; reading of the current session type declared in race.ini, with fallback to the CSP type.
- Three profile buttons with highlighting; a manual choice persists until automatic is switched back on.
- **Apply the settings of this section** checkboxes actually wired to the engine. All sections are disabled by default, with persistent activations per profile and values kept when disabled.
- Windows reserved for the pause/setup menus, diagnostics opened from the main panel; changes saved while paused.
- Spacing section: AI count, targets varying with car count/pace/length, progressive speed limiting only on track days, native restoration on disabling and on reload.
- Library of 16 named custom presets; saving/loading of values and activations, exact highlighting of the loaded preset, indication after modification.
- Tests covering neutral start, migration, independence of profiles and sections, cdata UI functions, menus, persistence, 9/50 AI densities, small tracks and progressive limiting.

## 1.0.0-rc.1 — 19 October 2026

Rewrite following HumanAI PDR v1.0: pure core, J/Q/C profiles, geometric perception, personalities, yielding, overtaking, racing, endurance, classes, lapped cars, headlights, zones, persistence and debug. Addition of the Appendix A tests, fuzzing, soak and the Lua scope linter.

Horizontal settings tabs without a checkbox in the titles. Separate checkbox under the title to show/hide the settings, without changing the AI functions. Navigation and buttons with line wrapping, adaptive texts and full-width sliders. Two CSP windows, permanent loading and a single simulation callback.

Fix for oversized tabs: explicit vector size, native single-line height, horizontal margin reduced to 16. Native `cdata` UI functions are recognised to avoid a forced fallback to three columns. Regression test reproducing the old squares, then checking the height and line wrapping with the native calls and an enlarged font.

Checks strengthened after review: native cdata functions, recovery by model/driver identity, player exclusion even at a non-zero index, returns to the centre subject to occupancy, deferred reset, restoration without a jump on resume, quarantine of an AI in error, time rollback and zone parsing without execution.

Removal of the old Traffic Planner hookup; its native sources restored from the backups. No track modified and no RARE integration. Release candidate as long as the physical tests and the strict CPU peak criterion are not validated.
