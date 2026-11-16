# Release measurements

Released version: Beta 2.0.3. All strict PDR criteria accepted: **no**, open points below. These results are not a guarantee of in-game FPS.

- Catalogue and checks: **1494/1494**, including the 78 PDR situations and the 10,000-step fuzz.
- Integration: **190 cases**, status True.
- Linter: 72 files, status True.
- Soak: 1,728,000 frames, 8 simulated hours, 40 AI, 0 errors.
- Memory after collection: 16287.6 to 18686.1 KiB; drift 2398.5 KiB after the bench warm-up phase.
- Strict bench memory criterion (<256 KiB over the whole window): **False**. Drift during the last hour: **30.6 KiB**. The total variation is kept even when the last hour is more stable.
- Core at 30 AI: mean **0.318 ms**, P99 **0.541 ms**, raw maximum **1.302 ms** over 30,000 frames.
- Mean <0.3 ms: **False**. Maximum <1 ms: **False**.

The maximum is not filtered. This benchmark includes neither the real SDK nor the UI. The kinematic tests do not certify the physical driving.

Comparison with Beta 2.0.2: same load (track day, multi-class, weather), 30,000 frames measured after warm-up, independent VMs, no profiler, each version measured by its own bench on the same machine. Both benches enable the same JIT compiler cache as the app in the game (since Beta 1.40; the `compilateur JIT` log line confirms that CSP accepts it).

| AI | Mean Beta 2.0.2 / Beta 2.0.3 (ms) | P99 Beta 2.0.2 / Beta 2.0.3 (ms) | Raw peak Beta 2.0.2 / Beta 2.0.3 (ms) |
|---|---|---|---|
| 9 | 0.090 / 0.093 | 0.383 / 0.423 | 1.994 / 2.302 |
| 30 | 0.453 / 0.439 | 0.668 / 0.670 | 1.557 / 1.496 |
| 60 | 1.251 / 1.296 | 1.771 / 1.833 | 3.073 / 6.869 |

Run-to-run variability (10 to 40%) forbids turning these figures into a guaranteed FPS gain. The separate benchmark and the one after the soak have different VM histories and are shown separately.

Integration also covers wet/dry compounds, pit stops, compensation without rain tyres and the priority of native rain handling. The real cost of CSP calls, the driving and the GPU/CPU FPS remain to be observed in the game. The native counter of the diagnostics includes the adapters but not the drawing of the windows.

Open criteria: Physical tests in the game and real CSP cost; Core mean cost <0.3 ms; Core raw peak <1 ms; Total bench memory variation <256 KiB.

The exact source hashes and the structured results are in `RELEASE_STATUS.json`.
