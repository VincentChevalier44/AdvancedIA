# Release measurements

Released version: Beta 1.52. All strict PDR criteria accepted: **no**, open points below. These results are not a guarantee of in-game FPS.

- Catalogue and checks: **695/695**, including the 78 PDR situations and the 10,000-step fuzz.
- Integration: **136 cases**, status True.
- Linter: 48 files, status True.
- Soak: 1,728,000 frames, 8 simulated hours, 40 AI, 0 errors.
- Memory after collection: 7461.6 to 8308.5 KiB; drift 847.0 KiB after the bench warm-up phase.
- Strict bench memory criterion (<256 KiB over the whole window): **False**. Drift during the last hour: **13.0 KiB**. The total variation is kept even when the last hour is more stable.
- Core at 30 AI: mean **0.213 ms**, P99 **0.548 ms**, raw maximum **5.318 ms** over 30,000 frames.
- Mean <0.3 ms: **True**. Maximum <1 ms: **False**.

The maximum is not filtered. This benchmark includes neither the real SDK nor the UI. The kinematic tests do not certify the physical driving.

Comparison with Beta 1.50: same load (track day, multi-class, weather), 30,000 frames measured after warm-up, independent VMs, no profiler, each version measured by its own bench on the same machine. Both benches enable the same JIT compiler cache as the app in the game (since Beta 1.40; the `compilateur JIT` log line confirms that CSP accepts it).

| AI | Mean Beta 1.50 / Beta 1.52 (ms) | P99 Beta 1.50 / Beta 1.52 (ms) | Raw peak Beta 1.50 / Beta 1.52 (ms) |
|---|---|---|---|
| 9 | 0.070 / 0.073 | 0.146 / 0.194 | 0.365 / 3.353 |
| 30 | 0.317 / 0.326 | 0.579 / 0.721 | 1.185 / 4.672 |
| 60 | 0.766 / 0.861 | 1.219 / 2.008 | 3.172 / 10.504 |

Run-to-run variability (10 to 40%) forbids turning these figures into a guaranteed FPS gain. The separate benchmark and the one after the soak have different VM histories and are shown separately.

Integration also covers wet/dry compounds, pit stops, compensation without rain tyres and the priority of native rain handling. The real cost of CSP calls, the driving and the GPU/CPU FPS remain to be observed in the game. The native counter of the diagnostics includes the adapters but not the drawing of the windows.

Open criteria: Physical tests in the game and real CSP cost; Core raw peak <1 ms; Total bench memory variation <256 KiB.

The exact source hashes and the structured results are in `RELEASE_STATUS.json`.
