# Settings and functions inventory Beta 1.50

This inventory links every declared parameter to its consumers. A static reference shows a connection, not proof of a physical result. The `PARAMETER_BOUNDARY_ENGINE` tests and the two full walks through the interface complete this trace.

| Section | Parameter | Range | Default J / P / Q / C | Consumers |
|---|---|---|---|---|
| general | `levelPct` — Level (%) | 40 to 110 | 95 / 100 / 100 / 100 | src/director.lua:152, src/groups.lua:8, src/lang_en.lua:155, src/mistakes.lua:33, src/tips_en.lua:48 |
| general | `aggressionPct` — Aggression (%) | 0 to 100 | 55 / 45 / 45 / 80 | src/director.lua:153, src/director.lua:1276, src/groups.lua:8, src/lang_en.lua:155, src/tips_en.lua:49 |
| general | `caution` — Caution | 0.5 to 8 | 1.6 / 2.2 / 2.2 / 1.2 | src/applier.lua:10, src/applier.lua:92, src/applier.lua:300, src/applier.lua:306, src/applier.lua:329, src/applier.lua:1085, src/applier.lua:1093, src/applier.lua:1176, src/applier.lua:1196, src/caps.lua:2, src/director.lua:154, src/director.lua:156, src/director.lua:159, src/director.lua:161, src/director.lua:162, src/director.lua:682, src/director.lua:683, src/director.lua:727, src/director.lua:778, src/director.lua:811, src/director.lua:923, src/director.lua:934, src/director.lua:1149, src/director.lua:1150, src/director.lua:1152, src/director.lua:1153, src/director.lua:1173, src/director.lua:1191, src/director.lua:1258, src/director.lua:1276, src/director.lua:1279, src/director.lua:1281, src/director.lua:1328, src/director.lua:1343, src/director.lua:1348, src/director.lua:1351, src/engine.lua:133, src/engine.lua:181, src/engine.lua:592, src/engine.lua:648, src/groups.lua:8, src/lang_en.lua:82, src/lang_en.lua:85, src/lang_en.lua:155, src/lang_en.lua:189, src/lang_en.lua:288, src/lang_en.lua:289, src/lang_en.lua:318, src/tips_en.lua:50, src/tips_en.lua:51, src/tips_en.lua:54, src/tips_en.lua:106, src/tips_en.lua:142, src/tips_en.lua:216, src/tips_en.lua:223, src/tips_en.lua:277, src/tips_en.lua:284, src/tips_en.lua:296 |
| general | `brakeZonePct` — Emulated braking zone (%) | 50 to 150 | 100 / 100 / 100 / 100 | src/director.lua:1281, src/groups.lua:8, src/lang_en.lua:155, src/tips_en.lua:51 |
| general | `paceSpreadPct` — Level spread (%) | 0 to 20 | 8 / 3 / 3 / 2 | src/groups.lua:9, src/lang_en.lua:155, src/persona.lua:13, src/tips_en.lua:52 |
| general | `aggrSpreadPct` — Aggression spread (%) | 0 to 30 | 12 / 8 / 8 / 10 | src/groups.lua:9, src/lang_en.lua:155, src/persona.lua:14, src/tips_en.lua:53 |
| general | `cautSpreadPct` — Caution spread (%) | 0 to 30 | 12 / 8 / 8 / 8 | src/groups.lua:9, src/lang_en.lua:155, src/persona.lua:15, src/tips_en.lua:54 |
| general | `pitExitSpread` — Staggered pit exits, practice and qualifying (s per AI, 0 = free) | 0 to 30 | 0 / 10 / 10 / 0 | src/groups.lua:10, src/lang_en.lua:155, src/lang_en.lua:285, src/lang_en.lua:307, src/tips_en.lua:55, src/traffic.lua:17, src/traffic.lua:52, src/traffic.lua:115 |
| general | `spawnMode` — AI distribution at session start | native, pits, track | track / pits / pits / native | src/flood.lua:107, src/groups.lua:10, src/lang_en.lua:155, src/tips_en.lua:56, src/traffic.lua:26 |
| general | `spawnMinCars` — Spread from (AI) | 2 to 60 | 10 / 10 / 10 / 10 | src/engine.lua:286, src/flood.lua:108, src/groups.lua:10, src/lang_en.lua:155, src/tips_en.lua:59, src/traffic.lua:10, src/traffic.lua:67 |
| general | `spawnPitPct` — AI left in the pits at the start (%) | 0 to 50 | 25 / 25 / 25 / 25 | src/groups.lua:10, src/lang_en.lua:155, src/tips_en.lua:57, src/traffic.lua:72, src/traffic.lua:74 |
| general | `spawnGapVariation` — Start gap variation (%) | 0 to 100 | 100 / 100 / 100 / 100 | src/groups.lua:10, src/lang_en.lua:155, src/tips_en.lua:58, src/traffic.lua:80, src/traffic.lua:83 |
| general | `floodRangeKm` — CSP AI flood range, below the threshold (km) | 1 to 5 | 1 / 1 / 1 / 1 | src/engine.lua:271, src/engine.lua:286, src/engine.lua:287, src/groups.lua:10, src/lang_en.lua:155, src/tips_en.lua:60 |
| yield | `yieldEnabled` — Standard yielding | boolean | true / true / true / false | src/director.lua:381, src/director.lua:822, src/groups.lua:18, src/lang_en.lua:156, src/tips_en.lua:62 |
| yield | `yieldSide` — Yield side | left, right, auto | right / right / right / right | src/director.lua:133, src/director.lua:134, src/director.lua:141, src/director.lua:144, src/director.lua:424, src/director.lua:562, src/director.lua:780, src/groups.lua:18, src/lang_en.lua:156, src/lang_en.lua:286, src/persona.lua:23, src/tips_en.lua:63 |
| yield | `yieldOffset` — Yield offset | 0.2 to 0.95 | 0.65 / 0.8 / 0.8 / 0.6 | src/director.lua:805, src/groups.lua:18, src/lang_en.lua:156, src/tips_en.lua:64 |
| yield | `yieldDetectBehind` — Rear detection (m) | 30 to 400 | 100 / 200 / 200 / 80 | src/director.lua:388, src/groups.lua:18, src/lang_en.lua:156, src/tips_en.lua:65 |
| yield | `yieldBehindMargin` — Follower speed advantage (km/h) | 1 to 30 | 6 / 4 / 4 / 6 | src/director.lua:341, src/director.lua:385, src/director.lua:822, src/groups.lua:18, src/lang_en.lua:156, src/tips_en.lua:66 |
| yield | `yieldHorizon` — Rear horizon (s) | 3 to 30 | 10 / 12 / 12 / 8 | src/director.lua:386, src/groups.lua:18, src/lang_en.lua:156, src/tips_en.lua:67 |
| yield | `confirmTime` — Confirmation (s) | 0.1 to 2 | 0.6 / 0.4 / 0.4 / 0.5 | src/director.lua:405, src/director.lua:1082, src/director.lua:1083, src/groups.lua:18, src/lang_en.lua:156, src/tips_en.lua:68 |
| yield | `yieldHoldMin` — Minimum hold (s) | 0.3 to 5 | 1 / 1 / 1 / 1 | src/director.lua:432, src/director.lua:823, src/director.lua:847, src/flash.lua:78, src/groups.lua:19, src/lang_en.lua:157, src/tips_en.lua:69 |
| yield | `yieldHoldAfterMin` — Hold after the pass, min. (s) | 0.2 to 6 | 0.8 / 0.6 / 0.6 / 0.8 | src/groups.lua:19, src/lang_en.lua:157, src/persona.lua:27, src/persona.lua:38, src/tips_en.lua:70 |
| yield | `yieldHoldAfterMax` — Hold after the pass, max. (s) | 0.2 to 6 | 2.2 / 1.6 / 1.6 / 1.8 | src/groups.lua:19, src/lang_en.lua:157, src/persona.lua:27, src/persona.lua:38, src/tips_en.lua:71 |
| yield | `yieldSlowdownPct` — Slowdown while yielding (%) | 0 to 20 | 6 / 8 / 8 / 6 | src/director.lua:810, src/director.lua:1284, src/groups.lua:20, src/lang_en.lua:157, src/tips_en.lua:72 |
| yield | `inviteSlowdownPct` — Extra slowdown to invite a pass (%) | 0 to 25 | 10 / 10 / 10 / 10 | src/director.lua:815, src/groups.lua:20, src/lang_en.lua:157, src/tips_en.lua:73 |
| yield | `yieldMaxHold` — Maximum yield duration (s) | 8 to 60 | 25 / 25 / 25 / 25 | src/director.lua:857, src/flash.lua:45, src/groups.lua:19, src/lang_en.lua:157, src/tips_en.lua:74 |
| yield | `pressureEnabled` — Reaction to pressure | boolean | true / true / true / false | src/director.lua:392, src/director.lua:401, src/groups.lua:21, src/lang_en.lua:158, src/tips_en.lua:75 |
| yield | `pressureGap` — Pressure distance (m) | 5 to 30 | 15 / 15 / 15 / 15 | src/director.lua:392, src/director.lua:395, src/groups.lua:21, src/lang_en.lua:158, src/tips_en.lua:76 |
| yield | `pressureTime` — Pressure duration (s) | 1 to 15 | 4 / 3 / 3 / 4 | src/director.lua:401, src/groups.lua:21, src/lang_en.lua:158, src/tips_en.lua:77 |
| blue | `blueFlagEnabled` — Blue flags | boolean | false / true / true / true | src/director.lua:331, src/director.lua:1382, src/engine.lua:48, src/groups.lua:22, src/lang_en.lua:159, src/panel.lua:20, src/tips_en.lua:79 |
| blue | `blueFlagRange` — Blue flag range (m) | 50 to 400 | 150 / 200 / 200 / 150 | src/director.lua:363, src/director.lua:1382, src/director.lua:1391, src/engine.lua:48, src/groups.lua:22, src/lang_en.lua:159, src/panel.lua:29, src/tips_en.lua:80 |
| blue | `blueFlagSide` — Side under blue flag | auto, left, right | auto / auto / auto / auto | src/director.lua:134, src/groups.lua:22, src/lang_en.lua:159, src/lang_en.lua:286, src/tips_en.lua:81 |
| flash | `flashMode` — Headlight flashes | never, lapped, always | always / always / always / lapped | src/director.lua:372, src/flash.lua:50, src/flash.lua:59, src/groups.lua:23, src/lang_en.lua:160, src/lang_en.lua:286, src/tips_en.lua:83 |
| flash | `flashRange` — Flash range (m) | 40 to 250 | 200 / 200 / 200 / 150 | src/director.lua:350, src/director.lua:356, src/director.lua:389, src/director.lua:665, src/director.lua:669, src/engine.lua:819, src/engine.lua:820, src/flash.lua:58, src/groups.lua:23, src/lang_en.lua:160, src/tips_en.lua:84 |
| flash | `flashMinAdvantage` — Speed advantage for a flash (km/h) | 3 to 40 | 12 / 8 / 8 / 15 | src/director.lua:1291, src/flash.lua:45, src/groups.lua:23, src/lang_en.lua:160, src/tips_en.lua:85 |
| flash | `flashCloseAdvantage` — Close-range advantage (km/h) | -10 to 15 | -5 / -5 / -5 / 6 | src/flash.lua:44, src/groups.lua:23, src/lang_en.lua:160, src/tips_en.lua:86 |
| flash | `flashRequestTTL` — Request lifetime (s) | 3 to 20 | 8 / 8 / 8 / 8 | src/director.lua:1300, src/flash.lua:73, src/flash.lua:74, src/groups.lua:23, src/lang_en.lua:160, src/tips_en.lua:87 |
| flash | `flashObliviousPct` — First flash missed (%) | 0 to 40 | 10 / 5 / 5 / 10 | src/flash.lua:70, src/groups.lua:24, src/lang_en.lua:160, src/tips_en.lua:88 |
| flash | `flashMaxReactors` — Cars reacting | 1 to 3 | 3 / 3 / 3 / 3 | src/flash.lua:67, src/groups.lua:24, src/lang_en.lua:160, src/tips_en.lua:89 |
| flash | `hornEnabled` — Horn counts as a flash | boolean | false / false / false / false | src/engine.lua:813, src/engine.lua:814, src/groups.lua:24, src/lang_en.lua:160, src/tips_en.lua:90 |
| flash | `aiFlashEnabled` — AI-to-AI headlight flashes | boolean | true / true / true / true | src/director.lua:1287, src/groups.lua:24, src/lang_en.lua:160, src/tips_en.lua:91 |
| overtake | `overtakeEnabled` — Overtaking | boolean | true / true / true / true | src/director.lua:1000, src/director.lua:1011, src/groups.lua:25, src/lang_en.lua:161, src/tips_en.lua:93 |
| overtake | `overtakeSide` — Overtaking side | opposite, auto, left, right | left / left / left / left | src/director.lua:141, src/director.lua:142, src/director.lua:562, src/director.lua:1075, src/groups.lua:25, src/lang_en.lua:161, src/tips_en.lua:94 |
| overtake | `overtakeOffset` — Overtaking offset | 0.2 to 0.95 | 0.7 / 0.65 / 0.65 / 0.6 | src/director.lua:861, src/groups.lua:26, src/lang_en.lua:161, src/tips_en.lua:95 |
| overtake | `overtakeDetectAhead` — Forward detection (m) | 20 to 200 | 60 / 50 / 50 / 50 | src/director.lua:918, src/director.lua:1026, src/director.lua:1032, src/groups.lua:25, src/lang_en.lua:161, src/tips_en.lua:96 |
| overtake | `overtakeAheadMargin` — Speed advantage to overtake (km/h) | 1 to 30 | 8 / 10 / 10 / 3 | src/director.lua:1019, src/groups.lua:25, src/lang_en.lua:161, src/tips_en.lua:97 |
| overtake | `overtakeHorizon` — Forward horizon (s) | 2 to 20 | 6 / 6 / 6 / 6 | src/director.lua:1026, src/groups.lua:25, src/lang_en.lua:161, src/tips_en.lua:98 |
| overtake | `overtakeClearMargin` — Clearance after overtaking (m) | 8 to 40 | 18 / 20 / 20 / 10 | src/director.lua:916, src/director.lua:1074, src/groups.lua:26, src/lang_en.lua:161, src/tips_en.lua:99 |
| overtake | `overtakeRestTime` — Pause after overtaking (s) | 0 to 10 | 2 / 3 / 3 / 1 | src/director.lua:922, src/groups.lua:26, src/lang_en.lua:161, src/tips_en.lua:100 |
| overtake | `overtakeChain` — Chain overtakes | boolean | true / false / false / true | src/director.lua:918, src/groups.lua:26, src/lang_en.lua:162, src/tips_en.lua:101 |
| overtake | `stuckTime` — Held-up confirmation (s) | 0.5 to 10 | 2 / 3 / 3 / 1.2 | src/director.lua:1028, src/director.lua:1291, src/groups.lua:25, src/lang_en.lua:162, src/tips_en.lua:102 |
| overtake | `stuckPaceRatio` — Held-up pace threshold | 0.8 to 0.99 | 0.93 / 0.93 / 0.93 / 0.95 | src/director.lua:328, src/groups.lua:25, src/lang_en.lua:162, src/tips_en.lua:103 |
| overtake | `pullOutGapBase` — Pull-out distance (m) | 4 to 15 | 8 / 8 / 8 / 8 | src/director.lua:913, src/groups.lua:26, src/lang_en.lua:162, src/tips_en.lua:104 |
| overtake | `pullOutGapPerMps` — Pull-out gain (s) | 0 to 0.5 | 0.25 / 0.25 / 0.25 / 0.25 | src/director.lua:913, src/groups.lua:26, src/lang_en.lua:162, src/tips_en.lua:105 |
| overtake | `slipstreamEnabled` — Slipstream | boolean | true / true / true / true | src/director.lua:1145, src/director.lua:1152, src/groups.lua:26, src/lang_en.lua:162, src/tips_en.lua:106 |
| overtake | `defenseEnabled` — Defending | boolean | true / true / true / true | src/director.lua:965, src/groups.lua:27, src/lang_en.lua:162, src/tips_en.lua:107 |
| overtake | `defenseMaxOffset` — Maximum defending offset | 0.1 to 0.5 | 0.35 / 0.35 / 0.35 / 0.35 | src/director.lua:934, src/groups.lua:27, src/lang_en.lua:162, src/tips_en.lua:108 |
| overtake | `defenseCooldown` — Pause between defences (s) | 2 to 30 | 8 / 8 / 8 / 8 | src/director.lua:972, src/groups.lua:27, src/lang_en.lua:162, src/tips_en.lua:109 |
| overtake | `defenseTriggerGap` — Defending distance (m) | 5 to 25 | 12 / 12 / 12 / 12 | src/director.lua:965, src/groups.lua:27, src/lang_en.lua:162, src/tips_en.lua:110 |
| overtake | `towBreakEnabled` — Break the tow on straights | boolean | false / false / false / true | src/director.lua:537, src/director.lua:602, src/groups.lua:28, src/lang_en.lua:154, src/tips_en.lua:6 |
| overtake | `towBreakRange` — Tow to break: distance (m) | 10 to 60 | 30 / 30 / 30 / 30 | src/director.lua:531, src/director.lua:539, src/groups.lua:28, src/lang_en.lua:154, src/tips_en.lua:7 |
| overtake | `towBreakStraight` — Minimum straight (m) | 200 to 1500 | 400 / 400 / 400 / 400 | src/director.lua:530, src/director.lua:555, src/groups.lua:28, src/lang_en.lua:154, src/tips_en.lua:8 |
| overtake | `dirtyAirEnabled` — Dirty air behind a car | boolean | false / true / true / true | src/director.lua:510, src/groups.lua:28, src/lang_en.lua:154, src/tips_en.lua:9 |
| overtake | `dirtyAirGap` — Dirty air: distance (m) | 5 to 40 | 20 / 20 / 20 / 20 | src/director.lua:507, src/director.lua:511, src/director.lua:513, src/groups.lua:28, src/lang_en.lua:154, src/tips_en.lua:10 |
| overtake | `dirtyAirLiftPct` — Dirty air: throttle lift in corners (%) | 0 to 10 | 3 / 3 / 3 / 3 | src/director.lua:1330, src/director.lua:1332, src/groups.lua:28, src/lang_en.lua:154, src/lang_en.lua:285, src/tips_en.lua:11 |
| overtake | `finalLapsEnabled` — Last-laps urgency | boolean | false / false / false / true | src/director.lua:518, src/groups.lua:29, src/lang_en.lua:154, src/tips_en.lua:12 |
| overtake | `finalLaps` — Last laps concerned | 1 to 10 | 3 / 3 / 3 / 3 | src/director.lua:515, src/director.lua:523, src/director.lua:526, src/director.lua:700, src/groups.lua:29, src/lang_en.lua:154, src/tips_en.lua:13 |
| overtake | `finalAggressionPct` — Extra aggression (%) | 0 to 50 | 15 / 15 / 15 / 15 | src/director.lua:697, src/director.lua:700, src/groups.lua:29, src/lang_en.lua:154, src/lang_en.lua:285, src/tips_en.lua:14 |
| overtake | `finalDefensePct` — Stronger defence (%) | 0 to 100 | 40 / 40 / 40 / 40 | src/director.lua:700, src/director.lua:949, src/groups.lua:29, src/lang_en.lua:154, src/lang_en.lua:285, src/tips_en.lua:15 |
| lateral | `rampSpeed` — Lateral movement speed | 0.1 to 1 | 0.3 / 0.3 / 0.3 / 0.45 | src/director.lua:279, src/groups.lua:15, src/lang_en.lua:163, src/tips_en.lua:112 |
| lateral | `rampAccel` — Lateral acceleration | 0.5 to 4 | 1.5 / 1.5 / 1.5 / 2 | src/director.lua:281, src/groups.lua:15, src/lang_en.lua:163, src/tips_en.lua:113 |
| lateral | `lowPassTau` — Lateral smoothing (s) | 0.05 to 1 | 0.25 / 0.25 / 0.25 / 0.2 | src/director.lua:282, src/groups.lua:15, src/lang_en.lua:163, src/tips_en.lua:114 |
| lateral | `maxSideOffset` — Maximum offset | 0.3 to 0.95 | 0.85 / 0.85 / 0.85 / 0.8 | src/director.lua:212, src/director.lua:786, src/director.lua:805, src/director.lua:927, src/director.lua:934, src/groups.lua:16, src/lang_en.lua:163, src/tips_en.lua:115 |
| lateral | `cornerMin` — Straight threshold | 0 to 1 | 0.35 / 0.35 / 0.35 / 0.5 | src/director.lua:347, src/director.lua:422, src/director.lua:444, src/director.lua:511, src/director.lua:835, src/director.lua:931, src/director.lua:1001, src/director.lua:1010, src/director.lua:1102, src/director.lua:1288, src/director.lua:1311, src/director.lua:1327, src/director.lua:1362, src/groups.lua:16, src/lang_en.lua:163, src/tips_en.lua:116, src/traffic.lua:199 |
| lateral | `cornerYawRef` — Yaw rate reference (rad/s) | 0.2 to 1.2 | 0.5 / 0.5 / 0.5 / 0.5 | src/director.lua:598, src/groups.lua:16, src/lang_en.lua:163, src/tips_en.lua:117 |
| lateral | `lateralCooldown` — Pause between direction changes (s) | 0.3 to 5 | 1.2 / 1.2 / 1.2 / 1 | src/director.lua:177, src/director.lua:190, src/director.lua:502, src/groups.lua:16, src/lang_en.lua:163, src/tips_en.lua:118 |
| lateral | `emergencyReleaseFactor` — Release factor | 1 to 4 | 2 / 2 / 2 / 2 | src/director.lua:267, src/groups.lua:16, src/lang_en.lua:163, src/tips_en.lua:119 |
| human | `reactMin` — Minimum reaction (s) | 0.1 to 2 | 0.25 / 0.2 / 0.2 / 0.2 | src/groups.lua:11, src/lang_en.lua:164, src/persona.lua:10, src/tips_en.lua:121 |
| human | `reactMax` — Maximum reaction (s) | 0.1 to 2 | 0.9 / 0.6 / 0.6 / 0.6 | src/groups.lua:11, src/lang_en.lua:164, src/persona.lua:10, src/tips_en.lua:122 |
| human | `awMin` — Minimum awareness delay (s) | 0.2 to 5 | 0.6 / 0.4 / 0.4 / 0.4 | src/groups.lua:11, src/lang_en.lua:164, src/persona.lua:10, src/tips_en.lua:123 |
| human | `awMax` — Maximum awareness delay (s) | 0.2 to 5 | 2 / 1.2 / 1.2 / 1.2 | src/groups.lua:11, src/lang_en.lua:164, src/persona.lua:10, src/tips_en.lua:124 |
| human | `paceDriftPct` — Slow pace drift (%) | 0 to 6 | 2 / 1 / 1 / 1 | src/director.lua:151, src/groups.lua:12, src/lang_en.lua:164, src/tips_en.lua:125 |
| human | `personalLineJitter` — Line variation | 0 to 0.15 | 0.05 / 0.03 / 0.03 / 0.02 | src/director.lua:939, src/director.lua:944, src/groups.lua:12, src/lang_en.lua:164, src/tips_en.lua:126 |
| human | `lapseEnabled` — Brief lapses in focus | boolean | true / false / false / false | src/director.lua:1265, src/groups.lua:13, src/lang_en.lua:164, src/tips_en.lua:127 |
| human | `lapseIntervalMin` — Minimum interval (s) | 20 to 900 | 60 / 120 / 120 / 120 | src/groups.lua:13, src/lang_en.lua:165, src/persona.lua:24, src/persona.lua:45, src/tips_en.lua:128 |
| human | `lapseIntervalMax` — Maximum interval (s) | 20 to 900 | 300 / 600 / 600 / 600 | src/groups.lua:13, src/lang_en.lua:165, src/persona.lua:24, src/persona.lua:45, src/tips_en.lua:129 |
| human | `lapseDurMin` — Minimum duration (s) | 0.5 to 8 | 1.5 / 1 / 1 / 1 | src/groups.lua:13, src/lang_en.lua:165, src/persona.lua:25, src/persona.lua:46, src/tips_en.lua:130 |
| human | `lapseDurMax` — Maximum duration (s) | 0.5 to 8 | 3 / 2 / 2 / 2 | src/groups.lua:13, src/lang_en.lua:165, src/persona.lua:25, src/persona.lua:46, src/tips_en.lua:131 |
| human | `lapseDropMin` — Minimum pace loss (%) | 0 to 25 | 6 / 3 / 3 / 3 | src/groups.lua:13, src/lang_en.lua:165, src/persona.lua:26, src/persona.lua:47, src/tips_en.lua:132 |
| human | `lapseDropMax` — Maximum pace loss (%) | 0 to 25 | 12 / 7 / 7 / 7 | src/groups.lua:13, src/lang_en.lua:165, src/persona.lua:26, src/persona.lua:47, src/tips_en.lua:133 |
| human | `laneBiasEnabled` — Pace-based line | boolean | true / false / false / false | src/groups.lua:12, src/lang_en.lua:165, src/persona.lua:23, src/tips_en.lua:134 |
| human | `laneBiasMax` — Maximum line bias | 0 to 0.4 | 0.25 / 0.25 / 0.25 / 0.25 | src/groups.lua:12, src/lang_en.lua:165, src/persona.lua:23, src/tips_en.lua:135 |
| human | `mistakesEnabled` — AI driving mistakes (lock-ups, wheelspin) | boolean | true / true / true / true | src/groups.lua:14, src/lang_en.lua:166, src/lang_en.lua:307, src/mistakes.lua:54, src/tips_en.lua:136 |
| human | `mistakeRate` — Mistakes: rate (per hour per AI) | 0 to 6 | 1 / 0.5 / 0.5 / 0.5 | src/groups.lua:14, src/lang_en.lua:166, src/lang_en.lua:308, src/mistakes.lua:54, src/mistakes.lua:88, src/tips_en.lua:137 |
| start | `startDelay` — Start delay (s) | 0 to 30 | 0 / 0 / 0 / 2 | src/applier.lua:11, src/applier.lua:268, src/applier.lua:278, src/applier.lua:430, src/applier.lua:431, src/applier.lua:434, src/applier.lua:452, src/applier.lua:741, src/applier.lua:761, src/applier.lua:1065, src/applier.lua:1070, src/caps.lua:2, src/director.lua:687, src/director.lua:712, src/director.lua:730, src/director.lua:1106, src/director.lua:1255, src/director.lua:1256, src/engine.lua:133, src/engine.lua:474, src/engine.lua:478, src/engine.lua:482, src/engine.lua:495, src/groups.lua:17, src/lang_en.lua:167, src/lang_en.lua:288, src/mistakes.lua:57, src/tips_en.lua:139, src/traffic.lua:17, src/traffic.lua:145, src/traffic.lua:163, src/traffic.lua:167 |
| start | `startCautionMult` — Caution at the start | 1 to 3 | 1 / 1 / 1 / 1.3 | src/director.lua:1258, src/engine.lua:48, src/groups.lua:17, src/lang_en.lua:167, src/tips_en.lua:142 |
| start | `startAggrMult` — Aggression at the start | 0.2 to 1 | 1 / 1 / 1 / 0.8 | src/director.lua:1258, src/engine.lua:48, src/groups.lua:17, src/lang_en.lua:167, src/tips_en.lua:143 |
| start | `startRelax` — Settling time after the start (s) | 2 to 30 | 12 / 12 / 12 / 25 | src/director.lua:687, src/director.lua:1106, src/director.lua:1255, src/director.lua:1256, src/engine.lua:482, src/groups.lua:17, src/lang_en.lua:167, src/mistakes.lua:57, src/tips_en.lua:144 |
| start | `startLaneHold` — Hold the grid lane at the start | boolean | false / false / false / false | src/director.lua:1260, src/engine.lua:48, src/engine.lua:482, src/groups.lua:17, src/lang_en.lua:167, src/tips_en.lua:140 |
| start | `firstLapCare` — Careful first lap (start and restarts) | boolean | false / false / false / true | src/firstlap.lua:22, src/groups.lua:17, src/lang_en.lua:167, src/tips_en.lua:141 |
| accidents | `obstacleEnabled` — Avoid stopped or crashed cars | boolean | true / true / true / true | src/director.lua:730, src/groups.lua:31, src/lang_en.lua:168, src/tips_en.lua:146 |
| accidents | `obstacleSpeedKmh` — Obstacle speed (km/h) | 5 to 50 | 25 / 25 / 25 / 25 | src/director.lua:735, src/director.lua:740, src/director.lua:745, src/director.lua:790, src/engine.lua:550, src/groups.lua:31, src/incidents.lua:283, src/incidents.lua:435, src/incidents.lua:445, src/incidents.lua:491, src/lang_en.lua:168, src/lights.lua:57, src/penalties.lua:41, src/tips_en.lua:147 |
| accidents | `obstacleDetect` — Obstacle detection (m) | 50 to 300 | 150 / 150 / 150 / 150 | src/director.lua:739, src/director.lua:740, src/director.lua:761, src/groups.lua:31, src/lang_en.lua:168, src/tips_en.lua:148 |
| accidents | `obstacleLevelDrop` — Level drop near an obstacle (%) | 0 to 50 | 25 / 25 / 25 / 25 | src/director.lua:778, src/groups.lua:31, src/lang_en.lua:168, src/tips_en.lua:149 |
| accidents | `obstacleCautionMult` — Caution near an obstacle | 1 to 3 | 1.5 / 1.5 / 1.5 / 1.5 | src/director.lua:778, src/groups.lua:31, src/lang_en.lua:168, src/tips_en.lua:150 |
| accidents | `avoidOffset` — Avoidance offset | 0.3 to 0.9 | 0.6 / 0.6 / 0.6 / 0.6 | src/director.lua:786, src/groups.lua:32, src/lang_en.lua:168, src/tips_en.lua:151 |
| accidents | `contactRecovery` — Recovery after contact | boolean | true / true / true / true | src/director.lua:718, src/groups.lua:32, src/lang_en.lua:169, src/tips_en.lua:152 |
| accidents | `incidentStop` — Crashed AI stop | boolean | true / true / true / true | src/groups.lua:32, src/incidents.lua:489, src/lang_en.lua:169, src/tips_en.lua:153 |
| accidents | `incidentStopMin` — Minimum stop (s) | 1 to 15 | 3 / 3 / 3 / 3 | src/groups.lua:32, src/incidents.lua:493, src/lang_en.lua:169, src/tips_en.lua:154 |
| accidents | `incidentStopMax` — Maximum stop (s) | 1 to 30 | 8 / 8 / 8 / 8 | src/groups.lua:32, src/incidents.lua:493, src/lang_en.lua:169, src/tips_en.lua:155 |
| accidents | `rejoinGap` — Clear track behind to rejoin (m) | 30 to 300 | 120 / 120 / 120 / 120 | src/groups.lua:32, src/incidents.lua:271, src/lang_en.lua:169, src/tips_en.lua:156 |
| accidents | `yellowEnabled` — Yellow flags (incident zone) | boolean | true / true / true / true | src/groups.lua:33, src/incidents.lua:872, src/incidents.lua:933, src/lang_en.lua:170, src/lights.lua:49, src/tips_en.lua:157 |
| accidents | `yellowBefore` — Zone start before the incident (m) | 50 to 800 | 300 / 300 / 300 / 300 | src/groups.lua:33, src/incidents.lua:862, src/incidents.lua:877, src/incidents.lua:880, src/incidents.lua:938, src/incidents.lua:939, src/incidents.lua:947, src/incidents.lua:948, src/lang_en.lua:170, src/tips_en.lua:161 |
| accidents | `yellowAfter` — Zone end after the incident (m) | 0 to 300 | 50 / 50 / 50 / 50 | src/groups.lua:33, src/incidents.lua:877, src/incidents.lua:938, src/lang_en.lua:170, src/tips_en.lua:162 |
| accidents | `yellowHold` — Hold after clearing (s) | 0 to 60 | 10 / 10 / 10 / 10 | src/groups.lua:33, src/incidents.lua:480, src/lang_en.lua:170, src/penalties.lua:41, src/tips_en.lua:163 |
| accidents | `yellowDecel` — Approach deceleration (m/s²) | 2 to 10 | 5 / 5 / 5 / 5 | src/delta.lua:159, src/delta.lua:191, src/director.lua:653, src/engine.lua:1015, src/groups.lua:33, src/incidents.lua:891, src/incidents.lua:930, src/lang_en.lua:170, src/sanctions.lua:515, src/tips_en.lua:164 |
| accidents | `zoneDeltaPct` — Double yellow: reference time slower by (%) | 5 to 200 | 15 / 15 / 15 / 15 | src/delta.lua:90, src/groups.lua:34, src/lang_en.lua:171, src/lang_en.lua:308, src/tips_en.lua:159 |
| accidents | `slowZoneKmh` — Double yellow: Slow Zone speed (km/h, 0 = delta time) | 0 to 150 | 0 / 0 / 0 / 0 | src/delta.lua:89, src/groups.lua:34, src/lang_en.lua:171, src/lang_en.lua:285, src/lang_en.lua:308, src/tips_en.lua:160 |
| accidents | `yellowSpeedKmh` — Double yellow: fallback speed, unknown pace (km/h) | 30 to 200 | 50 / 50 / 50 / 50 | src/delta.lua:87, src/delta.lua:90, src/groups.lua:34, src/incidents.lua:883, src/incidents.lua:885, src/incidents.lua:929, src/lang_en.lua:171, src/lang_en.lua:309, src/tips_en.lua:158 |
| accidents | `yellowHud` — AC native yellow flag on the HUD | boolean | false / false / false / false | src/groups.lua:35, src/incidents.lua:959, src/lang_en.lua:172, src/tips_en.lua:176 |
| accidents | `flagPanel` — AdvancedIA flag panel while driving | boolean | true / true / true / true | src/cspgui.lua:147, src/groups.lua:35, src/lang_en.lua:172, src/lang_en.lua:309, src/panel.lua:222, src/tips_en.lua:177 |
| accidents | `yellowMessage` — On-screen incident messages | boolean | true / true / true / true | src/engine.lua:773, src/engine.lua:778, src/engine.lua:793, src/groups.lua:35, src/incidents.lua:119, src/incidents.lua:138, src/incidents.lua:142, src/incidents.lua:382, src/incidents.lua:395, src/incidents.lua:396, src/incidents.lua:532, src/incidents.lua:547, src/incidents.lua:555, src/incidents.lua:563, src/incidents.lua:587, src/incidents.lua:597, src/incidents.lua:646, src/incidents.lua:664, src/incidents.lua:670, src/incidents.lua:681, src/incidents.lua:786, src/incidents.lua:948, src/lang_en.lua:172, src/tips_en.lua:178 |
| accidents | `deltaBeeps` — Delta: beeps | boolean | true / true / true / true | src/engine.lua:669, src/groups.lua:35, src/lang_en.lua:172, src/tips_en.lua:174 |
| accidents | `playerPenalties` — Player penalties under flags | boolean | false / true / true / true | src/engine.lua:977, src/groups.lua:36, src/lang_en.lua:173, src/penalties.lua:80, src/penalties.lua:81, src/tips_en.lua:172 |
| accidents | `deltaTolerance` — Delta: mini-sector tolerance (s) | 0 to 1 | 0.5 / 0.5 / 0.5 / 0.5 | src/delta.lua:138, src/groups.lua:36, src/lang_en.lua:173, src/tips_en.lua:173 |
| accidents | `penaltySeconds` — Penalty: throttle cut (s) | 2 to 15 | 5 / 5 / 5 / 5 | src/bridge.lua:139, src/bridge_layout.lua:49, src/engine.lua:795, src/groups.lua:36, src/lang_en.lua:173, src/penalties.lua:83, src/penalties.lua:84, src/penalties.lua:86, src/penalties.lua:90, src/penalties.lua:124, src/penalties.lua:134, src/penalties.lua:159, src/tips_en.lua:175 |
| accidents | `penaltyDisqualify` — Offences allowed before disqualification | 1 to 20 | 5 / 5 / 5 / 5 | src/bridge.lua:143, src/engine.lua:762, src/engine.lua:777, src/engine.lua:781, src/engine.lua:795, src/groups.lua:36, src/lang_en.lua:173, src/penalties.lua:56, src/penalties.lua:158, src/sanctions.lua:145, src/sanctions.lua:148, src/sanctions.lua:153, src/tips_en.lua:170 |
| accidents | `aiPenalties` — AI sanctions under flags | boolean | false / true / true / true | src/groups.lua:36, src/lang_en.lua:173, src/penalties.lua:171, src/tips_en.lua:171 |
| rules | `noMoveBraking` — No change of direction under braking | boolean | true / true / true / true | src/director.lua:710, src/groups.lua:56, src/lang_en.lua:174, src/tips_en.lua:180 |
| rules | `neutralization` — Neutralisation after a major incident | local, fcy, vsc, sc | local / local / local / local | src/engine.lua:66, src/groups.lua:56, src/incidents.lua:388, src/incidents.lua:517, src/incidents.lua:674, src/lang_en.lua:174, src/tips_en.lua:181 |
| rules | `majorIncidentTime` — Major incident: car stopped on track (s) | 5 to 60 | 15 / 15 / 15 / 15 | src/engine.lua:65, src/engine.lua:66, src/groups.lua:56, src/incidents.lua:465, src/incidents.lua:527, src/lang_en.lua:174, src/tips_en.lua:182 |
| rules | `fcySpeedKmh` — FCY: fallback speed, unknown pace (km/h) | 40 to 150 | 80 / 80 / 80 / 80 | src/delta.lua:98, src/delta.lua:101, src/delta.lua:103, src/groups.lua:57, src/incidents.lua:394, src/incidents.lua:678, src/incidents.lua:906, src/lang_en.lua:174, src/lang_en.lua:310, src/tips_en.lua:183 |
| rules | `fcyDeltaPct` — FCY: reference time slower by (%) | 10 to 150 | 50 / 50 / 50 / 50 | src/delta.lua:101, src/delta.lua:103, src/groups.lua:57, src/incidents.lua:396, src/incidents.lua:547, src/incidents.lua:906, src/lang_en.lua:174, src/lang_en.lua:310, src/panel.lua:249, src/tips_en.lua:184 |
| rules | `vscDeltaPct` — VSC: reference time slower by (%) | 10 to 80 | 30 / 30 / 30 / 30 | src/delta.lua:98, src/groups.lua:57, src/incidents.lua:547, src/incidents.lua:906, src/lang_en.lua:174, src/lang_en.lua:311, src/panel.lua:248, src/tips_en.lua:185 |
| rules | `neutralizationHold` — Minimum neutralisation time (s) | 10 to 180 | 30 / 30 / 30 / 30 | src/groups.lua:56, src/incidents.lua:529, src/incidents.lua:557, src/incidents.lua:678, src/lang_en.lua:175, src/tips_en.lua:186 |
| rules | `safetyCarSpeedKmh` — Safety Car speed (km/h) | 60 to 250 | 120 / 120 / 120 / 120 | src/delta.lua:158, src/groups.lua:66, src/incidents.lua:620, src/incidents.lua:851, src/incidents.lua:852, src/incidents.lua:904, src/incidents.lua:907, src/lang_en.lua:175, src/tips_en.lua:187 |
| rules | `safetyCarEscalation` — Safety Car if the incident escalates | boolean | false / true / true / true | src/engine.lua:59, src/groups.lua:66, src/incidents.lua:525, src/incidents.lua:526, src/lang_en.lua:175, src/tips_en.lua:189 |
| rules | `restartOvertake` — Overtaking allowed after the restart | line, scIn | line / line / line / line | src/groups.lua:66, src/incidents.lua:142, src/incidents.lua:577, src/lang_en.lua:176, src/panel.lua:243, src/tips_en.lua:188 |
| rules | `redFlagEnabled` — Red flag on a serious accident (practice, qualifying, race) | boolean | true / true / true / true | src/engine.lua:60, src/groups.lua:58, src/incidents.lua:631, src/lang_en.lua:176, src/lang_en.lua:311, src/tips_en.lua:190 |
| rules | `redFlagCars` — Red flag: cars stopped on track | 2 to 10 | 3 / 3 / 3 / 3 | src/groups.lua:58, src/incidents.lua:628, src/incidents.lua:632, src/incidents.lua:633, src/incidents.lua:636, src/incidents.lua:638, src/lang_en.lua:176, src/lang_en.lua:311, src/tips_en.lua:191 |
| rules | `redFlagSpeedKmh` — Red flag: fallback speed, unknown pace (km/h) | 40 to 150 | 80 / 80 / 80 / 80 | src/delta.lua:95, src/groups.lua:58, src/incidents.lua:643, src/incidents.lua:911, src/lang_en.lua:176, src/lang_en.lua:312, src/tips_en.lua:192 |
| rules | `redDeltaPct` — Red flag: reference time slower by (%) | 10 to 200 | 60 / 60 / 60 / 60 | src/delta.lua:95, src/groups.lua:58, src/incidents.lua:911, src/lang_en.lua:176, src/lang_en.lua:312, src/tips_en.lua:193 |
| rules | `redFlagHold` — Red flag: minimum suspension (s) | 20 to 600 | 60 / 60 / 60 / 60 | src/groups.lua:58, src/incidents.lua:643, src/incidents.lua:659, src/lang_en.lua:176, src/lang_en.lua:312, src/tips_en.lua:194 |
| rules | `redFlagWork` — Red flag: tyres changed in the pits (stop counts) | boolean | false / false / false / false | src/groups.lua:58, src/lang_en.lua:176, src/lang_en.lua:313, src/pits.lua:121, src/pits.lua:181, src/pits.lua:186, src/strategy.lua:421, src/tips_en.lua:196 |
| rules | `redRestart` — Restart after a red flag | rolling, standing | rolling / rolling / rolling / rolling | src/groups.lua:55, src/groups.lua:58, src/incidents.lua:134, src/incidents.lua:539, src/lang_en.lua:176, src/panel.lua:242, src/tips_en.lua:195 |
| rules | `mandatoryStops` — Mandatory stops in the race | 0 to 3 | 0 / 0 / 0 / 0 | src/bridge.lua:154, src/bridge_layout.lua:57, src/engine.lua:853, src/engine.lua:856, src/engine.lua:861, src/engine.lua:863, src/groups.lua:63, src/hudinfo.lua:114, src/hudinfo.lua:115, src/hudinfo.lua:116, src/lang_en.lua:177, src/pits.lua:57, src/pits.lua:67, src/pits.lua:72, src/pits.lua:161, src/pits.lua:163, src/pits.lua:177, src/pits.lua:224, src/pits.lua:225, src/strategy.lua:183, src/strategy.lua:381, src/tips_en.lua:197 |
| rules | `pitWindowOpenPct` — Window opens (% of race) | 5 to 95 | 25 / 25 / 25 / 25 | src/groups.lua:63, src/lang_en.lua:177, src/pits.lua:63, src/tips_en.lua:198 |
| rules | `pitWindowClosePct` — Window closes (% of race) | 5 to 100 | 75 / 75 / 75 / 75 | src/groups.lua:63, src/lang_en.lua:177, src/pits.lua:63, src/tips_en.lua:199 |
| rules | `pitTyres` — New tyres at every stop (pit rules active) | boolean | true / true / true / true | src/groups.lua:64, src/lang_en.lua:177, src/lang_en.lua:316, src/pits.lua:181, src/strategy.lua:421, src/tips_en.lua:200 |
| rules | `pitRepair` — Repairs at every stop in the race (bodywork, suspension, engine) | boolean | true / true / true / true | src/applier.lua:388, src/engine.lua:133, src/engine.lua:962, src/groups.lua:64, src/lang_en.lua:177, src/lang_en.lua:316, src/pits.lua:155, src/pits.lua:186, src/pits.lua:188, src/sanctions.lua:7, src/sanctions.lua:446, src/tips_en.lua:201 |
| rules | `pitCompoundChange` — Change dry compound (F1) | boolean | false / false / false / false | src/engine.lua:861, src/groups.lua:64, src/lang_en.lua:177, src/pits.lua:40, src/pits.lua:66, src/pits.lua:123, src/tips_en.lua:202 |
| rules | `minPitTime` — Minimum stop time (s, 0 = free) | 0 to 120 | 0 / 0 / 0 / 0 | src/bridge.lua:154, src/bridge_layout.lua:58, src/groups.lua:64, src/lang_en.lua:178, src/lang_en.lua:285, src/pits.lua:57, src/pits.lua:180, src/tips_en.lua:203 |
| rules | `maxStintMin` — Maximum stint (min, 0 = free) | 0 to 240 | 0 / 0 / 0 / 0 | src/bridge.lua:154, src/bridge_layout.lua:57, src/groups.lua:64, src/lang_en.lua:178, src/lang_en.lua:285, src/pits.lua:57, src/pits.lua:172, src/pits.lua:230, src/tips_en.lua:205 |
| rules | `pitFuel` — Fuel at enforced stops | refuel, plan, ac | refuel / refuel / refuel / refuel | src/groups.lua:65, src/lang_en.lua:178, src/lang_en.lua:286, src/pits.lua:237, src/tips_en.lua:204 |
| rules | `pitsClosed` — Pit lane closed under neutralisation | open, pitFcy, pitFcySc | open / open / open / open | src/bridge.lua:123, src/bridge_layout.lua:37, src/engine.lua:845, src/engine.lua:947, src/groups.lua:65, src/incidents.lua:20, src/incidents.lua:43, src/incidents.lua:619, src/incidents.lua:622, src/lang_en.lua:178, src/lang_en.lua:286, src/sanctions.lua:586, src/strategy.lua:291, src/strategy.lua:389, src/strategy.lua:408, src/tips_en.lua:206 |
| rules | `pitMessage` — Pit window opening message | boolean | true / true / true / true | src/groups.lua:63, src/lang_en.lua:178, src/lang_en.lua:315, src/pits.lua:69, src/pits.lua:79, src/tips_en.lua:207 |
| rules | `overtakeMode` — Overtake Mode (F1 2026, within one second at detection) | boolean | false / false / false / false | src/director.lua:1307, src/groups.lua:59, src/lang_en.lua:179, src/lang_en.lua:313, src/tips_en.lua:208 |
| rules | `overtakeModeGap` — Overtake Mode: detection gap (s) | 0.3 to 2 | 1 / 1 / 1 / 1 | src/director.lua:1309, src/groups.lua:59, src/lang_en.lua:179, src/lang_en.lua:313, src/tips_en.lua:209 |
| rules | `overtakeModeBoostPct` — Overtake Mode: level gain (%) | 0 to 5 | 2 / 2 / 2 / 2 | src/director.lua:1311, src/groups.lua:59, src/lang_en.lua:179, src/lang_en.lua:314, src/tips_en.lua:210 |
| rules | `drsAssist` — Player DRS: beep and panel | boolean | true / true / true / true | src/engine.lua:503, src/engine.lua:733, src/engine.lua:812, src/groups.lua:60, src/lang_en.lua:180, src/panel.lua:163, src/panel.lua:228, src/tips_en.lua:169 |
| rules | `rulesDrs` — DRS: racing rules (rain, flags, start, Safety Car, red flag) | boolean | false / true / true / true | src/engine.lua:680, src/groups.lua:60, src/lang_en.lua:180, src/lang_en.lua:301, src/lang_en.lua:314, src/tips_en.lua:166 |
| rules | `rulesDrsLaps` — DRS: leader laps before enabling (start, SC, red flag) | 0 to 5 | 1 / 1 / 1 / 1 | src/engine.lua:704, src/groups.lua:60, src/lang_en.lua:180, src/lang_en.lua:314, src/tips_en.lua:167 |
| rules | `aiDrs` — AI DRS: opened in the zones | boolean | true / true / true / true | src/engine.lua:718, src/groups.lua:60, src/lang_en.lua:180, src/tips_en.lua:168 |
| rules | `drsBeepVolume` — Beeps (DRS and delta): volume (%) | 25 to 400 | 200 / 200 / 200 / 200 | src/engine.lua:503, src/engine.lua:673, src/engine.lua:812, src/groups.lua:60, src/lang_en.lua:180, src/lang_en.lua:315, src/tips_en.lua:165 |
| rules | `bopEnabled` — BoP: pace evened out within each class | boolean | false / false / false / false | src/classes.lua:42, src/director.lua:156, src/groups.lua:61, src/lang_en.lua:181, src/lang_en.lua:315, src/tips_en.lua:211 |
| rules | `bopStrengthPct` — BoP: maximum correction (%) | 0 to 5 | 2 / 2 / 2 / 2 | src/classes.lua:45, src/groups.lua:61, src/lang_en.lua:181, src/tips_en.lua:212 |
| rules | `proAmEnabled` — Pro-Am driver ratings (Bronze to Platinum) | boolean | false / false / false / false | src/groups.lua:61, src/lang_en.lua:181, src/persona.lua:31, src/persona.lua:32, src/tips_en.lua:213 |
| rules | `predictableSlowClass` — Slower class: predictable line | boolean | false / false / false / false | src/director.lua:806, src/groups.lua:62, src/lang_en.lua:181, src/tips_en.lua:214 |
| endurance | `enduranceOverlay` — Endurance layer | boolean | false / false / false / false | src/director.lua:157, src/director.lua:594, src/director.lua:1266, src/groups.lua:37, src/lang_en.lua:182, src/persona.lua:6, src/tips_en.lua:216 |
| endurance | `multiClass` — Multi-class | boolean | false / false / false / false | src/delta.lua:135, src/director.lua:91, src/director.lua:100, src/director.lua:1397, src/engine.lua:304, src/engine.lua:581, src/engine.lua:746, src/engine.lua:823, src/groups.lua:38, src/incidents.lua:869, src/lang_en.lua:182, src/sanctions.lua:227, src/sanctions.lua:490, src/tips_en.lua:217 |
| endurance | `classGapPct` — Gap between classes (%) | 3 to 25 | 8 / 8 / 8 / 8 | src/classes.lua:31, src/groups.lua:38, src/lang_en.lua:182, src/tips_en.lua:218 |
| endurance | `classYieldMargin` — Class speed advantage (km/h) | 1 to 15 | 4 / 4 / 4 / 4 | src/director.lua:367, src/director.lua:822, src/groups.lua:38, src/lang_en.lua:182, src/tips_en.lua:219 |
| endurance | `stintLevelSwing` — Variation between stints (%) | 0 to 8 | 3 / 3 / 3 / 3 | src/groups.lua:37, src/lang_en.lua:182, src/persona.lua:28, src/tips_en.lua:220 |
| endurance | `stintDegradationPct` — Degradation over a stint (%) | 0 to 5 | 1 / 1 / 1 / 1 | src/director.lua:158, src/groups.lua:37, src/lang_en.lua:182, src/tips_en.lua:221 |
| weather | `weatherAdaptation` — Adapt pace to the weather | boolean | true / true / true / true | src/director.lua:161, src/director.lua:388, src/groups.lua:39, src/lang_en.lua:183, src/tips_en.lua:223 |
| weather | `weatherTyresEnabled` — Manage dry and wet tyres | boolean | true / true / true / true | src/engine.lua:831, src/groups.lua:39, src/lang_en.lua:183, src/tips_en.lua:224, src/weather.lua:25 |
| weather | `weatherMessage` — On-screen message on a weather change | boolean | true / true / true / true | src/engine.lua:837, src/groups.lua:42, src/lang_en.lua:183, src/lang_en.lua:310, src/tips_en.lua:225 |
| weather | `rainGripBoostPct` — Rain compensation without wet tyres (%) | 0 to 30 | 15 / 15 / 15 / 15 | src/groups.lua:39, src/lang_en.lua:183, src/lang_en.lua:309, src/tips_en.lua:226, src/weather.lua:38 |
| weather | `outLapEnabled` — Out-lap: tyre warm-up | boolean | false / true / true / true | src/groups.lua:40, src/lang_en.lua:154, src/strategy.lua:221, src/strategy.lua:230, src/tips_en.lua:16 |
| weather | `outLapLevelPct` — Out-lap: level lowered by (%) | 0 to 15 | 7 / 7 / 7 / 7 | src/groups.lua:40, src/lang_en.lua:154, src/lang_en.lua:285, src/strategy.lua:210, src/strategy.lua:221, src/strategy.lua:224, src/strategy.lua:240, src/strategy.lua:461, src/tips_en.lua:17 |
| weather | `lockWearEnabled` — Lock-ups linked to tyre wear | boolean | false / true / true / true | src/groups.lua:41, src/lang_en.lua:154, src/mistakes.lua:75, src/mistakes.lua:103, src/tips_en.lua:18 |
| weather | `lockWearGain` — Lock-ups: gain at the end of a stint | 0 to 3 | 1.5 / 1.5 / 1.5 / 1.5 | src/groups.lua:41, src/lang_en.lua:154, src/lang_en.lua:285, src/mistakes.lua:50, src/tips_en.lua:19 |
| weather | `lockFlatSpotKm` — Flat spot: wear added per lock-up (km) | 0 to 5 | 1 / 1 / 1 / 1 | src/groups.lua:41, src/lang_en.lua:154, src/lang_en.lua:285, src/mistakes.lua:103, src/mistakes.lua:104, src/tips_en.lua:20 |
| lights | `lightsYellow` — Yellow · yellow flag, Safety Car, VSC, FCY | boolean | true / true / true / true | src/groups.lua:53, src/lang_en.lua:183, src/lang_en.lua:285, src/tips_en.lua:228 |
| lights | `lightsRed` — Red · red flag | boolean | true / true / true / true | src/groups.lua:53, src/lang_en.lua:183, src/lang_en.lua:285, src/lights.lua:113, src/tips_en.lua:229 |
| lights | `lightsBlue` — Blue · blue flag shown to you | boolean | true / true / true / true | src/groups.lua:53, src/lang_en.lua:183, src/lights.lua:129, src/tips_en.lua:230 |
| lights | `lightsWhite` — White · very slow vehicle ahead | boolean | true / true / true / true | src/groups.lua:53, src/lang_en.lua:183, src/lights.lua:127, src/tips_en.lua:231 |
| lights | `lightsOrange` — Orange · slippery track | boolean | true / true / true / true | src/groups.lua:53, src/lang_en.lua:183, src/lights.lua:128, src/tips_en.lua:232 |
| lights | `lightsGreen` — Green · end of zone, neutralisation and restart | boolean | true / true / true / true | src/groups.lua:53, src/lang_en.lua:183, src/lights.lua:97, src/lights.lua:123, src/tips_en.lua:233 |
| lights | `lightsGreenTime` — Green duration (s) | 0 to 15 | 5 / 5 / 5 / 5 | src/groups.lua:54, src/lang_en.lua:183, src/lang_en.lua:285, src/lights.lua:96, src/lights.lua:123, src/tips_en.lua:234 |
| lights | `lightsHold` — Delay before a less important colour (s) | 0.5 to 5 | 1.5 / 1.5 / 1.5 / 1.5 | AdvancedIA.lua:453, src/applier.lua:473, src/applier.lua:532, src/applier.lua:533, src/groups.lua:54, src/lang_en.lua:183, src/tips_en.lua:235 |
| strategy | `strategyEnabled` — Individual pit-stop strategy | boolean | false / false / false / true | src/groups.lua:44, src/lang_en.lua:154, src/strategy.lua:304, src/tips_en.lua:21 |
| strategy | `strategyTyreWearPct` — Tyre wear before stopping (%) | 10 to 95 | 30 / 30 / 30 / 30 | src/groups.lua:44, src/lang_en.lua:154, src/strategy.lua:123, src/strategy.lua:197, src/strategy.lua:202, src/tips_en.lua:22 |
| strategy | `strategyFuelMarginLaps` — Fuel margin (laps) | 0 to 3 | 1 / 1 / 1 / 1 | src/groups.lua:44, src/lang_en.lua:154, src/lang_en.lua:285, src/pits.lua:259, src/strategy.lua:131, src/tips_en.lua:23 |
| strategy | `strategyUndercut` — Undercut and overcut (reacting to rivals’ stops) | boolean | false / false / false / true | src/groups.lua:44, src/lang_en.lua:154, src/strategy.lua:364, src/strategy.lua:455, src/tips_en.lua:24 |
| strategy | `strategyRiskPct` — Average risk taking (%) | 0 to 100 | 50 / 50 / 50 / 50 | src/groups.lua:45, src/lang_en.lua:154, src/persona.lua:35, src/tips_en.lua:25 |
| strategy | `strategySpreadPct` — Spread between strategists (%) | 0 to 100 | 60 / 60 / 60 / 60 | src/groups.lua:45, src/lang_en.lua:154, src/persona.lua:35, src/tips_en.lua:26 |
| strategy | `failuresEnabled` — Progressive mechanical failures | boolean | false / false / false / true | src/groups.lua:46, src/lang_en.lua:154, src/strategy.lua:256, src/tips_en.lua:27 |
| strategy | `failureRate` — Failures: rate (per hour and per AI) | 0 to 2 | 0.05 / 0.05 / 0.05 / 0.05 | src/groups.lua:46, src/lang_en.lua:154, src/lang_en.lua:285, src/strategy.lua:256, src/strategy.lua:264, src/tips_en.lua:28 |
| strategy | `failureLossPct` — Failure: maximum pace loss (%) | 3 to 30 | 12 / 12 / 12 / 12 | src/groups.lua:46, src/lang_en.lua:154, src/strategy.lua:250, src/strategy.lua:269, src/tips_en.lua:29 |
| sanctions | `sanTrackLimits` — Track limits (at least three wheels off) | boolean | false / true / true / true | src/groups.lua:47, src/lang_en.lua:154, src/sanctions.lua:310, src/sanctions.lua:327, src/tips_en.lua:30 |
| sanctions | `sanTrackWarnings` — Warnings before a penalty (race) | 0 to 5 | 3 / 3 / 3 / 3 | src/groups.lua:47, src/lang_en.lua:154, src/lang_en.lua:285, src/sanctions.lua:257, src/sanctions.lua:258, src/sanctions.lua:259, src/sanctions.lua:260, src/tips_en.lua:31 |
| sanctions | `sanCutPenalty` — Corner cut with a time gain: throttle cut | boolean | false / false / false / true | src/groups.lua:47, src/lang_en.lua:154, src/sanctions.lua:321, src/sanctions.lua:345, src/tips_en.lua:32 |
| sanctions | `sanCutSeconds` — Throttle cut (s) | 2 to 15 | 5 / 5 / 5 / 5 | src/groups.lua:47, src/lang_en.lua:154, src/sanctions.lua:323, src/sanctions.lua:324, src/sanctions.lua:325, src/sanctions.lua:326, src/tips_en.lua:33 |
| sanctions | `sanJumpStart` — Jump start | boolean | false / false / false / true | src/groups.lua:48, src/lang_en.lua:154, src/sanctions.lua:100, src/sanctions.lua:591, src/tips_en.lua:34 |
| sanctions | `sanPitSpeed` — Pit-lane speeding | boolean | false / false / false / true | src/groups.lua:48, src/lang_en.lua:154, src/sanctions.lua:100, src/sanctions.lua:391, src/tips_en.lua:35 |
| sanctions | `sanPitExit` — Pit-exit line crossed | boolean | false / false / false / true | src/groups.lua:48, src/lang_en.lua:154, src/sanctions.lua:100, src/sanctions.lua:401, src/tips_en.lua:36 |
| sanctions | `sanProcedureKind` — Penalty for procedural offences | drive, stopgo, time | drive / drive / drive / drive | src/groups.lua:48, src/lang_en.lua:154, src/sanctions.lua:395, src/sanctions.lua:405, src/sanctions.lua:591, src/tips_en.lua:37 |
| sanctions | `sanWrongWay` — Wrong way: black flag | boolean | false / true / true / true | src/groups.lua:49, src/lang_en.lua:154, src/sanctions.lua:374, src/tips_en.lua:38 |
| sanctions | `sanWrongWaySeconds` — Wrong way tolerated (s) | 2 to 15 | 5 / 5 / 5 / 5 | src/groups.lua:49, src/lang_en.lua:154, src/sanctions.lua:374, src/tips_en.lua:39 |
| sanctions | `sanServeLaps` — Laps to serve a penalty (then black flag) | 1 to 5 | 3 / 3 / 3 / 3 | src/groups.lua:49, src/lang_en.lua:154, src/sanctions.lua:4, src/sanctions.lua:170, src/sanctions.lua:175, src/sanctions.lua:176, src/sanctions.lua:518, src/sanctions.lua:534, src/tips_en.lua:40 |
| sanctions | `sanStopGoSeconds` — Stop-and-go: stop (s) | 5 to 30 | 10 / 10 / 10 / 10 | src/groups.lua:50, src/lang_en.lua:154, src/sanctions.lua:161, src/sanctions.lua:175, src/sanctions.lua:177, src/sanctions.lua:179, src/sanctions.lua:453, src/sanctions.lua:454, src/tips_en.lua:41 |
| sanctions | `sanTimeSeconds` — Time penalty (s) | 1 to 30 | 5 / 5 / 5 / 5 | src/groups.lua:50, src/lang_en.lua:154, src/sanctions.lua:167, src/sanctions.lua:169, src/sanctions.lua:257, src/sanctions.lua:261, src/sanctions.lua:361, src/sanctions.lua:507, src/tips_en.lua:42 |
| sanctions | `sanUnservedTime` — Unserved penalty added to the result | boolean | false / false / false / true | src/groups.lua:50, src/lang_en.lua:154, src/sanctions.lua:171, src/sanctions.lua:676, src/tips_en.lua:43 |
| sanctions | `sanGiveBack` — Give the place back after an off-track overtake | boolean | false / false / false / true | src/groups.lua:50, src/lang_en.lua:154, src/sanctions.lua:299, src/sanctions.lua:463, src/tips_en.lua:44 |
| sanctions | `sanGiveBackSeconds` — Time to give the place back (s) | 5 to 30 | 15 / 15 / 15 / 15 | src/groups.lua:50, src/lang_en.lua:154, src/sanctions.lua:477, src/sanctions.lua:478, src/tips_en.lua:45 |
| sanctions | `sanMessages` — AI sanction notices on screen | boolean | false / true / true / true | src/groups.lua:51, src/lang_en.lua:154, src/sanctions.lua:122, src/tips_en.lua:46 |
| traffic | `trafficGapSeconds` — Base gap (s) | 0.5 to 5 | 2.5 / 2.5 / 2.5 / 2.5 | src/groups.lua:30, src/lang_en.lua:184, src/tips_en.lua:237, src/traffic.lua:209 |
| traffic | `trafficDensityGain` — Distance added per AI (m) | 0.5 to 5 | 2.8 / 2.8 / 2.8 / 2.8 | src/groups.lua:30, src/lang_en.lua:184, src/tips_en.lua:238, src/traffic.lua:209 |
| traffic | `trafficVariation` — Gap variation (%) | 0 to 50 | 45 / 45 / 45 / 45 | src/groups.lua:30, src/lang_en.lua:184, src/tips_en.lua:239, src/traffic.lua:208 |
| traffic | `trafficMaxReduction` — Maximum speed reduction (%) | 2 to 20 | 14 / 14 / 14 / 14 | src/groups.lua:30, src/lang_en.lua:184, src/tips_en.lua:240, src/traffic.lua:219 |

