# Jolt PhysicsServer3D process counters

Previously `JoltPhysicsServer3D::get_process_info()` always returned zero, even
during an active simulation. This made the engine's Physics 3D active-object
and collision-pair monitors useless with Cgame's default Jolt backend; it
also gave false failures in existing contact-heavy stress scenarios.

The Jolt backend now publishes two **cached, last-completed-step** values:

- `INFO_ACTIVE_OBJECTS`: the exact sum of active Jolt rigid and soft bodies
  across active Jolt physics spaces, using the constant-time public
  `PhysicsSystem::GetNumActiveBodies()` counters. No all-body scans.
- `INFO_COLLISION_PAIRS`: the sum of Jolt contact-added and
  contact-persisted **manifold callbacks** during the step, accumulated
  per worker thread without contended locks and merged after
  `PhysicsSystem::Update`. This is a **collision activity proxy**, not
  a count of unique broadphase candidate pairs: multi-subshape objects and
  CCD collision substeps may generate more than one callback per body pair.
  It is nevertheless nonzero for actual dense contacts, including when
  scripts have not requested detailed contact reports.

`INFO_ISLAND_COUNT` remains **unsupported (zero)**: Jolt's public
`PhysicsSystem` interface does not expose the island builder's exact count.
Do not interpret zero as proof of no active physics islands.

The cached values are updated once after a completed step, summed across
all active spaces, and saturated at `INT32_MAX` because the Godot API returns
an integer. The manifold callbacks use thread-local counters and the same
once-per-step synchronization barrier already used for contact/area event
delivery. No atomics or extra spin locks are added to every contact callback.

## Tests

```sh
python3 -m unittest tests/stress/test_jolt_process_counters.py -v
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_process_info_regression.gd
```

The runtime fixture launches 64 overlapping, active rigid bodies, checks that
the active-body and contact monitors report activity, removes all bodies and
checks that both counters return to zero. The automated native CI job selects
the `Jolt Physics` backend explicitly.

Compare the numbers with the same scene and fixed timestep on other backends,
but do **not** compare `INFO_COLLISION_PAIRS` numerically between Jolt and
GodotPhysics3D: their event and broadphase counting semantics differ.

This feature improves profiling, correctness of stress reporting and
measurement; it is **not a proven simulation FPS optimization**.
