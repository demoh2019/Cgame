# Native rollback netcode and deterministic physics (experimental)

This built-in module ports the GDScript rollback netcode and deterministic physics stack to C++ so that
rollback, resimulation and physics stepping run without script calls.

## Classes

| Class | Purpose |
| --- | --- |
| `CgameRollbackNetcode` | GGPO-style core: input ring buffers, local prediction, input delay, max prediction window (stalls), snapshot ring, rollback and resimulation, per-frame checksums, `desync_detected` signal. The step is a `Callable` or a native `CgameRollbackStepProvider`. |
| `CgameClientPrediction` | Server-authoritative movement prediction: sequence numbers, reconciliation, exponentially decaying visual error, snap above a threshold. |
| `CgameRollbackDebugger` | Wraps a netcode: records rollbacks with their cause, per-player prediction miss rate, desyncs with a key-path state diff, text report. |
| `CgameNetConditioner` | Latency, jitter, loss, duplication, reordering and bandwidth cap with a per-packet log. Deterministic per seed. |
| `CgameDeterministicPhysics` | Spheres and boxes, SAT, sequential impulses, group sleeping, snapshot/restore bytes, checksum, ray casts. |
| `CgamePhysicsRollback` | Adapter between the physics world and the netcode (native step provider) plus `rewind_query()` lag compensation with snapshot interpolation. |
| `CgamePhysicsTimeline` | Per-step phase timings, bounded ring, report and Chrome trace (`chrome://tracing`, Perfetto) export. |

`cgame_physics_core.{h,cpp}` holds the solver itself. It depends on the C++ standard library only (no engine
types, no `real_t`) so the simulation always runs in IEEE double precision.

## Determinism rules (physics)

- Bodies are stored sorted by id; the broadphase sweep and the contact pairs are sorted with id tie-breaks.
- Nothing iterates a hash map during a step. The solver uses a fixed iteration count and no warm starting, so
  `snapshot()` serializes the complete state (little-endian doubles).
- Identical inputs give identical bytes on the same build and platform. Cross-compiler or cross-architecture
  bit equality (for example differing floating-point contraction) is not guaranteed.

In the netcode, player ids are integers, remote checksums are checked in ascending frame order, and checksums
are a hash of the serialized state `Dictionary`.

## Native stepping

```gdscript
var physics := CgamePhysicsRollback.new()
physics.world.add_body(1, CgameDeterministicPhysics.SHAPE_SPHERE, 1.0, Vector3(0, 1, 0), Vector3(0.5, 0, 0))
physics.bind_player(10, 1)
var net := CgameRollbackNetcode.new()
physics.setup_net(net, [10, 20], [10], 1.0 / 60.0, 2, 8) # net now steps the physics natively
```

From C++, implement `CgameRollbackStepProvider::rollback_step()` and call
`CgameRollbackNetcode::set_step_provider()` after `setup()`.

## GDScript facades

`game_facade/*.gd` (repository root) expose `create()` factories that use the native class when
`ClassDB.class_exists()` reports it and fall back to the GDScript implementations in `res://scripts/shared/`.

## Tests

`tests/test_cgame_rollback.h` (doctest, `TESTS_ENABLED`) mirrors the GDScript test suites: peers converge to the
lockstep reference under latency and jitter, late input rollback reproduces identical bytes (also with the native
physics step), desync detection, stalls, client prediction, debugger, conditioner (latency, loss for a seed,
duplicates, reordering, bandwidth), box stack sleeping, restitution, determinism, snapshot restore, ray casts,
rewind hit and miss, and the timeline trace. Run with `bin/godot... --test --test-case="*Cgame*"`.

## Known limitations

- Rotations of dynamic bodies use a plain angular velocity integration with quaternion renormalization.
- No continuous collision detection, joints or compound shapes.
- The module registers its classes at the scene level so it also builds with 3D disabled.
