# Changelog

Newest first. Each entry says what changed, why, and how it was verified.

## Beta 1.59.1 — 11 November 2026

Fixes after bedstyboi's report (practice at Donington: a yellow flag that never left the last sector, a penalty for
passing crashed cars, a black flag in free practice).

- **Cleared off track, really.** The 1.59 rule « a car stopped off track, far from the racing line, is cleared after
  15 s » only worked during a race start: the distance to the racing line was not read at any other time. It is now read
  for every slow or stopped car off the track, in every session. Before, such a car kept its yellow flag until it was
  towed (30 s or more) or for up to 2 minutes.
- **Car wedged on the track.** A car in an incident on the track that keeps twitching without leaving a 15 m circle
  (against a wall, behind a barrier) was never « stopped » long enough to be towed, and kept a double yellow for ever. It
  is now towed to its pit box after 45 s (`IA immobile depannee a son stand (bloquee, …)`).
- **Passing a crashed car under yellow.** A car that has just crashed or just ended its incident can be passed for 30 s
  (10 s before, the yellow hold): it often rejoins slowly while another car's zone is still active. Same rule for the AI.
- **Red flag, « track really blocked ».** The decision of Beta 1.47 placed every stopped car on the racing line except
  during a race start, for the same reason (lateral position not read). The lateral position of every slow or stopped
  car is now read along the track direction (not the car's heading, wrong for a car sideways), in every session: cars
  across the whole width give the red flag, cars parked on one side with room to pass do not.
- **Throttle-cut penalty, explained.** The overlay's explanation line now reads « AC penalty: lift fully off the throttle
  for N s; it then clears by itself » (the penalty is AC's own; the app only requests it and shows AC's countdown).
- **No black flag outside the race.** In practice and qualifying, offences under flags beyond the allowed number keep
  giving the throttle cut; AC's black flag (disqualification) is for the race only. The « next offence disqualifies »
  warning follows the same rule.

Verified by `tests/review159n.lua` (6 checks) and 14 mutations. Journals of the reference scenes unchanged.

## Beta 1.59 — 10 November 2026

A review of Beta 1.58 after the driver's races of 10 November, the fixes asked for in the audit, and an « overlay off »
switch. The new features of this version (each off by default) are described in their own sections.

### Yellow flags and incidents (the driver's 10-lap race: 28 incidents, 13 yellow notices)
- **Spin.** A spin now needs a real loss of speed (25 km/h since the slide began) or a car slower than the obstacle
  speed. A long slide on a kerb or the grass at pace no longer raises a yellow flag.
- **Sliding car as an obstacle.** It must have slid for 0.6 s (`K.spinTime`). A one-frame slip no longer makes the car
  behind swerve.
- **Double yellow.** A car on the track that is stopped, driving the wrong way, or slower than the obstacle speed (never
  counted below 40 km/h). A car still rolling at pace is a single yellow, with the same first-lap fallback speed.
- **Cleared off track.** A car stopped fully off track (four wheels out or beyond the edge), more than 8 m from the
  racing line, is cleared after 15 s (`incident ecarte: arretee hors piste, loin de la trajectoire depuis 15 s`). It stays
  cleared until it moves or has been back on track for 2 s.
- **One notice per group.** A second incident within the zone length of one already announced gives the player no new
  notice or message. Zones, speeds, delta and light panels are unchanged.
- **Difficult spot.** Incidents of three different cars within 100 m in five minutes mark the spot (`point difficile:
  … m`). The AI then drive there with 15% more caution and start no overtake within 100 m. The spot is forgotten after
  10 minutes in a race (30 elsewhere). The start, restarts and the careful first lap never arm one, and at most a quarter
  of the lap is covered.

### First lap
- The caution cap of the careful lap also applies under a yellow flag.
- An AI already slower than 60% of its learnt pace is no longer slowed further.
- The braking-zone caution is ×1.25 (×1.4 before).
- In a corner, in the pack, the radar lift is graded by the time to contact, as on a straight. A real obstacle (closing
  at 60 km/h or more) still gets the full lift.

### Race and AI
- **Last laps.** At most 20% of the race (estimated laps in a timed race), and at least one lap.
- **Mistakes.** At least 60 s between two mistakes in the field (20 s before).
- **Failures.** At least 5 minutes between two failures in the field.
- **General section unticked.** No AI distribution and no staggered pit exits by the app at the session start.
- **Undercut on the mandatory stop.**
  - Since 1.47, an AI whose only remaining stop was the mandatory one requested the undercut and withdrew it in the same frame (« arret retire (plus necessaire) »), so it never happened.
  - Undercut, cover and overcut now really move the mandatory stop, inside the window, within the shared pit-call limit.
  - It also works against the player: an AI that owes its mandatory stop can now really cover or overcut your stop.
  - A car towed to its box no longer counts as a rival's stop.
  - A marked request is only made early enough in the window (the same margin as the pit-stop placement).

### Track-day traffic (decision 19: the driver's 1.58 track days, 139 yields with 5 passes, 393 and 685 refusals)
Track day, Practice and Qualifying only; the race is unchanged.
- **A yielding AI really lifts:** top speed 15 km/h under the follower's on straights (40 m range), lowered gently at 6 km/h/s from the highest follower speed seen (no spiral when the follower brakes), released gently at 8 km/h/s; no cap with two cars or more queued behind it for 3 s, nor for a car already slow.
- **The follower commits** on a car yielding to it: no *target faster*, *no progress*, *no closing* or *attempt too long* abort; safety aborts unchanged.
- **Yield refusal only for a clearly slower follower** (more than 3 km/h of usual pace lower; the 1.55 rule refused anyone not 3 % faster).
- **Slow car with an unknown usual pace:** an obstacle under 50% of its class pace (before: diagnostic only); the whole queue behind it (up to six cars) may go round or pass it; AC's light gap braking (under 30%) no longer blocks it on straights.
- **Front radar:** no braking for a car moving aside that will be clear at contact (the player making room); real overlaps unchanged.
- **Corner-entry priority (decision 19i, every profile):** side by side at a corner, the car whose nose is more than 2.2 m behind gives way (leaves its pass or defence, gentle lift-off without a car close behind, no move towards the other car), decided in the first second of the corner; journal line and minute counter.
- **Player moving aside:** AC's own light gap braking (under 30%) no longer blocks the pass when the player is 2 m or more off the AI's line within 40 m on a straight (no invitation was ever logged: the pass guard stopped before it).
- New minute-summary part: slow-car passes, queue passes, yield caps lifted for a queue.
- **Queue behind a car that made room (first 1.59 track day: 42 *fast follower* aborts out of 113 attempts):** outside the race, an attempt on a car yielding to it, on the player moved aside or on a slow car or its queue is no longer given up because a faster car arrives behind (it follows through the same gap); a car of the queue already past in the passing lane no longer closes it; against the player moved aside and slower than the AI's usual pace here, no *target faster* abort either.
- **Review of this section:** the radar exemption needs a straight, a car that is not turning nor in an incident and a lateral speed of 0.5 m/s held 0.15 s; corner priority only opens in a corner or under real braking, one line per corner; the yield cap reference lasts the whole yield; Nordschleife recognised from 15 km.
- **Yields and passes that work together (second 1.59 track day: 70 yields, 2 completed, 19 passes given up to yield):** outside the race, an AI in the middle of a pass no longer starts an ordinary yield to a faster follower or to another AI's headlight flash (the follower goes through behind it; the player's flash, blue flag, class and flying lap rules are unchanged); a yield granted to an AI is now attacked by that AI unless it is clearly slower here, even at a similar pace; corner priority needs a car really alongside (not the car straight ahead in the line) and only ends the pass when that car is its target.

