# Release measurements

Released version: Beta 2.0.4. All strict PDR criteria accepted: **no**, open points below. These results are not a guarantee of in-game FPS.

- Catalogue and checks: **1552/1552**, including the 78 PDR situations and the 10,000-step fuzz.
- Integration: **193 cases**, status True.
- Linter: 73 files, status True.
- Soak: 1,728,000 frames, 8 simulated hours, 40 AI, 0 errors.
- Memory after collection: 9049.5 to 19452.9 KiB; drift 10403.4 KiB after the bench warm-up phase.
- Strict bench memory criterion (<256 KiB over the whole window): **False**. Drift during the last hour: **208.4 KiB**. The total variation is kept even when the last hour is more stable.
- Core at 30 AI: mean **0.587 ms**, P99 **1.003 ms**, raw maximum **10.374 ms** over 30,000 frames.
- Mean <0.3 ms: **False**. Maximum <1 ms: **False**.

The maximum is not filtered. This benchmark includes neither the real SDK nor the UI. The kinematic tests do not certify the physical driving.

Comparison with Beta 2.0.3: same load (track day, multi-class, weather), 30,000 frames measured after warm-up, independent VMs, no profiler, each version measured by its own bench on the same machine. Both benches enable the same JIT compiler cache as the app in the game (since Beta 1.40; the `compilateur JIT` log line confirms that CSP accepts it).

| AI | Mean Beta 2.0.3 / Beta 2.0.4 (ms) | P99 Beta 2.0.3 / Beta 2.0.4 (ms) | Raw peak Beta 2.0.3 / Beta 2.0.4 (ms) |
|---|---|---|---|
| 9 | 0.093 / 0.123 | 0.423 / 0.378 | 2.302 / 2.103 |
| 30 | 0.439 / 0.640 | 0.670 / 1.045 | 1.496 / 6.722 |
| 60 | 1.296 / 1.531 | 1.833 / 2.347 | 6.869 / 4.286 |

Run-to-run variability (10 to 40%) forbids turning these figures into a guaranteed FPS gain. The separate benchmark and the one after the soak have different VM histories and are shown separately.

Integration also covers wet/dry compounds, pit stops, compensation without rain tyres and the priority of native rain handling. The real cost of CSP calls, the driving and the GPU/CPU FPS remain to be observed in the game. The native counter of the diagnostics includes the adapters but not the drawing of the windows.

Open criteria: Physical tests in the game and real CSP cost; Core mean cost <0.3 ms; Core raw peak <1 ms; Total bench memory variation <256 KiB.

The exact source hashes and the structured results are in `RELEASE_STATUS.json`.
