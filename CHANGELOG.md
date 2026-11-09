# Changelog

Newest first. Each entry says what changed, why, and how it was verified.

## Beta 1.52 — 9 November 2026

A full adversarial review of Beta 1.51 (five reviewers, then four areas fixed and merged), plus one feature asked for
by the driver: the SpotterEnginer update is announced on the HOME tab.

### SpotterEnginer update announced on HOME, never installed by AdvancedIA (driver's decision)
- SpotterEnginer publishes the state of its own update in `ac.store('SpotterEnginer.update', 'v=1;installed=…;latest=…;state=available|uptodate|checking|error|incompatible[;needs=…]')`,
  200 bytes at most; unknown fields are ignored.
- AdvancedIA reads that key only when SpotterEnginer is installed, every 10 s at most. Under **HOME › TO CHECK** it shows
  *SpotterEnginer x.y available (installed: a.b)* or *SpotterEnginer needs AdvancedIA x.y*; the **SpotterEnginer ›** link
  opens the spotter's window, which handles its own update.
- No GitHub request for it and no repository written in AdvancedIA. SpotterEnginer has its own repository and its own
  update module; it depends on AdvancedIA (silent without it, never online). Install AdvancedIA alone, or both.

### AI driving
- The `yieldBlue`, `yieldQuali` and `yieldClass` flags are cleared when the yield ends. An AI that had yielded once (blue
  flag, class or flying lap) used to lose its last-laps urgency and its tow breaking, and its owed place was cancelled
  until its next stop.
- `bluePending` is cleared when the yield is not judged (yellow, neutralisation, braking, lapse, car alongside): the level
  no longer stays at ×0.92 for a whole neutralisation.
- During the anti-weaving rest (up to 20 s), priority yields (blue flag, class, flying lap) can start and are no longer cut
  short.
- A chained overtake goes through the same guards as the first one: anti-weaving rest and limit, lapse, flying laps,
  careful first lap, ignored pair, target yielding on the same side. The log notes every chained attempt.
- Practice and qualifying: the « a car not on a flying lap never attacks a flying car » guard can no longer be bypassed by
  a headlight flash between AI, and an AI's flash no longer hides the flying car.
- The planned cool-down lap (qualifying) needs the **General** tab: without it, no level is written.
- Laps that are not flying laps no longer enter an AI's learned pace, which no longer drifts down.
- Eleven AI timers are now rebased with the 24-hour clock rebase (courtesy after a pass by the player, logs, overtakes).
- Flying laps: the logged reason is right (out-lap, cool-down, in-lap, damaged car, car too slow); the « in a row » count is
  reset after an aborted lap; a red flag during a cool-down lap hands the level back gently; the loop no longer runs
  outside practice and qualifying.
- The minute-summary counters are exact: every end of a priority yield is counted (completed and lost), and held overtakes
  once per episode.
- Clean-up: direction counting factored, `paceBin` and four dead fields removed, hard-coded values named (`launchCare`,
  `blueForgetMult`, `passSideAssert`, `mergeOutlierCount`), `string.format` moved out of the hot path, defence tested in
  the race only.

### Racing rules and engine
- **F1, player's stop:** a stop validated after the window has closed, while the compound change is still pending, is no
  longer penalised: the penalty waits for the compound decision.
- **F1, « same compound » warning:** no longer lost after a standing start.
- **Mandatory-stop window closed:** a stop made afterwards no longer counts, even under a red flag, and no AI is called for
  the mandatory stop any more; the strategy no longer reacts to a mandatory stop after the window has closed.
- The maximum stint no longer counts the wait on the grid.
- A slow damaged AI called to the pits counts in the limit of simultaneous pit calls.
- The overlay no longer shows « Stop 0/1 » when the stop is waived (race turned wet).
- The strategy learns the lap time even when fuel is left to AC.
- Flag panel: it reads the current frame's values (player's pit stop, place to give back); the player's pit fields are
  cleared at a session change.
- 24-hour clock rebase: the overlay (`HudInfo.rebase`), the strategy out-lap, the slow-car teleport, AI flood, the
  staggered pit exits, the grid, incident and recovery timers are now shifted too. No more hold of about 86,400 s.
- An « abnormally slow » car is forgotten at a session change.
- **Session preset:**
  - switching profile A → B → A in the same session no longer applies the preset again;
  - new key `track#index#profiles served` (the old key is still read);
  - never while the app is switched off;
  - the old Beta 1.29 rule no longer applies in a replay or online.
- Mandatory stop on/off: dead code removed (spreading over several stops, next slice); texts say « mandatory stop to do ».
- The `depart:` log line also counts the feet held on the straight.
- The pit-stop draw no longer uses the same salt as the driving mistakes (`pitSalt` 80000 → 8152).
- Hard-coded values named: `lightsOutSalt`, `gridGapFine`, `gridGapStep`, `queueSpeedMargin`, `strategyRivalMinSpeed`.
- Strings built every frame removed: preset key, Safety Car state, weather key, fuel key.

### Host layer (restore, Safety Car, updates)
- **Safety Car held, or AI parked:** after a session change or an app reload they are no longer restored then written
  again every frame. Before: four writes per frame and a log line every 5 s (visible in the 6 November log).
- **Repairs:** an AI repaired in practice is repaired again at its first stop of the race.
- **Safety Car wait lifted** when its hold ends without a release. Before, a native 600 s wait stayed set.
- **Race fuel set again** after a session restart.
- **Safety Car exits** are reset at every session. Before, after two exits it stayed parked for the whole game launch.
- The race saves (pits, penalties, strategy, sanctions) are cleared at a session change: a restart followed by a reload
  no longer resumes the previous race.
- Lateral sign measurement: no longer cancelled in a loop.
- **App switched off:**
  - the player is read again, so an update installs in the pits and is no longer refused « while driving »;
  - the other cars are marked invalid for the bridge.
- **Unload:** protected read; lateral offset handed back to 0 unconditionally; CSP options handed back only when rolling
  back to a version older than Beta 1.40.
- The recovery point also keeps the requested fuel and the Safety Car hold (two columns; the old format is still read).
- Mean cost in the summary: right even when the engine is not running.
- **Performance:** the global settings, the capability report, the window check and the measurement-block check are no
  longer computed every frame; car sizes are read with the metadata; loops run over the real number of cars.
- Updates: one asset prefix (`Update.assetPrefix`); dead leftovers of the Beta 1.33/1.34 module removed (`legacyMarker`,
  `legacyReport`); the module error is kept in the log.
- Old ACAdvancedIA installation: when its folder has no manifest any more, the leftover of its update module
  (`cfg/extension/state/ACAdvancedIA-update`) is deleted once, after checking every name, with a log line.
- Hard-coded values named: `tyreWriteGap`, `nativeLevelMax`, `weatherGripMax`, `minCaution`, `levelReadMax`,
  `storeMaxBytes`, `flagLeftoverDelay` (the restore resend is now in seconds instead of a frame count),
  `windowCheckPeriod`.

### Settings, presets and interface
- **Race, Rules tab unticked:** the escalation Safety Car no longer comes out.
- **Custom presets saved with an older version:**
  - the Beta 1.42 settings (strategy, failures, sanctions, dirty air, out-lap, lock-ups) take the profile's default, no
    longer the track day's;
  - preset revision 15: data revisions 20 (tyre wear 75 → 30 %) and 21 (start wait 1 → 2 s) are replayed;
  - `firstLapCare`, `qualiTraffic` and `qualiCoolLaps` take the profile's default when they equal the track day's.
- **Data revision 22:** a custom preset loaded before Beta 1.51 gets the `Perso` mark, once, so the session preset no
  longer replaces it.
