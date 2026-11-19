# Cgame whole-engine stress and performance regression suite

Independent, reproducible workloads for CPU, script execution, object lifetime,
allocation churn, scene-tree mutations, physics, IO, data codecs, threads and
render-node throughput. A Python watchdog samples *process resident RAM* and
kills each isolated scenario on timeout or RSS overrun. Godot also emits its own
static-memory monitor measurements (which **are not** equivalent to process RSS).

## Quick start

Build the current Cgame/Godot branch (a normal editor binary is sufficient;
for native C++ test suites compile with `tests=yes`), then run:

```bash
python3 -m unittest discover -s tests/stress -p 'test_*.py' -v
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 --preset smoke --output out/stress-smoke.json
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 --preset standard --output out/stress-standard.json

# Long soak: repeated allocations and frame processing.
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 --preset soak --output out/stress-soak.json

# EXPLICITLY opt-in: very high CPU/RAM/physics pressure; run on an isolated host.
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 --preset brutal --output out/stress-brutal.json
```

To run specific workloads:

```bash
python3 tests/stress/run.py --godot /path/to/godot --case containers,scene_tree,threads --repeats 10 --scale 16 --timeout 600 --rss-limit-mib 4096 --output out/selected.json

# Real 2D/3D renderer requires a display; never interpret headless dummy-server
# output as a GPU benchmark. Use an actual GPU host for useful measurements.
python3 tests/stress/run.py --godot /path/to/godot --render-mode display --case render_2d,render_3d --preset standard --output out/render.json

# Compare with a baseline captured on identical hardware, build and settings.
python3 tests/stress/run.py --godot /path/to/godot --preset standard --baseline out/baseline.json --max-regression-pct 10 --output out/current.json

# Optional heuristic for post-warm-up retained allocator memory in memory_churn.
python3 tests/stress/run.py --godot /path/to/godot --case memory_churn --max-retained-growth-mib 64 --output out/memory.json

# Find the first failing or resource-limited scale. Each scale starts in a
# NEW engine process, and escalation stops at the first failed scale.
python3 tests/stress/run.py --godot /path/to/godot --case scene_reparent,thread_contention,compression --preset standard --scale 2 --ramp --ramp-steps 6 --ramp-factor 2 --output out/ramp.json
```

Run `--list-cases` for supported identifiers.

| Area | Case | Loads applied |
| --- | --- | --- |
| Containers | `containers` | Typed Array, Dictionary, random indexed reads, large allocations |
| GDScript | `script_vm`, `strings`, `math` | Interpreter loops, typed indexing, string operations, Vector3 math |
| Events, scene | `signals`, `scene_tree`, `packed_scene` | Emission, Node creation/query/grouping/free, scene pack/instantiate |
| Data and IO | `images`, `json`, `stream`, `file_io` | Image buffers, JSON roundtrip, binary StreamPeer, real filesystem writes |
| Parallelism | `threads`, `thread_contention` | N worker threads, plus shared-counter mutex contention and lost-update validation |
| Navigation | `astar_grid`, `astar_3d` | Repeated 2D grid and 3D graph paths with endpoint validation |
| Animation | `tweens` | Large numbers of repeatedly moving, node-bound Tween tracks |
| Audio | `audio_buffers` | High-volume 16-bit WAV sample buffer construction (not live mixing) |
| Serialization | `variant_codec` | Lossless Variant binary serialization and deserialization |
| Physics | `physics_2d`, `physics_3d` | Rigid bodies/collision shapes and physics frames |
| Allocator | `memory_churn` | Multiple cycles of ephemeral PackedByteArray allocations |
| Rendering | `render_2d`, `render_3d`, `render_multimesh` | Shared texture/mesh, high instance counts and frame pumping (display only) |
| Dynamic scene lifetime | `scene_reparent` | Thousands of nodes moved between parents with ownership checks |
| Storage and resource codecs | `resource_roundtrip`, `compression` | Repeated resource save/load without cache, plus Zstandard compression checks |
| Text pattern matching | `regex` | Thousands of compiled-expression searches and result validation |
| Direct physics queries | `physics_queries_2d` | High-volume raycasts against a known collider while physics advances |

## Presets and safety

| Preset | Scale | Physics/render frames | Repeats per case | Per-process timeout | RSS cap |
| --- | ---: | ---: | ---: | ---: | ---: |
| smoke | 1 | 12 | 1 | 90 s | 2 GiB |
| standard | 4 | 90 | 3 | 240 s | 4 GiB |
| soak | 12 | 600 | 5 | 900 s | 6 GiB |
| brutal | 50 | 3600 | 10 | 1800 s | 8 GiB |

Timeout and RSS caps are per workload process. These are *failure containment*,
not a promise that your host cannot run out of memory: RSS is sampled, and very
short-lived spikes can be missed. The host also needs RAM for the OS and drivers.
No workload deletes or modifies project source files; `file_io` only writes and
deletes its own test file in the project's `user://` data directory.

`all` omits render cases in headless mode. Headless rendering uses a dummy
server: physics and object allocation remain useful, GPU performance does not.
Use a dedicated GPU runner with a real display for rendering conclusions.
Virtual displays with software rendering are valid only for software-GL baselines.

## Reports and regression interpretation

The JSON report includes per-case runs, wall time, CPU seconds, p95, maximum
sampled child RSS, post-warm-up RSS change, engine-reported time, p50/p95/p99
sampled frame/physics latencies, physics spikes, collision pairs,
draw calls, VRAM and memory, failure reason (crash/timeout/RSS/invalid
result), platform and configuration. The `rankings` section sorts the heaviest
passing cases by each measured metric; these are triage indicators, **not** a
comparison of normalized workload throughput. The optional `--ramp` mode uses
case names such as `compression@8` in the report for each tested scale. Use fixed workloads, hardware, build flags,
GPU driver, render mode, and thermal settings for meaningful comparisons.
Baseline checks fail when median wall time or max RSS grow beyond the configured
percentage; transient noise warrants repeated measurements. Leak detection via
`memory_churn` is an **allocator-retention heuristic**, not a proof of a leak:
allocators and caches legitimately retain pages.

CI validates the Python harness on every change to this directory. A scheduled
smoke run and opt-in manual workflow compile **this fork** and execute actual
engine workloads. The `brutal` preset is **never scheduled automatically**.
For full security/memory investigations, independently run C++ unit tests,
ASan/UBSan/TSan builds, Valgrind/heap profiling, long-lived multiplayer sessions,
real device GPU/mobile profiling, shader import/export projects, and fuzzing.
No finite synthetic suite can cover every engine feature or prove absence of
optimization bugs.


## Interpreting limits and heavy runs

- `--ramp` is opt-in and capped at a scale of 1000. The first failing scale
  terminates escalation **for that case**, but the run continues with the next
  selected case. A timeout, crash, invalid result or watchdog RSS limit is
  recorded as a failure and the run exits nonzero.
- `max_post_warmup_rss_growth_mib` measures sampled process RSS change from
  the first sample after 20% of the run to the last sample. Positive change
  flags a candidate for heap profiling; it is **not** definitive leak evidence.
  Scenario startup and operating-system page retention can create false positives.
- `frame_latency_ms` and `physics_latency_ms` contain p50, p95, p99 and
  maximum **engine Performance-monitor samples**, not GPU profiler timestamps.
  Use engine and GPU profilers for root cause analysis.
- On Linux/macOS, timed-out jobs are placed in their own process group so that
  subprocesses spawned by a test do not outlive the watchdog. Run brutal mode
  only on a dedicated machine; all limits apply per child and heavy suites may
  run for hours.