### Track day built-in preset (decision 20)
- New built-in **Track day** preset for every track but the Nordschleife: as Nordschleife Touristenfahrten, but free yield and overtaking sides and fewer headlight flashes.
- The session preset of a track day is now chosen by track: Nordschleife Touristenfahrten when the name contains *nordschleife*, or *nurburgring* / *nuerburgring* over 15 km (fn_nurburgring was missed before); Track day elsewhere (fn_imola got the Nordschleife preset before). A personal preset or Multi-class endurance is kept.

### Pit lane (review of the 1.58 fix)
- A pass through the lane counts as served only once the car has really stopped in its box.
- A box touched while still rolling counts as the same arrival: the service is still allowed, and the stop is never
  counted twice.
- AC's pit-request field is read on its own, tried once per launch. On a CSP without it, the car reads no longer fall
  back to the missing-field path.

### Player pit reminder
- When the window opens, the overlay says so for 15 s.
- After that, the reminder shows at most once per lap, for 10 s, just before the pit entry once it is known (otherwise in
  the last third of the lap). It is never permanent.
- **SpotterEnginer pit plan.** Read only, contract v1, `ac.store` key `SpotterEnginer.pitplan`, read every second
  while SpotterEnginer is installed.
  - A fresh plan is followed: the stamp must have moved in the last 6 s of engine time. Nothing is shown before the
    planned lap, and the reminder comes on that lap.
  - *Box now* is never shown while the pits are closed. Near the end of the window, our own reminders come back.
  - In every other case, the app's own reminders apply: a stale, absent or unreadable plan, *none*, a plan lap outside
    our window, or *done* while the stop is still owed.