## Adjustable global options

| Key | Default | Range | Consumers |
|---|---|---|---|
| `levelMode` | auto | auto, native, grip, none | src/applier.lua:1088, src/applier.lua:1095, src/caps.lua:4, src/caps.lua:52, src/caps.lua:53, src/lang_en.lua:83, src/tips_en.lua:258 |
| `useGripBoost` | false | boolean | src/applier.lua:1095, src/caps.lua:53, src/tips_en.lua:259 |
| `gripPerLevelPct` | 0.004 | [0, 0.01] | src/applier.lua:1095, src/lang_en.lua:152, src/tips_en.lua:270 |
| `useBrakeAssist` | true | boolean | src/applier.lua:1073, src/applier.lua:1102, src/director.lua:1181, src/engine.lua:48, src/tips_en.lua:260 |
| `overrideAwareness` | false | boolean | src/applier.lua:1081, src/tips_en.lua:261 |
| `occLatMin` | 0.3 | [0.1, 1] | src/lang_en.lua:152, src/lang_en.lua:317, src/perception.lua:53, src/perception.lua:54, src/perception.lua:55, src/tips_en.lua:266 |
| `occLatMax` | 5.5 | [2, 8] | src/director.lua:681, src/director.lua:786, src/director.lua:875, src/director.lua:918, src/director.lua:1083, src/lang_en.lua:152, src/lang_en.lua:317, src/perception.lua:42, src/perception.lua:47, src/perception.lua:54, src/perception.lua:55, src/perception.lua:107, src/tips_en.lua:267 |
| `occMargin` | 6 | [2, 15] | src/lang_en.lua:152, src/lang_en.lua:317, src/perception.lua:45, src/perception.lua:50, src/tips_en.lua:268 |
| `occSpeedGain` | 0.8 | [0, 2] | src/lang_en.lua:152, src/lang_en.lua:317, src/perception.lua:45, src/perception.lua:50, src/tips_en.lua:269 |
| `seed` | 19731019 | [0, 2147483647] | src/director.lua:69, src/director.lua:412, src/director.lua:557, src/director.lua:593, src/director.lua:971, src/director.lua:1268, src/engine.lua:106, src/engine.lua:187, src/engine.lua:456, src/engine.lua:566, src/engine.lua:825, src/engine.lua:845, src/engine.lua:967, src/flash.lua:70, src/grid.lua:178, src/grid.lua:210, src/incidents.lua:401, src/incidents.lua:493, src/lang_en.lua:84, src/mistakes.lua:88, src/mistakes.lua:97, src/persona.lua:5, src/persona.lua:8, src/persona.lua:9, src/persona.lua:28, src/persona.lua:30, src/persona.lua:40, src/persona.lua:43, src/persona.lua:45, src/persona.lua:46, src/persona.lua:47, src/pits.lua:56, src/pits.lua:164, src/strategy.lua:253, src/strategy.lua:264, src/strategy.lua:266, src/strategy.lua:268, src/strategy.lua:269, src/strategy.lua:270, src/strategy.lua:305, src/strategy.lua:339, src/tips_en.lua:271, src/tips_en.lua:291, src/tips_en.lua:357, src/traffic.lua:69, src/traffic.lua:86, src/traffic.lua:120, src/traffic.lua:197, src/util.lua:18, src/util.lua:19, src/util.lua:32, src/weather.lua:9, src/weather.lua:11, src/weather.lua:14, src/weather.lua:28 |
| `debugLog` | false | boolean | src/director.lua:88, src/director.lua:1334, src/lang_en.lua:84, src/tips_en.lua:265 |

