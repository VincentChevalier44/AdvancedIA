# Release measurements

Released version: Beta 1.62. All strict PDR criteria accepted: **no**, open points below. These results are not a guarantee of in-game FPS.

- Catalogue and checks: **1189/1189**, including the 78 PDR situations and the 10,000-step fuzz.
- Integration: **175 cases**, status True.
- Linter: 66 files, status True.
- Soak: 1,728,000 frames, 8 simulated hours, 40 AI, 0 errors.
- Memory after collection: 8640.2 to 20517.2 KiB; drift 11877.0 KiB after the bench warm-up phase.
- Strict bench memory criterion (<256 KiB over the whole window): **False**. Drift during the last hour: **51.3 KiB**. The total variation is kept even when the last hour is more stable.
- Core at 30 AI: mean **0.478 ms**, P99 **0.777 ms**, raw maximum **5.966 ms** over 30,000 frames.
- Mean <0.3 ms: **False**. Maximum <1 ms: **False**.

The maximum is not filtered. This benchmark includes neither the real SDK nor the UI. The kinematic tests do not certify the physical driving.

Comparison with Beta 1.61: same load (track day, multi-class, weather), 30,000 frames measured after warm-up, independent VMs, no profiler, each version measured by its own bench on the same machine. Both benches enable the same JIT compiler cache as the app in the game (since Beta 1.40; the `compilateur JIT` log line confirms that CSP accepts it).

| AI | Mean Beta 1.61 / Beta 1.62 (ms) | P99 Beta 1.61 / Beta 1.62 (ms) | Raw peak Beta 1.61 / Beta 1.62 (ms) |
|---|---|---|---|
| 9 | 0.078 / 0.091 | 0.484 / 0.521 | 2.520 / 2.437 |
| 30 | 0.378 / 0.485 | 0.770 / 0.822 | 2.214 / 33.660 |
| 60 | 1.288 / 1.267 | 2.121 / 1.916 | 5.321 / 25.067 |

Run-to-run variability (10 to 40%) forbids turning these figures into a guaranteed FPS gain. The separate benchmark and the one after the soak have different VM histories and are shown separately.

Integration also covers wet/dry compounds, pit stops, compensation without rain tyres and the priority of native rain handling. The real cost of CSP calls, the driving and the GPU/CPU FPS remain to be observed in the game. The native counter of the diagnostics includes the adapters but not the drawing of the windows.

Open criteria: Physical tests in the game and real CSP cost; Core mean cost <0.3 ms; Core raw peak <1 ms; Total bench memory variation <256 KiB.

The exact source hashes and the structured results are in `RELEASE_STATUS.json`.