- `Perso` mark: saving a custom preset sets it; deleting the loaded preset clears it; **Restore** also clears the last
  preset loaded for that profile, and its tooltip says the next session will apply the recommended preset.
- **Staggered pit exits** is hidden in the race and in hotlap, where it has no effect.
- The start panel gives the right instruction in practice, qualifying and hotlap when the panel is unticked.
- Interface: the count of changed settings is cached (about 240 calls per frame before); named constants for the caches,
  the blinking, the slider steps and one shared tolerance; flags through `K.flag*`; the numbers of `K` are no longer
  copied into the French and English texts; the duplicated lists of `src/config.lua` are reused.
- Clean-up: dead constants removed (`startCorner`, `sanStraightCurve`, `cspReloadRelease`, `flagLeftoverEvery`), six dead
  language keys and dead migration branches removed; `lightsYellow` documented as a purely visual switch; no text speaks
  of a « number of stops » any more.

### Repository, documentation and tests
- New tests: `tests/review152a.lua` (10), `review152b.lua` (7), `review152c.lua` (16), `review152d.lua` (5),
  `review152e.lua` (2) and an integration case for the SpotterEnginer line; each fails on Beta 1.51. Tests updated because
  they froze a fixed defect: `FIXSA_WINDOW_HOLD_142`, `MANDATORY_PIT_WINDOW`, `PIT_CALLS_NEVER_WITHDRAWN`, preset revision
  14 → 15 (`extended.lua`, `schema142.lua`), `updates.lua` (leftovers of the old module) and the sleeping-car reads of the
  integration cases.
- `tests/mutate.py`: one flat list of mutations, anchors re-aligned on Beta 1.52, nine new mutations for the 1.52 fixes;
  the useful tree is copied once per process, each mutated file is restored byte for byte, the clean result is computed
  once per test, the strict-globals runtime of `test_pdr.py` is used, and `--jobs`/`--only` were added. Three mutations
  whose code became the real code or was removed are gone; the mutations no test caught any more are caught again
  (`REVIEW152C_SC_HELD_NO_LOOP_SESSION` checks that no restore is pending right after the session change; the Safety Car
  relaunch case checks the immediate start at every repeat; the yellow-flag queue mutation is checked by
  `AI_ZONE_QUEUE`).
- Test tools: `integration.py` no longer overwrites its results with a filtered run (`INT_FILTER`); `lint.py` writes
  `tests/lint-results.json`, read by `report.py`; the PDR case count, the fuzz length and the release frame count are read,
  not hard-coded; `report.py` takes the previous version's measurement from the last `docs/RELEASE_STATUS.json` and checks
  that the README shows the manifest version without any link into `dist/`; `package.py` ships the README without its
  banner (docs/ is not shipped) and reads the font list from `src/applier.lua`; `audit.py` covers the Hotlap profile and
  every global option, without line numbers; `devtools.py` paths come from `ADVANCEDIA_GAME` and `ADVANCEDIA_SETTINGS`.
