# CPU/GPU frame pacing: comparable before/after measurements

**Goal:** improve Cgame's renderer and Albion After without confusing CPU stalls
with GPU load or claiming gains from invented FPS figures.

## Design (Godot / Unity / Unreal lessons)

Unreal Insights, Unity Profiler and Godot's render diagnostics all separate
rendering workload from game-thread work. Albion After now records two
independent distributions during its existing screenshot-demo window:

- **CPU frame interval:** `SceneTree.get_process_delta_time()` in milliseconds;
  this includes scheduling, waits and game work. It is not a GPU timer.
- **GPU render duration:** native `RenderingServer.viewport_get_measured_render_time_gpu()`
  in milliseconds. The engine's existing GPU timestamp implementation is used,
  without new GPU readbacks or render passes. These timestamps may lag a frame,
  so their per-sample indices cannot be matched to CPU deltas.

Both use real sampled p50/p95/p99 durations. CPU **1% low FPS** is the reciprocal
of the *mean duration of the slowest ceil(1% of frames)*, not `1000/p99`.
A single 100ms hitch in 100 frames therefore correctly yields 10 FPS 1% low
even if interpolated p99 is close to 11ms.

## Capture

Run the same screenshot demo with fixed camera, resolution, render preset,
hardware, and world conditions before and after the changes. Example:

```bash
# Start the appropriate local game/server as usual; use the identical args
# for both builds and save their stdout.
godot --path game -- --screenshot /tmp/scene.png --demo hub 2>&1 | tee before.log
# Repeat on the candidate binary -> after.log.
python tools/compare_frame_pacing.py before.log after.log
python -m unittest discover -s tools/tests -p 'test_compare_frame_pacing.py' -v
godot --headless --path game --script res://tests/run_graphics.gd
```

The demo prints human-readable CPU and GPU distributions and a machine
record beginning with `CGAME_FRAME_BENCHMARK `. The shared engine
`tools/compare_frame_pacing.py` reads the **last** such record in each log,
reports deltas, and refuses to compare distinct renderer backends. Optional
`--max-p95-regression-pct 10` enables a CI regression gate when at least 30
valid frames are measured per available stream.

GPU timestamps are enabled during screenshot capture on Forward+, even if
Auto quality is disabled. Other manual-quality runs keep timestamp capture off.
Compatibility/headless and unsupported GPU timers print **unavailable**, never
a fabricated GPU 1% low or GPU FPS.

## Validation boundaries

The Python comparison utility has standalone unit tests. The game GDScript
suite verifies sampling, serialization and the revised statistic formula.
Neither a headless smoke run nor a static regression test proves visual
quality or Apple M1 GPU performance. A built Cgame executable and fixed
Metal test scene are required for real, controlled before/after numbers.
The tool does not auto-assert improved FPS, visual fidelity or frame pacing.
