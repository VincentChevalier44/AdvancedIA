# CSP API notes

This page lists the Custom Shaders Patch Lua API that AdvancedIA uses today, and how it behaves in game. Release history is in [CHANGELOG.md](../CHANGELOG.md).

- **Reference version.** The app was developed and checked against **CSP 0.3.0-preview675 (build 4210)**.
  - Its SDK lives in `extension/internal/lua-sdk/ac_apps/lib.lua`. There is no separate `ac_physics_ai.lua`: the `physics.*` functions are defined in `lib.lua`.
  - The test installation now runs CSP 0.3.2-preview2. A note says so when a behaviour was observed on that version.
- **No line numbers.** SDK line numbers move between CSP builds, so this page names functions only.
- **Sources.** "SDK" means the comments in `lib.lua`. "Observed" means seen in game, in the app's session log or in CSP's log.

## Contents

- [General rules](#general-rules)
- [Manifest and entry points](#manifest-and-entry-points)
- [Reading the simulation state](#reading-the-simulation-state)
- [AI commands and their restoration](#ai-commands-and-their-restoration)
- [Flags and track light panels](#flags-and-track-light-panels)
- [Pits and Quick Pitstop](#pits-and-quick-pitstop)
- [Session memory and storage](#session-memory-and-storage)
- [Files and updates](#files-and-updates)
- [CSP gui.ini options](#csp-guiini-options)
- [Windows and drawing](#windows-and-drawing)
- [Companion-app bridge](#companion-app-bridge)
- [Pitfalls observed in game](#pitfalls-observed-in-game)

## General rules

- **Every CSP call is probed and protected.**
  - A function counts as present only if it is a Lua function or a callable cdata.
  - Not every `cdata` is a function. `physics.allowed()` itself is exposed as a callable cdata in a real session.
  - Calls run under `pcall`. CSP returns its error text, and the capability layer keeps the first 160 characters.
  - After three failures (`K.capabilityFailures`) a capability is switched off. The log shows its first failure and when it was switched off.
  - The **DIAGNOSTICS** tab lists every capability and why it is unavailable.
- **`physics.allowed()`** gives access to the `physics.*` setters. Observed: it returns true on the original Spa without changing `surfaces.ini`.
- **Online and replay.**
  - No command is sent online: `isOnlineRace` or `isAltOnlineRace`.
  - No command is sent during a replay: `isReplayActive` or `isReplayOnlyMode`.
  - No AI command (setters, offset, controls) goes to the player (`isUserControlled`, at any index, not only 0) or to a remote car (`isRemote`). The exceptions are the player-only flag and penalty, and the DRS rule.
  - Cars without local physics (`physicsAvailable == false`) and cars that are not AI-controlled (`isAIControlled`) are skipped too.
- **Argument count.** Setters receive `(index, value)`. The only exceptions are those whose SDK documents a further argument:
  - `setAISplineOffset` (`overrideAiAwareness`);
  - `setCarPosition` (`dir`);
  - `setAITractionMistake` (`severity`);
  - `overrideAIRequestedFuel` (`lapsToComplete`);
  - `setTyresVirtualKM` (`wheels`);
  - `setSuspensionDamage` (`wheels`, passed as `nil`).

  `physics.overrideRacingFlag(flag)` and `physics.setCarPenalty(type, parameter)` take no car index.
- **`ac.Disposable` is a function.** It is not an object with a `dispose` method. Subscriptions such as `ac.onMessage`, `ac.onCSPConfigChanged` and `ac.blockSystemMessages` are released with `pcall(token)`.

## Manifest and entry points

- `manifest.ini` declares:
  - `[CORE] LAZY=NONE`;
  - one window, `[WINDOW_0] ID=main` with `FUNCTION_MAIN=HUMANAI__MAIN`, `FLAGS=MAIN,SETUP,NO_TITLE_BAR,NO_BACKGROUND,NO_SCROLLBAR,NO_SCROLL_WITH_MOUSE` and `GROUP=SETTINGS`;
  - `[UI_CALLBACKS] IN_GAME=HUMANAI__HUD`.

  There is no `[SIM_CALLBACKS]` section and no minimum CSP version.
- **Manifest names are methods of CSP's `script` table**, not free Lua globals.
- **The engine runs from `script.update(dt)`**, which calls `script.HUMANAI__UPDATE`.
  - CSP calls `script.update` every frame, even with no window open ([Lua apps wiki](https://github.com/ac-custom-shaders-patch/acc-lua-sdk/wiki/Lua-apps)) and while the setup menu is shown.
  - It is the only update entry point.
- **The overlay draws without updating.** `HUMANAI__HUD` (IN_GAME) draws the in-game overlay and never updates the engine.
- **One global.** The app adds a single global table, `HUMANAI`. When the app is reloaded, the previous instance's `HUMANAI.release` runs first.
- **Lifecycle callbacks.**
  - `ac.onRelease(callback)` runs on unload; `ac.onSessionStart(callback)` on a session change. Each is registered once, and its callback is protected.
  - `ac.onSessionStart` also reports a restart of the same session index. The tracked writes are then resynchronised.
- **`ac.restartApp()`** reloads the app on the next frame. The app first releases everything, as on unload.
- **JIT cache.** `jit.opt.start('maxtrace=8000','maxmcode=16384')` runs at the top of `AdvancedIA.lua`, through `rawget(_G, 'jit')`.
  - With the default 1,000 traces and 512 KB, the engine recompiled all its code every one to two minutes.
  - If the call is refused, the engine drives the cars one protected call at a time instead of in one batch.

## Reading the simulation state

- **`ac.getSim()` and `ac.getCar(index)` return cdata structures.**
  - Reading an undeclared member throws in game, but not with the test host's Lua tables.
  - The lint therefore checks every field read against `tests/sdk-fields.json`, which is extracted from the installed SDK.
  - Reads of newly used fields get their own `pcall`.
- **Indices.** `ac.getCar(index)` is 0-based. The player is usually index 0 offline, but the app checks `isUserControlled` on every car.
- **Session fields:**
  - `timeToSessionStart`, `currentSessionTime` and `sessionTimeLeft` are in **milliseconds**; so are `bestLapTimeMs` and `previousLapTimeMs`.
  - `trackLengthM` comes from the AI spline, in metres. A length of 0 means no lateral manoeuvre.
  - `isPaused` and `isInMainMenu` are distinct. The setup or garage menu does not stop the session: the engine keeps running.
- **Session type.**
  - `ac.INIConfig.raceConfig()` gives read-only `race.ini`, with no password or online GUID. `config:get('SESSION_<currentSessionIndex>', 'TYPE', 0)` and `'NAME'` are read once per session, and again after a read failure.
  - TYPE values: 1 practice, 2 qualifying, 3 race, 4 hotlap, 5 time attack, 6 drift, 7 drag, as in `ac.SessionType`.
  - Content Manager signatures, from the installation's crash archives:
    - Track day: a single session, `NAME=Track Day`, `TYPE=1`;
    - Practice: `NAME=Practice`, `TYPE=1`;
    - Weekend: Practice/1, Qualifying/2, Race/3.
  - A name containing `trackday` (case and punctuation ignored) means Track day.
  - Without a readable `race.ini`, the app falls back to `raceSessionType`, and a practice session counts as a Track day.
- **Race progress:**
  - `pitWindowStartTime` and `pitWindowEndTime` (the declared window), `time`, `leaderLapCount`;
  - `ac.getSession(i).laps`, `durationMinutes` and `isTimedRace`;
  - `pitsSpeedLimit`, ignored below 40 km/h;
  - `fuelConsumptionRate` (0: fuel use off);
  - `mechanicalDamageRate` (0: damage off).
- **Car geometry.**
  - `position` is in metres, `velocity` in m/s and `speedKmh` in km/h; `look`, `side` and `aabbSize` are vectors.
  - The SDK only describes `side` as "sideways", so it is never assumed to point left.
  - In AC, +X is the left of a car looking towards +Z. The app's lateral basis `(-look.z, look.x)` therefore points right.
- **`ac.getTrackAISplineSides(progress)`** returns a `vec2`: x is the distance to the left edge, y to the right edge, in metres.
- **Car state:**
  - `splinePosition` (0–1), `lapCount` (laps completed), `racePosition` (1 = first, 0 if unknown);
  - `gas` and `brake` (0–1), `wheelsOutside`, `isLapValid`, `currentSector`;
  - `collidedWith`: 0 or more while in contact.
- **Pit state.**
  - `isInPitlane` or `isInPit` means "in the pits".
  - `isInPit` alone means "at its own pit box".
- **Tyres and fuel:**
  - `compoundIndex` (0-based) and `isAIUsingRainTyres`;
  - `ac.getTyresName` and `ac.getTyresLongName`, read for up to 32 compounds, two new catalogues per frame;
  - `wheels[i].tyreWear` (0 new to 1 worn per the SDK; not yet confirmed in game), `tyreVirtualKM`, core and optimum temperatures, `isBlown`;
  - `fuel`, `maxFuel`, and `fuelPerLap` (AC's estimate).
- **Damage:**
  - `damage` gives five zones, in km/h of impact;
  - `suspensionDamage` (0–1), `engineLifeLeft` (1000 new, broken at 0), `gearboxDamage` (0–1).
  - The player's damage is read once a second. An AI car's damage is read only at its pit box, below 25 km/h (`K.damageReadSpeed`), or while it is watched as abnormal or slow.
- **Lights and horn.**
  - `highBeams` means "high beams on or headlight flash".
  - `headlightsActive`, `lowBeams` (the switch, not a pulse), `flashingLightsActive` and `hornActive` are the other candidates.
  - The player's flash signal is learned from real transitions. Nothing counts as available before a signal has been seen.
- **DRS:** `drsPresent`, `drsAvailable`, `drsActive`.
- **Weather:** `rainIntensity`, `rainWetness`, `rainWater`.
- **Identity:**
  - `ac.getCarID(i)`, `ac.getDriverName(i)` and `ac.getCarSkinID(i)` (the livery folder);
  - `ac.getTrackID()`, `ac.getTrackName()` and `ac.getTrackLayout()` (empty without a layout);
  - `ac.getPatchVersion()`, shown in the diagnostics.
- **Other apps.** `ac.getAppWindows()` lists the open app windows (`name`, `title`).
  - It is used to warn about apps that may also drive the AI.
  - A known window does not prove that its app writes anything, so the banner says "check what it does".

## AI commands and their restoration

No CSP getter exists for the current offset, the extra grip, the caution or a top-speed cap. The app therefore restores the documented neutral values, not "the value before". Another app's cap cannot be restored identically.

| Function | Contract (SDK) and use |
|---|---|
| `physics.setAISplineOffset(i, offset, overrideAiAwareness?)` | **Normalised**: −1 is full left and +1 full right, limited by the track width. It is never in metres; `setAISplineAbsoluteOffset` takes metres and is not used. The sign is calibrated; see [Pitfalls](#pitfalls-observed-in-game). |
| `physics.setAILevel(i, level)` | Setter range 0–2; the `aiLevel` field is documented 0–1. The app probes 1.05 (`K.probeLevel`) with a deferred read-back and restores the initial value if that fails. In native mode commands go up to `K.nativeLevelMax` (1.1); otherwise they stop at 1 and the optional grip bonus stands in. |
| `physics.setAIAggression(i, value)` | 0–1. 100% in the launcher is 0.95, so commands are capped at 0.95. |
| `physics.setAICaution(i, value)` | 0–16, default 1, experimental. Commands stay between 0.5 and 16. |
| `physics.setExtraAIGrip(i, value)` | **1 = normal grip**; "120% by default" means 1.2. Grip is written only when the grip bonus or the weather compensation is on. One setter combines both, and the weather factor is at most `K.weatherGripMax` (1.3). It never stacks with native wet tyres. |
| `physics.setAITopSpeed(i, kmh)` | km/h; `1e9` removes the cap. Used for spacing, yellow zones, FCY, VSC, the Safety Car queue and standing-start approach. Two sources combine as their minimum. |
| `physics.setAIThrottleLimit(i, limit)` | 0 to 1, where 1 removes the limit. Used for sanction throttle cuts, dirty air and failures. Lowered gradually, never below 0.3, and written once per change. The app writes exactly 1 once the limit comes back above 0.99, and also when the car is not driven (pits, off track, release). |
| `physics.setAIStopCounter(i, seconds)` | "Makes the AI brake for a given time", the mechanism AC uses after an incident; 0 releases it. The app sends 1.5 s pulses renewed every 0.5 s, so a car is released by itself if the app stops. It also holds the pit box, the pit-exit merge and the standing-start grid. |
| `ac.overrideCarControls(i)` | Returns `ac.CarControlsInput?`. The final `brake` is the maximum of native and imposed. Every write sets neutral values for the other fields: `combineAxis=true`, `steer=math.huge` (keep), `gas=0`, `handbrake=0`, `clutch=1`, `requestedGearIndex=0`, `mguhMode=-1`, `kers=-1`. `headlightsFlash=true` flashes for one frame. No throttle is ever imposed. |
| `physics.setAIBrakeMistake(i, seconds)`, `physics.setAITractionMistake(i, seconds, severity)` | Driving mistakes. They are written once per decision, with nothing to give back. `severity` multiplies the throttle. |
| `physics.setTyresVirtualKM(i, wheel, km)` | `wheels` is an `ac.Wheel` (0–3 is a single wheel). Used for the flat spot of a lock-up on the more worn front tyre, one event at a time and bounded per stint. |
| `physics.allowCarDRS(i, disable)` | **`true` forbids DRS** (the argument was once `enable`, which was a bug). Marked deprecated in the SDK, with no documented replacement. It applies to the player as well. It is given back at the end of the rule, when the tab is unticked, on unload, and after an abrupt stop (the `;D` marker of the resume data). |
| `physics.setCarDRS(i, active)` | Opens or closes an AI car's DRS when present and available: at most one opening per second, and it closes at once under braking. |
| `physics.setAINoInput(i, true)` | Parks the Safety Car ("parked"). |
| `physics.teleportCarTo(i, 'PIT')` | Without `preserveDamage`, **the moved car is repaired**. Used for the Safety Car, disqualified AI, and stranded or slow damaged AI, only when the car is not already at its pit box. |
| `physics.setCarPosition(i, pos, nil)` | `nil` aligns the car with the AI spline (since 0.3.0-preview124). `pos` comes from `ac.trackProgressToWorldCoordinate(progress)`. Used to place AI around the track in a track day. |
| `physics.setCarVelocity(i, v)` | The launch after a placement. It is sent only once the position jump has been seen, along the car's own axis. |
| `physics.setAITimeToStart(i, s)`, `physics.awakeCar(i)` | Cancel the native wait (`0`) and wake the car: used at lights out, for placement, and to release held cars. |
| `physics.setCarBodyDamage(i, vec4)`, `physics.setSuspensionDamage(i, wheels?, damage)`, `physics.setCarEngineLife(i, life)` | Pit-box repairs: body to `vec4(0,0,0,0)`; suspension with `wheels = nil` (all) and damage 0; engine to 1000 (new). |
| `physics.setCarFuel(i, litres)` | Start fuel, once per car and session. |
| `ac.findNodes('carRoot:'..i):applySkin(folder)` | The "safety" livery on the Safety Car. The original livery (`ac.getCarSkinID`) is put back afterwards and on unload. Available since CSP 0.3.0. |

- **Grid slots.**
  - Read from `ac.findNodes('AC_START_<k>')`, `SceneReference:size()` and `:getWorldTransformationRaw().position` (`nil` without a node).
  - `ac.worldCoordinateToTrack(v)` then gives X, the normalised lateral position (−1 left, +1 right), and Z, the progress.
  - Read once per track. Any failure falls back to computed slots.
- **No teleport to `START`.** It would use each car's original slot, and its timing behaviour is unknown.
- **AC's gantry lights cannot be driven.** They have no track condition input, so the overlay draws its own lights.
- **Commands that CSP does not offer here:**
  - AC's penalties (`physics.setCarPenalty`) apply to the user car only.
  - `physics.markLapAsSpoiled` "works only during the race".
  - AI sanctions and invalidated AI laps in practice and qualifying therefore stay inside the app. An AI drive-through is a pit request without service.
- **Recovery after a reload.** `ac.store('humanai:recovery')` records, per owned car, the original level and aggression, the offset, and which of level, aggression, caution, grip, brake, top speed, rain tyres, pit request, stop counter, park and fuel request the app held. The header carries the player flag (`;F`) and DRS (`;D`). A reloaded instance gives all of these back, and always gives the throttle back.

## Flags and track light panels

- **`physics.overrideRacingFlag(flag)`** imposes the player's flag until `ac.FlagType.None`.
  - The SDK note on `ui.drawRaceFlag` says it "would also affect track conditions".
  - `ac.FlagType` values 3, 4, 6, 7, 9, 10, 11, 15 and 16 are marked *does not work yet* for AC's own display. `SessionSuspended` (the red flag) is one of them.
  - Value 5 (`Stop`) shows as AC's black flag.
- **`ac.getSim().raceFlagType`** returns the overridden value.
  - Each frame is marked `flagOwned` when the value shown is the app's, so the app never reads back its own flag as one of AC's.
  - AC's penalties (`currentPenaltyType`) are still read.
- **Native flags that count as free:**
  - "none" (0);
  - AC's start flag (1), which AC can hold for the whole session, as in hotlap;
  - AC's yellow, but only for the app's yellow or red.

  Blue (12), white (14), chequered (13), black (5) and penalty (8) are never covered.
- **Red (5) is written only while CSP hides AC's flags** (`[HIDE] HIDE_RACE_FLAGS`, read when writing). Otherwise the app writes yellow, so AC never shows a black flag for a red one.
- **Track light panels.**
  - Panels light up through `[CONDITION_…] INPUT=FLAG_TYPE` in the track configuration, with a LUT from the flag value to a colour.
  - Usual LUT: 1 green, 2 yellow, 3 orange, 4 orange-red, 5 red, 6 grey-white, 12 blue, 13 off or red, 14 white.
  - Configurations come from the track's `extension/ext_config.ini` or from CSP's `extension/config/tracks/loaded/<track>.ini`.
  - CSP's shared `common/conditions.ini` defines `RACING_FLAG` on `FLAG_TYPE`, so a track may light panels with `CONDITION=RACING_FLAG` only (Sepang, Vallelunga).
- **Includes.**
  - Configurations include other files with `[INCLUDE: file]` section headers or `INCLUDE = a, b` keys. The F1 2026 layouts use `[INCLUDE: ../../common/…]`, `[INCLUDE: ../../extension/ext_config.ini]` and `[INCLUDE: extension/config/tracks/loaded/<track>.ini]`.
  - An include resolves from the including file's folder, with `.` and `..` resolved. `common/…` resolves in `extension/config/tracks/common`, and `extension/…` also from the Assetto Corsa folder (`ac.FolderID.Root`).
  - Only paths inside `content/tracks/<track>/` or `extension/config/` are read. Absolute paths, drive letters and escapes are refused, and comparisons ignore case.
  - Limits: at most 64 files (`K.lightsFiles`), 4 MB each and 8 MB in all. Reading happens once per track and stops at the first match.
  - Track identifiers containing `..` or other unexpected characters are never read.
- **Player penalties.** `physics.setCarPenalty(type, parameter)` takes:
  - `ac.PenaltyType.SlowDown` (3), a throttle cut for the given seconds, only with race settings that allow it;
  - `BlackFlag` (4) and `ReleaseBlackFlag` (5), with no parameter.

  The black flag is lifted on unload, on deactivation and on a session change. It is imposed again after an app reload.

## Pits and Quick Pitstop

- **`physics.setAIPitStopRequest(i, value)`.** Since 0.3.0-preview147, `false` also blocks the pits for a short time.
  - A request therefore stays true in the pit lane, until the stop.
  - `false` is sent only outside the pit lane, and on unload.
- **`physics.setAIRainTyres(i, bool)`** overrides AC's choice. It is called only when the native `isAIUsingRainTyres` differs from the decision, or when the app already holds it.
- **`physics.setAITyres(i, compoundIndex)`** sets the compound and **resets tyre damage**. It is called only:
  - in the pits, stopped or driving in the pit lane;
  - stopped on the grid before the start, or stopped in the first 15 seconds of a session.
- **`ac.areTyresLegal(shortName)`** returns `false` for a compound that is illegal in this race; if every compound is illegal, all of them are legal.
- **`physics.overrideAIRequestedFuel(i, litres, lapsToComplete?)`** sets the fuel requested at the next stop, never more than the tank holds. `math.huge` removes the override.
- **Quick Pitstop.** `ac.getPitstopSpinners()` (CSP 0.2.7 and later) lists the menu entries (`name`, `type`, `min`, `max`, `value`, `values` per preset).
  - `ac.getSim().currentQuickPitPreset` is the selected preset, 0-based.
  - The app reads them every `K.pitPlanPeriod` s, never every frame, and never changes the player's preset.
  - Value-to-compound mapping is assumed only when unambiguous; otherwise the log says so.
- **Pit-lane exit.** `isInPitlane` can drop for one frame, so an exit is confirmed only after 1 s out of the lane (`K.sanLaneDebounce`). The exit point is taken from the first frame out.
- **Pit state at session start.** `isInPit` and `isInPitlane` read false for a moment, and the first frame may hold no car yet. Placement waits for the AI cars plus 0.5 s. A car counts as placed only within 100 m of its spot.
- **No live reload of `new_behaviour.ini`.**
  - CSP's AI flood setting lives in `ac.FolderID.ExtCfgUser` + `new_behaviour.ini`, absent until something changes. Its defaults are in `ac.FolderID.ExtCfgSys` + `new_behaviour.ini` (`[AI_FLOOD] ENABLED=1`, `MIN_TRACK_LENGTH=7000`).
  - The app changes only `ENABLED` and `SPAWN_*` in `[AI_FLOOD]`.
  - Observed: CSP reads this file when the game is launched, not when a session restarts.

## Session memory and storage

- **`ac.store(key, value)` / `ac.load(key)`** are session-shared storage for Lua and Python. They survive an app reload but not a game restart.
  - Keys starting with `.` are hidden from Lua Debug.
  - The app uses `humanai:recovery`, `humanai:pits`, `humanai:penalties`, `humanai:strategy`, `humanai:sanctions`, `humanai:presetsession`, `humanai:cspgui` and the log marker `.AdvancedIA.journal`.
  - Recovery text above 64 KiB (`K.storeMaxBytes`) is ignored on reading.
- **`ac.storage(layout, prefix)`** is persistent. Writes are delayed by CSP and happen only when a value changes.
  - Files: `Documents/Assetto Corsa/cfg/extension/state/lua/app/<app>.ini` (for example `AdvancedIA.ini`).
  - Prefixes: `humanai:g:` for globals, `humanai:p:<profile>:` for profiles, `humanai:custom:<n>:` for the custom presets.
  - Only primitive values are stored, with no Lua code. Writes are grouped and never happen during a replay.
- **A newer schema survives a roll back.** When the stored `schemaVersion` is newer than the app's, it is no longer replaced by the defaults. Each known key is validated, and the higher version is kept on save.
- **Renamed folder.** The settings of the old `ACAdvancedIA` folder (`ACAdvancedIA.ini`) are not copied: CSP reads and writes that file itself. The app only tells the driver what to do, with the game closed.

## Files and updates

- **Folders:**
  - `ac.getFolder(ac.FolderID.ScriptOrigin)` is the app folder;
  - `ExtCfgState` is `Documents/Assetto Corsa/cfg/extension/state`, never live-reloaded;
  - `ExtCfgUser` is `cfg/extension`;
  - `ExtCfgSys` is `extension/config`;
  - `ContentTracks` and `ContentCars` are the content folders;
  - `ACAppsLua` is `apps/lua`;
  - `Logs` is `Documents/Assetto Corsa/logs`.
- **`ac.readDataFile(path)`** reads `tracks/<trackId>.lua`, the zones file, as text. The identifier is filtered and text above 64 KiB is refused. The zones are parsed as a table, without `load` or `loadstring`.
- **`io.scanDir(folder, '*', callback(name, attributes))`** lists files. `attributes` is an FFI structure (`isDirectory`), not a Lua table. It is used for the car database (`ContentCars`) and the update folders.
- **`io.save(path, data, true)`** writes to a temporary file, then replaces the target.
  - When the file exists, the replacement goes through `io.replaceFile`, which keeps the old content as `<path>.bak`.
  - The app deletes that `.bak` after each write and each deletion: `boot.txt`, `gui.ini`, `new_behaviour.ini`.
- **`io.copyFile(from, to, false)`** copies, and `false` (`failIfExists`) allows overwriting.
- **`io.move(from, to, true)`** is MoveFileEx without a copy. It fails between drives (Steam on D:, Documents on C:), so anything crossing into the app folder is copied.
- **`io.deleteDir`** removes an empty folder only. A folder is emptied first, then its sub-folders are removed deepest first, then the folder itself.
- **Session log.**
  - `io.open(path, 'a')` appends to `Logs/AdvancedIA.log` every two seconds (three previous files kept); the file is never rewritten. `os.date` stamps the lines.
  - On the first cycle of a game launch, `io.fileExists` and `io.move` rotate the old files. The `.AdvancedIA.journal` marker continues the same file after an app reload.
  - After three failures the log switches off; the engine is unaffected.
- **CSP and AC logs** are truncated when they exceed their maximum size, often as soon as a 30-car grid loads. The app's log does not depend on that limit.
- **`ac.pauseFilesWatching(true)`** suspends CSP's live reload for a few seconds. CSP reloads an app when a file in its folder changes, so the app writes nothing there before the final copy.

### Update from GitHub

- **Network.** `web.get(url, headers, callback(err, response))` returns `response.status` and `response.body` (binary-safe).
  - At most two requests run at once, with 30 s default timeouts and no progress callback. The size shown comes from the release asset.
  - `api.github.com` needs a `User-Agent` header.
  - `releases/latest` answers 404 while nothing is published. GitHub answers 403 or 429 when the unauthenticated limit (60 requests per hour) is reached.
  - `browser_download_url` redirects to GitHub's storage, and the redirect is followed.
- **Decoding.** `JSON.parse(text)` decodes the release. `ac.checksumSHA256(data)` returns the digest as text; 32 raw bytes are accepted as well.
- **Zips.**
  - `io.scanZip(data)` lists the entries and `io.loadFromZip(data, entry)` reads the package manifest.
  - `io.extractFromZipAsync(data, folder, {crucial = 'apps/lua/AdvancedIA/manifest.ini'}, callback)` unpacks. Since 0.2.10, the crucial entry is extracted last under a temporary name, and its absence is an error.
- **Work folder.** The work folder is `ExtCfgState/AdvancedIA-update/`:
  - `next/` holds the unpacked package;
  - `current/` holds the files about to be replaced;
  - `backup/` holds the previous version;
  - `installing.txt`, `updated.txt`, `boot.txt` and `failed.txt` are its markers.
- **Final copy.** It runs synchronously in one frame.
  - Each file is copied to `<destination>.new` next to its target, then renamed with `io.move(tmp, destination, true)`. Both are on the same drive, so the move is a rename.
  - File watching is paused again before each file and resumed at the end.
  - Order: `src/` first, then the other files, then `AdvancedIA.lua`, and `manifest.ini` last. `io.createFileDir` creates new folders.
- **Recovery** runs at the very top of `AdvancedIA.lua`, under `pcall`, before any other module is required. When it copied files, it asks for one `ac.restartApp()` on the first frame.
- **Boot sentinel.** `boot.txt` is written by a fresh install and counted at each start. It is removed once the engine and the interface have run without error. Two failed starts roll back to `backup/`.
- **A failed module cannot be required again**: LuaJIT raises *loop or previous error loading module*. If `src/update` fails to load, the entry file stores its stand-in in `package.loaded['src/update']`.
- **`os.openURL(url)`** opens the release page, https only.

## CSP gui.ini options

- **`ac.blockSystemMessages('.')`** hides AC's messages, and `ac.onMessage(callback)` still receives them.
  - A test message (`ac.setMessage(title, '', nil, 0.1)`) checks that the listener still receives hidden messages.
  - It does **not** hide AC's own top banner. That banner is controlled by CSP's `[HIDE] HIDE_SYSTEM_MESSAGES` ("Hide system messages (like ABS)"). `HIDE_RACE_FLAGS` hides AC's flags.
- **Where the values live.**
  - User file: `ac.FolderID.ExtCfgUser` + `gui.ini`, written by Content Manager and absent until something changes.
  - Applied values: `ac.INIConfig.cspModule(ac.CSPModuleID.GUI):get('HIDE', key, false)`.
  - `ac.onCSPConfigChanged(ac.CSPModuleID.GUI, fn)` reports a re-read.
  - Observed on CSP 0.3.2-preview2 (3 November): `HIDE_SYSTEM_MESSAGES=1` written by the app was re-read live. The app still handles a re-read that only happens at launch.
- **Between the app's write and CSP's re-read**, the applied value is the one read at the app's first start in this game process (`ac.store('humanai:cspgui')`), never the file's.
- **State file.** `ExtCfgState` + `ACAdvancedIA-cspgui.ini` keeps the original values, which survive a crash:
  - `v1`;
  - one line per held key (`KEY=original`, or `KEY` when absent);
  - `original <bytes>` and `written <bytes>` blocks (`-` when the file did not exist).
- **AC's session box.** `ac.disableExtraHUDElements('sessionTime', hide)` hides it while the overlay shows the session; it is given back on unload.

## Windows and drawing

- **The settings window `main` follows the menu.**
  - It opens with `ac.setWindowOpen('main', visible)` when menu visibility changes.
  - Outside the menus, `ac.isWindowOpen('main')` is checked at most every second (`K.windowCheckPeriod`), and the window is closed if it is open.
- **`ac.accessAppWindow(name)`** returns an `ac.AppWindowAccessor?`.
  - The app uses the names `IMGUI_LUA_AdvancedIA_main` (its own window, made compact once with `:size()` and `:resize()`) and `IMGUI_LUA_SpotterEnginer_main` (opened with `:setVisible(true)`).
  - This name pattern is the convention the code relies on; it is not documented in the SDK.
- **Overlay.** `ui.transparentWindow(id, pos, size, noPadding, inputs, content)` draws the overlay, like SuperHUD.
  - `inputs` is on while the overlay is unlocked or not click-through.
  - The screen size comes from `ac.getUI().windowSize`.
- **Custom drawing.** The interface is drawn by the app: `ui.drawRectFilled`, `ui.drawQuadFilled`, `ui.drawTriangleFilled`, `ui.drawCircleFilled`, `ui.drawImage`, `ui.invisibleButton`, `ui.itemHovered`/`itemActive`, mouse functions, `ui.pushClipRect`, `ui.inputText` and `ui.setNextItemWidth`.
  - If any required function is missing, the window shows only a message asking for a newer CSP.
- **Text** uses DirectWrite: `ui.pushDWriteFont`/`popDWriteFont`, `ui.dwriteDrawText`, `ui.dwriteDrawTextClipped` and `ui.measureDWriteText`.
  - Fonts ship in `fonts/` and are named relative to the app, for example `'Barlow:fonts/barlow;Weight=Regular'`.
  - If a font file is missing, the app falls back to Segoe UI and Consolas.
- **Sounds.** `ac.AudioEvent.fromFile({filename = …, use3D = false, loop = false}, false)` plays the DRS and delta beeps.
  - `cameraInteriorMultiplier` defaults to 0.25, so the three camera multipliers are set to 1. `volume` follows the setting.
  - `setVolumeChannel(ac.AudioChannel.Main)` ties the sound to the master volume.
  - The previous event is disposed of before each beep and on unload.
- **Clipboard.** `ac.setClipboardText` copies exports.

## Companion-app bridge

- **`ac.connect(layout)`** (`common/ac_extras_connect.lua`) creates a structure shared between the session's Lua scripts. Both sides must pass exactly the same layout.
  - The layout lives in `src/bridge_layout.lua`, byte-identical in AdvancedIA and SpotterEnginer.
  - A `key` field holds `ac.StructItem.key(...)` to avoid collisions.
  - Types used: `boolean`, `int32`, `uint32`, `float`, `double`, `string(capacity)` and `array(struct(...), 61)` for the cars.
- **When it opens.** `Applier.bridgeOpen` runs only if `Applier.companionInstalled('SpotterEnginer')` finds `ACAppsLua/SpotterEnginer/manifest.ini` (via `io.fileExists`). The check runs once at launch, inside `pcall`. Without the companion app, `ac.connect` is never called.
- **Publishing** (`src/bridge.lua`) is pure Lua and reads only.
  - It runs once per frame after the engine update, inside `pcall`. An error closes the bridge only.
  - Strings are written only when they change, cut at their capacity on a UTF-8 boundary.
- **`SpotterEnginer.update`** (read since Beta 1.52) is a session-memory key that SpotterEnginer writes itself.
  - AdvancedIA reads it with `ac.load` every `K.companionUpdatePeriod` (10 s), only when SpotterEnginer is installed.
  - Contract v1: `v=1;installed=…;latest=…;state=…[;needs=…]`, at most 200 bytes, with unknown fields ignored.
    - `state` is one of `available`, `uptodate`, `checking`, `error` or `incompatible`.
    - Versions are at most 32 bytes and use letters, digits, `.`, `-`, `?` and spaces.
  - Anything else counts as absent.
  - AdvancedIA only shows the state and opens SpotterEnginer's window. It never downloads or installs anything for it.

## Pitfalls observed in game

- **Offset sign.**
  - The app's lateral basis `(-look.z, look.x)` points right. On this installation the calibration measures `offsetSign = −1`: a positive offset moves the car against that basis. Only the sides chosen in the interface are converted from the SDK convention.
  - The sign is stored in the settings. **`offsetSign = 0` means no lateral command at all**: from 26 to 30 October no AI moved sideways.
  - A migration puts −1 back, and the calibration confirms or corrects it.
  - The calibration needs an isolated AI pair outside the pits, in the same direction, on a straight. It measures in the reference car's frame and gives up if a side becomes occupied.
- **AC's flag can stay on.** After `overrideRacingFlag(None)`, CSP can keep showing the app's last flag, as seen at Monza and at Spa on 4 November.
  - While the value shown equals the app's last one, the release is sent again every `K.flagLeftoverDelay` s.
  - After the last try, the app writes AC's start flag and then releases it, so no red or black flag is left on screen.
- **AC's red banners.** AC draws *CUT DETECTED* / *LAP WILL NOT COUNT* and *PENALTY, SLOW DOWN FOR n SECONDS…*, even with `HIDE_SYSTEM_MESSAGES=1` applied and `ac.blockSystemMessages('.')` active.
  - No CSP option or function hides them, and they reach `ac.onMessage` too.
  - The app recognises AC's own texts (`Config.acDrawnMessages`, taken from `acs.exe`) and never repeats them on the overlay.
- **Cars sent sliding.** A position and a computed velocity set in the same frame sent all 30 AI cars sliding on the first attempt. The launch now waits until the position jump has been seen.
- **Clocks.** Observed on 3 November: CSP did not expose the Windows counter, so every cost read "not measured".
  - Frame cost uses `QueryPerformanceCounter` through `ffi` when allowed.
  - Otherwise it uses `os.preciseClock`, if a short probe loop at launch shows it advancing.
  - Otherwise it falls back to `os.clock`, in 1 ms steps: the mean stays right but the maximum is rounded.
  - The source is logged once.