The section switches go through `C.on`/`C.effective` and are walked by the interface tests. `classPatterns` uses the `C.patterns` parser, `Classes.configure/update`, the eight dedicated rows and validated storage. The manual/automatic choice, the main button, panic, presets and the diagnostics tools are examined in AUDIT_V1.md.

## Functions examined

List taken from the AST of the 47 active files, including local and anonymous functions. The review, fixes and limits are in AUDIT_V1.md. This list does not mean 100% branch coverage.

| File | Line | Function |
|---|---|---|
| AdvancedIA.lua | 11 | `(anonymous)` |
| AdvancedIA.lua | 16 | `none` |
| AdvancedIA.lua | 20 | `(anonymous)` |
| AdvancedIA.lua | 21 | `(anonymous)` |
| AdvancedIA.lua | 21 | `(anonymous)` |
| AdvancedIA.lua | 21 | `(anonymous)` |
| AdvancedIA.lua | 30 | `(anonymous)` |
| AdvancedIA.lua | 43 | `restartOnly` |
| AdvancedIA.lua | 44 | `script.update` |
| AdvancedIA.lua | 45 | `script.HUMANAI__UPDATE` |
| AdvancedIA.lua | 46 | `script.HUMANAI__MAIN` |
| AdvancedIA.lua | 47 | `script.HUMANAI__MENU` |
| AdvancedIA.lua | 48 | `script.HUMANAI__FLAGS` |
| AdvancedIA.lua | 49 | `script.HUMANAI__HUD` |
| AdvancedIA.lua | 115 | `carName` |
| AdvancedIA.lua | 119 | `announce` |
| AdvancedIA.lua | 144 | `dirty` |
| AdvancedIA.lua | 152 | `(anonymous)` |
| AdvancedIA.lua | 160 | `(anonymous)` |
| AdvancedIA.lua | 163 | `cspLog` |
| AdvancedIA.lua | 168 | `(anonymous)` |
| AdvancedIA.lua | 177 | `cspStep` |
| AdvancedIA.lua | 198 | `writeJournal` |
| AdvancedIA.lua | 211 | `cancelProbe` |
| AdvancedIA.lua | 212 | `syncRestored` |
| AdvancedIA.lua | 222 | `anyOwned` |
| AdvancedIA.lua | 227 | `step` |
| AdvancedIA.lua | 233 | `stop` |
| AdvancedIA.lua | 239 | `saveRace` |
| AdvancedIA.lua | 252 | `release` |
| AdvancedIA.lua | 270 | `updateLog` |
| AdvancedIA.lua | 274 | `(anonymous)` |
| AdvancedIA.lua | 289 | `startProbe` |
| AdvancedIA.lua | 290 | `(anonymous)` |
| AdvancedIA.lua | 318 | `session` |
| AdvancedIA.lua | 327 | `lightsCheck` |
| AdvancedIA.lua | 334 | `update` |
| AdvancedIA.lua | 361 | `(anonymous)` |
| AdvancedIA.lua | 362 | `(anonymous)` |
| AdvancedIA.lua | 466 | `updateTick` |
| AdvancedIA.lua | 486 | `protect` |
| AdvancedIA.lua | 516 | `bridgeWork` |
| AdvancedIA.lua | 517 | `bridgeStep` |
| AdvancedIA.lua | 526 | `(anonymous)` |
| AdvancedIA.lua | 527 | `script.HUMANAI__UPDATE` |
| AdvancedIA.lua | 551 | `script.update` |
| AdvancedIA.lua | 552 | `script.HUMANAI__MENU` |
| AdvancedIA.lua | 555 | `protectUI` |
| AdvancedIA.lua | 569 | `timedUI` |
| AdvancedIA.lua | 584 | `script.HUMANAI__MAIN` |
| AdvancedIA.lua | 596 | `script.HUMANAI__FLAGS` |
| AdvancedIA.lua | 598 | `script.HUMANAI__HUD` |
| src/applier.lua | 14 | `note` |
| src/applier.lua | 17 | `callable` |
| src/applier.lua | 25 | `nativeClock` |
| src/applier.lua | 32 | `(anonymous)` |
| src/applier.lua | 37 | `osClock` |
| src/applier.lua | 49 | `initClock` |
| src/applier.lua | 55 | `present` |
| src/applier.lua | 61 | `setBrake` |
| src/applier.lua | 66 | `setFlash` |
| src/applier.lua | 67 | `write` |
| src/applier.lua | 84 | `(anonymous)` |
| src/applier.lua | 88 | `M.new` |
| src/applier.lua | 97 | `(anonymous)` |
| src/applier.lua | 107 | `M.clock` |
| src/applier.lua | 119 | `M.access` |
| src/applier.lua | 126 | `M.openStore` |
| src/applier.lua | 153 | `M.savePreset` |
| src/applier.lua | 159 | `(anonymous)` |
| src/applier.lua | 167 | `M.deletePreset` |
| src/applier.lua | 169 | `(anonymous)` |
| src/applier.lua | 174 | `readOption` |
| src/applier.lua | 179 | `readRaceFlagsHidden` |
| src/applier.lua | 184 | `M.readFlagsHidden` |
| src/applier.lua | 188 | `M.menu` |
| src/applier.lua | 202 | `M.compactWindow` |
| src/applier.lua | 206 | `(anonymous)` |
| src/applier.lua | 208 | `(anonymous)` |
| src/applier.lua | 213 | `M.baselines` |
| src/applier.lua | 219 | `M.dirty` |
| src/applier.lua | 220 | `M.rebase` |
| src/applier.lua | 231 | `M.save` |
| src/applier.lua | 234 | `(anonymous)` |
| src/applier.lua | 246 | `restoreRain` |
| src/applier.lua | 250 | `restoreSkin` |
| src/applier.lua | 254 | `(anonymous)` |
| src/applier.lua | 258 | `M.restore` |
| src/applier.lua | 311 | `send` |
| src/applier.lua | 319 | `field` |
| src/applier.lua | 324 | `claim` |
| src/applier.lua | 333 | `weather` |
| src/applier.lua | 360 | `tyreLabel` |
| src/applier.lua | 366 | `pitRequest` |
| src/applier.lua | 430 | `startDelay` |
| src/applier.lua | 440 | `place` |
| src/applier.lua | 458 | `hold` |
| src/applier.lua | 475 | `flagText` |
| src/applier.lua | 480 | `unwritten` |
| src/applier.lua | 487 | `redHidden` |
| src/applier.lua | 498 | `nativeFree` |
| src/applier.lua | 505 | `M.flagReleased` |
| src/applier.lua | 508 | `M.flagMine` |
| src/applier.lua | 509 | `leftover` |
| src/applier.lua | 528 | `M.flag` |
| src/applier.lua | 561 | `M.reportCaps` |
| src/applier.lua | 571 | `gridNode` |
| src/applier.lua | 578 | `M.gridNodes` |
| src/applier.lua | 594 | `folder` |
| src/applier.lua | 599 | `normalPath` |
| src/applier.lua | 607 | `inside` |
| src/applier.lua | 608 | `lightsLoad` |
| src/applier.lua | 613 | `lightsRead` |
| src/applier.lua | 675 | `M.trackLights` |
| src/applier.lua | 686 | `flash` |
| src/applier.lua | 698 | `safetySkin` |
| src/applier.lua | 702 | `(anonymous)` |
| src/applier.lua | 704 | `(anonymous)` |
| src/applier.lua | 711 | `safety` |
| src/applier.lua | 719 | `(anonymous)` |
| src/applier.lua | 772 | `recover` |
| src/applier.lua | 785 | `M.releaseBlackFlag` |
| src/applier.lua | 792 | `M.penalty` |
| src/applier.lua | 806 | `disposeBeep` |
| src/applier.lua | 806 | `(anonymous)` |
| src/applier.lua | 807 | `M.beep` |
| src/applier.lua | 815 | `play` |
| src/applier.lua | 828 | `M.deltaBeep` |
| src/applier.lua | 835 | `(anonymous)` |
| src/applier.lua | 839 | `play` |
| src/applier.lua | 844 | `(anonymous)` |
| src/applier.lua | 849 | `M.drs` |
| src/applier.lua | 873 | `releaseDrs` |
| src/applier.lua | 880 | `M.sessionBox` |
| src/applier.lua | 881 | `M.screen` |
| src/applier.lua | 887 | `M.listenMessages` |
| src/applier.lua | 891 | `M.blockMessages` |
| src/applier.lua | 895 | `M.dispose` |
| src/applier.lua | 901 | `scriptFolder` |
| src/applier.lua | 906 | `M.fontDir` |
| src/applier.lua | 908 | `(anonymous)` |
| src/applier.lua | 917 | `M.appFile` |
| src/applier.lua | 925 | `M.journalOpen` |
| src/applier.lua | 927 | `(anonymous)` |
| src/applier.lua | 943 | `M.clockText` |
| src/applier.lua | 948 | `M.journalWrite` |
| src/applier.lua | 952 | `(anonymous)` |
| src/applier.lua | 957 | `M.storeText` |
| src/applier.lua | 958 | `M.loadText` |
| src/applier.lua | 959 | `M.message` |
| src/applier.lua | 961 | `M.probeMessage` |
| src/applier.lua | 963 | `folderFile` |
| src/applier.lua | 970 | `floodPath` |
| src/applier.lua | 971 | `M.floodRead` |
| src/applier.lua | 982 | `M.floodLeftover` |
| src/applier.lua | 994 | `saveClean` |
| src/applier.lua | 1004 | `M.floodWrite` |
| src/applier.lua | 1008 | `fileText` |
| src/applier.lua | 1015 | `removeFile` |
| src/applier.lua | 1020 | `M.cspPort` |
| src/applier.lua | 1025 | `(anonymous)` |
| src/applier.lua | 1026 | `(anonymous)` |
| src/applier.lua | 1027 | `(anonymous)` |
| src/applier.lua | 1028 | `(anonymous)` |
| src/applier.lua | 1029 | `(anonymous)` |
| src/applier.lua | 1030 | `(anonymous)` |
| src/applier.lua | 1031 | `(anonymous)` |
| src/applier.lua | 1032 | `(anonymous)` |
| src/applier.lua | 1039 | `M.watchGui` |
| src/applier.lua | 1044 | `M.apply` |
| src/applier.lua | 1132 | `M.register` |
| src/applier.lua | 1136 | `M.unregister` |
| src/applier.lua | 1138 | `(anonymous)` |
| src/applier.lua | 1143 | `M.nextSession` |
| src/applier.lua | 1169 | `M.clipboard` |
| src/applier.lua | 1170 | `M.checkpoint` |
| src/applier.lua | 1181 | `M.recover` |
| src/applier.lua | 1209 | `M.pitSpinners` |
| src/applier.lua | 1211 | `(anonymous)` |
| src/applier.lua | 1233 | `M.oldSettings` |
| src/applier.lua | 1234 | `(anonymous)` |
| src/applier.lua | 1244 | `M.companionInstalled` |
| src/applier.lua | 1246 | `(anonymous)` |
| src/applier.lua | 1258 | `bridgeItem` |
| src/applier.lua | 1264 | `bridgeStruct` |
| src/applier.lua | 1270 | `M.bridgeOpen` |
| src/applier.lua | 1272 | `(anonymous)` |
| src/bridge.lua | 15 | `finite` |
| src/bridge.lua | 16 | `num` |
| src/bridge.lua | 17 | `int` |
| src/bridge.lua | 18 | `bool` |
| src/bridge.lua | 20 | `index` |
| src/bridge.lua | 22 | `left` |
| src/bridge.lua | 24 | `fit` |
| src/bridge.lua | 30 | `M.new` |
| src/bridge.lua | 35 | `text` |
| src/bridge.lua | 40 | `code` |
| src/bridge.lua | 42 | `M.beat` |
| src/bridge.lua | 48 | `M.close` |
| src/bridge.lua | 49 | `cars` |
| src/bridge.lua | 87 | `M.publish` |
| src/bridge_layout.lua | 84 | `L.code` |
| src/calibration.lua | 7 | `M.new` |
| src/calibration.lua | 8 | `resetSafe` |
| src/calibration.lua | 18 | `safe` |
| src/calibration.lua | 32 | `M.step` |
| src/calibration.lua | 80 | `M.cancel` |
| src/caps.lua | 3 | `M.new` |
| src/caps.lua | 8 | `M.call` |
| src/caps.lua | 19 | `M.restoreCall` |
| src/caps.lua | 21 | `probeSwapped` |
| src/caps.lua | 22 | `probeRestore` |
| src/caps.lua | 24 | `M.cancelProbe` |
| src/caps.lua | 30 | `M.probe` |
| src/caps.lua | 51 | `M.mode` |
| src/classes.lua | 4 | `M.new` |
| src/classes.lua | 5 | `M.configure` |
| src/classes.lua | 8 | `M.laps` |
| src/classes.lua | 13 | `M.update` |
| src/classes.lua | 41 | `M.balance` |
| src/config.lua | 58 | `M.solo` |
| src/config.lua | 73 | `M.hidden` |
| src/config.lua | 78 | `add` |
| src/config.lua | 84 | `n` |
| src/config.lua | 85 | `b` |
| src/config.lua | 86 | `e` |
| src/config.lua | 576 | `M.defaults` |
| src/config.lua | 587 | `M.sectionsChanged` |
| src/config.lua | 594 | `M.anySection` |
| src/config.lua | 598 | `choice` |
| src/config.lua | 599 | `M.patterns` |
| src/config.lua | 609 | `M.validate` |
| src/config.lua | 643 | `M.validateGlobals` |
| src/config.lua | 664 | `M.preset` |
| src/config.lua | 676 | `M.on` |
| src/config.lua | 677 | `M.any` |
| src/config.lua | 682 | `M.effective` |
| src/config.lua | 718 | `M.effectiveGlobals` |
| src/config.lua | 725 | `M.needsOffset` |
| src/config.lua | 728 | `equal` |
| src/config.lua | 744 | `M.legacyMatch` |
| src/config.lua | 769 | `M.upgradeObstacles` |
| src/config.lua | 780 | `M.migrateProfile` |
| src/config.lua | 848 | `M.migrate` |
| src/config.lua | 916 | `M.kept` |
| src/config.lua | 917 | `ruleValue` |
| src/config.lua | 918 | `M.restore` |
| src/config.lua | 927 | `applyValues` |
| src/config.lua | 931 | `M.weekendSwitch` |
| src/config.lua | 940 | `M.applyRules` |
| src/config.lua | 955 | `M.spreadRules` |
| src/config.lua | 969 | `M.mark` |
| src/config.lua | 973 | `M.setMark` |
| src/config.lua | 979 | `M.withRules` |
| src/config.lua | 990 | `category13` |
| src/config.lua | 1004 | `M.migrateRules` |
| src/config.lua | 1014 | `M.closestRuleCategory` |
| src/config.lua | 1023 | `M.ruleCategory` |
| src/config.lua | 1035 | `M.autoProfile` |
| src/cspgui.lua | 32 | `hidden` |
| src/cspgui.lua | 33 | `list` |
| src/cspgui.lua | 38 | `heldKeys` |
| src/cspgui.lua | 46 | `block` |
| src/cspgui.lua | 47 | `M.serialize` |
| src/cspgui.lua | 58 | `M.parse` |
| src/cspgui.lua | 67 | `read` |
| src/cspgui.lua | 84 | `M.new` |
| src/cspgui.lua | 88 | `note` |
| src/cspgui.lua | 90 | `M.take` |
| src/cspgui.lua | 91 | `session` |
| src/cspgui.lua | 96 | `M.start` |
| src/cspgui.lua | 114 | `M.reloaded` |
| src/cspgui.lua | 121 | `M.frozen` |
| src/cspgui.lua | 122 | `M.applied` |
| src/cspgui.lua | 124 | `M.pending` |
| src/cspgui.lua | 127 | `M.view` |
| src/cspgui.lua | 136 | `stop` |
| src/cspgui.lua | 143 | `M.want` |
| src/cspgui.lua | 153 | `M.step` |
| src/cspgui.lua | 227 | `M.release` |
| src/delta.lua | 10 | `accumulator` |
| src/delta.lua | 11 | `M.new` |
| src/delta.lua | 17 | `M.reset` |
| src/delta.lua | 21 | `M.rebase` |
| src/delta.lua | 26 | `bin` |
| src/delta.lua | 32 | `M.size` |
| src/delta.lua | 40 | `M.refresh` |
| src/delta.lua | 71 | `M.pace` |
| src/delta.lua | 79 | `M.reference` |
| src/delta.lua | 88 | `M.zoneReference` |
| src/delta.lua | 94 | `regime` |
| src/delta.lua | 107 | `sectors` |
| src/delta.lua | 110 | `advance` |
| src/delta.lua | 124 | `brakeFloor` |
| src/delta.lua | 125 | `zoneExists` |
| src/delta.lua | 130 | `M.update` |
| src/delta.lua | 199 | `M.penalized` |
| src/director.lua | 18 | `M.newState` |
| src/director.lua | 49 | `M.reset` |
| src/director.lua | 68 | `M.configure` |
| src/director.lua | 76 | `transition` |
| src/director.lua | 91 | `faster` |
| src/director.lua | 92 | `sideFree` |
| src/director.lua | 94 | `paceBin` |
| src/director.lua | 97 | `freeAt` |
| src/director.lua | 107 | `realAdvantage` |
| src/director.lua | 116 | `playerSlow` |
| src/director.lua | 124 | `inviteGeometry` |
| src/director.lua | 131 | `userSide` |
| src/director.lua | 132 | `fixedSide` |
| src/director.lua | 133 | `yieldSide` |
| src/director.lua | 140 | `passSide` |
| src/director.lua | 149 | `baseModifiers` |
| src/director.lua | 166 | `directionAllowed` |
| src/director.lua | 189 | `directionBudget` |
| src/director.lua | 199 | `wanted` |
| src/director.lua | 200 | `limitText` |
| src/director.lua | 209 | `M.reachable` |
| src/director.lua | 220 | `laneTarget` |
| src/director.lua | 229 | `laneHold` |
| src/director.lua | 255 | `M.lateral` |
| src/director.lua | 293 | `busy` |
| src/director.lua | 306 | `pace` |
| src/director.lua | 330 | `lapOrClass` |
| src/director.lua | 335 | `yieldTrigger` |
| src/director.lua | 442 | `M.trafficCap` |
| src/director.lua | 455 | `aeroMap` |
| src/director.lua | 470 | `straightBin` |
| src/director.lua | 471 | `aeroRuns` |
| src/director.lua | 488 | `lapsAhead` |
| src/director.lua | 494 | `rival` |
| src/director.lua | 501 | `directionRoom` |
| src/director.lua | 509 | `dirtyAir` |
| src/director.lua | 517 | `urgency` |
| src/director.lua | 536 | `towStart` |
| src/director.lua | 572 | `M.step` |
| src/director.lua | 1211 | `(anonymous)` |
| src/engine.lua | 30 | `startReport` |
| src/engine.lua | 56 | `decisionTime` |
| src/engine.lua | 72 | `contacts` |
| src/engine.lua | 102 | `M.new` |
| src/engine.lua | 110 | `(anonymous)` |
| src/engine.lua | 112 | `(anonymous)` |
| src/engine.lua | 137 | `M.changed` |
| src/engine.lua | 138 | `M.select` |
| src/engine.lua | 141 | `M.reset` |
| src/engine.lua | 145 | `M.rebase` |
| src/engine.lua | 175 | `M.configure` |
| src/engine.lua | 192 | `drsBeep` |
| src/engine.lua | 198 | `drive` |
| src/engine.lua | 211 | `M.drawnByAC` |
| src/engine.lua | 219 | `M.message` |
| src/engine.lua | 253 | `M.floodInit` |
| src/engine.lua | 262 | `flood` |
| src/engine.lua | 299 | `slowReset` |
| src/engine.lua | 301 | `(anonymous)` |
| src/engine.lua | 303 | `slowCars` |
| src/engine.lua | 380 | `raceInfo` |
| src/engine.lua | 390 | `M.step` |
| src/firstlap.lua | 17 | `M.new` |
| src/firstlap.lua | 18 | `M.reset` |
| src/firstlap.lua | 20 | `M.arm` |
| src/firstlap.lua | 35 | `finish` |
| src/firstlap.lua | 37 | `addPoint` |
| src/firstlap.lua | 44 | `M.nextPoint` |
| src/firstlap.lua | 51 | `M.headway` |
| src/firstlap.lua | 53 | `M.update` |
| src/flash.lua | 4 | `M.new` |
| src/flash.lua | 13 | `M.learn` |
| src/flash.lua | 14 | `M.sampleLearn` |
| src/flash.lua | 26 | `M.step` |
| src/flash.lua | 43 | `M.advantage` |
| src/flash.lua | 47 | `M.dispatch` |
| src/flood.lua | 12 | `trim` |
| src/flood.lua | 13 | `lines` |
| src/flood.lua | 20 | `header` |
| src/flood.lua | 21 | `keyOf` |
| src/flood.lua | 23 | `M.get` |
| src/flood.lua | 36 | `M.edit` |
| src/flood.lua | 69 | `M.truthy` |
| src/flood.lua | 71 | `M.state` |
| src/flood.lua | 78 | `round` |
| src/flood.lua | 80 | `M.values` |
| src/flood.lua | 88 | `M.backup` |
| src/flood.lua | 96 | `M.restore` |
| src/flood.lua | 106 | `M.decide` |
| src/grid.lua | 21 | `M.new` |
| src/grid.lua | 25 | `clearCars` |
| src/grid.lua | 26 | `clearPlayer` |
| src/grid.lua | 27 | `M.reset` |
| src/grid.lua | 32 | `M.rebase` |
| src/grid.lua | 39 | `byPosition` |
| src/grid.lua | 46 | `byRank` |
| src/grid.lua | 52 | `M.sortByRank` |
| src/grid.lua | 56 | `M.sortByPosition` |
| src/grid.lua | 66 | `M.resolve` |
| src/grid.lua | 94 | `M.start` |
| src/grid.lua | 116 | `gap` |
| src/grid.lua | 128 | `approach` |
| src/grid.lua | 141 | `pitStarter` |
| src/grid.lua | 147 | `release` |
| src/grid.lua | 162 | `expected` |
| src/grid.lua | 172 | `placedPlayer` |
| src/grid.lua | 178 | `M.step` |
| src/groups.lua | 70 | `M.build` |
| src/hudinfo.lua | 11 | `M.new` |
| src/hudinfo.lua | 19 | `M.lapTime` |
| src/hudinfo.lua | 25 | `M.clock` |
| src/hudinfo.lua | 31 | `reset` |
| src/hudinfo.lua | 38 | `M.message` |
| src/hudinfo.lua | 50 | `M.flood` |
| src/hudinfo.lua | 57 | `passes` |
| src/hudinfo.lua | 78 | `recap` |
| src/hudinfo.lua | 98 | `item` |
| src/hudinfo.lua | 103 | `strip` |
| src/hudinfo.lua | 123 | `M.update` |
| src/incidents.lua | 8 | `clearCar` |
| src/incidents.lua | 13 | `M.new` |
| src/incidents.lua | 33 | `clearOrder` |
| src/incidents.lua | 39 | `M.reset` |
| src/incidents.lua | 49 | `M.rebase` |
| src/incidents.lua | 77 | `hold` |
| src/incidents.lua | 81 | `message` |
| src/incidents.lua | 94 | `M.flushHeld` |
| src/incidents.lua | 102 | `note` |
| src/incidents.lua | 105 | `unavailable` |
| src/incidents.lua | 112 | `restart` |
| src/incidents.lua | 123 | `M.lightsOut` |
| src/incidents.lua | 133 | `standing` |
| src/incidents.lua | 142 | `restartRule` |
| src/incidents.lua | 145 | `leaderLap` |
| src/incidents.lua | 170 | `rankOf` |
| src/incidents.lua | 177 | `byRank` |
| src/incidents.lua | 182 | `release` |
| src/incidents.lua | 202 | `ahead` |
| src/incidents.lua | 210 | `gates` |
| src/incidents.lua | 232 | `freeze` |
| src/incidents.lua | 251 | `M.restoring` |
| src/incidents.lua | 257 | `M.restored` |
| src/incidents.lua | 264 | `traffic` |
| src/incidents.lua | 278 | `queued` |
| src/incidents.lua | 295 | `passable` |
| src/incidents.lua | 301 | `(anonymous)` |
| src/incidents.lua | 306 | `blocked` |
| src/incidents.lua | 325 | `free` |
| src/incidents.lua | 337 | `toPlace` |
| src/incidents.lua | 345 | `toExit` |
| src/incidents.lua | 351 | `seen` |
| src/incidents.lua | 358 | `leaderOf` |
| src/incidents.lua | 370 | `queueHead` |
| src/incidents.lua | 380 | `scOut` |
| src/incidents.lua | 387 | `placeFailed` |
| src/incidents.lua | 401 | `M.update` |
| src/incidents.lua | 843 | `M.safety` |
| src/incidents.lua | 862 | `position` |
| src/incidents.lua | 867 | `M.cap` |
| src/incidents.lua | 917 | `M.player` |
| src/journal.lua | 3 | `M.new` |
| src/journal.lua | 5 | `M.collect` |
| src/journal.lua | 14 | `M.take` |
| src/journal.lua | 22 | `M.summary` |
| src/journal.lua | 45 | `c` |
| src/lights.lua | 19 | `M.new` |
| src/lights.lua | 24 | `M.reset` |
| src/lights.lua | 30 | `M.rebase` |
| src/lights.lua | 40 | `slow` |
| src/lights.lua | 74 | `damage` |
| src/lights.lua | 90 | `green` |
| src/lights.lua | 105 | `M.decide` |
| src/lights.lua | 134 | `M.update` |
| src/lights.lua | 147 | `M.output` |
| src/lights.lua | 153 | `M.scan` |
| src/lights.lua | 157 | `close` |
| src/lights.lua | 190 | `M.equipped` |
| src/locale.lua | 12 | `copy` |
| src/locale.lua | 19 | `fill` |
| src/locale.lua | 25 | `texts` |
| src/locale.lua | 30 | `M.valid` |
| src/locale.lua | 32 | `M.set` |
| src/merge.lua | 14 | `car` |
| src/merge.lua | 15 | `M.new` |
| src/merge.lua | 21 | `M.rebase` |
| src/merge.lua | 22 | `M.reset` |
| src/merge.lua | 27 | `M.before` |
| src/merge.lua | 29 | `learn` |
| src/merge.lua | 44 | `arriving` |
| src/merge.lua | 61 | `M.update` |
| src/merge.lua | 106 | `M.idle` |
| src/mistakes.lua | 10 | `car` |
| src/mistakes.lua | 11 | `M.new` |
| src/mistakes.lua | 16 | `M.reset` |
| src/mistakes.lua | 20 | `M.rebase` |
| src/mistakes.lua | 32 | `risk` |
| src/mistakes.lua | 44 | `lockFactor` |
| src/mistakes.lua | 53 | `M.update` |
| src/oldinstall.lua | 12 | `colors` |
| src/oldinstall.lua | 15 | `M.window` |
| src/oldinstall.lua | 24 | `M.overlay` |
| src/oldinstall.lua | 28 | `(anonymous)` |
| src/oldinstall.lua | 36 | `M.run` |
| src/oldinstall.lua | 38 | `(anonymous)` |
| src/oldinstall.lua | 44 | `(anonymous)` |
| src/oldinstall.lua | 45 | `none` |
| src/oldinstall.lua | 47 | `(anonymous)` |
| src/oldinstall.lua | 48 | `(anonymous)` |
| src/panel.lua | 14 | `M.new` |
| src/panel.lua | 19 | `blue` |
| src/panel.lua | 40 | `native` |
| src/panel.lua | 66 | `joinOr` |
| src/panel.lua | 71 | `pitTexts` |
| src/panel.lua | 95 | `M.pitAnnounce` |
| src/panel.lua | 105 | `show` |
| src/panel.lua | 155 | `M.native` |
| src/panel.lua | 171 | `M.visible` |
| src/panel.lua | 177 | `M.infractions` |
| src/panel.lua | 185 | `M.warn` |
| src/panel.lua | 187 | `M.notice` |
| src/panel.lua | 189 | `initials` |
| src/panel.lua | 199 | `restartInfo` |
| src/panel.lua | 221 | `M.update` |
| src/penalties.lua | 10 | `M.new` |
| src/penalties.lua | 16 | `clear` |
| src/penalties.lua | 19 | `grant` |
| src/penalties.lua | 20 | `entitled` |
| src/penalties.lua | 21 | `M.reset` |
| src/penalties.lua | 27 | `M.rebase` |
| src/penalties.lua | 41 | `passable` |
| src/penalties.lua | 44 | `serving` |
| src/penalties.lua | 50 | `M.mayPass` |
| src/penalties.lua | 54 | `decide` |
| src/penalties.lua | 61 | `deadline` |
| src/penalties.lua | 65 | `M.update` |
| src/penalties.lua | 146 | `M.giveBackLimit` |
| src/penalties.lua | 152 | `owe` |
| src/penalties.lua | 156 | `sanction` |
| src/penalties.lua | 170 | `M.ai` |
| src/penalties.lua | 262 | `M.serialize` |
| src/penalties.lua | 272 | `M.restore` |
| src/penalties.lua | 292 | `M.resume` |
| src/perception.lua | 5 | `M.new` |
| src/perception.lua | 14 | `M.relative` |
| src/perception.lua | 34 | `M.occupancy` |
| src/perception.lua | 61 | `M.prepare` |
| src/perception.lua | 73 | `M.refresh` |
| src/perception.lua | 96 | `M.find` |
| src/perception.lua | 100 | `M.corridor` |
| src/persona.lua | 5 | `M.fill` |
| src/persona.lua | 8 | `r` |
| src/persona.lua | 9 | `trait` |
| src/persona.lua | 43 | `M.nextLapse` |
| src/pitplan.lua | 11 | `M.new` |
| src/pitplan.lua | 12 | `M.reset` |
| src/pitplan.lua | 16 | `M.rebase` |
| src/pitplan.lua | 20 | `count` |
| src/pitplan.lua | 25 | `name` |
| src/pitplan.lua | 26 | `list` |
| src/pitplan.lua | 33 | `M.planned` |
| src/pitplan.lua | 46 | `M.update` |
| src/pits.lua | 5 | `clear` |
| src/pits.lua | 12 | `M.new` |
| src/pits.lua | 17 | `M.reset` |
| src/pits.lua | 22 | `M.rebase` |
| src/pits.lua | 28 | `M.progress` |
| src/pits.lua | 35 | `M.compound` |
| src/pits.lua | 47 | `M.repairTime` |
| src/pits.lua | 53 | `tyreShort` |
| src/pits.lua | 54 | `notice` |
| src/pits.lua | 56 | `M.update` |
| src/pits.lua | 194 | `learn` |
| src/pits.lua | 214 | `lapsLeft` |
| src/pits.lua | 222 | `stintLaps` |
| src/pits.lua | 236 | `M.fuel` |
| src/pits.lua | 268 | `M.serialize` |
| src/pits.lua | 274 | `M.forget` |
| src/pits.lua | 275 | `M.restore` |
| src/presets.lua | 7 | `M.signature` |
| src/presets.lua | 16 | `M.layout` |
| src/presets.lua | 22 | `M.decode` |
| src/presets.lua | 73 | `M.capture` |
| src/presets.lua | 79 | `M.encode` |
| src/presets.lua | 85 | `M.apply` |
| src/remote.lua | 22 | `callable` |
| src/remote.lua | 23 | `folder` |
| src/remote.lua | 30 | `hex` |
| src/remote.lua | 33 | `(anonymous)` |
| src/remote.lua | 37 | `files` |
| src/remote.lua | 38 | `(anonymous)` |
| src/remote.lua | 46 | `folders` |
| src/remote.lua | 47 | `(anonymous)` |
| src/remote.lua | 54 | `rank` |
| src/remote.lua | 58 | `ordered` |
| src/remote.lua | 59 | `(anonymous)` |
| src/remote.lua | 63 | `parseList` |
| src/remote.lua | 75 | `lib` |
| src/remote.lua | 80 | `M.new` |
| src/remote.lua | 95 | `exists` |
| src/remote.lua | 96 | `load` |
| src/remote.lua | 97 | `save` |
| src/remote.lua | 104 | `delete` |
| src/remote.lua | 111 | `clock` |
| src/remote.lua | 114 | `watch` |
| src/remote.lua | 115 | `list` |
| src/remote.lua | 118 | `clear` |
| src/remote.lua | 126 | `copy` |
| src/remote.lua | 129 | `swap` |
| src/remote.lua | 137 | `listOf` |
| src/remote.lua | 138 | `complete` |
| src/remote.lua | 144 | `p.get` |
| src/remote.lua | 146 | `(anonymous)` |
| src/remote.lua | 151 | `p.json` |
| src/remote.lua | 152 | `p.sha256` |
| src/remote.lua | 153 | `p.entries` |
| src/remote.lua | 154 | `p.entry` |
| src/remote.lua | 155 | `p.installedVersion` |
| src/remote.lua | 157 | `p.sourceVersion` |
| src/remote.lua | 158 | `p.sourceComplete` |
| src/remote.lua | 159 | `p.sourceHas` |
| src/remote.lua | 164 | `p.markerFile` |
| src/remote.lua | 165 | `p.marker` |
| src/remote.lua | 167 | `p.mark` |
| src/remote.lua | 169 | `p.clearMarker` |
| src/remote.lua | 174 | `p.report` |
| src/remote.lua | 175 | `p.takeReport` |
| src/remote.lua | 182 | `p.boot` |
| src/remote.lua | 187 | `p.bootSet` |
| src/remote.lua | 188 | `p.bootClear` |
| src/remote.lua | 190 | `p.bootOk` |
| src/remote.lua | 191 | `p.failedNote` |
| src/remote.lua | 192 | `p.failed` |
| src/remote.lua | 193 | `p.clearFailed` |
| src/remote.lua | 195 | `p.log` |
| src/remote.lua | 196 | `p.open` |
| src/remote.lua | 199 | `p.stage` |
| src/remote.lua | 202 | `(anonymous)` |
| src/remote.lua | 216 | `p.snapshot` |
| src/remote.lua | 240 | `p.place` |
| src/remote.lua | 263 | `p.promote` |
| src/remote.lua | 289 | `empty` |
| src/remote.lua | 293 | `p.tidy` |
| src/remote.lua | 296 | `gone` |
| src/remote.lua | 306 | `(anonymous)` |
| src/remote.lua | 318 | `p.restart` |
| src/sanctions.lua | 20 | `car` |
| src/sanctions.lua | 37 | `clearCar` |
| src/sanctions.lua | 44 | `M.new` |
| src/sanctions.lua | 53 | `rebuild` |
| src/sanctions.lua | 60 | `M.reset` |
| src/sanctions.lua | 69 | `M.rebase` |
| src/sanctions.lua | 84 | `dropTransient` |
| src/sanctions.lua | 94 | `reasonText` |
| src/sanctions.lua | 101 | `event` |
| src/sanctions.lua | 110 | `M.aiNotice` |
| src/sanctions.lua | 121 | `notice` |
| src/sanctions.lua | 130 | `name` |
| src/sanctions.lua | 133 | `blackFlag` |
| src/sanctions.lua | 146 | `escalate` |
| src/sanctions.lua | 150 | `addTime` |
| src/sanctions.lua | 161 | `unservedSeconds` |
| src/sanctions.lua | 165 | `issue` |
| src/sanctions.lua | 185 | `lineBin` |
| src/sanctions.lua | 186 | `ignoredAt` |
| src/sanctions.lua | 187 | `lineIgnored` |
| src/sanctions.lua | 192 | `refund` |
| src/sanctions.lua | 207 | `lineSeen` |
| src/sanctions.lua | 221 | `cutGain` |
| src/sanctions.lua | 240 | `behind` |
| src/sanctions.lua | 254 | `strike` |
| src/sanctions.lua | 263 | `invalidate` |
| src/sanctions.lua | 276 | `progress` |
| src/sanctions.lua | 277 | `watchStart` |
| src/sanctions.lua | 290 | `appManoeuvre` |
| src/sanctions.lua | 293 | `trackLimits` |
| src/sanctions.lua | 342 | `throttle` |
| src/sanctions.lua | 367 | `wrongWay` |
| src/sanctions.lua | 380 | `pitLane` |
| src/sanctions.lua | 426 | `serve` |
| src/sanctions.lua | 461 | `giveBack` |
| src/sanctions.lua | 519 | `lap` |
| src/sanctions.lua | 539 | `resume` |
| src/sanctions.lua | 555 | `M.update` |
| src/sanctions.lua | 636 | `better` |
| src/sanctions.lua | 643 | `classify` |
| src/sanctions.lua | 651 | `(anonymous)` |
| src/sanctions.lua | 668 | `M.watch` |
| src/sanctions.lua | 688 | `M.position` |
| src/sanctions.lua | 690 | `M.serialize` |
| src/sanctions.lua | 701 | `M.restore` |
| src/snapshot.lua | 4 | `hexByte` |
| src/snapshot.lua | 6 | `collidedWith` |
| src/snapshot.lua | 10 | `damageValues` |
| src/snapshot.lua | 16 | `damageRead` |
| src/snapshot.lua | 21 | `playerDamage` |
| src/snapshot.lua | 28 | `M.new` |
| src/snapshot.lua | 40 | `vector` |
| src/snapshot.lua | 43 | `laneProbe` |
| src/snapshot.lua | 44 | `(anonymous)` |
| src/snapshot.lua | 47 | `readCar` |
| src/snapshot.lua | 130 | `simRead` |
| src/snapshot.lua | 151 | `(anonymous)` |
| src/snapshot.lua | 155 | `raceRead` |
| src/snapshot.lua | 163 | `conflictingApp` |
| src/snapshot.lua | 172 | `wearRead` |
| src/snapshot.lua | 186 | `tyres` |
| src/snapshot.lua | 210 | `M.read` |
| src/snapshot.lua | 233 | `(anonymous)` |
| src/snapshot.lua | 245 | `(anonymous)` |
| src/snapshot.lua | 285 | `M.zones` |
| src/snapshot.lua | 300 | `utf8Char` |
| src/snapshot.lua | 305 | `jsonName` |
| src/snapshot.lua | 325 | `carName` |
| src/snapshot.lua | 336 | `M.carLoader` |
| src/snapshot.lua | 337 | `byName` |
| src/snapshot.lua | 338 | `M.carStep` |
| src/snapshot.lua | 340 | `(anonymous)` |
| src/snapshot.lua | 348 | `(anonymous)` |
| src/snapshot.lua | 369 | `menuVisible` |
| src/snapshot.lua | 370 | `M.menu` |
| src/strategy.lua | 16 | `car` |
| src/strategy.lua | 30 | `clear` |
| src/strategy.lua | 31 | `M.new` |
| src/strategy.lua | 38 | `M.reset` |
| src/strategy.lua | 46 | `M.forget` |
| src/strategy.lua | 47 | `M.rebase` |
| src/strategy.lua | 57 | `render` |
| src/strategy.lua | 64 | `rebuild` |
| src/strategy.lua | 71 | `event` |
| src/strategy.lua | 77 | `relang` |
| src/strategy.lua | 83 | `wearOf` |
| src/strategy.lua | 87 | `name` |
| src/strategy.lua | 92 | `wearUse` |
| src/strategy.lua | 93 | `probe` |
| src/strategy.lua | 110 | `lapsLeft` |
| src/strategy.lua | 120 | `plan` |
| src/strategy.lua | 166 | `eligible` |
| src/strategy.lua | 170 | `want` |
| src/strategy.lua | 181 | `mandatoryDue` |
| src/strategy.lua | 185 | `rivals` |
| src/strategy.lua | 211 | `outLap` |
| src/strategy.lua | 253 | `failure` |
| src/strategy.lua | 297 | `M.update` |
| src/strategy.lua | 465 | `M.serialize` |
| src/strategy.lua | 472 | `M.restore` |
| src/traffic.lua | 5 | `M.new` |
| src/traffic.lua | 24 | `M.mode` |
| src/traffic.lua | 28 | `identity` |
| src/traffic.lua | 31 | `check` |
| src/traffic.lua | 49 | `plan` |
| src/traffic.lua | 69 | `(anonymous)` |
| src/traffic.lua | 126 | `M.exits` |
| src/traffic.lua | 179 | `M.update` |
| src/ui.lua | 23 | `idOf` |
| src/ui.lua | 32 | `fmt` |
| src/ui.lua | 40 | `wrap` |
| src/ui.lua | 42 | `number` |
| src/ui.lua | 46 | `shown` |
| src/ui.lua | 51 | `wrapAll` |
| src/ui.lua | 52 | `globalTips` |
| src/ui.lua | 72 | `ruleView` |
| src/ui.lua | 75 | `ruleCategoryOf` |
| src/ui.lua | 82 | `texts` |
| src/ui.lua | 101 | `same` |
| src/ui.lua | 101 | `(anonymous)` |
| src/ui.lua | 103 | `(anonymous)` |
| src/ui.lua | 115 | `M.new` |
| src/ui.lua | 135 | `(anonymous)` |
| src/ui.lua | 145 | `text` |
| src/ui.lua | 149 | `fontsOnce` |
| src/ui.lua | 153 | `mark` |
| src/ui.lua | 155 | `groupDigits` |
| src/ui.lua | 164 | `loadedHere` |
| src/ui.lua | 176 | `touch` |
| src/ui.lua | 179 | `presetTarget` |
| src/ui.lua | 188 | `loadBuiltin` |
| src/ui.lua | 205 | `builtinActive` |
| src/ui.lua | 229 | `carDatabase` |
| src/ui.lua | 256 | `input` |
| src/ui.lua | 281 | `valueText` |
| src/ui.lua | 289 | `intText` |
| src/ui.lua | 294 | `shortLabel` |
| src/ui.lua | 296 | `modified` |
| src/ui.lua | 301 | `segmentFits` |
| src/ui.lua | 314 | `toggleOpts` |
| src/ui.lua | 324 | `settingControl` |
| src/ui.lua | 398 | `hiddenNote` |
| src/ui.lua | 410 | `groupHeight` |
| src/ui.lua | 423 | `drawGroup` |
| src/ui.lua | 452 | `split` |
| src/ui.lua | 469 | `groupColumns` |
| src/ui.lua | 483 | `ruleBlock` |
| src/ui.lua | 533 | `safetyBlock` |
| src/ui.lua | 616 | `patternBlock` |
| src/ui.lua | 678 | `globalSwitch` |
| src/ui.lua | 685 | `globalChoice` |
| src/ui.lua | 693 | `globalSlider` |
| src/ui.lua | 711 | `choiceHead` |
| src/ui.lua | 719 | `globalBlock` |
| src/ui.lua | 773 | `statusLines` |
| src/ui.lua | 812 | `switchList` |
| src/ui.lua | 828 | `cspStatus` |
| src/ui.lua | 835 | `flagsNext` |
| src/ui.lua | 836 | `overlayBlock` |
| src/ui.lua | 893 | `lightsPhase` |
| src/ui.lua | 899 | `lightsStatus` |
| src/ui.lua | 919 | `legendRows` |
| src/ui.lua | 934 | `lightsLegend` |
| src/ui.lua | 964 | `activeFor` |
| src/ui.lua | 987 | `resetSection` |
| src/ui.lua | 1002 | `sectionsOn` |
| src/ui.lua | 1004 | `modifiedCount` |
| src/ui.lua | 1011 | `sectionContent` |
| src/ui.lua | 1041 | `language` |
| src/ui.lua | 1050 | `updateAct` |
| src/ui.lua | 1060 | `megabytes` |
| src/ui.lua | 1062 | `updateText` |
| src/ui.lua | 1095 | `updateBlock` |
| src/ui.lua | 1188 | `aiCars` |
| src/ui.lua | 1196 | `stateKey` |
| src/ui.lua | 1208 | `live` |
| src/ui.lua | 1211 | `sessionKind` |
| src/ui.lua | 1219 | `headerBar` |
| src/ui.lua | 1357 | `banner` |
| src/ui.lua | 1378 | `addWarning` |
| src/ui.lua | 1381 | `currentSignature` |
| src/ui.lua | 1387 | `entrySignature` |
| src/ui.lua | 1394 | `openTarget` |
| src/ui.lua | 1400 | `kpi` |
| src/ui.lua | 1412 | `homeTab` |
| src/ui.lua | 1681 | `sectionPane` |
| src/ui.lua | 1747 | `settingsTab` |
| src/ui.lua | 1800 | `ruleRow` |
| src/ui.lua | 1809 | `rulesTab` |
| src/ui.lua | 1874 | `raceRows` |
| src/ui.lua | 1882 | `aiRaceBlock` |
| src/ui.lua | 1893 | `diagnosticTab` |
| src/ui.lua | 2152 | `M.compactSize` |
| src/ui.lua | 2155 | `windowSetup` |
| src/ui.lua | 2175 | `lower` |
| src/ui.lua | 2195 | `drawWindow` |
| src/ui.lua | 2205 | `M.where` |
| src/ui.lua | 2210 | `M.main` |
| src/ui.lua | 2241 | `faded` |
| src/ui.lua | 2242 | `panelPalette` |
| src/ui.lua | 2272 | `box` |
| src/ui.lua | 2276 | `write` |
| src/ui.lua | 2286 | `font` |
| src/ui.lua | 2294 | `fontRelease` |
| src/ui.lua | 2297 | `textWidth` |
| src/ui.lua | 2313 | `fitSize` |
| src/ui.lua | 2322 | `rect4` |
| src/ui.lua | 2323 | `M.flagLayout` |
| src/ui.lua | 2359 | `quad` |
| src/ui.lua | 2364 | `cutBack` |
| src/ui.lua | 2371 | `drsBadge` |
| src/ui.lua | 2376 | `updateCode` |
| src/ui.lua | 2381 | `infractionText` |
| src/ui.lua | 2386 | `badge` |
| src/ui.lua | 2393 | `checker` |
| src/ui.lua | 2397 | `diagonal` |
| src/ui.lua | 2403 | `meatball` |
| src/ui.lua | 2409 | `stripes` |
| src/ui.lua | 2414 | `startLights` |
| src/ui.lua | 2422 | `deltaText` |
| src/ui.lua | 2432 | `deltaBox` |
| src/ui.lua | 2443 | `placeBox` |
| src/ui.lua | 2452 | `blueBox` |
| src/ui.lua | 2464 | `pillsWidth` |
| src/ui.lua | 2466 | `pillRow` |
| src/ui.lua | 2484 | `pill` |
| src/ui.lua | 2491 | `giveBackText` |
| src/ui.lua | 2495 | `blueText` |
| src/ui.lua | 2501 | `lightsCode` |
| src/ui.lua | 2508 | `placeText` |
| src/ui.lua | 2527 | `M.overlayParts` |
| src/ui.lua | 2553 | `M.overlayHeight` |
| src/ui.lua | 2563 | `sessionStrip` |
| src/ui.lua | 2612 | `flags` |
| src/ui.lua | 2738 | `M.flags` |
| src/ui.lua | 2746 | `nativeBox` |
| src/ui.lua | 2750 | `M.restoreNative` |
| src/ui.lua | 2751 | `screenSize` |
| src/ui.lua | 2754 | `hudContent` |
| src/ui.lua | 2789 | `M.hud` |
| src/ui.lua | 2808 | `(anonymous)` |
| src/update.lua | 40 | `M.version` |
| src/update.lua | 47 | `M.label` |
| src/update.lua | 49 | `M.newer` |
| src/update.lua | 55 | `str` |
| src/update.lua | 56 | `starts` |
| src/update.lua | 58 | `M.cut` |
| src/update.lua | 65 | `M.notes` |
| src/update.lua | 79 | `M.release` |
| src/update.lua | 101 | `M.digest` |
| src/update.lua | 109 | `safe` |
| src/update.lua | 119 | `M.content` |
| src/update.lua | 130 | `M.files` |
| src/update.lua | 137 | `M.requires` |
| src/update.lua | 153 | `M.manifestVersion` |
| src/update.lua | 158 | `M.stopped` |
| src/update.lua | 164 | `M.new` |
| src/update.lua | 169 | `event` |
| src/update.lua | 175 | `M.take` |
| src/update.lua | 182 | `M.busy` |
| src/update.lua | 189 | `fail` |
| src/update.lua | 195 | `parse` |
| src/update.lua | 204 | `M.parseReport` |
| src/update.lua | 216 | `bootCheck` |
| src/update.lua | 237 | `M.recover` |
| src/update.lua | 288 | `(anonymous)` |
| src/update.lua | 289 | `(anonymous)` |
| src/update.lua | 290 | `(anonymous)` |
| src/update.lua | 291 | `(anonymous)` |
| src/update.lua | 292 | `(anonymous)` |
| src/update.lua | 293 | `(anonymous)` |
| src/update.lua | 294 | `(anonymous)` |
| src/update.lua | 295 | `(anonymous)` |
| src/update.lua | 296 | `M.recoverText` |
| src/update.lua | 303 | `M.start` |
| src/update.lua | 334 | `M.tidy` |
| src/update.lua | 342 | `live` |
| src/update.lua | 344 | `M.check` |
| src/update.lua | 348 | `(anonymous)` |
| src/update.lua | 362 | `M.cancel` |
| src/update.lua | 370 | `place` |
| src/update.lua | 403 | `M.install` |
| src/update.lua | 415 | `(anonymous)` |
| src/update.lua | 420 | `(anonymous)` |
| src/update.lua | 428 | `(anonymous)` |
| src/update.lua | 431 | `(anonymous)` |
| src/update.lua | 444 | `M.rollback` |
| src/update.lua | 454 | `M.tick` |
| src/update.lua | 481 | `M.reported` |
| src/update.lua | 482 | `M.view` |
| src/update.lua | 501 | `M.fresh` |
| src/update.lua | 508 | `M.offered` |
| src/util.lua | 4 | `M.finite` |
| src/util.lua | 5 | `M.clamp` |
| src/util.lua | 6 | `M.number` |
| src/util.lua | 7 | `M.lerp` |
| src/util.lua | 8 | `M.sign` |
| src/util.lua | 9 | `M.wrap` |
| src/util.lua | 10 | `M.spline` |
| src/util.lua | 11 | `M.approach` |
| src/util.lua | 12 | `M.ema` |
| src/util.lua | 14 | `M.imul` |
| src/util.lua | 18 | `M.hash` |
| src/util.lua | 24 | `M.random` |
| src/util.lua | 32 | `M.unit` |
| src/util.lua | 33 | `M.newLog` |
| src/util.lua | 38 | `M.log` |
| src/util.lua | 54 | `M.wrapText` |
| src/weather.lua | 5 | `M.new` |
| src/weather.lua | 9 | `M.dryChoice` |
| src/weather.lua | 14 | `M.step` |
| src/widgets.lua | 13 | `hex` |
| src/widgets.lua | 20 | `W.colors` |
| src/widgets.lua | 57 | `forget` |
| src/widgets.lua | 59 | `W.setFonts` |
| src/widgets.lua | 64 | `W.fonts` |
| src/widgets.lua | 67 | `use` |
| src/widgets.lua | 74 | `release` |
| src/widgets.lua | 76 | `level` |
| src/widgets.lua | 78 | `role` |
| src/widgets.lua | 82 | `W.upper` |
| src/widgets.lua | 92 | `vec` |
| src/widgets.lua | 98 | `W.point` |
| src/widgets.lua | 103 | `W.begin` |
| src/widgets.lua | 116 | `W.frame` |
| src/widgets.lua | 117 | `W.rect` |
| src/widgets.lua | 121 | `W.frameRect` |
| src/widgets.lua | 125 | `W.line` |
| src/widgets.lua | 126 | `W.circle` |
| src/widgets.lua | 128 | `canQuad` |
| src/widgets.lua | 133 | `W.quad` |
| src/widgets.lua | 142 | `W.tri` |
| src/widgets.lua | 149 | `W.para` |
| src/widgets.lua | 154 | `W.panel` |
| src/widgets.lua | 160 | `W.text` |
| src/widgets.lua | 164 | `count` |
| src/widgets.lua | 165 | `width` |
| src/widgets.lua | 176 | `fitted` |
| src/widgets.lua | 195 | `tail` |
| src/widgets.lua | 204 | `W.shrink` |
| src/widgets.lua | 208 | `W.cell` |
| src/widgets.lua | 210 | `W.right` |
| src/widgets.lua | 212 | `W.lines` |
| src/widgets.lua | 229 | `W.paragraph` |
| src/widgets.lua | 235 | `W.lineHeight` |
| src/widgets.lua | 237 | `inside` |
| src/widgets.lua | 247 | `W.help` |
| src/widgets.lua | 252 | `hashId` |
| src/widgets.lua | 256 | `W.hit` |
| src/widgets.lua | 265 | `W.mouseX` |
| src/widgets.lua | 267 | `W.marker` |
| src/widgets.lua | 272 | `bar` |
| src/widgets.lua | 276 | `W.heading` |
| src/widgets.lua | 290 | `W.label` |
| src/widgets.lua | 291 | `W.labelWidth` |
| src/widgets.lua | 294 | `W.titleFit` |
| src/widgets.lua | 303 | `buttonStyle` |
| src/widgets.lua | 315 | `W.button` |
| src/widgets.lua | 338 | `W.link` |
| src/widgets.lua | 345 | `W.linkWidth` |
| src/widgets.lua | 347 | `W.icon` |
| src/widgets.lua | 363 | `W.switchShape` |
| src/widgets.lua | 369 | `W.switch` |
| src/widgets.lua | 379 | `W.toggleHeight` |
| src/widgets.lua | 380 | `W.toggle` |
| src/widgets.lua | 398 | `chipStyle` |
| src/widgets.lua | 403 | `W.chipWidth` |
| src/widgets.lua | 404 | `W.chip` |
| src/widgets.lua | 409 | `W.chipRight` |
| src/widgets.lua | 411 | `W.dotChipWidth` |
| src/widgets.lua | 412 | `W.dotChip` |
| src/widgets.lua | 422 | `W.choiceIds` |
| src/widgets.lua | 428 | `W.segment` |
| src/widgets.lua | 468 | `W.segmentFits` |
| src/widgets.lua | 474 | `W.cycle` |
| src/widgets.lua | 487 | `W.tile` |
| src/widgets.lua | 506 | `W.row` |
| src/widgets.lua | 517 | `W.nav` |
| src/widgets.lua | 529 | `W.slider` |
| src/widgets.lua | 553 | `W.pm` |
| src/widgets.lua | 563 | `W.inputFrame` |
| src/widgets.lua | 570 | `W.message` |
| src/widgets.lua | 582 | `W.scroll` |
| src/widgets.lua | 608 | `W.clip` |
| src/widgets.lua | 615 | `W.visible` |
| src/widgets.lua | 621 | `tipColors` |
| src/widgets.lua | 632 | `W.finish` |
| src/widgets.lua | 644 | `W.step` |
| src/zones.lua | 6 | `M.parse` |
| src/zones.lua | 9 | `skip` |
| src/zones.lua | 17 | `token` |
| src/zones.lua | 18 | `value` |
| src/zones.lua | 67 | `M.at` |
| src/zones.lua | 77 | `M.export` |
