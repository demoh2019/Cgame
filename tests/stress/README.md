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

For reproducible CPU profiling of 2D hierarchy invalidation and native process
dispatch (two separate processes under the runner's RSS/time watchdogs):

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case canvas_transform_2d,process_dispatch --scale 4 \
  --repeats 7 --frames 90 --rss-limit-mib 4096 --output out/canvas-process.json
```

The `canvas_transform_2d` scenario separates time spent invalidating a wide
subtree from the subsequent cost of rebuilding descendants' global transforms.
The `process_dispatch` scenario measures frame processing overhead with
native Nodes (rather than scripted callbacks) and reports process and physics
monitors. Timings must be compared on identical hardware, engine configuration
and load; headless runs are **not** GPU benchmarks.

Profile curve changes with repeatable workloads on the same CPU and engine build:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case curve_bake,curve_nearest --scale 8 --repeats 7 \
  --rss-limit-mib 4096 --output out/curves.json
```

The scenarios separately report `bake_ms`, `sample_ms`,
`closest_point_ms`, `closest_offset_ms`, and `sample_baked_ms`.
These measure CPU code, not the GPU. Compare against baseline medians from
identical hardware; checksum and baked-point counts help spot semantic drift.

### Curve tessellation CPU/RAM scaling

The headless `curve_tessellation_2d` and `curve_tessellation_3d` workloads measure
`construction_ms`, `adaptive_ms`, `even_ms` and `bake_ms`
separately, and validate control points and closed-path endpoints. Compare
before/after runs on identical hardware to quantify the impact of the
contiguous subdivision buffers and cached Bezier endpoints.

```bash
python3 tests/stress/scale_sweep.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case curve_tessellation_2d,curve_tessellation_3d \
  --scales 1,2,4,8,16 --repeats 5 --frames 90 \
  --output out/curve-scale.json --summary-md out/curve-scale.md
```


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
| Packet framing | `packet_stream` | StreamPeerBuffer/PacketPeerStream ring-buffer transfers at variable sizes |
| UI layout | `ui_layout` | Repeated GridContainer relayout with hundreds to thousands of Buttons |
| Physics | `physics_2d`, `physics_3d` | Rigid bodies/collision shapes and physics frames |
| Allocator | `memory_churn` | Multiple cycles of ephemeral PackedByteArray allocations |
| Rendering | `render_2d`, `render_3d` | Shared texture/mesh, many draw nodes, frame pumping (display only) |
| Geometry / meshes | `geometry_2d`, `mesh_build` | Convex hulls, triangulation and SurfaceTool mesh construction |
| Input / scene groups | `input_dispatch`, `group_calls` | Dispatch input actions and bulk group method calls |
| Image codec | `image_codec` | Repeated PNG encode/decode and size validation |
| Curve baking | `curve_bake` | 1000-sample rebakes after edits, cached interpolation across hundreds of control points |
| Path projection | `curve_nearest` | Curve2D/3D closest-point and offset searches plus baked-distance sampling with separate timings |
| 2D transform propagation | `canvas_transform_2d` | Wide CanvasItem subtree; separate parent transform mutation and descendant global-transform rebuild times |
| SceneTree notification dispatch | `process_dispatch` | Thousands of native Nodes with mixed ordinary/internal process flags and frame/physics time monitors |

## GodotPhysics persistent-contact memory layout

The built-in 2D/3D pair contact structs no longer retain an unused world
position. The 3D contact struct also no longer stores the unused feature-A
index (feature-B is still required to identify soft-body nodes).

An isolated C++ float-layout comparison, using the same field order and
primitive sizes (not the full Godot engine), estimates **16 bytes saved per
2D pair** (2 contacts) and **64 bytes saved per 3D pair** (4 contacts).
The actual saving depends on target alignment, `real_t` precision, active
pair counts and allocator behavior, so confirm engine RSS with paired runs:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_contact_manifolds_2d,physics_3d \
  --scale 8 --repeats 5 --frames 120 --rss-limit-mib 6144 \
  --output out/contact-layout.json
```

Compare the peak process RSS and actual collision-pair counts to a baseline
from the same host. Pair structs only become a major saving when many pairs
are alive; isolated bodies do not allocate one.

## Sparse constraint-island scheduling (2D and 3D)

After per-island `pre_solve`, the built-in GodotPhysics scheduler skips islands
whose remaining constraint lists are empty. Area monitoring constraints always
return `false` from `pre_solve` after emitting notifications, so this removes
worker-group overhead in sensor-dense scenes without dropping enter/exit events.
A compact index list is allocated only if at least 32 islands and at
least one quarter of all islands are empty; smaller sparse cases retain direct
indexing to avoid allocation and per-task indirection. If no islands remain,
solver dispatch is skipped unconditionally.

Run the headless 2D+3D area-only regression with built-in GodotPhysics enabled:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_sensor_island_regression.gd
```

This test creates independent sensor/body pairs and checks all enter and exit
notifications; it is a correctness test, **not** a performance measurement.
For speed/RSS comparisons capture before/after runs using the runner's
`physics_sparse_2d`, `physics_sparse_3d` and
`physics_contact_manifolds_2d` workloads on the same host.

## Configurable material friction mixing (Box2D-style)

GodotPhysics previously always combined the two contacting bodies' friction as
`abs(min(friction_a, friction_b))`. Projects can now opt into other material
combination rules with `physics/2d/solver/friction_combine_mode` and
`physics/3d/solver/friction_combine_mode`:

| Value | Mode | Example: 0.25 vs. 1.0 |
| ---: | --- | ---: |
| 0 | Legacy Minimum (default, backwards compatible) | 0.25 |
| 1 | Geometric Mean (Box2D-style) | 0.5 |
| 2 | Average | 0.625 |
| 3 | Maximum | 1.0 |

For the opt-in modes, coefficients are converted to non-negative magnitudes
before mixing. The 0 mode retains the historical GodotPhysics behavior,
including its treatment of negative material friction. Both backends read
this setting **once when a new physics space is created**. Changes to this
setting do not update already created spaces or third-party physics backends.

Mixed friction is calculated once per rigid-body contact pair's pre-solve pass,
not repeatedly on every solver iteration. A frictionless pair retains the
existing fast path with tangential impulses disabled.

The separate low-level regression compares three isolated worlds (legacy,
geometric mean, and geometric mean with one frictionless material). All worlds
use the same sliding-body geometry:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress --script res://physics_friction_mix_regression.gd
```

It asserts that the geometric mean slows sliding more than legacy mixing,
while mixing with zero still produces a frictionless contact. Run with
**built-in GodotPhysics**
selected. The script restores the original ProjectSettings value and frees all
RIDs. This regression checks one geometry and material combination; it is not
a complete friction or determinism proof.

For contact throughput and numerical-stability measurements across large
manifolds, compare the existing `physics_contacts_friction_2d`,
`physics_contact_manifolds_2d`, and `physics_3d` stress cases with the same
hardware and engine build.

## Rigid/soft 3D contact throughput and stability

The built-in GodotPhysics rigid/soft contact solver now skips expensive
tangent-velocity and inertia calculations when friction is zero, while
preserving normal collision impulses. It also guards singular normal and
tangent effective masses, discards stale tangential warm-start impulses after
the friction material changes to zero, and projects retained tangent impulses
into the new contact plane when a soft surface rotates. Both 3D rigid/rigid and
rigid/soft friction solvers check squared tangential speed before taking a
square root, skipping it for stationary or nearly stationary contacts.

For persisted rigid/soft contacts, warm-start impulses follow the same
time-step ratio and `physics/3d/solver/warm_start_coefficient` policy as
rigid/rigid contacts. Cached tangent impulses are clamped to the current
material's friction cone.

Use the new **two 3D stress cases** for before/after throughput and
numerical-stability comparisons. Each creates 16 soft spheres and 16 rigid
spheres per scale, in isolated lanes, with otherwise identical geometry:

```bash
python3 tests/stress/run.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_soft_contacts_zero_friction_3d,physics_soft_contacts_friction_3d \
  --scale 1 --frames 120 --repeats 3 --timeout 360 \
  --output out/soft-contacts-3d.json
```

The benchmarks report physics time, frame intervals, and collision pairs,
and fail if no pairs are generated or sampled body states become non-finite.
Use the built-in GodotPhysics 3D backend; another backend does not exercise
this solver. Benchmark identical builds on the same machine, and separate
sparse-body tests from expensive soft contact workloads. These new cases do
not constitute a completed performance measurement until run.

## Contact restitution stability (Jolt / Box2D-style threshold)

Built-in GodotPhysics now suppresses contact restitution when the approaching
speed along the contact normal is below a configurable per-space cutoff:

- `physics/2d/solver/restitution_velocity_threshold`: default **30 px/s**
- `physics/3d/solver/restitution_velocity_threshold`: default **1 m/s**

Setting the cutoff to `0` disables low-speed suppression. These settings are
read when a GodotPhysics space is created; they do not affect third-party
physics backends and do not retroactively change existing spaces. This changes
low-speed rebound behavior intentionally, while preserving higher-speed bounce.

The low-level `physics_restitution_2d` and `physics_restitution_3d` stress
cases check that two equal-mass, zero-gravity bodies settle after a slow
head-on impact, but rebound after a faster impact:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_restitution_2d,physics_restitution_3d \
  --scale 1 --frames 12 --repeats 3 --timeout 120 \
  --output out/restitution-regression.json
```

Run these with the built-in GodotPhysics server selected. Record results before
and after changes, and verify build/test status independently.

## Cached broadphase AABB: no-op update fast path (Box2D-style)

Built-in GodotPhysics 2D and 3D now check the previously submitted
`Shape::aabb_cache` before calling `BroadPhase::move`. When the exact
bounds have not changed, the physics collision object skips a redundant
BVH lookup and tree lock entirely. Creation of a new proxy, real transform
changes, shape resizing, and CCD swept-AABB changes still update the tree.

Box2D uses fat AABBs to avoid reinserting a proxy for small movements;
GodotPhysics already avoids some tree refits internally. This new early
guard avoids the *call itself* for identical proxies, without increasing
their bounds or changing collision filtering. Jolt's broadphase similarly
prioritizes incremental updates and static/dynamic separation. The gain
depends on how frequently client code repeats unchanged transforms.

Correctness regression: unchanged bounds must keep the object queryable,
while moving or resizing must invalidate and replace the cached proxy:

```bash
python3 -m unittest discover -s tests/stress -p 'test_physics_broadphase_aabb_cache.py' -v
./bin/godot.macos.editor.arm64 --headless --path tests/stress \
  --script res://physics_broadphase_aabb_cache_regression.gd
```

Benchmark identical-transform update throughput separately from object
creation. Compare each case with the **same case** on an older build and
identical hardware, not against a moving-body workload:

```bash
python3 tests/stress/run.py --godot ./bin/godot.macos.editor.arm64 \
  --case physics_proxy_same_aabb_2d,physics_proxy_same_aabb_3d \
  --scale 4 --frames 90 --repeats 5 --timeout 600 \
  --rss-limit-mib 4096 --output out/broadphase-same-aabb.json
```

A scale of 977 uses 1,000,448 static physics bodies **per scenario** and
must only be attempted on a dedicated, sufficiently provisioned host with
strict RSS and timeout limits. The workload returns `ns_per_update`,
`unchanged_transform_updates_ms`, `peak_physics_ms`, and frame p95.
A successful source inspection is not a substitute for runtime tests.

## Million-body sparse physics benchmark (opt-in)

`physics_rid_sparse_2d` and `physics_rid_sparse_3d` construct collision-shaped
rigid bodies directly in dedicated PhysicsServer spaces, avoiding SceneTree and
node-per-body costs. Each body is active (sleep disabled), gravity is zero, and
bodies are spaced far enough apart to avoid collisions. The scenarios separately
report creation, physics frame, and RID cleanup costs; the harness also records
peak process-tree RSS and enforces timeout/RSS limits.

For a manageable initial sample:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_rid_sparse_2d,physics_rid_sparse_3d \
  --scale 16 --frames 90 --repeats 5 \
  --output out/physics-rid-sparse.json
```

**Only on an isolated, sufficiently provisioned host:** scale 977 constructs
1,000,448 active rigid bodies in each case. The process can consume substantial
RAM and time. Use strict limits and compare runs on the same machine.

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_rid_sparse_2d,physics_rid_sparse_3d \
  --scale 977 --frames 30 --repeats 1 --timeout 1800 \
  --rss-limit-mib 8192 --output out/physics-million.json
```

To stress broadphase updates and velocity integration, run the matching
`physics_rid_moving_2d` and `physics_rid_moving_3d` cases. Every body gets
the same linear velocity so their relative separation remains unchanged,
avoiding collision-workload contamination of the movement benchmark:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_rid_moving_2d,physics_rid_moving_3d \
  --scale 16 --frames 90 --repeats 5 \
  --output out/physics-rid-moving.json
```

This isolates **sparse** solver and broadphase overhead. It does **not** imply
million-body real-time stability in densely colliding scenes, simulate any
fluid/material physics, or cover rendering. Run dense-contact and joint-chain
scenarios separately for numerical stability, tunneling and contact throughput.

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
No workload modifies project source files; IO workloads write and remove only
files they generate in the project's `user://` data directory.

`all` omits render cases in headless mode. Headless rendering uses a dummy
server: physics and object allocation remain useful, GPU performance does not.
Use a dedicated GPU runner with a real display for rendering conclusions.
Virtual displays with software rendering are valid only for software-GL baselines.

## Absolute performance budgets

When a baseline is unavailable, enforce explicit per-scenario limits:

```bash
python3 tests/stress/run.py --godot /path/to/godot \
  --preset standard --max-frame-ms 33.3 --max-physics-ms 20 \
  --max-vram-mib 2048 --rss-limit-mib 4096 \
  --output out/budget-gates.json
```

The frame and physics thresholds use engine `Performance` monitors for
scenarios that publish those metrics. They **do not** measure GPU render
latency or total presentation latency; use GPU vendor profilers for that.
An omitted metric is not treated as a pass against a corresponding budget:
it is *not measured* in that scenario. Hard RSS/time watchdogs apply to
every scenario independently, including ones without frame monitors.

## Synthetic editor import benchmark

Cold/warm resource imports have a separate entrypoint, because editor asset
loading cannot be measured reliably by an in-game GDScript scenario:

```bash
python3 tests/stress/editor_import.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --textures 128 --scenes 512 --repeats 3 --output out/import.json

# Heavier importer pressure; synthetic project is created in a temporary dir:
python3 tests/stress/editor_import.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --textures 1024 --scenes 4096 --repeats 5 --timeout 1200 \
  --rss-limit-mib 8192 --output out/import-brutal.json
```

The generator uses pure Python/stdlib to create reproducible PNG images,
Godot scenes and scripts. The importer is a real Godot process and the
watchdog records process CPU, resident memory, and cold/warm elapsed times.
Run on an isolated machine for heavy presets. It does not alter source files.

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

## Additional coverage: tracked hot paths

| Scenario | Bottleneck under pressure |
| --- | --- |
| `packed_arrays` | Native typed float arrays and byte conversion |
| `sorting` | Array sort followed by many binary-search lookups |
| `animation_tracks` | AnimationPlayer timeline seeks and Node property updates |
| `physics_raycast_2d`, `physics_raycast_3d` | PhysicsServer direct-space queries against static colliders |
| `render_multimesh_3d` | GPU instancing and frame sampling (display mode only) |

The physics query timer isolates ray traversal; overall duration also includes
collider construction and cleanup. Compare like-for-like workloads on the same
hardware using `--baseline`. Use `--summary-md` to rank expensive runs, while
remembering that raw time across different cases is not a normalized benchmark.

## Cross-metric bottleneck diagnosis

New cases: `resource_load` benchmarks cache-bypassed PackedScene reads,
`input_map` exercises input action registration/lookup/removal, and
`transform_hierarchy` stresses 3D transform propagation.

The built-in `--summary-md` provides a compact overview; the separate
diagnostic script ranks engine time, peak RSS and frame spikes independently,
and highlights per-case changes relative to a compatible baseline:

```bash
python3 tests/stress/diagnose.py out/stress.json --top 15 --output out/bottlenecks.md
python3 tests/stress/diagnose.py out/current.json --baseline out/baseline.json --output out/regressions.md
```

Do not compare raw timings of different scenarios as if they performed equal
work. Compare the *same* workload on the same host, with matching build,
graphics driver, seed and resource limits, then profile recurring regressions.

## Dense 2D A* graph stress

`astar_graph` covers point-graph construction and repeated checked shortest-path
queries on a connected 32x32 AStar2D grid, complementing the existing
`astar_grid` and `astar_3d` workloads. Sweep this case using
`tests/stress/scale_sweep.py --case astar_graph --scales 1,2,4,8`.

## Scale sweep: detect superlinear paths

Run the same isolated engine workload at increasing sizes, compute the
median log-log time-growth exponent and inspect resident-memory growth:

```bash
python3 tests/stress/scaling.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case containers,script_vm,animation_tracks,physics_raycast_3d \
  --scales 1,2,4,8 --repeats 3 --output-dir out/scaling

# Optional failure threshold for sufficiently long (>50 ms) engine workloads:
python3 tests/stress/scaling.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case all --scales 1,4,12,50 --flag-exponent 1.6 \
  --rss-limit-mib 8192 --timeout 1200 --output-dir out/large-sweep
```

Inspect `sweep.md`, `sweep.json` and `scale_<n>.json` for per-scenario
results. High exponents can indicate unexpectedly expensive algorithms, but
are not proof of an optimization defect: each stress case has a different
amount of fixed setup work, and tiny timings are excluded to reduce noise.
All engine runs still use the existing per-process RSS and timeout watchdogs.
Avoid sweeping display-only tests on dummy or software-rendered GPU backends
when measuring target-hardware graphics performance.

## Reliable macOS RSS sampling

On macOS without `psutil`, the active process-tree watchdog uses one
`ps -axo pid=,ppid=,rss=,time=` snapshot to aggregate RAM and CPU for Godot
and its child processes (RSS is reported by BSD ps in KiB). The preferred low-overhead path for
long stress runs is to install `psutil`:

```bash
python3 -m pip install psutil
```

Any case still running after one second with **no obtainable RSS samples**
fails as `rss_monitor_unavailable` instead of silently pretending the
RSS limit was enforced. On very short runs, a process can finish before
the first sample. Neither `ps` nor `psutil` captures all instantaneous
memory spikes; use Allocations and VM Tracker on macOS for deep analysis.

## In-process long-lived memory soak

A separate `memory_soak.gd` SceneTree runs **hundreds or thousands of
allocation/free cycles in the same process**, rather than restarting Godot
on each iteration. Two CPU/headless scenarios are currently supported:
`nodes` (scene-tree creation/destruction) and `packed` (8-KiB
PackedByteArray churn). It samples `Performance.MEMORY_STATIC` once per
cycle and the Python watchdog independently caps actual process RSS.

```bash
# Quick first pass:
python3 tests/stress/memory_soak.py --godot ./bin/godot.macos.editor.arm64 \
  --cycles 300 --batch 300 --repeats 3 \
  --output out/memory-soak.json

# Opt-in deep soak, preferably on an isolated machine:
python3 tests/stress/memory_soak.py --godot ./bin/godot.macos.editor.arm64 \
  --cycles 3000 --batch 800 --repeats 5 \
  --timeout 1200 --rss-limit-mib 6144 \
  --max-retained-growth-mib 256 \
  --output out/memory-soak-long.json
```

The analyzer discards the first 10% of cycles as warm-up and compares
median memory samples in early and late windows. It also calculates
a linear memory trend after warm-up. This detects **retained allocator
memory**, which may be caching or legitimate allocator behavior rather
than a leak. Investigate suspicious results with Instruments Allocations
and VM Tracker on macOS, or a native heap profiler. The RSS watchdog
is a process safety limit, not an exact measure of transient allocation
peaks. The growth threshold is opt-in; no threshold is a universal
leak detector.

## Process-tree resource watchdog

Each workload is launched in an isolated process group. The watchdog samples
combined resident RAM and CPU use for Godot **and its children**, not only the
main PID. Results include `peak_processes`, use schema version 2, and record
`configuration.rss_scope = "process_tree"`. Re-capture older baselines: parent-only
RSS and process-tree RSS are not directly comparable.

Linux requires no dependencies beyond /proc. On macOS and Windows install
`psutil` (`python3 -m pip install psutil`) for descendant-inclusive sampling.
A timeout or RAM overrun terminates the workload's entire process group.
Short memory spikes shorter than the sampling interval can still be missed.


## A* frontier decrease-key pressure

`astar_relax_2d` and `astar_relax_3d` build a large open set, then improve
every candidate through a cheaper intermediate point. Each query checks the
exact expected route. The JSON detail includes `search_ms`, measured after
graph construction, so search costs can be isolated from setup costs.

```bash
python3 tests/stress/scale_sweep.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case astar_relax_2d,astar_relax_3d \
  --scales 1,2,4,8,16 --repeats 5 --frames 12 \
  --output out/astar-frontier.json --summary-md out/astar-frontier.md
```

A headless renderer is enough. Use matching builds and hardware for comparison.

## BitMap performance and image pipeline

The native BitMap implementation uses masked byte-span fills for
`set_bit_rect`, 64-bit SWAR counting for `get_true_bit_count`, and
packed row-major paths for resize, blit and L8 image export. LA8 input
avoids an unnecessary Image duplicate. All changes keep pixel-level
correctness tests in `tests/scene/test_bit_map.cpp`, including odd-width
rows, clipped rectangles, overlapping self-blits and nearest-neighbor
up/downscaling.

```bash
python3 tests/stress/run.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case bitmap_rects,bitmap_pipeline \
  --preset standard --repeats 5 \
  --output out/bitmap.json --summary-md out/bitmap.md
```

`bitmap_rects` isolates large packed writes and population counting.
`bitmap_pipeline` additionally reports per-run blit, resize, L8
conversion and LA8 alpha-import time. For comparisons, use identical
hardware and engine build settings; synthetic C++ microbenchmarks cannot
predict whole-game FPS. A dedicated GitHub Actions workflow runs native
BitMap correctness tests and these workloads on the actual fork.

## StreamPeerBuffer bulk throughput

`stream_bulk` tests 8 KiB binary writes, complete reads and oversized partial
reads. It verifies returned bytes, tracks transferred data and reports
`read_write_ms` separately from initial buffer construction. Unlike the
`stream` workload (32-bit primitive calls), this targets bulk transfers.

```bash
python3 tests/stress/scale_sweep.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \\
  --case stream,stream_bulk --scales 1,2,4,8,16 --repeats 5 \\
  --output out/stream-scaling.json --summary-md out/stream-scaling.md
```


## AStarGrid2D construction, shrink and RAM pressure

The `astar_grid_rebuild` workload alternates large wide/tall maps with a tiny
8×8 region. It validates coordinate addressing, routes, occupancy reset and
reports independent `build_ms` and `shrink_ms`, plus before/after static-memory
deltas. This specifically exercises contiguous point storage and the
bulk-initialized occupancy mask. The case caps its largest side at 2048 cells;
use the OS process RSS sampler in `run.py` for actual resident memory.
Allocator-retained RSS is not proof of a leak.

```bash
python3 tests/stress/scale_sweep.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case astar_grid_rebuild --scales 1,2,4,8,16 --repeats 5 \
  --output out/astar-grid-rebuild.json --summary-md out/astar-grid-rebuild.md
```

## Grid reflow: dense and sparse column stress

`grid_reflow` separately exercises GridContainer's reflow algorithm:
hundreds/thousands of Controls with varying minimum sizes, expandable
rows and columns, and an extreme case with one million **declared**
columns but only a small number of actual children. The engine now
stores per-cell scratch measurements in dense `LocalVector` buffers,
and represents trailing empty columns by an integer count rather than
allocating one RBSet node for every empty column. Regression tests check
capped expansion, minimum sizes, hidden Controls, and sparse columns.

```bash
python3 tests/stress/run.py \
  --godot ./bin/godot.macos.editor.arm64 \
  --case ui_layout,grid_reflow --scale 8 --frames 180 --repeats 5 \
  --timeout 600 --rss-limit-mib 6144 \
  --output out/grid-reflow.json --summary-md out/grid-reflow.md
```

The scenario reports p95 reflow, maximum reflow, sparse reflow, and
engine process duration. The measured reflow duration includes the
wait for the next frame and must **not** be interpreted as raw
GridContainer C++ function execution time. Compare identical builds,
hardware and settings for useful regressions; it does not measure GPU
frame presentation. These workloads are resource limited via the
shared Python watchdog.

Native BitMap hotpaths now also specialize full-map fill/clear,
small alpha images, and constant alpha masks, while retaining
byte-precise tests for non-multiple-of-eight widths and alpha
threshold boundaries.

### PacketPeer batch CPU/RAM profiling

The headless `packet_tx_batch`, `packet_rx_batch` and `packet_variant_reuse`
workloads separate transmit framing, buffered receive and alternating
small/large Variant encoding. They report `send_ms`, `receive_ms` and
`roundtrip_ms` along with packet counts and checksums.

```bash
python3 tests/stress/scale_sweep.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case packet_tx_batch,packet_rx_batch,packet_variant_reuse \
  --scales 1,2,4,8,16 --repeats 5 --frames 90 \
  --output out/packet-scale.json --summary-md out/packet-scale.md
```


## Per-phase CPU hotspot reports

All numeric workload `detail` fields ending in `_ms` are summarized as
**median per-phase milliseconds** across successful repeats, provided
that every repeat has that field. Missing or nonfinite samples are not
silently imputed. The summary Markdown now includes a separate ranking
for these per-phase measurements, and baseline comparisons can flag
regressions in a particular phase even when overall process time stays
unchanged.

For example, `bitmap_pipeline` reports blit, resize, L8 export and
LA8 import durations. `grid_reflow` reports reflow wait time and the
sparse million-column case separately. Frame-driven durations may
include scheduling delays, so these measurements are *triage signals*,
not C++ function-only timings. Always compare the same test case,
input size, platform, build flags, clock conditions and driver.

## Streaming GZIP/DEFLATE throughput

The `gzip_stream` scenario cycles between GZIP and raw-zlib DEFLATE
for difficult-to-compress payloads, checks the full byte-for-byte result
and reports separate `compression_ms` and `decompression_ms` timings.
Inputs and repeat counts are capped to keep brutal runs within a fixed
memory and time budget. The runner also records process RSS.

```bash
python3 tests/stress/scale_sweep.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case gzip_stream --scales 1,2,4,8,16 --repeats 5 \
  --output out/gzip-stream.json --summary-md out/gzip-stream.md
```

Use identical hardware and build settings for old/new comparisons.
The standalone zlib harness verifies finalization correctness, but is
not a substitute for the native Godot round-trip or benchmark results.

## GDScript array literal and Dictionary snapshot costs

`array_literals` constructs nonconstant, 16-entry untyped array literals,
targeting the GDScript VM's `OPCODE_CONSTRUCT_ARRAY`. The workload checks
elements and reports `construction_ms` after setup.

`dictionary_snapshot` builds a dictionary of integer keys and then
repeatedly extracts aligned `keys()` and `values()` arrays, reporting
`snapshot_ms` and validating key-value associations. Input size and
repetitions are capped for larger stress presets.

```bash
python3 tests/stress/scale_sweep.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case array_literals,dictionary_snapshot \
  --scales 1,2,4,8,16 --repeats 5 \
  --output out/variant-hotpaths.json --summary-md out/variant-hotpaths.md
```

Use matching platforms and engine builds and compare case-specific latency
and RSS. Workload microtimings include GDScript loop and validation overhead.

## Box and Flow container layout hotpaths

`BoxContainer` now computes minimum/desired sizes in one pass rather
than creating a linked list of controls, and caches expansion metrics
in a dense `LocalVector` instead of a new hash map per sort.
`FlowContainer` similarly stores child measurements by index, reuses
line and stretching buffers, and uses each child's existing stretch
state instead of allocating a separate activity array.

Both changes preserve existing alignment, visibility, maximum-size and
reverse-order layout tests in `tests/scene/test_box_container.cpp`
and `tests/scene/test_flow_container.cpp`. New native regression tests
cover mixed visible/hidden Controls and unrelated Node children.

```bash
python3 tests/stress/run.py \
  --godot ./bin/godot.macos.editor.arm64 \
  --case box_reflow,flow_reflow,grid_reflow \
  --scale 8 --frames 180 --repeats 5 \
  --timeout 600 --rss-limit-mib 6144 \
  --output out/ui-reflow.json --summary-md out/ui-hotspots.md
```

The UI workloads expose reflow scheduling latency p95/peak and engine
process time while the shared runner tracks process-tree RSS. The
per-frame metrics include waiting and should not be interpreted as
pure `_resort()` C++ execution time. For actual improvement percentages,
compare repeated runs of the same workload before and after the change
on the same hardware. The Box/Flow GitHub Actions workflow builds the
fork with native C++ tests and executes both targeted workloads.

## Deeply connected GodotPhysics islands

`physics_joint_chain_2d` and `physics_joint_chain_3d` attach many
RigidBodies with PinJoint nodes. The entire chain forms one island,
exercising the non-recursive island flood-fill used by GodotPhysics.
Each scenario measures peak physics processing time, per-frame intervals
and process RSS through the existing runner. The 2D/3D body counts are
capped at 4096/3072 respectively, so large scale presets stay bounded.

```bash
python3 tests/stress/scale_sweep.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_joint_chain_2d,physics_joint_chain_3d \
  --scales 1,2,4,8,16 --repeats 5 --rss-limit-mib 6144 \
  --output out/physics-joint-chains.json --summary-md out/physics-joint-chains.md
```

To check worst-case depth, increase the scale or use the brutal preset.
The scenario must be run with the GodotPhysics backend, not a third-party
physics implementation. Compare both runtime and peak resident memory.


### AStarGrid2D JPS and bulk-fill scaling

`astar_grid_jps` measures long horizontal and diagonal Jump Point Search
scans with the four diagonal movement policies. `astar_grid_fill` measures
contiguous obstacle-mask writes and weighted-point updates separately. These
headless workloads report engine-side stage timings and checksums, while the
shared stress runner records peak process RSS. Compare identical hardware,
build options and workloads against a pre-change baseline.

```bash
python3 tests/stress/scale_sweep.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case astar_grid_jps,astar_grid_fill \
  --scales 1,2,4,8,16 --repeats 5 --frames 90 \
  --timeout 600 --rss-limit-mib 6144 \
  --output out/astar-jps-bulk.json \
  --summary-md out/astar-jps-bulk.md
```


## Million-proxy broadphase pressure (opt-in)

The `physics_proxies_2d` and `physics_proxies_3d` scenarios create **1,000 × scale**
non-overlapping static bodies directly through `PhysicsServer2D/3D`, using one
shared shape RID per dimension. This excludes the scene-tree overhead of
`Node2D/Node3D` and isolates broadphase allocation, insertion, teardown and
the correctness of nearest-hit raycasts at both edges of the populated area.
Engine static-memory samples are diagnostics; process RSS is recorded by
`run.py` and subject to its hard limit.

Start with a small sweep to establish a per-machine baseline:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_proxies_2d,physics_proxies_3d --scale 10 \
  --repeats 3 --frames 12 --timeout 600 --rss-limit-mib 6144 \
  --output out/physics-proxies-10k.json
```

**Explicitly opt in** to one million bodies per dimension, in separate
processes on a dedicated host with enough RAM. The watchdog terminates
processes that exceed the per-run time/RSS limits:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_proxies_2d,physics_proxies_3d --scale 1000 \
  --repeats 1 --frames 12 --timeout 1800 --rss-limit-mib 12288 \
  --output out/physics-proxies-1m.json
```

These measure *sparse static proxies*, **not** one million interacting dynamic
rigid bodies at 60 FPS. Dynamic islands, narrowphase, constraint solving and
sleeping require separate performance and accuracy measurements.

### 3D CCD hot-path regression

The `physics_ccd_3d` scenario keeps small box-shaped dynamic bodies in CCD mode and
repeatedly fires them at thin static targets, resetting their positions each
physics frame. The repeated casts exercise the 3D body-pair CCD support loop;
plain `physics_3d` does not guarantee this path is exercised. Reported frame
p95, peak physics time and resident memory are suitable for same-hardware,
same-build before/after comparisons. This is a performance workload, not a
proof of missed-collision prevention.

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \\
  --case physics_ccd_3d --scale 4 --frames 90 --repeats 5 \\
  --rss-limit-mib 4096 --output out/physics-ccd-3d.json
```

Use `scale=1` first; `scale=1000` creates 64,000 dynamic and 64,000 static
bodies and should only be attempted on an isolated high-memory machine.

### 2D CCD edge-support coverage

The `physics_ccd_2d` workload repeatedly fires wide rectangles at small
targets intersecting only the **second** leading support ray. This catches the
cost of the multi-support ray CCD path; use the dedicated runtime regression
below to check correctness (not just contact throughput).

```bash
python3 tests/stress/run.py --godot ./bin/godot.macos.editor.arm64 \
  --case physics_ccd_2d --scale 4 --frames 90 --repeats 5 \
  --rss-limit-mib 4096 --output out/physics-ccd-2d.json

./bin/godot.macos.editor.arm64 --headless --path tests/stress \
  --script res://physics_ccd_edge_2d_regression.gd

python3 -m unittest discover -s tests/stress -p 'test_physics_ccd_2d_supports.py' -v
```

The stress result records frame p95 and peak physics time and can be compared
only between equivalent builds on identical hardware. The regression checks
that a projectile is stopped by the lower box corner rather than tunnelling
through a small obstacle. Two support rays are not equivalent to a full shape
cast: use `CCD_MODE_CAST_SHAPE` for more demanding collision geometry.

### 2D contact warm-start and friction regression

The standalone `physics_contact_solver_regression.gd` script uses three
independent dynamic circles sliding against static floors. It checks that
frictionless contact travels farther than frictional contact, that body
positions/velocities remain finite for 150 physics frames, and that changing
contact friction from 1 to 0.2 to 0 to 1 does not cause unstable velocities.
The test changes `Engine.physics_ticks_per_second` between 60, 120 and 240
and restores its previous value. It also exercises a non-default warm-start
coefficient in the newly created physics space.

This specifically exercises contact persistence, warm-start impulse reuse
and the zero-friction tangent-solver shortcut. It does not establish a speedup.

The optional project setting `physics/2d/solver/warm_start_coefficient` follows
Rapier's tunable contact warm-starting principle: `1.0` (default) fully
reuses compatible cached impulses, `0.0` disables reuse, and values between
them damp the cached impulse. It is read when creating a `GodotSpace2D`;
changing the project setting does not alter spaces already created. The
default `1.0` preserves existing fixed-timestep simulation behavior.
A timestep change scales the impulses by the ratio of new-to-previous
physics step; changes larger than 2x or smaller than 0.5x drop cached
impulses. Cached tangential impulses are always limited to
`friction * cached_normal_impulse` before warm starting, including when a
contact's friction coefficient changes.

For throughput, two matched low-level workloads use the same dense circle
geometry while varying only the friction coefficient. Compare each case
against a baseline from the same machine, binary settings and scale; do not
treat time differences *between* friction modes as an engine-version speedup.

```bash
python3 tests/stress/run.py --godot ./bin/godot.macos.editor.arm64 \
  --case physics_contacts_zero_friction_2d,physics_contacts_friction_2d \
  --scale 4 --frames 90 --repeats 5 --rss-limit-mib 4096 \
  --output out/physics-contact-solver.json
```

```bash
# Build an engine before running (arm64 macOS example):
scons platform=macos target=editor arch=arm64 -j$(sysctl -n hw.ncpu)

./bin/godot.macos.editor.arm64 --headless \
  --path tests/stress --script res://physics_contact_solver_regression.gd
```


### 2D persistent manifold matching regression

The new `physics_contact_recycling_regression.gd` script exercises a set of
independent rectangular bodies on static platforms. It reverses angular
velocity repeatedly while checking for nonfinite or runaway body states and
for the presence of actual collision pairs. This targets changes to
`GodotBodyPair2D::_contact_added_callback()`, which now assigns each new
manifold point to the nearest *unused* old contact before restoring its
accumulated impulses.

```bash
./bin/godot.macos.editor.arm64 --headless \
  --path tests/stress --script res://physics_contact_recycling_regression.gd
```

For repeated throughput measurements, `physics_contact_manifolds_2d` creates
real dynamic box contacts, rather than the circle-only contacts exercised by
the friction benchmarks. Baseline comparisons must use identical hardware,
Godot settings, workloads and build mode. This is a dense interacting-body
test, **not** a million-independent-proxy test.

```bash
python3 tests/stress/run.py --godot ./bin/godot.macos.editor.arm64 \
  --case physics_contact_manifolds_2d --scale 4 --frames 120 \
  --repeats 5 --rss-limit-mib 4096 \
  --output out/physics-contact-manifolds-2d.json
```

### Experimental 2D two-point block solver

Box2D's two-point velocity solver uses a small linear complementarity
problem (LCP) to solve two normal contact impulses together. Cgame exposes
an **opt-in** counterpart in the built-in GodotPhysics2D backend:

`physics/2d/solver/block_solver_enabled = true`

The default is **false** until real engine builds, platform tests and
same-hardware benchmarks confirm both stability and performance. Existing
simulations are unchanged by default. A new physics space reads the
setting when it is created; changing it does not affect existing spaces.

The block path runs only for two active manifold points with almost
identical normals and a well-conditioned 2x2 effective-mass matrix.
It enumerates all complementarity solutions (both constraints active,
either point active, or neither). Singular or inconsistent cases fall
back to the existing sequential per-point solver. Position-bias and
friction remain unchanged. The four scalar entries of the conditioned
contact matrix are now cached **once per pair per simulation step** in
`pre_solve`, instead of recomputing the matrix and determinant on every
solver iteration (typically 16). This trades a small, fixed amount of
per-pair memory for fewer arithmetic operations; it performs no new heap
allocation. Retained 2D tangential warm-start impulses are also projected
into the rotated contact tangent to avoid stale friction when a manifold
normal changes. The cached matrix is invalidated on every pre-solve pass,
and ill-conditioned or incomplete manifolds still use scalar PGS.

Pure-Python source-contract and 2x2 LCP reference tests exercise
all four complementarity active sets and 500 deterministic positive-definite
matrix scenarios. They check mathematical consistency and cache placement,
but do not replace compiling Cgame or running its physics scene:

```bash
python3 -m unittest discover -s tests/stress \
  -p 'test_physics_2d_block_matrix_cache.py' -v
```

The standalone regression creates eight independent stacks of four boxes.
It runs 240 physics frames each with block solving disabled/enabled,
checking collision pairs, finite velocities, runaway motion and settling:

```bash
./bin/godot.macos.editor.arm64 --headless \
  --path tests/stress --script res://physics_block_solver_regression.gd
```

To compare performance fairly, the benchmark cases have identical
geometry and workloads and only change the block-solver flag. Each run
creates a fresh physics space and restores its ProjectSettings override:

```bash
python3 tests/stress/run.py --godot ./bin/godot.macos.editor.arm64 \
  --case physics_contact_manifolds_2d,physics_contact_block_solver_2d \
  --scale 4 --frames 120 --repeats 5 --rss-limit-mib 4096 \
  --output out/physics-block-solver-comparison.json
```

Compare runtime, collision pair count, stability and RSS across modes.
Enabling block solving does not guarantee higher throughput: the 2x2
system adds work per iteration and can instead improve convergence.

## 3D large rigid-body islands: opt-in conflict-free parallel solver

GodotPhysics3D can now divide **one large connected rigid-body island** into
non-conflicting constraint colors, inspired by Box2D's graph-color solver and
Jolt's large-island scheduling. Each color contains constraints that do not
share body pointers; static/kinematic bodies are conservatively treated as
shared too. Colors run in sequence with a worker-pool barrier between each,
and a bounded serial overflow batch handles highly connected bodies.

Enable only after validating your project's behavior:

```ini
[physics]
3d/solver/parallel_large_islands=true
```

The setting is `false` by default, cached when a GodotPhysics3D space is
created and ignored by third-party physics backends. This path is attempted
only when **one active solve island** has at least 256 constraints, all
constraints have priority 1, and none involve soft bodies. Constraints with
higher joint priorities, soft-body dependencies, null/empty body lists, or
insufficient independent parallel work fall back to the existing sequential
priority solver. The bounded coloring scratch buffer is reused across steps.

As with any iterative constraint solver, changing the order of constraints
may change convergence and determinism. Keep the option disabled if strict
frame-for-frame comparison with the legacy solver is required.

Run source contracts and the runtime finite-state/joint-spacing regression:

```bash
python3 -m unittest discover -s tests/stress -p 'test_physics_3d_large_island_coloring.py' -v
./bin/godot.macos.editor.arm64 --headless --path tests/stress \
  --script res://physics_large_island_3d_regression.gd
```

Benchmark the **identical** 320-joint-per-scale connected chain with
parallelism off/on in separate engine processes. The third case adds a
priority-2 joint and checks the sequential fallback. Run one case at a
time under the same binary/hardware conditions:

```bash
python3 tests/stress/run.py --godot ./bin/godot.macos.editor.arm64 \
  --case physics_large_island_3d_serial,physics_large_island_3d_parallel,physics_large_island_3d_priority \
  --scale 2 --frames 90 --repeats 5 --timeout 600 \
  --rss-limit-mib 4096 --output out/physics-large-island-3d.json
```

The tests check finite body states and joint spacing, not physical
equivalence to the serial solver or measured performance improvements.
Start with small scales and monitor CPU usage, peak RSS and frame p95.

## 3D contact warm-start timestep and material stability

Built-in GodotPhysics3D now scales cached normal, friction, and bias impulses
by `current_delta / previous_delta` when the physics tick rate changes.
Timestep ratios outside `[0.5, 2.0]` discard those impulses rather than
injecting stale forces. Cached friction is also clamped to the **current**
Coulomb limit `mixed_friction * cached_normal_impulse` before warm starting,
including when an existing material's friction is reduced.

The optional project setting `physics/3d/solver/warm_start_coefficient`
follows Rapier's contact warm-start scaling: `1.0` is the default and
preserves existing fixed-timestep behavior; `0.0` disables cached impulse
reuse; intermediate values damp it. This setting is read once when a
GodotPhysics3D space is created, not on every contact or every frame.
Changing it does not retroactively affect already created spaces. This
setting does not modify a third-party physics backend.

Run both structural and simulation-level regressions with a freshly
compiled engine:

```bash
python3 -m unittest discover -s tests/stress -p 'test_physics_3d_warmstart_timestep.py' -v

./bin/godot.macos.editor.arm64 --headless --path tests/stress \
  --script res://physics_warmstart_timestep_3d_regression.gd
```

The simulation test switches physics tick rates from 60 to 120 to 30 to
60 Hz and lowers friction while contacts persist. It checks finite
velocities/transforms, bounds runaway motion, and requires at least one
collision pair. This is a **stability regression**, not evidence of better
performance or a proof of physically exact contact impulses.

## 3D frictionless contact solver regression

The `physics_frictionless_3d` workload is identical in topology to
`physics_3d` but applies a shared zero-friction material to every body.
This exercises the fast path that skips 3D tangential impulse and inertia
work while preserving normal, bias and restitution impulses.

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_3d,physics_frictionless_3d --scale 4 --frames 90 \
  --repeats 3 --timeout 600 --rss-limit-mib 6144 \
  --output out/frictionless-3d.json
```

For contact correctness, run the independent 3D material-switch test:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_frictionless_3d_regression.gd
```

Compare performance of each case **against the same case on the baseline**,
not the frictional case against the frictionless case; they intentionally
model different physical behavior.

## Unbounded nearest-hit 2D/3D raycast regression

The broadphase raycast now streams candidate shapes to the exact narrowphase
and shortens the active ray after each closer hit. Unlike the older
`cull_segment()` result-array path, it does **not** silently discard candidates
after `INTERSECTION_QUERY_MAX = 2048`. Other bounded query APIs retain their
existing limits and semantics.

Verify closest-hit correctness across 4,096 non-overlapping static bodies in
**each** dimension, in forward and reverse directions, with collision-layer
filtering:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_ray_overflow_regression.gd
```

The C++ BVH unit tests independently verify that the streaming visitor sees
4,096 candidates without clipping, respects tree masks, and returns the closest
hit when clipping is enabled. Build with `tests=yes` to include native tests.

For speed comparisons at 4,000+ shapes, benchmark existing raycast workloads
against an earlier build **on the same machine**:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_raycast_2d,physics_raycast_3d --scale 50 \
  --repeats 3 --frames 12 --timeout 600 --rss-limit-mib 6144 \
  --output out/physics-raycast-5k.json
```

A successful correctness check is **not** proof of million-body throughput;
measure both execution time and peak process RSS separately.

## Near-first streaming BVH raycasts

Streaming raycasts now visit intersecting BVH roots and binary child nodes in
the order of their **estimated entry fraction** along the ray. As with Jolt's
early-out fraction and Box2D's clipped tree raycasts, the first nearby exact
hit can reject distant nodes before they enter the narrowphase. The hint is
only used to order work: `BVH_ABB::intersects_segment()` still decides whether
a node intersects, including axis-aligned, reversed and grazing cases.

The change uses the existing iterative LIFO stack, no priority queue or
per-object heap allocation. It cannot guarantee first-hit ordering *inside*
each multi-item BVH leaf; the exact raycast visitor continues to clip using
the closest hit and remains correct if earlier callbacks see farther objects.

Unit tests (native `tests=yes`) cover:
- 4,096 candidates, nearest-hit clipping and fewer narrowphase callbacks;
- ordering independent of static/dynamic tree insertion order;
- reversed and axis-aligned 2D/3D rays.

For existing stress-suite timings on the same engine binary and hardware:

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_raycast_2d,physics_raycast_3d --scale 50 \
  --repeats 5 --frames 12 --timeout 600 --rss-limit-mib 6144 \
  --output out/raycast-near-first.json
```

Compare query time and process RSS to an otherwise identical baseline build.
No specific CPU/latency speedup is claimed without measured results.


### Experimental parallel solving of one large 2D physics island

Jolt splits very large simulation islands into independent constraint groups,
and Box2D uses graph coloring to ensure that parallel tasks do not update the
same body. Cgame now supports a conservative, **opt-in** approach for the
built-in GodotPhysics2D solver:

`physics/2d/solver/parallel_large_islands = true`

The default is **false** until engine builds, thread sanitizers, stability and
performance tests validate the implementation. Only a single large active
island in the physics step takes this path. Small islands still use the
existing serial/parallel island dispatcher.

For a large island (at least 256 constraints), the step builds a 16-color
greedy constraint graph: every body touched by a constraint reserves that
color, including static and kinematic bodies for conservative thread safety.
A color with at least 64 constraints can solve in parallel; a barrier
separates colors and solver iterations. Constraints that cannot be colored
within 16 colors go to a serial overflow batch. If there is too little
parallelizable work, the algorithm falls back to the original sequential
solver. No additional fields are stored on bodies or contacts.

The standalone regression compares 120 physics frames of the same connected
384-body / 383-pin-joint chain with the option disabled and enabled. It checks
joint count, representative finite states and link separation:

```bash
./bin/godot.macos.editor.arm64 --headless \
  --path tests/stress --script res://physics_large_island_regression.gd
```

For repeatable scale and RAM measurements, the low-level stress case creates
its own physics space after changing the project setting and restores the
setting immediately after creation (existing spaces do not update their
configuration):

```bash
python3 tests/stress/run.py --godot ./bin/godot.macos.editor.arm64 \
  --case physics_large_island_serial_2d,physics_large_island_parallel_2d \
  --scale 4 --frames 120 --repeats 5 --rss-limit-mib 4096 \
  --output out/physics-large-island.json
```

Both cases use identical chain geometry and initial velocities. Compare the
median/p95 frame time, peak physics time, process RSS, and final joint
separation. Adding thread dispatch and graph construction can make small or
highly connected islands *slower*, and altered constraint order can affect
numerical outcomes. This should not be enabled by default without measurements.

## Jolt collision substepping (opt-in)

Jolt's `PhysicsSystem::Update(delta, collision_steps, ...)` supports repeating
collision detection and integration within the same engine physics frame.
Cgame previously always used one collision step. Two project settings now expose
that upstream Jolt capability without increasing the default CPU cost:

| Project setting | Default | Meaning |
| --- | ---: | --- |
| `physics/jolt_physics_3d/simulation/collision_steps` | `1` | Minimum number of collision/integration passes in each Jolt tick (clamped to 1–8) |
| `physics/jolt_physics_3d/simulation/max_collision_step_seconds` | `0.0` | Disabled when zero; otherwise request enough passes so each subdivision is at most this many seconds, subject to the eight-step cap |

For example, use `collision_steps = 2` to increase contact stability at the
expense of more CPU per tick. Or set `max_collision_step_seconds = 0.01`
to request additional passes whenever a physics tick is longer than 10 ms.
The effective count is the greater of the configured minimum and the
time-based requirement, capped at eight.

These settings apply to **Jolt Physics 3D** only, not GodotPhysics2D or
GodotPhysics3D. The default (`collision_steps=1`, `max_collision_step_seconds=0`)
preserves the old behavior. This feature is not a substitute for continuous
collision detection (CCD) on very fast objects; enable CCD separately when
needed. Additional collision passes may increase CPU time substantially.

Compare the same physical workload on the same machine/backend before and
after adjusting settings:

```sh
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_ccd_3d,physics_dense_3d,physics_joint_chain_3d \
  --preset standard --output out/jolt-substeps.json \
  --summary-md out/jolt-substeps.md
```

Run `python3 -m unittest tests/stress/test_jolt_collision_substeps.py -v`
for the source-wiring contracts; also build and execute the native physics
tests to confirm actual runtime behavior. No performance improvement should
be inferred merely from the presence of this configuration option.
