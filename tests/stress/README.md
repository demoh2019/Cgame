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
```

Run `--list-cases` for supported identifiers.

| Area | Case | Loads applied |
| --- | --- | --- |
| Containers | `containers` | Typed Array, Dictionary, random indexed reads, large allocations |
| GDScript | `script_vm`, `strings`, `math` | Interpreter loops, typed indexing, string operations, Vector3 math |
| Events, scene | `signals`, `scene_tree`, `packed_scene` | Emission, Node creation/query/grouping/free, scene pack/instantiate |
| Data and IO | `images`, `json`, `stream`, `file_io` | Image buffers, JSON roundtrip, binary StreamPeer, real filesystem writes |
| Parallelism | `threads` | N native worker threads with independently repeatable numeric work |
| Navigation | `astar_grid` | Repeated 64×64 A* paths around obstacles, path validity checks |
| Animation | `tweens` | Large numbers of repeatedly moving, node-bound Tween tracks |
| Audio | `audio_buffers` | High-volume 16-bit WAV sample buffer construction (not live mixing) |
| Serialization | `variant_codec` | Lossless Variant binary serialization and deserialization |
| Physics | `physics_2d`, `physics_3d` | Rigid bodies/collision shapes and physics frames |
| Allocator | `memory_churn` | Multiple cycles of ephemeral PackedByteArray allocations |
| Rendering | `render_2d`, `render_3d` | Shared texture/mesh, many draw nodes, frame pumping (display only) |
| Resource loading | `resource_load` | PackedScene save/load with cache bypass, verified contents and cleanup |
| Input registry | `input_map` | Repeated InputMap action add/match/erase operations |
| Transform propagation | `transform_hierarchy` | Dense Node3D hierarchy with global transform invalidation and reads |
| Geometry / meshes | `geometry_2d`, `mesh_build` | Convex hulls, triangulation and SurfaceTool mesh construction |
| Input / scene groups | `input_dispatch`, `group_calls` | Dispatch input actions and bulk group method calls |
| Image codec | `image_codec` | Repeated PNG encode/decode and size validation |

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
No workload deletes or modifies project source files; IO workloads write and
remove only their generated files in the project's `user://` data directory.

`all` omits render cases in headless mode. Headless rendering uses a dummy
server: physics and object allocation remain useful, GPU performance does not.
Use a dedicated GPU runner with a real display for rendering conclusions.
Virtual displays with software rendering are valid only for software-GL baselines.

## Reports and regression interpretation

The JSON report includes per-case runs, wall time, CPU seconds, p95, maximum
sampled child RSS, engine-reported time, physics spikes, collision pairs,
draw calls, VRAM and memory, failure reason (crash/timeout/RSS/invalid
result), platform and configuration. Use fixed workloads, hardware, build flags,
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

## Extended bottleneck diagnostics

The stress suite now includes eight additional integrity-checked cases:

| Area | Case | Stress dimension |
| --- | --- | --- |
| Scene lookup | `node_paths` | Repeated cached NodePath lookups in a wide tree; reports lookup-only time |
| Pattern matching | `regex` | Many regular-expression searches with verified match counts |
| Data compression | `compression` | Zstandard compress/decompress roundtrips with byte-for-byte validation |
| Cryptography | `hashing` | Repeated SHA-256 contexts with deterministic digest checks |
| Resource serialization | `resource_io` | Repeated native .tres save/load using cache bypass and cleanup |
| 3D navigation | `astar_3d` | Graph construction and repeated 3D shortest-path searches |
| UI/layout | `ui_layout` | Hundreds of Controls, forced layout passes and process-frame profiling |
| Synchronization | `thread_contention` | Eight or fewer threads contending on a Mutex with a checked shared counter |

Write a ranked Markdown report alongside the full JSON diagnostics:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 --preset standard --summary-md out/hotspots.md --output out/stress.json
```

The report sorts workloads by elapsed wall time and flags high p95/median
variability, RSS nearing its limit, and process overhead relative to engine time.
It also records median and p95 **in-engine duration** independently of process
startup, and baseline comparisons now track median engine time. These rankings
are a triage aid, not a universal throughput leaderboard: scenarios do different
amounts of work. Native CI archives both JSON and Markdown artifacts.

## Nonlinear scaling sweeps (opt-in)

For the same case and same machine, comparing progressively larger workloads
reveals more than a single slow run. Each scale/repeat runs in its **own process**
under the same timeout and RSS watchdog as the normal suite. The sweep
separately calculates median engine time, wall time and process RSS.

```bash
python3 tests/stress/scale_sweep.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case containers,node_paths,compression,astar_3d,physics_2d,physics_3d \
  --scales 1,2,4,8,16 --frames 90 --repeats 5 \
  --timeout 600 --rss-limit-mib 6144 \
  --output out/scale-sweep.json --summary-md out/scale-sweep.md
```

To run every available headless case use `--case all`; display workloads
require `--render-mode display` on a GPU-capable host. A sweep is **not**
scheduled in CI: large input sizes can saturate a shared runner. The generated
Markdown report ranks the estimated engine-time scaling exponent and flags
high timing variance and accelerating RSS. An exponent above 1 suggests
nonlinear growth in this particular test workload, **not** necessarily an
O(n²) implementation. CPU affinity, import caches, driver and memory limits
must be controlled for trustworthy comparisons. In particular, RSS acceleration
is not proof of a leak.

## Cross-metric bottleneck diagnosis

The standard --summary-md summary ranks wall time and flags high variance.
For additional **independent** engine-time, memory, frame-spike rankings and
per-case baseline deltas, use:

```bash
python3 tests/stress/diagnose.py out/stress.json --top 15 --output out/bottlenecks.md
python3 tests/stress/diagnose.py out/current.json --baseline out/baseline.json --output out/regressions.md
```

Both report formats are diagnostic aids, not absolute cross-subsystem efficiency
rankings. Compare each scenario against its own baseline with matching workload
settings, hardware and graphics driver. Investigate recurring bottlenecks using
a CPU sampling profiler, heap profiler or GPU capture.
