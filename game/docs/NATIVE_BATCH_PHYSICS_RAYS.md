# Cgame batch 3D physics ray queries

## Feature summary

Cgame adds a general-purpose native engine API:

```gdscript
var queries: Array[PhysicsRayQueryParameters3D] = []
queries.append(PhysicsRayQueryParameters3D.create(listener_position, enemy_position, 1))
queries.append(PhysicsRayQueryParameters3D.create(listener_position, doorway_position, 1))
var hits: Array = get_world_3d().direct_space_state.intersect_rays(queries)
# hits[i] uses the exact same Dictionary contract as intersect_ray(queries[i]).
```

`PhysicsDirectSpaceState3D.intersect_rays(queries)` processes a bounded
sequence of unrelated raycasts through **one GDScript/native method call**.
It retains one query per physical ray and preserves each query's own
collision mask, excluded RIDs, bodies/areas flags, backfaces and
inside-hit options. A non-hit contributes an empty Dictionary in its
original position. Empty input returns an empty array.

### Engine guarantees

- **Up to 32 rays per call.** Larger inputs are rejected before querying.
  This prevents an accidental unbounded physics workload.
- Validates *all* query instances and finite endpoints before querying,
  so bad scripts never receive a partial batch.
- Reuses the regular `PhysicsDirectSpaceState3D.intersect_ray` collision
  backend, which includes GodotPhysics3D and any supported custom physics
  extension. There is no second broadphase or new collision behavior.
- The dictionary fields match a single query: `position`, `normal`,
  `face_index`, `collider_id`, `collider`, `shape`, `rid`.
- **Synchronous** and physics-thread-safe only under the same conditions
  as ordinary direct space raycasts. No background physics calls, no
  extra GPU ray tracing, no claims that 32 raycasts cost one raycast.

## Albion After integration

`Audio._physics_process` now collects up to its *existing hard limit* of
three collision checks for active 3D sounds. It submits the independent
queries to `AudioSpatial.trace_rays`, which invokes the native batch API
only if this Cgame build supports it. Otherwise it performs the same
queries sequentially via the official Godot `intersect_ray` API.

Each result is associated with the correct sound source by query index.
The original <0.75 m source-prop exemption, heightfield line-of-sight
check, 0.25 second recheck cadence, native source-local gain and
low-pass response, stock audio fallback, and voice prioritization all
remain intact. Terrain scans are still limited to the same three physics
probes per physics tick; no RPC or server-side gameplay changes.

The general engine method is not audio-specific: future AI visibility,
combat interaction, sensor arrays and environmental effects can also
submit a bounded set of physical rays with independent filters.

## Tests

- `tests/scene/test_physics_space_batch_rays.cpp`: dedicated mock physics
  space verifies query order, collision masks, body flags, misses, empty
  input and identical dictionary contract for single and batch queries.
- `game/tests/test_native_batch_rays.gd`: portable native-vs-serial
  dispatch parity and existing gameplay scheduling invariants.
- `game/tests/test_audio_geometry_occlusion.gd`: the original world
  obstruction regression updated to verify native batch dispatch.
- Dedicated `game/tests/run_physics_batch.gd` headless runner and native
  CI; also registered in `game/tests/run_all.gd`.

```sh
# With a Cgame custom editor build (with tests=yes):
godot --headless --test --test-case="*Batch rays preserve order, masks and misses*"
godot --headless --path game --script res://tests/run_physics_batch.gd

# Same GDScript fallback suite can run with stock Godot 4.x:
godot --headless --path game --script res://tests/run_physics_batch.gd
```

## Comparable engines

- [Godot 4 PhysicsDirectSpaceState3D](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html)
- [Unreal Engine traces overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/traces-in-unreal-engine---overview)

This is a new script-call batching API, not Unreal's multi-hit raycast.
Unreal's multi-hit trace gathers multiple collisions along *one* ray,
whereas Cgame batches many independent queries; these are different
operations with different cost models. No FPS improvement is asserted
before profiling representative ray-heavy scenes.
