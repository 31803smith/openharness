# Native Release interaction benchmark

**Handoff status, September 13, 2026:** this previously untracked fixture is saved
for continuation, not a validated measurement result. Before building/running,
update the old `Harness V2` product-name replacement in `prepare.py`, the process
name check in `run.py`, and the initial native responder selection. See the
[handoff](../../../docs/harness-v2-handoff.md) and
[failed calibration notes](../../../docs/harness-v2-performance.md#native-calibration-remains-unmeasured-2026-09-13).
Keep isolation and foreground/key-window guards intact; no p50/p95/p99 result
has been accepted.

This macOS fixture measures AppKit-queued input through the production Swarm
screen, terminal session parser and Flutter renderer. It runs as **Harness
Benchmark**, in an isolated copy with its own bundle ID, synthetic transports,
blocked HTTP and temporary state. It never reads the user's saved Swarms or sends
input to an agent. The benchmark bridge is appended only to the copied native
host; it is absent from the production Runner and V2 bundle.

From `desktop/`, build with a compatible Flutter SDK and Xcode:

```sh
python3 tool/native_benchmark/prepare.py --flutter /path/to/flutter
```

Use the `BENCHMARK_APP` path printed by the build. Normally close V2 and finish
other builds/tests first. Keep this fixture in the foreground during a run; it
exits on focus loss instead of reclaiming focus between observations. The runner
refuses to start alongside another V2 or benchmark process and never quits them.

```sh
python3 tool/native_benchmark/run.py \
  --app '/private/tmp/harness-native-benchmark-EXAMPLE/desktop/build/macos/Build/Products/Release/Harness Benchmark.app' \
  --terminals 16 --samples 120 \
  --output /private/tmp/harness-native-16.json
```

Repeat with `--terminals 48` and a fresh output path. Use `--samples 3` only for
calibration, not percentile claims. The fixture closes itself normally when it
finishes; reopen V2 afterward. Launch through `run.py`, which uses Launch Services
and supplies the required environment. Opening the fixture without that
environment fails immediately.

## Workload and timing boundary

- A 1280 × 800 content area, four visible terminals, 16 or 48 retained sessions,
  and 1,000 initial scrollback rows each. Every Swarm is visited before warming.
- Typing posts `x` through AppKit and echoes it through the production binary
  output handler with zero simulated network RTT. The exact destination session
  and input count are checked. Focus uses Cmd+1…4; tabs use Cmd+Shift+].
- One cold interaction per operation, then 20 warmups and the requested measured
  observations for each operation, both idle and with output to every terminal
  at 20 Hz. Each burst repaints eight rows with ANSI cursor save/restore. Reported
  byte counts, phase duration and skipped bursts expose the achieved output load.
- Input is posted only to this fixture's own `NSApplication` queue and window.
  Both aggregate and device-side modifier flags, with press/release events, match
  AppKit's keyboard representation. Initial content focus is established once;
  subsequent navigation must perform its own focus handoff.
- The first post-frame callback after the expected state/output change captures
  the engine's frame number. It joins that exact ID to `FrameTiming`, including
  its wall-clock raster-finish timestamp. Results retain every sample, including
  warmup and cold observations, and summarize p50/p95/p99/max in milliseconds.
- The fixture uses the real layout file store in a fresh temporary directory.
  Normal discovery, networking, telemetry and background services are disabled.

**These are native event-queue-to-Flutter-raster timings**, not physical
keyboard-to-photon measurements. They exclude device scanning, real transport
and agent response time, GPU/display presentation, and the completion of separate
AppKit titlebar drawing. The configured display maximum is recorded; it does not
establish a fixed refresh rate. This does not measure app startup, IME, paste,
scrolling, reconnect, or every output pattern. Preserve slower runs and report
the machine, build revision, host load and sampling limits with results.