- Documentation: frozen October audits (`AUDIT.md`, `docs/AUDIT_RC4.md`, `docs/AUDIT_V1.md`, `docs/AUDIT_V1_1.md`),
  `COMPATIBILITY.md` and `docs/INTERFACE.md` removed (their useful parts are in the README); entries up to Beta 1.39 moved
  to [docs/HISTORY.md](https://github.com/VincentChevalier44/AdvancedIA/blob/main/docs/HISTORY.md); generated result files
  are no longer tracked.
- `docs/API_NOTES.md` rewritten as a current reference sorted by topic (manifest and entry points, state, AI commands
  and their restore, flags, pits, storage, files and updates, gui.ini, windows and drawing, companion bridge, pitfalls
  seen in game), without a version log; APIs no longer called were removed, those the code uses were added.
- The window callback `script.HUMANAI__FLAGS`, absent from the manifest since Beta 1.25, is removed (tests draw the flag
  panel through `HUMANAI.drawFlags`).

**Verification**: 695 checks, 0 failures (`tests/test_pdr.py`, the 78 PDR situations included); 136 integration cases;
1,672 mutations, all detected (`tests/mutate.py`); clean lint (48 files); parameter audit (223 profile parameters, 50
global options). Golden runs against Beta 1.51: the full race (12 AI, 12 laps) has the same journal and stops, only the
« app-led overtakes » count moves (12 → 14, chained overtakes now attributed); the track day and rules scenes have fewer
chained overtakes (they now pass the guards) and two more yields (blue flags cleared). Benchmark medians against Beta 1.51
(5 alternated passes, 30,000 frames): 0.069 / 0.322 / 0.810 ms at 9 / 30 / 60 AI (1.51: 0.072 / 0.318 / 0.796, within
noise); long track (60.6 km, 46 AI): 0.355 ms mean, P99 0.793 ms (1.51: 0.374 / 0.884). 8-hour soak: 0 errors, 0.32 ms
mean, memory drift 847 KB, 13 KB in the last hour (1.51 on the same machine: 0.40 ms, 981 KB, 14 KB); the open criteria
(single-frame peak under 1 ms, total memory variation under 256 KiB) are still open, as in earlier versions
(`docs/MESURES.md`). The package is accepted by the Beta 1.51 updater.

## Beta 1.51 — 9 November 2026

### Built-in preset for the session detected (driver's request)
- With the automatic profile, each new session (track and session index) gets its built-in preset, applied and lit at
  once: practice → **Free practice**, qualifying → **Flying-lap qualifying**, race → **Realistic race**, track day (the
  Nordschleife included) → **Nordschleife Touristenfahrten**; hotlap: none. Another built-in preset chosen for that
  profile (Multi-class endurance) is kept; a custom preset loaded into that profile (new mark `Perso`) is never replaced.
- The profile's championship rules (rule set, mandatory stop, Safety Car), the driver's preferences and class patterns
  are kept; the driver's changes during the session stay until the next one; reloading the app in the same game launch
  does nothing (session key kept in `ac.store`, `humanai:presetsession`).
- New switch **Built-in preset for the session detected** (HOME › BUILT-IN PRESETS, global `presetBySession`, on by
  default). Off, or with a manual profile: the Beta 1.29 rule (recommended preset once for a profile never set, nothing
  lit). This reverses the Beta 1.29 decision.
- A built-in preset tile now lights without comparing the championship rules (`C.presetMatchSkip`). One shared code path
  for the tile click and the session (`C.applyBuiltin`).
- Log: `preset_session: <name> (profil <P>[, circuit Nordschleife])`, `preset_session: aucun (...)`.

### Mandatory stop: on or off (driver's request)
- **Mandatory stop in the race** is now on or off: one stop is required in the window, then every car (AI strategy and
  player) makes as many stops as it needs. The 0–3 slider is gone (the switch stays); profiles and custom presets saved
  with 2 or 3 stops read back as 1, without a validation error.

### Practice and qualifying: flying laps first (in-game report: an AI leaving the pits forced its way past the player on a flying lap)
- New module `src/quali.lua` and setting **Practice and qualifying: flying laps first** (`qualiTraffic`, Yielding tab, on
  in Practice and Qualifying, hidden elsewhere). Each car is on a flying lap or not: out-lap from the pit exit to the line
  (one more lap if the line comes within 30 s of the pit exit), cool-down or aborted lap (under 75 % of the fleet's pace
  there, corrected by the car's long pace, for 4 s, until the line), in-lap (called in), damaged car.
- An AI not on a flying lap yields to the closest flying car within 3 s behind it that is closing in (or within 30 m), like
  under a blue flag: through the queue rule (car ahead within 60 m), the follower-stall and pair-ignore rules, and a
  slower car closer behind no longer hides it; the flying AI takes the gap at once.
- It never attacks a flying car ahead (unless invited, or that car is abnormally slow). A flying AI does no standard
  yielding for a car that is not on a flying lap (the player's headlight flash is still honoured).
- Pit exit: the end-of-pit-lane hold (track day since 1.41) now also applies in Practice and Qualifying, for flying cars
  only.
- AI cool-down laps in qualifying (`qualiCoolLaps`, on by default, Qualifying only): after one or two flying laps in a row
  (drawn per AI), a lap at a level 12 % lower, until the line, then a new flying lap; never when less than 2.5 laps of
  session time remain. Counted in the minute summary (`refroidissements des IA N`).
- Player on an out-lap or cool-down lap: message **Flying lap — <driver> is coming on a flying lap: let them by** when a
  flying AI is within 3 s behind (once per AI every 30 s), new bridge kind `fastCar` (shown; value = AC index, extra = gap
  in s).
- Log: `cede a <name> en tour lance (...)`, `tour lance: <name> arrive derriere le joueur (...)`, `jonction des stands: X
  attend Y en tour lance`, and in the minute summary `tours lances : cessions N (abouties N, perdues N), attaques retenues
  N, retenues a la jonction N, avis au joueur N`.

**Verification**: new `tests/quali151.lua` (9 tests, including a 20 min animated qualifying scene). The fixture keeps
hand-set scenes free of the session preset and of the flying-lap rules (`g.presetBySession=false`, `qualiTraffic=false`),
which their own tests switch on. Known before 1.51 (also fails on the installed 1.50 sources):
`QUEUE_NOT_BEHIND_SERVING` (65.3 / 65.3).

## Beta 1.50 — 5 November 2026

### Start and first lap: no more lifting on the straight (Monza, 25 cars, 5 November 11:23)
- In the start and the first lap, on a straight (driver not braking, car straight, outside the anticipation window of a
  braking point), an AI keeps its foot down in the slipstream: no time-gap caution and no radar caution there.
- The front radar lifts only when contact is less than 0.6 s away, by a graded amount, with no free lane alongside,
  and **never** when the car behind is closer to hitting it than it is to hitting the car ahead (the player at full
  throttle 6 m behind an AI that lifted rear-ended it). Real obstacles (closing faster than 60 km/h) keep the previous
  behaviour; the anticipation before braking zones is unchanged.
- The straight is judged on geometry only (car straight, outside the anticipation of the pack's first braking or of a
  learnt braking point): AC's own following brake in the pack no longer turns the straight into a corner approach (in
  the 13:09 start with the first 1.50 build it did, so the rule almost never applied). Only a free brake (no car within
  the free headway ahead) sets the pack's first braking point; a following brake no longer ends the launch phase.
  No follow caution on the straight during the start and the first lap either.
- Log: minute summary « ligne droite : pied tenu N fois (dont voiture de derriere plus pres M) »; every radar lift or
  brake of the start and the first lap now says why: « (anticipation du freinage) », « (courbe) », « (approche
  rapide) », « (contact X s, aucun couloir libre) », « (contact X s, dernier recours) ».

### Safety Car leaves the pits by itself
- In service the Safety Car is held in its pit box by AC's own wait (start delay and brake counter, renewed) instead of
  being parked without a driver; released, it drives down the pit lane and joins the track. Normal deployment: released
  when the leader is about 20 s from the pit exit (at most 90 s after the call); red-flag restart: it leaves first and
  the AI follow 3 s later in the frozen order.
- If it does not leave its box within 40 s, or the pit lane within 45 s, it is placed on track as in 1.48, but never
  within the player's sight (800 m ahead, 300 m behind). In the first real deployment (5 November 14:57) it still did
  not leave its box (the fallback placed it after 10 s); every 5 s the journal now writes « voiture de securite: sortie
  en cours X s (V km/h, emplacement oui/non, voie des stands oui/non) » so the next deployment shows why. Recalled after the green flag without entering the pits, it is
  sent back to its box only once out of the player's sight (at most 60 s).
- Log lines: « retenue a son emplacement », « liberee, sort par la voie des stands », « sortie de son stand »,
  « sortie en piste devant <name> », « en tete de la file », « rentre ce tour », « rentree a son stand ».
- Bridge: the new internal phase `exit` is published as `call` (as `place` already was).

### No overtaking under VSC, FCY, Safety Car and the restart lap (5 November 14:57)
- In the first real Safety Car the AI passed the leading player one after another, and some passed the Safety Car
  itself; the player finished 15th. Under neutralisation every AI now queues behind the nearest car ahead on the track
  within 60 m, whatever its lane — the player, an AI or the Safety Car — matching its speed (the limit is set at once
  within 30 m). Only a crashed car may be passed; a slow player or the Safety Car is never « passable » any more.
- A car serving a penalty (the player's throttle cut, an AI's 5 s lift) stays in the queue under neutralisation:
  passing it is an infraction, as for any car (outside neutralisation, a car serving a penalty may still be passed).
- An AI that passes illegally under neutralisation or on the restart lap now also **gives the place back**: it slows
  below the passed car's pace until that car is ahead again (at most 30 s), on top of the 5 s lift and the strike. The
  passed car may retake the place without penalty. Dropped if the passed car leaves the race, enters the pits or
  crashes. Log: « sanction IA: X rend la place a Y (au plus 30 s) », « place rendue IA: X a Y (neutralisation) »,
  « place a rendre IA: X a Y, abandonnee (raison) ». Local yellow zones are unchanged.
- With the fallback placement, the queue forms behind the race leader (the player when he leads): « en tete de la
  file » names the first car behind the Safety Car.

### Companion bridge announcements (SpotterEnginer)
- New kinds, silent (never a top-of-screen message), re-emitted on the next frame if dropped: `scOut`, `scLeading`,
  `restartPlace`, `restartRetake`, and `pitPlanOk` (the player fixed his Quick Pitstop strategy after a « same
  compound » warning; the warning is cleared at once) (see README, « Companion app bridge »).

### F1 mandatory stop: reminder latched
- The « change compound » reminder before the pit entry is latched until the entry point: braking inside the window no
  longer hides it and announces it a second time (it is released if the car moves more than 200 m away from the
  entry).
- The player's tyre catalogue is now read (it was read for the AI only): compound names in the journal, the overlay
  and the announcements (« SS → S »), and the Quick Pitstop strategy is finally checked. Mapping confirmed in game:
  the compound spinner goes from -1 (no change) to 3, 0..3 = SS, S, M, H.

**Verification**: 646 checks, 645 passed; 134 integration cases; clean lint; 8-hour soak without errors (`docs/RELEASE_STATUS.json` of Beta 1.50).

## Beta 1.49 — 5 November 2026

The app is renamed **AdvancedIA** (it was ACAdvancedIA). Driving and rules are unchanged.

### New name everywhere
- Folder `apps/lua/AdvancedIA`, entry script `AdvancedIA.lua`, name in AC's app list and in the window header
  (**ADVANCED**·**IA**), the overlay, the update notices, the tooltips and every text; session log
  `Documents/Assetto Corsa/logs/AdvancedIA.log`.
- GitHub repository `VincentChevalier44/AdvancedIA`, packages `AdvancedIA-Beta-X.zip` / `.sha256`. The update button
  reads the new repository and accepts only packages under `apps/lua/AdvancedIA/`; its work folder is now
  `state/AdvancedIA-update` (the old `ACAdvancedIA-update` is never read, so a rollback can never put an old version
  in the new folder).
- New banner (JPEG).
- Kept on purpose: the companion bridge keys `ACAdvancedIA.Bridge.*` (frozen format shared with SpotterEnginer,
  `src/bridge_layout.lua` unchanged), the settings prefixes `humanai:*`, and the CSP state file
  `ACAdvancedIA-cspgui.ini`, which holds your original CSP display options.

### F1 mandatory stop: compound change (Monza log, 5 November 09:55)
- The player's stop counted only if the compound read at the box exit differed; it is now followed from the box
  arrival until the pit-lane exit plus 3 s (AC may update the fitted compound a little later), and counted as soon as
  it changes. The log names the compounds (`compte: compose change (SS -> S, …)`, `non compte: compose inchange
  (SS -> SS)`). The player's compound names are now read too (they were read for the AI only, hence `0 -> 1`).
- Overlay, F1 rules, while the stop is due: *Mandatory stop · change compound*; about 20 s before the pit entry
  (learnt from the other cars, otherwise the last third of the lap), in the pit lane and in the box: *Change compound:
  you are on SS → fit S or M*. After the stop: *Mandatory stop validated (SS → S)*, or for 8 s *Stop not counted: same
  compound (SS → SS). In F1, change compound.* Never above a flag, a penalty, the blue flag or DRS.
- Pit strategy check: the compound of the selected Quick Pitstop preset (`ac.getPitstopSpinners`, CSP 0.2.7+) is read
  at the start, every 2 s while the stop is due and on entering the pit lane (never per frame, never changed by the
  app). Same compound planned: *Pit strategy: same compound planned (SS). In F1, choose another compound (S or M) in
  the pit menu.* for 8 s, and in the pre-entry reminder; otherwise *Pit strategy: S planned, stop valid*. The value to
  compound mapping is only used when unambiguous (one value per compound, or one more for « no change »), and the
  whole menu is written once to the log (`strategie des stands (Quick Pitstop): …`). Older CSP: one log line
  (`strategie des stands illisible`), no warning.

### Race start wait: 2 s by default
- *Start delay (s)* (Start section, Race profile) now defaults to 2 s instead of 1 s (driver's request). A Race profile
  still on the old 1 s default moves to 2 s on the first launch (`profils mis a jour …: C:attente au depart 2 s`); a
  value you set yourself stays as it is.

### Moving from ACAdvancedIA (one manual install)
- The update button of Beta 1.48 and older cannot move the app to the new folder: install this version by hand
  once (README › *Moving from ACAdvancedIA*): close the game, back up and delete `apps/lua/ACAdvancedIA`, extract the
  package at the AC root, and rename `state/lua/app/ACAdvancedIA.ini` to `AdvancedIA.ini` before the first launch to
  keep your settings.
- While the old version (`apps/lua/ACAdvancedIA/manifest.ini`) is still installed, AdvancedIA drives nothing (no AI
  command, flag, CSP option, AI flood or bridge write) and shows the instruction in its window and on screen, in
  French and English; one log line (`ancienne version ACAdvancedIA encore installee`). An empty leftover folder is
  harmless.
- First launch without the old settings file renamed: *ACAdvancedIA settings not carried over* under **HOME › TO
  CHECK**, with the file to copy; one log line.

**Verification**: 629 checks; 132 integration cases; 1,611 mutations, all detected; clean lint, parameter audit; the reference scenes are identical to Beta 1.48 (they set their own start wait; also identical with the old 1 s default); the end-to-end race scene too; 8-hour soak with 0 errors (memory between 10.8 and 12.1 MB, peak frame 0.79 ms); engine bench, median of five alternating runs, 9 / 30 / 60 AI: 0.064 / 0.303 / 0.757 ms (Beta 1.48: 0.058 / 0.275 / 0.738 ms); long track (60.6 km, 46 AI): 0.324 ms, P99 0.763 ms (Beta 1.48: 0.317 ms, P99 0.726 ms); companion bridge with SpotterEnginer installed: 0.010 / 0.015 / 0.023 ms per frame (9 / 30 / 60 AI), none without it.

## Beta 1.48 — 4 November 2026

Red-flag restart and Safety Car, from the 4 November Monza log (18:11): the Safety Car never left its pit box, the
restart order was not the red-flag order, and the overlay showed no restart position.

### The Safety Car really leads
- AC's AI never drove the Safety Car out of its box, in any deployment (`restee dans la voie des stands`, then an FCY
  fallback). It is now **placed on the track** through CSP, the method already used to spread the AI on a track day:
  - red-flag restart, pit exit known: 200 m after it, the AI waiting in their boxes until it is placed;
  - pit exit unknown: 250 m ahead of the first car out, once that car is 30 m onto the track;
  - ordinary deployment: 200 m ahead of the leader, after the 10 s call;
  - always on a point with no car within 80 m, retried every 2 s; not placed within 15 s: VSC (F1 restart) or FCY, logged.
- It drives at 80 km/h while the first car behind is more than 120 m back, then at its set speed.
- In its last lap, if it misses the pit entry and crosses the line, the green comes there and it is sent back to its box.
- It is only ever parked in its pit box (never across the track after a failed return).
- Log: `voiture de securite: posee en piste a X m, Y m devant <name> (jonction|premiere sortie|meneur)`.

### Restart order frozen at the red flag
- The classification at the red flag, the player included, sets the pit exit, the standing-restart grid, the overlay
  and the overtaking exemption (`drapeau rouge: ordre fige (N voitures), joueur P7 derriere <name>`).
- The restart waits until every AI is at its box, not just in the pit lane.
- Each car leaves its box once the one before it in the order has left and passed its box: at most 20 s of waiting,
  45 s behind the player (`sortie des stands: X attend Y`, `attente maximale`).

### Restart indicator on the overlay
- In the pits: a **RESTART P7** box and *Stay in the pits · restart P7 behind …*, *Wait: … leaves before you*,
  *Go: P7 behind …* (P1: *behind the Safety Car*). On track: a green *P7 · BEHIND D. FERRO* pill, or an amber
  *RETAKE P7: PASS … (ALLOWED)* pill. The session line shows the frozen position. French and English.

### Retaking your place is not an overtake
- During the pit exit, the restart lap and until the line, passing a car classed behind you in the frozen order is
  allowed, for the player and the AI (`reprise: X reprend sa place sur Y`). Passing a better-classed car or the
  Safety Car is still penalised; nothing changes after the line.

### Stops under the red flag
- F1: the tyre change under the red flag counts even before the pit window opens (lap 1).
- GT and Endurance: no work and no stop counted, also for a car that reaches its box after the restart.
- With a compulsory compound change, the player's stop counts only if the compound changed; the player's stops are logged.

### Companion bridge
- Layout v1 unchanged; the new placing phase is reported as `call`.

**Verification**: 625 checks; 129 integration cases; 1,570 mutations, all detected; clean lint, parameter audit; the reference scenes are identical to Beta 1.47; the end-to-end race scene too; 8-hour soak with 0 errors (memory between 9.6 and 10.6 MB, peak frame 1.03 ms); engine bench, median of five alternating runs, 9 / 30 / 60 AI: 0.055 / 0.253 / 0.662 ms (Beta 1.47: 0.053 / 0.249 / 0.637 ms); long track (60.6 km, 46 AI): 0.283 ms, P99 0.595 ms (Beta 1.47: 0.294 ms, P99 0.597 ms); companion bridge with SpotterEnginer installed: 0.007 / 0.011 / 0.016 ms per frame (9 / 30 / 60 AI), none without it.

## Beta 1.47 — 4 November 2026

AI behaviour fixes from the 4 November logs, and CSP display options kept ticked.

### Race starts
- The launch phase no longer ends on a brief yaw blip on the straight (the yaw must be held 0.3 s) or on the app's own
  radar brake read back from the pedal; it ends at the AI's own first real braking, or 2.5 s before the point where the
  pack ahead first braked, and never comes back.
- Front radar before the first braking zone: brake capped at 0.18, and with a car close behind (less than 0.6 s, at
  least 8 m: the same rule for an F1 at 300 km/h and a road car at 100 km/h), a throttle lift only (no brake). On the
  Monza pack scene: radar brakings in the first 10 s 28 → 0. The start log line counts the lifts.
- Standing still on the grid no longer counts as being stopped on track: a car still slow a second after the lights went
  out was an obstacle to avoid, and the cars behind it swerved (AVOID) in the middle of the pack.

### Careful first lap (new setting, Start section, on in the race presets)
The driver's idea: on the first lap everyone is really careful. In a race, at the start and at every restart (green flag
after the safety car, end of a red-flag restart lap, standing restart), every AI drives its first lap as a careful
driver. Every rule is counted in time, never in metres, so it behaves the same for F1, GT3/GT4, road cars and mixed
classes:
- **Gap counted in time**: below 0.8 s to the car ahead, caution rises gently (up to ×1.3 under 0.25 s), never on the
  launch straight; never a brake or a speed limit on a straight.
- **Every braking zone of the lap anticipated**: braking points are learnt live where a car with nobody close ahead
  brakes from 60 km/h or more (no fixed distance, no data needed from earlier sessions); with a car less than 0.8 s
  ahead, caution rises 2 s before such a point or as soon as the car ahead brakes.
- **Radar: throttle lift first.** Above 0.8 s to contact, or on a straight, or with a car close behind: lift only. Below
  0.8 s while braking: a light brake (0.18). A full radar brake only for a contact less than 0.4 s away (a real
  obstacle).
- No defence, no tow-breaking, no dirty-air lift; overtakes only on a real straight, away from braking zones (its own,
  the target's or a learnt point ahead), with 1.5× the usual advantage and a 1.3× longer free corridor.
- Avoidance (AVOID) only for a stopped or very slow car (under 30 % of the AI's own speed, or under the obstacle speed):
  a braking wave or a hairpin is never an obstacle.
- Aggression at most 85 % of the base; overall caution at most 2× the base (start, following, radar and braking
  multipliers stacked up to 3 or 4 and slowed the pack to a crawl into the first corner), except under yellow flags,
  neutralisation or red flag.
- The mode ends for each AI at its first crossing of the line (a crossing in the first 10 s after a restart does not
  count), when the pack has spread around it (more than 2 s ahead and behind for 3 s), after 3 minutes at most, or when
  it enters the pits; it is then released over 3 s. From lap 2 the commands are exactly those of a race without the mode.
- Journal: `premier tour: mode attentif pour N IA (depart|relance|depart arrete)` at the start, `premier tour: fin du mode
  attentif apres X s (… ligne franchie, peloton etire, delai, stands ; N point(s) de freinage appris)` at the end, and a
  `premier tour attentif : …` segment in the minute summary (anticipations, radar lifts and brakes, avoidances refused,
  overtakes held).
- Start bench (tests/startbench147.lua, simplified model of AC's AI: Monza, Spa, a first corner 400 m from the grid, a
  narrow street circuit × F1, GT3, road cars, mixed classes, 24 AI, 3 draws): lap-1 rear contacts 216 → 142 (AC alone
  320), at the first braking zone 137 → 94, avoidances in the pack 29 → 7, radar brakings on straights 66 → 33 (18 of
  them for a contact less than 0.4 s away), lap-1 time +0.5 %.

### Red flag only when the track is really blocked (the driver's decision)
- The red flag now needs at least 3 cars (setting unchanged) stopped for 10 s **because of an incident**: damage, a
  spin, stopped off the racing line (more than 4 m) or off the track, or stopped alone on the track. Undamaged cars
  waiting on the racing line behind a stopped car (the queue behind the accident) never count.
- And the track must be really blocked: where those cars stand (within 40 m), they leave no 2.5 m passage across the
  track width (each car's width plus 0.3 m on each side; checked for both sides of the line).
- Otherwise the race goes on under yellows, VSC or Safety Car as before, by severity. The journal says why, once per
  episode: `pas de drapeau rouge: N voitures arretees dont M dans la file[, piste encore passable]`; the red flag line
  reads `drapeau rouge: N voitures accidentees immobilisees 10 s, piste bloquee`.
- On the start bench (two cars spun at the first corner, 16 scenes × 3 draws), the pile-ups no longer stop the race:
  383 of 384 AI complete lap 1 (before: 255, red flag in several draws with half the field sent to the pits), cars slowed
  by a yellow 163 → 58, rear contacts 175 → 114.

### Double yellow with an unknown pace
- Before the pace is learnt (first lap of a session), the double-yellow speed is relative to the car: 35 % of its top
  speed seen so far, never under the « unknown pace » speed (50 km/h). Before, every car, F1 or road car, was slowed to
  50 km/h through the whole zone after a first-lap pile-up. Cars slowed by the yellow on the start bench: only those
  at most about 350 m (9 s) before the incident.

### Defence, overtaking, yielding
- Defence only against a follower clearly to one side (≥ 0.5 m), at most 20 km/h faster (or ≥ 1.5 s to contact), on a
  real straight with straight ahead, never alongside, on an out-lap, during the pit-exit guard or near the pit junction.
  Every defence is logged (`defense:`).
- Overtake loops: a pair ignored after "target faster" is no longer re-attacked on closing alone without a real
  advantage, and needs 2.5× more closing.
- Practice and qualifying: a yield nobody uses ends after 3.5 s.
- Blue flag: a lapped car's yield is never refused or counted by the anti-zigzag cap; "laisse passer" no longer logged
  twice when the lap gap flickers at the line.
- Pit exit: the lateral offset restarts from zero.

### Strategy and sanctions
- Tyre wear threshold before a stop: default 30 % (was 75 %, never reached at the 1–1.4 % per lap measured in game),
  minimum 10 %; profiles still on 75 % move to 30 % (data revision 20), tuned values stay.
- Undercut and cover also for a mandatory stop still due.
- No track-limits warning within 3 s of a contact (car pushed off).

### Log
- "carburant demande" only when the request changes by 5 L or more; the radar line notes the follower's gap; the
  summary of the last, partial minute is written when the app closes.

### CSP display options (Hide system messages, Hide race flags)
- They now stay ticked while the app is installed and active, also with the game closed, so Content Manager shows them
  ticked. Panic, closing the game, unloading the app or a crash no longer give your original values back.
- Your original values come back when you switch the option off in Overlay › AC displays, switch the app off (APP
  button), turn off the app's flag panel in the profile in use (flags), or when the overlay stops taking over AC's
  messages (messages). An option you ticked yourself is never touched. After uninstalling the app, untick them in
  Content Manager › Custom Shaders Patch › GUI if you want AC's own flags and messages back.

### Track light panels and overlay after a red flag
- After a red flag and a session restart (Monza, 4 November), CSP could keep showing the app's own red (AC's black flag, value 5) once it was handed back; the app then took it for a native AC black flag: panels stuck red, overlay stuck on the black flag, every later yellow or green refused (« drapeau natif 5 »).
- The app now remembers the last flag it wrote. After handing it back, that value still shown is treated as its own (never a native black flag, overwritten when a new colour is wanted); the restore is sent again (3 times, 1 s apart), then AC's start flag is written and handed back. Every new session, restarts included, hands the flag back again. A real AC black flag the app never wrote is still respected.
- The missing « rouge » journal line at that red flag was dropped by the journal rate limit (20 « carburant demande » lines in the same second); those lines are now written only when the request changes.

### Updates and bridge
- The update report names the version that was really running before an in-app update (it could show « Beta 1.45 -> Beta 1.45 » when CSP had kept an older compiled copy of the app).
- Includes the Beta 1.46 companion-app bridge for SpotterEnginer, still inactive unless SpotterEnginer is installed.

**Verification**: 621 checks; 127 integration cases; 1,522 mutations, all detected; clean lint, parameter audit; the reference scenes are those of the 1.47 fixes, except the intended relative double-yellow fallback (identical again with the old fallback); the end-to-end race scene is identical; 8-hour soak with 0 errors (memory between 10.0 and 11.0 MB, peak frame 0.95 ms); engine bench, median of five alternating runs, 9 / 30 / 60 AI: 0.055 / 0.258 / 0.651 ms (Beta 1.46: 0.053 / 0.233 / 0.595 ms); long track (60.6 km, 46 AI): 0.290 ms, P99 0.604 ms (Beta 1.46: 0.281 ms, P99 0.561 ms); companion bridge with SpotterEnginer installed: 0.008 / 0.011 / 0.017 ms per frame (9 / 30 / 60 AI), none without it.

## Beta 1.46 — 4 November 2026

Companion-app bridge for SpotterEnginer, inactive unless SpotterEnginer is installed.

- **Bridge**: when `apps/lua/SpotterEnginer/manifest.ini` exists (checked once at launch), the app opens two shared structures (`ac.connect`, layout v1 in `src/bridge_layout.lua`, identical in both apps) and copies its engine state into them every frame, read only. SpotterEnginer reads them to speak flags, neutralisations, the delta, penalties, the pit window and the AI sanctions and stops.
- **Without SpotterEnginer**: nothing is opened or computed; one journal line « pont des apps compagnes: SpotterEnginer absent, pont inactif ». The AI, the windows and the overlay behave exactly as in Beta 1.45.
- **Isolation**: the bridge never writes into the engine; an error in it closes the bridge alone (one journal line), never the engine or the interface; it is closed when the app unloads.
- **Dev tools**: `tests/devtools.py install` now gives copied files a fresh modification time (CSP kept running Beta 1.44 code after a 1.45 install that preserved the old dates).

**Verification**: 588 checks; 125 integration cases; 1,453 mutations, all detected; clean lint, parameter audit; the reference scenes identical to Beta 1.45 and the end-to-end race scene too; 8-hour soak with 0 errors (memory between 9.5 and 10.6 MB, peak frame 0.85 ms); engine bench, median of five alternating runs, 9 / 30 / 60 AI: 0.055 / 0.254 / 0.647 ms (Beta 1.45: 0.055 / 0.260 / 0.652 ms); long track (60.6 km, 46 AI): 0.306 ms, P99 0.713 ms (Beta 1.45: 0.301 ms, P99 0.713 ms); companion bridge with SpotterEnginer installed: 0.006 / 0.010 / 0.040 ms per frame (9 / 30 / 60 AI), none without it.

## Beta 1.45 — 4 November 2026

No grey frame around the settings window any more: the window has no CSP background or padding, like SetupLab, and the app paints its dark background edge to edge.

- **Window**: `manifest.ini` `[WINDOW_0]` gains `NO_BACKGROUND` and `PADDING=0,0`, and loses `BACKGROUND_COLOR=SETUP`. Nothing else changes: same size, minimum size, settings group, no title bar, no scroll bar.
- **When it shows**: CSP reads the window declaration when the game loads the app (`App is loaded … windows: 1` in `custom_shaders_patch.log`); the restart after an in-app update only reloads the script. After updating from the app, the window keeps its old frame until the next game launch.

**Verification**: 588 checks; 124 integration cases; 1,444 mutations, all detected; clean lint, parameter audit; the reference scenes identical to Beta 1.44 and the end-to-end race scene too; 8-hour soak with 0 errors (memory between 7.1 and 7.9 MB, peak frame 3.51 ms); engine bench, median of five alternating runs, 9 / 30 / 60 AI: 0.063 / 0.299 / 0.776 ms (Beta 1.44: 0.065 / 0.285 / 0.731 ms); long track (60.6 km, 46 AI): 0.286 ms, P99 0.624 ms (Beta 1.44: 0.311 ms, P99 0.786 ms).

## Beta 1.44 — 4 November 2026

The AI no longer stays behind you when you slow down or move aside to let it by (practice, qualifying and track day).

- **Never written off after one try.** An AI that gave up passing you because you sped up again (« cible plus rapide ») used to leave you alone for 45 s, then 3 min, then 10 min. Outside the race it now tries again as soon as you slow down; in the race nothing changes.
- **Invitations in gentle corners.** Outside the race, moving aside in front of an AI now invites it past in a gentle corner too (up to about 0.4 g), not only on a straight. The lateral gap counts once the part due to the curve itself is taken off, so a car simply following the bend is never taken for an invitation. In the race, invitations still need a straight.
- **A crawling player is passed.** Below 30 km/h the AI could neither treat you as an obstacle (under 25 km/h) nor overtake (30 km/h minimum). Outside the race, behind a player clearly slower than its own pace here, it may now pass at your speed, and the courtesy rule (no counter-attack right after you passed it) no longer holds it back once you slow down clearly.
- **Log**: `invitation du joueur non suivie` now names two more reasons, `joueur plus rapide` (you were pulling away) and `virage` (corner tighter than 0.4 g outside the race). A car held behind you or alongside you is no longer reported as a « slow vehicle ahead » (`vehicule lent devant le joueur … 0 m devant`). At the pit exit, an AI no longer « waits » for the car that has just left the pit lane in front of it (`attend … dans 0.0 s`, then `repart apres 0.0 s`).

**Verification**: 587 checks; 124 integration cases; 1,441 mutations, all detected; clean lint, parameter audit; the reference scenes identical to Beta 1.43 and the end-to-end race scene too; 8-hour soak with 0 errors (memory between 9.7 and 11.0 MB, peak frame 0.68 ms); engine bench, median of five alternating runs, 9 / 30 / 60 AI: 0.053 / 0.240 / 0.618 ms (Beta 1.43: 0.054 / 0.254 / 0.640 ms); long track (60.6 km, 46 AI): 0.291 ms, P99 0.640 ms (Beta 1.43: 0.272 ms, P99 0.626 ms).

## Beta 1.43 — 4 November 2026

AI sanction notices redrawn on the overlay as in the mockup.

- **AI sanction notices** get their own overlay panel, like the Safety Car and restart badges:
  - a badge with the code: DT drive-through, SG stop-and-go, +N time penalty, CUT throttle cut, POS give the place back; a black square with a white edge for a black flag;
  - the AI driver's name as the title, the sanction and its reason below (« Drive-through (jump start) », « +5 s (track limits) »);
  - a short label on the right of the session line: Sanction, Give the place back, Black flag.
- The panel takes the band only when it is free: nothing shown, or simple information (green, start, lap, update). Under one of your flags, the flag keeps the band and the notice goes to the session line, as before.
- Same timing and limits as before: one notice every 6 s at most, black flags always, and only when the overlay takes over AC's messages. The app's own AC message is never shown twice, and the log is unchanged.

**Verification**: 578 checks; 124 integration cases; 1,429 mutations, all detected; clean lint, parameter audit; the reference scenes identical to Beta 1.42 and the end-to-end race scene too; 8-hour soak with 0 errors (memory between 9.7 and 10.9 MB, peak frame 0.69 ms; Beta 1.42 on the same machine the same morning: 9.3 to 10.6 MB, 0.75 ms); engine bench, median of five alternating runs, 9 / 30 / 60 AI: 0.052 / 0.237 / 0.613 ms (Beta 1.42: 0.052 / 0.243 / 0.629 ms); long track (60.6 km, 46 AI): 0.277 ms, P99 0.601 ms (Beta 1.42: 0.307 ms, P99 0.675 ms).

## Beta 1.42 — 4 November 2026

AI race strategy and AI sanctions, breaking the tow and dirty air, tyre warm-up and wear, progressive failures and last-laps urgency: two new settings sections (**AI strategy**, **AI sanctions**) and new subgroups in **Overtaking** and **Weather**, all in the built-in presets.

- **AI strategy** (race): each AI plans its own stops from its tyre wear, its fuel and the laps left, with a random strategist character (cautious to bold), undercut and overcut against its direct rivals, refuelling for the next stint, and a stretched last stint rather than a stop one or two laps from the flag.
- **Progressive failures** (race, rare): a leak, overheating, a slow puncture or a battery drain lowers the pace gradually; the AI goes to the pits, is repaired, and is never parked on the track.
- **Out-lap warm-up and tyre wear**: a slightly slower out-lap after a real stop; more lock-ups on worn, asymmetric front tyres at the end of a stint, each adding a small flat spot.
- **Breaking the tow, dirty air, last laps**: one move on a long straight to break a direct rival's tow; a slight throttle lift and quicker micro-corrections in a car's wake in corners; more aggression and an earlier defence in the last laps against direct rivals only.
- **AI sanctions**, the same rules as yours: track limits (invalidated laps in practice and qualifying; warnings then time penalties in the race), a gradual throttle cut for a corner cut with a time gain, jump start, pit-lane speeding and pit-exit line (drive-through, stop-and-go or time penalty), wrong way and ignored penalties (black flag, car parked at its box), and giving a place back after an off-track overtake.
  - Honest note: AC cannot give its own penalties to an AI nor change its results. Time and unserved penalties go to the app's **corrected classification** (Diagnostic, journal, race recap). An AI drive-through is a pit call without service: AC's AI still stops briefly at its box. AI invalidated laps exist only in the journal and the Diagnostic.
- **Safety first**: a throttle cut only on a straight, never with a car closing behind; no sanction for an off caused by the app's own manoeuvre or under a yellow flag; a place where the AI line itself leaves the limits is ignored and its warnings taken back; a penalty the AI cannot serve (pit lane never used by the AI) becomes a time penalty; unticking a section or a switch stops what is under way.
- **Fixes found by a full race simulation**: an AI is no longer taken for an abnormally slow car after a standing start (its usual pace ratio is bounded); a strategist no longer pits one lap from the flag nor covers a rival with fresh tyres; a penalty pass is never counted as a stop.
- **Fixes from adversarial reviews**:
  - Sanctions: a jump start is counted once (sustained movement), unticking a section stops what is under way, safer throttle cuts (straight, closing speed, hysteresis), give-backs only between cars on the same lap, no black flag for a penalty the app could not ask to serve, a correct corrected classification with lapped cars, track-limit penalties never lead to a disqualification, the throttle always returns exactly to normal, and a disqualified AI is parked only at its box.
  - Strategy: no useless stop in the last laps (stop need decided on raw capacity), new tyres fitted at strategy stops and no repeated stop that changed nothing, a shared and stable pit-call limit, stops held until the mandatory window opens, no fuel learning under neutralisation, critical fuel always called, tyre wear used only once its scale is checked in game.
  - Tow and urgency: the tow move goes away from the follower and never towards the forced overtaking side, never against a faster or overtaking follower or you, returns before the braking zone, never followed by a defence on the same straight; urgency counted on each car's own laps; tow and dirty-air counters in the minute summary.
- **Fixes from a review of the fixes** (interactions between rule stops, strategy stops and penalty passes): a penalty pass no longer restarts the maximum-stint clock and never takes fuel, even when a rule stop falls due in the lane; a penalty waits for a rule or strategy stop that is due, and a new penalty call respects the shared pit-call limit; critical fuel is judged after the after-stop check (no extra stop right at the pit exit); fuel is judged only after a fuel stop (never after a failure stop); an unneeded stop request not yet called is withdrawn; overcut and reaction reset at any box visit; the tyre-wear probe counts laps observed since it started (app reloaded mid-race); a stop under a red flag never abandons tyre stops; no tyre forced in the wet when the app does not manage the weather; laps left of a timed race from the car's own pace, as for fuel; flat spots reset only when new tyres were fitted; no checkpoint save on every throttle write.
- **Note**: the out-lap warm-up and the level part of a failure act through the AI level and need the **General** section ticked; the throttle part of a failure works either way.

**Verification**: 574 checks; 123 integration cases; 1,418 mutations, all detected; clean lint, parameter audit; the three reference scenes identical to Beta 1.41 byte for byte with every new setting off and with them on; a new end-to-end race scene (12 AI, 12 laps: fuel, tyre wear, jump starts, cuts, pit speeding, wrong way, failures, tow, last laps, finish) with safety checks on every frame; 8-hour soak with 0 errors (memory between 8.6 and 9.7 MB, peak frame 0.63 ms); engine bench, median of five alternating runs, 9 / 30 / 60 AI: 0.051 / 0.234 / 0.588 ms (Beta 1.41: 0.046 / 0.215 / 0.571 ms); long track (60.6 km, 46 AI): 0.278 ms, P99 0.523 ms (Beta 1.41: 0.241 ms, P99 0.480 ms). Not yet checked in the game: see docs/VALIDATION.md (AI strategy and sanctions in a real race).

## Beta 1.41 — 3 November 2026

AI traffic fixes from an exhaustive audit of the 3 November track days (Fonteny, Isle of Man 60.6 km, Nordschleife Touristenfahrten): slow damaged AI, overtaking loops, pit-exit collisions and the anti-zigzag count.

- **Slow damaged AI:**
  - What was wrong: an AI crawling at 30 km/h where its class runs at 200 (damage) was too fast to be an obstacle and too slow to be overtaken, so a queue formed behind it for minutes. The app did not brake those cars: they were damaged by AC (suspension, body).
  - What changes: the car at the head of such a queue (below 60 % of *its own* usual pace, so a slow road car among GT cars is never concerned) becomes an obstacle the cars behind drive around after 5 s, and can be passed at any speed. It slows no further when it yields.
  - Damaged (suspension or body) and slow for 30 s, it is brought back to its pit in track day, practice and qualifying (the move itself repairs it), or called in during a race (once per session when the Rules tab is unticked, since such a stop repairs nothing).
  - In track day, practice and qualifying, a damaged AI that reaches its pit by itself is now repaired there.
  - A new log line `IA lente a contourner:` says when a slow AI becomes an obstacle. A slow spot that ends before 5 s is never added to the next one.
  - Until an AI's own usual pace is known (its first 20 s of free driving), the slow-AI line of Beta 1.39 is still written from its class pace, for the log only: nothing is commanded then.
- **Overtaking loops:**
  - What was wrong: up to 100 % of the attempts in a session ended because the target was faster, the same two cars trying up to 16 times.
  - What changes: an AI now overtakes a yielding car or the car holding it up only if that car is not pulling away and the AI is really faster at that spot (its learned free pace, 3 % margin).
  - After a failed attempt the pair is left alone for 45 s, then 3 min, then 10 min. This wait never delays a blue flag or a yield to a faster class.
  - An AI no longer yields to an equally fast AI that is merely close behind. A yield another AI does not use ends after 6 s on a straight; a yield to you is never ended that way.
  - While yielding, the AI's top speed on the straights is held 8 km/h under its usual pace, so the follower can get by. In track day with the Traffic tab, its speed limit then rises back gradually after the yield, at the Traffic tab's usual rate.
  - The overtaking corridor (free space needed ahead) is judged on the free pace only behind an abnormally slow AI; elsewhere it is unchanged.
- **Long tracks:** the learned pace now has one point every 50 m at most (Isle of Man: 1,213 points instead of 400).
- **Pit exit:**
  - The app learns where the pit lane joins the track.
  - Cars moving in the last 100 m of the pit lane (or rolling within 30 m of the merge) are seen by the cars on track (forward radar, avoidance). A car stopped in the pit lane, you included, is not.
  - **Track day only:** an AI driving out of the pit lane, past its own pit box, waits at the end of the lane, 10 s at most, while a car on track will reach the merge within about 5 s. It uses the same native stop as the hold in the pit box; the app still sends no line, speed or level command in the pit lane. In practice, qualifying and races, the pit exit stays AC's.
  - The first pit exit of each session is not covered yet: the merge point is learned from it.
- **Anti-zigzag limit:** a return to the AI's own line is no longer counted as a move to the other side, and a target frozen on the current offset (braking, car alongside) is never counted.
- **Track day:** the Safety Car is identified before the AI are spread on the track, so it is never placed on track and sent back.
- **AC's cut and penalty banners shown once:**
  - What was wrong: in your Beta 1.40 sessions, AC still drew its red banners *CUT DETECTED: LAP WILL NOT COUNT* and *PENALTY, SLOW DOWN FOR 9 SECONDS OR SLOW DOWN TO 35 KMH* although the app had ticked CSP's **Hide system messages** (and CSP had re-read it). The overlay showed them too, so you saw them twice.
  - Honest note: CSP has no option or function that hides these banners; AC keeps drawing them.
  - What changes: the overlay no longer shows AC's cut and penalty messages again (cut, slow-down, drive-through, stop and go, jump start, disqualification; matched on AC's own texts, any case). Every other message (other apps, votes, assists) is still shown as before. They are all still written to the session log, with one line per session: `messages d AC: penalites et coupes laissees a l affichage d AC (CSP ne permet pas de les masquer)`.
  - The overlay's own flags, signals and infractions are unchanged, and so are the app's own announcements (its *Penalty* messages in English are recognised as its own and still shown).
  - Limit: a message from another app that starts with *Penalty* or names a drive-through, a stop and go, a jump start or a disqualification is treated like AC's and not shown again (it stays in the log).
- **Track light panels (Melbourne 2026 layout):**
  - What was wrong: the panels stayed green under the app's yellow flags (log `panneaux lumineux du circuit: non detectes`). The layout's configuration includes its flag panels with paths such as `../../common/…`, and the app skipped every include containing `..`.
  - What changes: included files are now found the way CSP finds them: from the folder of the file that includes them (`..` allowed), `common/…` in CSP's track configurations, and `extension/…` also from the Assetto Corsa folder. A file is read only if it stays inside the track's own folder or CSP's configuration folder; absolute paths and anything outside are refused.
  - At most 64 files and 8 MB are read, once per track. When nothing is found, the log says how many files were read and how many includes were not read, and why.
  - On the author's installation, 25 of 46 tracks are now detected (76 of 151 layouts, 68 before): the 2026 layouts of Melbourne, Baku, Barcelona, Silverstone, Montreal, Monza, Shanghai and the Red Bull Ring.
- **Session log:**
  - **Minute summary:** contacts now counts real contacts between cars; yields where nobody passed are counted apart from completed ones.
  - **Slow AI lines:** the slow-AI line gives the AI's usual pace, its position, its pedals and the reason the episode ended.
  - **Plain-language reasons:** every overtake end reason is in plain words.
  - **Frame cost:** the cost per frame is measured again (with a fallback clock), and the clock used is logged.
  - **Pit exit:** new `jonction des stands:` lines.
- **No new setting:** settings, profiles and presets are unchanged.

**Verification**: 487 checks; 122 integration cases; 1,230 mutations, all detected; clean lint, parameter audit; golden scenes changed only as intended (*cible plus rapide* share of the attempts: track day 4 % to 0 %, race with 30 AI 24 % to 6 %, race with 60 AI 17 % to 4 %; completed passes stable or slightly up); 8-hour soak with 0 errors (memory between 8.2 and 9.5 MB, peak frame 0.99 ms); engine bench with 30 AI, median of five alternating runs: 0.218 ms (Beta 1.40: 0.221 ms); long track (60.6 km, 46 AI, 1213 pace points, pit exit merge learned and holds running), median of five alternating runs: 0.254 ms, P99 0.568 ms (Beta 1.40: 0.206 ms, P99 0.484 ms). Not yet checked in the game: the targets above come from decision-rule tests and must be confirmed with real session logs (see docs/VALIDATION.md), and the pit exit hold has not run in the game yet.

## Beta 1.40 — 3 November 2026

AC's own displays that the overlay takes over are now hidden while the app is active (your request: *every basic Assetto Corsa function we take over must no longer be shown*).

- **AC's top message banner** (*CUT DETECTED: LAP WILL NOT COUNT*, assists…) stayed on screen although the overlay already showed it: `ac.blockSystemMessages` does not hide it. The app now ticks CSP's own option **Hide system messages** (`Documents/Assetto Corsa/cfg/extension/gui.ini`, section `[HIDE]`) while the overlay takes over the messages.
- **AC's own flags** (top left corner): the app ticks CSP's **Hide race flags** while it is active. This also allows red on the track light panels.
- **Your settings are kept:**
  - an option you already ticked is never touched;
  - before the first write, the app saves the original file and values in its own state file (`cfg/extension/state/ACAdvancedIA-cspgui.ini`, never read by CSP), so a crash loses nothing;
  - the values come back when the app, **PANIC** or the switch stops hiding: the original file byte for byte when nothing else changed it, otherwise only the two keys;
  - a value you change yourself while the app holds it is left as it is;
  - no `.bak` is left behind, and there are at most 8 writes of `gui.ini` per game session (no write loop).
- **When it takes effect:**
  - if CSP re-reads `gui.ini` during the session, at once;
  - otherwise at the next game launch. The window says so, and the options are then kept until that launch, because restoring them on exit would mean they never apply.
  - Until CSP has applied **Hide race flags**, the app still counts AC's flags as shown: no red (AC's black flag) on the panels. **TO CHECK** says *effective at the next game launch*.
- **The test message also checks CSP's option:**
  - once it applies, a test message must still reach the overlay;
  - if it does not, the option is restored, the choice is kept, and the window says so;
  - ticking the switch again retries.
- **Overlay › Assetto Corsa displays:** two new switches, both on by default.
  - **Hide AC system messages (CSP option)**;
  - **Hide AC's own flags (CSP option)**;
  - a status line under them: waiting for CSP, next launch, applied, cannot be changed, or messages lost.
- **Other AC HUD elements stay as they are:** fuel, starting lights, damage, leaderboard, proximity, mirror, wrong way and ping. The overlay does not fully replace them:
  - fuel is shown only once its consumption is known;
  - the start lights only for the app's own standing restart.
  - Only the session box was already hidden.

**Verification**: 453 checks; 122 integration cases; 1,159 mutations, all detected; clean lint, parameter audit; golden scenes identical to Beta 1.39; 8-hour soak with 0 errors (memory between 7.6 and 8.8 MB, peak frame 1.17 ms); engine bench with 30 AI, median of five alternating runs: 0.210 ms (Beta 1.39: 0.223 ms). Not yet checked in the game: whether CSP's *Hide system messages* removes the *CUT DETECTED* banner, and whether CSP applies it live or at the next launch (see docs/VALIDATION.md).

## Older versions

Beta 1.39 and older, the 1.x.y versions and the release candidates are in the changelog archive,
[docs/HISTORY.md](https://github.com/VincentChevalier44/AdvancedIA/blob/main/docs/HISTORY.md) (in the repository, not
shipped with the app).
