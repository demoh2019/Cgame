# cgame_crowd — native crowd, mass-entity and population LOD

Native C++ replacements for three hot GDScript libraries in `game/scripts/shared/`.
All classes are `RefCounted`, registered at scene level, and deterministic.

| Class | Replaces | Purpose |
|---|---|---|
| `CgameCrowdAvoidance` | `crowd_avoidance.gd` | ORCA (RVO2 port) with spatial hash, LP1/2/3 incl. the 3D fallback, parallel over agents on `WorkerThreadPool` (>= 256 agents). Static `compute_velocities(...)` with the same signature. |
| `CgameMassEntity` | `mass_entity.gd` | Archetype SoA storage (`PackedVector3Array` / `PackedFloat32Array` / `PackedInt32Array` fragments), generational ids, `create` / `create_many` / `destroy` / `query`, processors in dependency order. Native built-ins `add_integrate_processor` and `add_crowd_avoidance_processor` avoid per-entity script calls. |
| `CgamePopulationLOD` | `population_lod.gd` | Herd simulation on a region grid: attractors, merge/split, decay, spawners, `promote` / `demote`. |

```gdscript
var world = CgameMassEntity.new()
world.define_fragment("pos", TYPE_PACKED_VECTOR3_ARRAY)
world.define_fragment("vel", TYPE_PACKED_VECTOR3_ARRAY)
world.define_fragment("pref", TYPE_PACKED_VECTOR3_ARRAY)
world.create_many({"pos": Vector3.ZERO, "vel": Vector3.ZERO, "pref": Vector3(1, 0, 0)}, 5000)
world.add_crowd_avoidance_processor("avoid", "pos", "vel", "pref", 0.5, 1.5, 3.0, 8.0, 16)
world.add_integrate_processor("move", "pos", "vel", PackedStringArray(["avoid"]))
world.run(delta)
```

## Differences from the GDScript versions

- `CgameMassEntity.query()` returns snapshots (copy-on-write); mutate through `set_value`, native
  processors or script processors. Script processors may modify `chunk[...]` arrays in place; changed
  arrays are written back after the call. The `parallel` flag is ignored for script callables.
- Entities cannot be created/destroyed and processors cannot change while `run()` executes.
- `CgamePopulationLOD` exposes herds through `get_herd(id)` / `herd_ids()` instead of a `herds` dictionary;
  tunables are properties with the same names (`max_herd_size`, `night`, ...). `kind_weight` became
  `set_kind_weight` / `get_kind_weight`.
- The random stream uses the engine's PCG like `RandomNumberGenerator`, but bit-identical replays against the
  GDScript implementation are not guaranteed (float precision of intermediate values).

## GDScript facade

`game_facade/cgame_crowd_facade.gd` picks the native class when `ClassDB.class_exists(...)` and otherwise
falls back to the GDScript implementation under `res://scripts/shared/`.

## Tests

Doctests under `tests/` (built with `tests=yes`): head-on avoidance distance, 200-agent crossing without
explosion, determinism, parallel path, infeasible-constraint fallback, mass create/destroy density, processor
ordering, native crowd processor, herd count conservation, promote/demote budget, decay and spawners.

```
scons tests=yes
bin/godot.<platform>.editor.<arch> --test --test-case="*Cgame*"
```

## Licensing

`cgame_crowd_avoidance.*` is derived from the RVO2 Library (Apache-2.0); see `LICENSE-RVO2.txt` and `NOTICE`.