### Overlay off (decision 15) and the overlay steps given on Overtake (decision 16)
- **App overlay (off: AC's own displays)**, in SETTINGS › ADVANCED › Overlay › CONTENT, on by default. When it is off:
  - the app draws no overlay at all, in any state;
  - AC's session box is shown again;
  - the two CSP hide options are given back to the user's values.
  - The FLAGS window stays empty too, and AC's messages are no longer blocked.
  - While CSP still hides AC's flags or messages (not re-read yet, write limit, read-only file), only the game's flags,
    penalties and messages are drawn, so nothing is lost.
  - Driving, rules, penalties and the bridge are unchanged.
- **App flag panel while driving** off: the band now shows only the game's own flags and penalties, as its tooltip and
  the README always said. The lap line, DRS and update notices no longer appear there.
- Each step is now checked by a test: flag panel in every profile, session info, end-of-race summary, AC messages, the
  two CSP options, overlay off.
- The overlay path in the flag-panel tooltip is now SETTINGS › ADVANCED › Overlay.

### Restarting the same race (decision 17, found by the SpotterEnginer session)
- **Symptom.** When AC restarted the same race (same session index), the previous race's result stayed. A second,
  empty `fin de course` line was written, and the bridge kept publishing `finished=true` with the old places.
- **Fix.** The overlay's race state (summary, starting place, finish) now starts again when the session's start drops
  back. The log says `course relancee: recapitulatif et place de depart remis a zero`.
- **Bridge.** Its values are now correct after a restart. The layout is unchanged.

### Detailed log
- DEBUG lines of the pure modules (the 1.58 `arrivee a l emplacement` line) are written only with the detailed log on,
  like every other DEBUG line.

### Interface and texts
- **HOME.** A one-click rule-set selector, the same choice as the RACING RULES tab. It is locked while a race is
  running and logged as `regles de course: … (changement)`.
- **SpotterEnginer 1.1.0 and 1.1.1.** These versions cannot update themselves, so HOME says to update them by hand.
- **Sanctions.** The 1.56 settings are under their own headings: *Repeat offences* and *Player*.
- **Light panels.** The frozen yellow switch is no longer shown; yellow is always on.
- **Tooltips.** Corrected for the fallback speed, the start caution, the last laps, the careful lap and the General
  section.

### Settings-effectiveness gate (new)
- `tests/effectiveness.py` checks every profile setting in two ways:
  - **Static:** it has a runtime reader outside the settings window.
  - **Dynamic:** the same scene, run with the setting at both ends, changes the engine's commands or log; or a targeted
    test names the setting.
- A setting that passes neither check fails the gate.
- Six settings that the generic scene cannot show now have a targeted test: zone end after the incident, VSC and
  red-flag delta, the two Overtake Mode settings, and the weather message.

### New features (each off by default)
- **Real AI runs in practice and qualifying** (switch **Practice and qualifying: real AI runs**, Yielding section, off by default).
  - Qualifying: out-lap, one flying lap (rarely a second one), in-lap, a wait in the box, then again, on the softest dry compound with little fuel. A run that no longer fits before the flag is not started.
  - Practice: a programme drawn per AI and per run (qualifying simulation, long run, tyre test, fuel test, setup test); every run ends in the pits and never goes past the end of the session.
- **Detailed log:** a line when an AI enters the pits in a race without an app request.
- **Varied starting strategies** (Race, off by default, AI strategy section).
  - Part of the AI start on a softer or harder dry compound, one step at most. The back of the grid leans harder and the front softer.
  - Their stops follow their wear.
  - Cars with compounds that cannot be ranked by name are left alone.
- **Pit stop for damage** (Race, Practice and Qualifying, off by default, Accidents section).
  - Damage is now read while driving.
  - A damaged AI pits for repairs when its bodywork, suspension or engine damage passes a threshold (gearbox damage cannot be repaired: log only).
  - Never under a flag or neutralisation (unless the car is unsafe) or in the last two laps, and within the shared pit-call limit.
- With both switches off (the default), behaviour and journals are unchanged.
- **Preset export and import** (HOME, under your custom presets).
  - EXPORT writes your custom presets and the settings of the five profiles to `Documents\Assetto Corsa\AdvancedIA\AdvancedIA-presets.ini`, to keep or share. If CSP refuses that folder, it falls back to the app folder in CSP and says so.
  - IMPORT reads the file back after a confirmation. Every value is validated; unknown keys are ignored, out-of-range values take the default, and a damaged file is refused as a whole.
  - The seed, the detailed log and the settings outside presets are never written or imported.
  - No new setting. Nothing changes unless you use the buttons (journals identical).

### Companion bridge
- Bridge: spin/wrong/halt/onTrack values corrected (layout unchanged). `spin`, `wrong` and `halt` were always false because the app keeps them as durations; they now follow the incident decision (the 1.59 spin with its speed loss, the wrong-way and stop times). `onTrack` now says whether each car is on the track at that moment, for every car, the player included. Found by the SpotterEnginer session.

### Review of the merged features
An independent review of the merged features (before the final chain) led to these fixes:
- Real AI runs: a called car keeps its place until it reaches the pit lane (before, the three places were handed out again every frame); run fuel uses the consumption learnt in the session with a lap and a half of reserve; no dry compound on a wet track; nothing planned during a penalty pass; no box wait under a red flag; compounds ranked like the starting strategies (Pirelli C1–C6 included).
- Pit stop for damage: calls already under way count towards the shared limit; the gearbox no longer calls an AI in nor makes it « unsafe » (it cannot be repaired); an AI in its box for another reason with damage is repaired too; state reset when the same race restarts.
- Settings: two nested blocks closed the list of new keys too early, so recent rules and sanctions keys were treated as old ones by the built-in preset match; fixed.
- Restarts and clock rebases now also cover the real runs and the damage calls; the duplicate « practice and qualifying only » note is gone; the preset file accepts a leading UTF-8 byte-order mark, and a file over the size limit is refused before it is read.

### Verification
- lint, test_pdr, integration and the effectiveness gate pass.
- New unit tests are in `tests/review159.lua`, with integration cases for decisions 16 and 17 and mutation anchors.
- The long chain (mutations, golden, race142, soak, bench, package) runs once on the merged tree.

## Beta 1.58 — 10 November 2026

First public update since Beta 1.52. It fixes the AI that went crazy in the pit lane after the race and a mandatory
stop that could be serviced in a loop, and it brings everything from Beta 1.53 to Beta 1.57.

### Fix: AI handed back to AC in the pit lane
Reported by a player on Overtake and seen by the driver too: after the chequered flag, AI returning to the pits crashed
into the pit wall and into each other instead of driving to their spots.

- **Cause.** The app never writes to a car in the pit lane (`src/applier.lua`, the per-car loop: `driven` requires
  `not car.pit`). When a car it was driving entered the lane, its last values stayed: lateral offset, speed cap,
  level, aggression, caution, grip. The restore path also skipped cars in the pits, so a finished car kept them while it
  drove to its box. The same happened during a race pit stop when the tyres are managed by the app.
- **Fix.** In the pit lane, a car the app was driving is handed back to AC: the offset returns to zero over a short ramp
  (`K.laneReleaseRate`, 1 per second, at most one second), then the speed cap is lifted and the original level,
  aggression, caution and grip are given back. Cars held on purpose (parked, held at their box, Safety Car) are not
  touched, and a pit stop requested by the app stays requested. The car is driven again normally when it leaves the
  lane.
- **Log.** `voiture rendue a AC apres l arrivee: <name>` or `voiture rendue a AC dans la voie des stands: <name>`, once
  per car and session, only when an offset or a speed cap was left. English patterns added.

### Fix: a requested stop serviced in a loop
Seen in the driver's race at Imola (10 laps, F1 rules, mandatory stop with a compound change): one AI sat in its box for
the last three minutes, fitted with new tyres eight times (SS, S, SS, S…), and its mandatory stop never counted.

- **Cause.** Its stop was requested, then it went off and stopped; AC or CSP moved it to its box. An arrival at the box
  right after a move does not count as a stop (a recovery is not a stop), so the request stayed. The app never cancels
  AC's pit request inside the pit lane, so AC kept bringing the car back to its box without it ever leaving the lane,
  and every new arrival was serviced again (`src/pits.lua`, the box arrival; `src/applier.lua`, the pit request). Each
  service picked "another dry compound than the one fitted", so the tyres alternated.
- **Fix.**
  - An AI whose stop is requested and that reaches its box after a move by AC or CSP is serviced there and that stop
    counts. A recovery by the app still never counts as the stop.
  - **One service per pass through the pit lane**: back in its box without having left the lane, a car gets no new
    tyres or repairs and no stop is counted (`emplacement de nouveau sans sortie de la voie des stands`, once per car).
  - Once the car has been serviced and has left its box, and the app no longer wants a stop, AC's pit request is lifted
    inside the lane too; a stop that did not count is requested again once the car is back on track.
  - F1 rule: until the car has raced on two different dry compounds, the app fits one it has not raced on yet (never
    back to the starting compound after a recovery); after that, as before, another than the one fitted.
  - Safety net for the mandatory stop only: serviced twice during its request without counting, the request is dropped
    for the session, with one warning (`arret demande abandonne`); a GT red-flag parking without work does not count.
  - Detailed log: one line per arrival at the box with AC's pit request (`isRequestingPitStop`), to check the cause in game.

### Everything since Beta 1.52
- **AI levels above 100 %** (1.53): in Automatic mode the native level is written up to 110 %; the probe result and the
  applied level are shown in the log and in DIAGNOSTICS.
- **DIAGNOSTICS in English** (1.53) when the interface is in English; the log file stays in French.
- **Overtaking and yielding** (1.54, 1.55): no more endless attempts on a car that is just as fast; outside the race,
  attempts without progress stop after 8 s (15 s at most); an AI only yields to a car that is really faster; fewer AI
  headlight flashes.
- **Rain tyres in the dry** (1.55): CSP's rain-tyre flag is set back to dry when it comes back on a dry track; the tyre
  list of each car model is logged.
- **Flying-lap warning** (1.55): « let it pass » only for a car that is really catching you.
- **Your own track limits** (1.56, off by default): warnings, then a time penalty or AC's throttle cut; escalating
  penalties and a CSV race report, also off by default. The section is now called « Sanctions ».
- **Older CSP versions and « online » by mistake** (1.57): an older CSP (for example preview212) no longer makes the app
  believe it is online; the suspension says why (online session, CSP alt-online mode, game state unreadable).

### How to report a problem
Please send three things: your log (`Documents\Assetto Corsa\logs\AdvancedIA.log`; the `.1`, `.2` and `.3` files are
the previous sessions), your CSP version (Content Manager, Custom Shaders Patch settings, or the DIAGNOSTICS tab), and
the session type (track day, practice, qualifying, race, hotlap), with the track and the car if you can.

### Verification
- lint 49 files, 0 errors; test_pdr 742 checks, 0 failures (11 new in `tests/review158.lua`); integration 152 cases, all
  pass (4 new: finished car handed back in the lane, app pit request kept in the lane, a requested stop after a move to
  the box served once while the car stays in the lane, a recovery then the mandatory stop); mutations 1,794 / 1,794
  detected (31 new); English journal coverage 59,708 lines, 0 problems (the driver's 10 November race log included);
  parameter audit 230 + 50.
- Journals against Beta 1.57: golden, race142 and the 8-hour soak identical line for line; golden and golden142 result
  files byte-identical. The unit-suite journal adds the new tests' lines and loses one: a player arrival at the box
  again without leaving the pit lane (a test artefact) is no longer counted as a second stop. Integration differs by
  the new cases, the updater fixtures' version numbers, timings and the weather pit case, where AC's pit request is now
  lifted once the car has left its box.
- Three existing tests follow the new rules: the reload case keeps the car on track (in the pit lane it is now handed
  back), the repair revisits leave the pit lane between visits, and the red-flag tow check has no pending request.
- Bench medians 9 / 30 / 60 AI: 0.067 / 0.304 / 0.756 ms (1.57: 0.067 / 0.304 / 0.751); long track 0.350 ms mean, P99
  0.761 ms (1.57: 0.349 / 0.768); 8-hour soak 0 errors, 0.21 ms mean (the same two strict criteria as before stay open);
  companion bridge unchanged. The package is accepted by the Beta 1.57, 1.56 and 1.52 updaters; `bridge_layout.lua`
  identical to SpotterEnginer's.
- To see in game: the AI after the chequered flag drive to their boxes cleanly; a requested stop is served once, even
  after AC moves the car to its box (`docs/VALIDATION.md`).

## Beta 1.57 — 10 November 2026

A player on Overtake (offline, connection off, CSP 0.3.0-preview212) saw *Online session: commands suspended* and the
app did nothing. Two fixes: the suspension is named, and an older CSP is read field by field. With a complete CSP
(preview675) nothing changes in behaviour: the golden, race and soak journals are identical to Beta 1.56.

### Named suspension (texts and log only)
The app used the same "online" status for three different cases. All three still suspend every command as before.

- **Named suspension.** The snapshot keeps `online` as the only flag that suspends, and adds its kind: a real online race
  (`isOnlineRace`), a CSP **alt-online** mode (`isAltOnlineRace`, a fake online race run by a New Modes Lua script,
  reported even offline), or a **failed read** of the game state (the protected read that already fell back to
  "online").
- **Texts (FR/EN).** The header status, the status chip and the HOME banner name each case: *CSP alt-online mode:
  commands suspended* (the banner says to start a normal offline session from Content Manager) and *Cannot read the game
  state: commands suspended* (the banner points to DIAGNOSTICS and the log). The real online texts are unchanged. The
  engine guard stays `online`, so the SpotterEnginer bridge is unchanged.
- **Log.** One line when a suspension starts or its kind changes: `suspension: session en ligne, aucune commande`,
  `suspension: mode alt-online de CSP (script New Modes, …)`, `suspension: lecture de l etat du jeu impossible
  (<error>)`. The error text is one line, without folders, at most 120 characters. A suspension of the same kind that
  comes back is logged again at most every 60 s. English patterns added for the DIAGNOSTICS log.
- **README**: Compatibility (alt-online), the safety guard table and a Troubleshooting entry.

### Older CSP versions read field by field
- The same player runs **CSP 0.3.0-preview212** (our reference is preview675), on a plain offline Track Day, and the app
  stayed "online". `ac.getSim()` and `ac.getCar()` return FFI structures, and reading a field that an older CSP lacks
  raises an error. The whole session read was protected as one block, so a single missing field (for example
  `isAltOnlineRace`) made it fail every frame, and the safety fallback suspended the app for ever. The car reads had the
  same weakness: one missing car field and no car was ever read.
- Now, at the first failure, every known session field (and, at the first failed car, every known car field) is tried
  once under protection. Missing ones are remembered for the whole launch and read as absent through a view of the
  structure, which gives the usual neutral value (online false, replay false, no DRS…). There is no protection per field
  and per frame: with a complete CSP no view is used and the reads are exactly as before.
- Only a missing car count or session index stays a real read error, now named: *Cannot read the game state*, log
  `suspension: lecture de l etat du jeu impossible (champ de CSP essentiel absent: carsCount)`.
- The race read (flag, pit window, leader laps) degrades the same way. The missing fields are logged once per new list
  (`champs de CSP absents (version plus ancienne, lus comme absents): session … | voitures …`, English pattern added) and
  listed under DIAGNOSTICS › CSP capabilities.
- The player's logs (Beta 1.52) showed `session: indice -1, … voitures 0, longueur 0 m` and `garde online, IA 0` for
  8 minutes with `erreurs 0`: the failed reads were counted nowhere visible. The minute summary now ends with
  ` | lectures de l etat du jeu en echec N` (since the launch, written only when N > 0), and DIAGNOSTICS › Rejected
  data includes them. A car that cannot be read is still marked invalid on its own; the other cars stay read.

### No reference to another app's visual style
- The driver's rule: the README, the tooltips (FR/EN), the API notes, the history and the source comments no longer
  compare the window or the overlay with another app. The README section is now *The settings
  window*. Texts only: no setting, behaviour or journal line changes.

### Verification
- lint 49 files, 0 errors; test_pdr 731 checks, 0 failures (7 new in `tests/review157.lua`); integration 148 cases, all
  pass (1 new: alt-online and real online named); mutations 1,763 / 1,763 detected (20 new); English journal coverage
  59,208 lines, 0 problems; parameter audit 230 + 50.
- Journals against Beta 1.56: golden, race142 and the 8-hour soak identical line for line; pdr only adds the new tests'
  lines; integration differs only by the new case, the updater fixtures' version numbers and timings. golden and
  golden142 result files byte-identical.
- Bench medians 9 / 30 / 60 AI: 0.067 / 0.306 / 0.781 ms (1.56: 0.070 / 0.317 / 0.768); long track 0.344 ms mean, P99
  0.686 ms (1.56: 0.341 / 0.702); 8-hour soak 0 errors, 0.20 ms mean (the same two strict criteria as before stay open).
- Package accepted by the Beta 1.56 and 1.55 updaters; `bridge_layout.lua` identical to SpotterEnginer's.
- Still to see in game: an older CSP (the player's preview212) listing its missing fields and driving the AI.

## Beta 1.56 — 9 November 2026

The driver approved three options after comparing AdvancedIA with Mavil Track Limit Manager. All three are **off by
default**: with the defaults the app behaves exactly as Beta 1.55.

### Your track limits handled by the app (optional)
- New switch **Your track limits handled by the app** in the **Sanctions** section (Practice, Qualifying, Race). It is
  meant for players who switch AC's own penalties off in Content Manager because a single off is enough for AC to
  penalise them.
- Same rules as the AI: at least three wheels off for 0.3 s at 40 km/h or more, no spin or contact just before, not under
  your yellow flag, a red flag or a neutralisation, nothing in the first seconds of a race or in the pits. The rule that
  ignores a place where the AI line itself leaves the limits does not apply to you, and your offs never feed it.
- Practice and Qualifying (**Your offs in practice and qualifying**): lap invalidated in the app (default), or a warning
  only. AC's lap times and grid never change.
- Race: the shared **Warnings before a penalty**, then **Your track-limits penalty (race)**: a time penalty in the app's
  corrected classification (default), or AC's native throttle cut. The throttle cut goes through the same channel as
  the flag penalties, never counts towards the black flag, and is never written over a decision taken less than 1 s
  earlier; if it is not written within 2 s (or CSP lacks it), a time penalty is given instead and the throttle cut is
  never written afterwards. Track-limit penalties never lead to a black flag.
- The app never drives your car. Notices go to the overlay's session line (also with AI notices off); the race recap
  adds *Track limits: N warning(s), +N s*.
- AC's penalties still on (read once per session) while the option is on: one WARN line
  (`limites de piste joueur: penalites d AC actives (roues dehors autorisees N), …`), a HOME warning that links to the
  section, and one overlay notice; AC's own cut banner seen: `limites de piste joueur: AC sanctionne encore les coupes`.
  The app's rule keeps running (the driver's choice). The app never changes AC's settings.

### Escalating penalties for repeat offences (optional)
- **Escalating penalties for repeat offences**, **Increase per repeat (s)** (5) and **Maximum penalty per off (s)** (30):
  each further track-limits time penalty of the same car, AI or you, adds the increase (5, 10, 15 s…), never above the
  maximum nor below **Time penalty (s)**. Track limits only; never a black flag. The journal line ends with
  `, recidive N`.
- Consistency fix that also applies with the option off (no visible change then): a place later found to be the AI
  line's own off gives back exactly the seconds that were added.

### Race report (optional)
- **Race report (CSV file)**: `Documents/Assetto Corsa/logs/AdvancedIA-race.csv`, written once per race when every car
  still racing has finished or 90 s after you finish; a partial report (`complete=0`) on a session change or when the
  app unloads during a started race. Five kept, rotated like the session log, at most 256 KB. RFC 4180, comma-separated:
  positions (corrected and AC), driver, car, class, laps, warnings, penalties by type, served, unserved time added,
  places given back, time added, black flag.

### Section name
- « Sanctions des IA » / "AI sanctions" is now « Sanctions » / "Sanctions" (label only; setting ids and stored settings
  are unchanged).

**Verification**: 724 checks, 0 failures (`tests/test_pdr.py`, 9 new tests in `tests/review156.lua`; the 1.42 schema test allows the
practice-only setting, the 1.42 practice track-limits test also checks the player's new wording); 147 integration cases
(five new: defaults, race time penalty, AC throttle cut and its fallback, AC penalties on, race report; the settings case
covers the seven new settings); 1,743 mutations, all detected (19 new); clean lint (49 files); parameter audit (230
profile parameters, 50 global options). Journal coverage: every new line has its English pattern; the 59,203 distinct
lines of the suites, the soak and the author's in-game logs of 9 November all translate. **With the defaults, French
journals identical to Beta 1.55**: golden (2,150 distinct lines, 2,255 lines) and full race (182 / 193) identical, golden
result files byte-identical, 8-hour soak identical (54,030 distinct lines, 75,078 lines); unit suite: no line removed,
only the lines of the new tests added; integration: the new cases, the updater fixtures' version numbers and timings.
With the three options switched on in the race defaults: golden race scenarios, full race and 8-hour soak without error
(soak memory 7.5–8.4 MB, as with the defaults). Benchmark medians against Beta 1.55 (9/30/60 AI): 0.068 / 0.300 /
0.732 ms (0.065 / 0.301 / 0.745); long track 0.355 ms mean, P99 0.763 ms (0.341 / 0.742); companion bridge 0.007 /
0.011 / 0.019 ms; soak 0.21 ms mean, memory 7.4–8.3 MB (the same two strict criteria as before stay open). Package
accepted by the Beta 1.55 and Beta 1.54 updaters.

## Beta 1.55 — 9 November 2026

The driver chose three fixes from the audit of the 9 November session logs (Nordschleife track day, Imola practice),
then reported AI on rain tyres in the dry and flying-lap warnings for cars that never came.

### Futile overtake attempts (outside the race)
- On the Nordschleife, attempts lasted 9 s on average and up to 62 s, and 27 of 43 ended « target faster »: the AI sat
  off its line behind a car exactly as fast, because the « not closing » abort is reset by every small closing moment.
- Outside the race, before the cars are side by side, an attempt that gains less than 3 m on the target in 8 s is
  aborted (`sans progres`), and an attempt is capped at 15 s unless it gained ground in the last 4 s
  (`tentative trop longue`). An attempt that keeps gaining is never cut. Both feed the same per-pair wait as « target
  faster » (45 s, 3 min, 10 min). Never against the player; the race is unchanged.
- The minute summary counts them in `annules` and appends `abandons : sans progres N, tentative trop longue N` when
  there were any.
- Integration case (6 min, a target that matches the attacker's pace when attacked): Beta 1.54 made 3 attempts, the
  longest 166 s; Beta 1.55 makes 1 attempt, cut after 8 s, then waits.

### Yields without a pass
- 36 yields in 10 min, 4 followed by a pass: an ordinary yield was triggered by a closing moment of 6 km/h (often a
  braking zone), so the yielding car kept the follower's pace and nobody passed.
- An ordinary yield to an AI (not a blue flag, a class, a flying lap or a headlight flash) now also requires the
  follower to be really faster at this point (learned free pace); unknown pace still yields. The player is not
  affected. A refusal is logged once per follower and episode: `cession refusee: A ne cede pas a B (pas plus rapide ici)`.
  The yield slowdown is unchanged.
- The minute summary appends how the yields ended besides passes and lost followers:
  `fins de cession : duree max N, jaune N, autres N`, and `cessions refusees (suiveur pas plus rapide) N`.
- Integration case (6 min, a follower of the same learned pace closing in bursts): 10 yields with Beta 1.54, none with
  Beta 1.55.

### Headlight flashes (outside the race)
- 80 AI flashes in 10 min, the same car yielding to the same flasher four times without being passed.
- After two yields to the same AI's flashes that end with no pass, that AI no longer flashes that car for 2 minutes
  (`appels de phares suspendus: A -> B apres 2 cessions sans passage, plus d appel pendant 120 s`). After an attempt
  that ended « fast follower » or « yields to its follower », the AI waits 20 s before flashing that target again
  (before: at once, 8 s after its previous flash). Race flashes (lapping, faster class) are unchanged.
- Integration case (6 min, a flasher held behind a car that yields but is never passed): 35 flashes and 69 yields with
  Beta 1.54, 4 flashes and 8 yields with Beta 1.55.

### AI rain tyres in the dry (Imola practice)
- The minute summary only counted compounds (`secs 23, pluie 0`), while CSP keeps a separate AI rain-tyre flag
  (`isAIUsingRainTyres`, set by `physics.setAIRainTyres`), independent of the compound index. Once the app had asked
  for dry tyres, a later return of that flag to « rain » was never corrected.
- On a dry track with tyres managed, the dry request is given again when the flag is back on (at most every 10 s;
  `pneus pluie de CSP revenus sur piste seche: consigne sec redonnee`, once per car).
- The `pneus IA` part of the minute summary ends with `drapeau pluie de CSP N` (the AI whose flag is on).
- Each AI car model's compounds are logged once per session with the class the app gives them:
  `gommes du modele <model>: <short> (<long>) sec|intermediaire|pluie|non autorise, …`.

### Flying-lap warning to the player (Practice, Qualifying)
- At Imola the player on an out-lap was warned five times in 45 s for cars that never caught them: the warning used
  the instantaneous closing speed and gap/speed, which swing in every braking zone.
- The warning now uses the time gap measured at the same point of the track (the moment the player passed that point
  against the moment the AI passes it) and needs a confirmed catch: at least 0.1 s gained per second over 3 s, or
  0.3 s per second over 1 s, a projected catch within 15 s, confirmed within 6 s of the car coming within 3 s. A car
  in the pit lane or off the track is never announced. The criterion is the one SpotterEnginer 1.1.1 uses. With the
  debug log on, an unconfirmed candidate is noted once: `tour lance non confirme: <name> (ecart, rapprochement)`.
- Integration case (Qualifying, 60 s): a car at the player's pace with ±25 km/h swings was announced twice by Beta 1.54,
  never by Beta 1.55; a car 25 % faster is announced by both.

**Verification**: 715 checks, 0 failures (`tests/test_pdr.py`, 11 new tests in `tests/review155.lua`; the Beta 1.51
flying-lap warning test now drives moving cars, since a warning needs a confirmed catch); 142 integration cases (four new:
futile attempts, yields without a real advantage, flashes toward a car that yields without being passed, the flying-lap
warning); 1,724 mutations, all detected (32 new; four older anchors follow the reworded lines, and the « not closing »
mutation is now caught by a race test, where it is still the only judge); clean lint (49 files); parameter audit
(223 profile parameters, 50 global options). Journal coverage: 6,023 distinct lines of the suites, all covered; the
59,172 distinct lines of the suites, the soak and the author's in-game logs of 9 November (Nordschleife, Imola) all
translate. French journals against Beta 1.54: full race identical; golden: the same counters in all three scenarios,
plus the new ones (track day: one yield refused, one flash suspension, five flash holds), two attempts starting 1 m
earlier and one front-radar line moved by that divergence; every minute summary gains `drapeau pluie de CSP N` and, when
used, the new parts; each session lists the compounds once per car model. 8-hour soak (40 AI): attempts 24,836 against
24,811, 3 « no progress » and 22 « attempt too long » aborts (none before), « target faster » 249 against 239, strict
waits 51 against 25, 205 yields refused, 5 flash suspensions, AI flashes 146 against 134, incidents 6 = 6, 0 errors.
Benchmark medians against Beta 1.54 (9/30/60 AI): 0.068 / 0.314 / 0.785 ms (0.067 / 0.308 / 0.766); long track
0.355 ms mean, P99 0.736 ms (0.361 / 0.773); companion bridge 0.008 / 0.013 / 0.019 ms; soak 0.21 ms mean, memory drift
819 KB over 8 h, 11 KB in the last hour (the same two strict criteria as before stay open). Package accepted by the
Beta 1.54 and Beta 1.53 updaters.

## Beta 1.54 — 9 November 2026

The driver's request after a track day on the Nordschleife (38 AI, 10 min): « many incidents, 14 spins, and AI stuck
behind another AI ».

### Overtake loop on the same target (fixed)
- In the session log, one AI attacked the same car six times in 6 minutes, each attempt ending « target faster », and
  flashed it 33 times. The pair wait after a « target faster » failure (45 s, then 3 min, then 10 min) existed, but a
  quicker learned pace at that point let a closing-only attempt through during the wait, and AI-to-AI flashes ignored the
  wait altogether (the target no longer yields to that car during it).
- From the second « target faster » failure on the same car (`K.passIgnoreStrict`), the wait only lets through an
  abnormally slow (damaged) target or an invitation; the learned-pace exception of Beta 1.47 still applies after the first
  failure. Outside the race an AI never flashes a car it is waiting behind (race flashes for lapping and classes are
  unchanged). A line `depassement suspendu: A -> B apres N echecs (cible plus rapide), plus de tentative pendant T s` is
  logged when the stricter wait starts.
- Integration case reproducing the loop: 8 attempts and 31 flashes in 6 min with Beta 1.53, 3 attempts and 1 flash
  (after the wait) with Beta 1.54.

### Spins: investigation, no retuning
- The 14 spins happened at the same places as in the Beta 1.50 sessions on this track (21 km, 18 km, 17 km), at a rate
  of 1.3 per minute against 1.9 to 2.7 in 1.50. The spinning AI were at levels 0.90 to 1.02 (no higher than the
  others), with no app braking, no injected mistake and no manoeuvre just before. Nothing in the log points at a 1.53
  change; whether the app plays a part at all needs an APP OFF run. Nothing was retuned.
- The spin context line now also gives the app's speed limit, whether a lapse in focus was running and the state the
  AI had just left (`limite …, inattention …, etat precedent …`), so the next session tells whether the spacing cap,
  a lapse or a return from an off-track excursion comes first.

**Verification**: 704 checks, 0 failures (`tests/test_pdr.py`, 4 new tests in `tests/review154.lua`); 138 integration cases
(one new: the overtake loop on the same target, 6 minutes); 1,692 mutations, all detected (9 new); clean lint (49 files);
parameter audit (223 profile parameters, 50 global options). Journal coverage: 5,949 distinct lines of the suites, all
covered; the 58,250 distinct lines of the soak, the suites and the author's in-game logs of 9 November all translate.
French journals against Beta 1.53: full race identical; golden adds one `depassement suspendu` line (race scenario, second
failure on the same pair; same overtake, flash and abort counts); the 8-hour soak diverges after its first strict wait
(25 of them): 24,811 attempts against 24,839, 239 « target faster » failures against 245, flashes unchanged (134);
spin context lines carry the three new fields. Golden fingerprints: the track-day ones identical, the race ones change
from frame 30,000 by the one extra journal line (the fingerprint counts journal lines). Benchmark medians against
Beta 1.53 (5 alternated passes, 30,000 frames): 0.066 / 0.312 / 0.748 ms at 9 / 30 / 60 AI (1.53: 0.066 / 0.311 / 0.784);
long track (60.6 km, 46 AI): 0.335 ms mean, P99 0.753 ms (1.53: 0.341 / 0.735); companion bridge 0.008 / 0.012 /
0.018 ms. 8-hour soak: 0 errors, 0.31 ms mean, memory drift 1,010 KB, 10 KB in the last hour; the strict peak and memory
criteria are still open, as in earlier versions. The package is accepted by the Beta 1.53 and Beta 1.52 updaters.

## Beta 1.53 — 9 November 2026

Two requests from the driver: AI levels above 100% (« I see no AI above 100% »), and the DIAGNOSTICS window entirely in
English when the interface is in English.

### AI levels above 100% (driver's decision)
- CSP's `physics.setAILevel` accepts a level from 0 to 2 (SDK); only the `aiLevel` value it reads back is documented
  from 0 to 1. Until now the **Automatic** mode waited for a 1.05 read-back, and with a read-back capped at 1.00 (and the
  grip bonus off by default) every command stopped at 100%: no AI could go above it.
- **Automatic** now writes the native level up to 110% (`K.nativeLevelMax`) as soon as the command exists. The 1.05
  probe is still made once (original value restored) and becomes information: a read-back below 1 proves a cap
  (`caps.clampProven`); only then, and only if the grip bonus is allowed, does Automatic switch to the grip bonus.
  Writing 1.05 to a CSP that caps the value gives the same result as the old cap.
- **Native if confirmed** keeps its meaning (needs the 1.05 read-back, caps at 100% otherwise); **Grip bonus allowed**
  and **Cap at 100%** are unchanged. A cap seen later on any car no longer cuts Automatic back to 1.00; it is logged once.
- Session log: `niveau au-dessus de 100 %: sonde 1.05 relue … (niveau d origine …) -> natif (jusqu a 110 %) (mode demande
  auto, bonus de grip non autorise)` at the end of the probe, a line at each later mode change, and a WARN line with the
  car, the value written and the value read back when a cap is first seen while driving.
- DIAGNOSTICS: the level mode note says *native (CSP 0–2), read-back: 1.05* or *read-back capped at 1.00*; the **AI CARS
  DRIVEN** table shows *requested>applied* (for example *1.05>1.00*) when the level written to the car differs from the
  one asked for.
- With 95% and an 8% spread (track day defaults), the AI range from about 87% to 103% plus the 2% slow pace variation:
  only some of them go above 100%, by a few points.

### DIAGNOSTICS window in English
- The event log of the DIAGNOSTICS window now shows its lines in the interface language. The session log file
  (`Documents/Assetto Corsa/logs/AdvancedIA.log`) stays in French, byte for byte as before (audits and tests read it).
- New `src/journal_en.lua`: 346 patterns, one per journal line format (driver names, values and CSP or Lua error texts
  copied as they are), 186 known phrases (reasons, states, choices) and the expressions of composite lines (minute
  summary, lists). `src/journal.lua` compiles it on first use; the window translates each new line once per language,
  never per frame, and redraws the lines when the language changes.
- Driver names from Content Manager can contain parentheses (« Name (100%, 100%) »): the patterns take the longest name
  that leaves the rest of the line valid.
- New `tests/journal_coverage.py`: every line written by the PDR, extended, integration, golden and race suites must be
  recognised by a pattern and keep, once in English, no accented letter and no common French word (names and copied
  values masked); ERROR lines and DEBUG state codes are kept as they are.

**Verification**: 700 checks, 0 failures (`tests/test_pdr.py`, 5 new tests in `tests/review153.lua`); 137 integration cases (one new:
auto mode above 100% with a capped read-back, applied level and English log in the DIAGNOSTICS window, French again after
the language change); 1,683 mutations, all detected (11 new); clean lint (49 files); parameter audit (223 profile
parameters, 50 global options). Journal coverage: 5,927 distinct lines of the suites, all covered; the 57,944 distinct
lines of the 8-hour soak, the suites and the author's in-game logs of 9 November all translate with no French left. French
journals against Beta 1.52: golden, full race and soak identical line for line; integration only adds the new level
lines (and the test fixtures' version numbers and timings). Golden fingerprints identical to Beta 1.52. Benchmark medians
against Beta 1.52 (5 alternated passes, 30,000 frames): 0.065 / 0.319 / 0.786 ms at 9 / 30 / 60 AI (1.52: 0.067 / 0.315 /
0.800, within noise); long track (60.6 km, 46 AI): 0.345 ms mean, P99 0.743 ms (1.52: 0.364 / 0.792); companion bridge
0.010 / 0.014 / 0.023 ms. 8-hour soak: 0 errors, 0.29 ms mean, memory drift 917 KB, 13 KB in the last hour; the open
criteria (single-frame peak under 1 ms, total memory variation under 256 KiB) are still open, as in earlier versions. The
package is accepted by the Beta 1.52 and Beta 1.49 updaters.

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

No grey frame around the settings window any more: the window has no CSP background or padding, and the app paints its dark background edge to edge.

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
