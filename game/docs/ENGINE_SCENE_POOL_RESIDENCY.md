# Frame-budgeted VFX pool residency (Niagara-inspired)

The custom Cgame engine already supports `SceneNodePool` with pooled
`PackedScene` reuse. Formerly, `prewarm_count = 12` in Albion After
allocated twelve `CPUParticles3D` scenes synchronously in `_ready()`.
Allocating large pools in one callback can create CPU frame spikes.

Unreal Niagara uses component pooling and configurable pool sizing; its
best-practices documentation cautions that warm-up work can hitch:
https://dev.epicgames.com/documentation/unreal-engine/scalability-and-best-practices-for-niagara
https://dev.epicgames.com/documentation/unreal-engine/system-settings-reference-for-niagara-effects-in-unreal-engine

## Native API

`SceneNodePool.maintain_residency(target_total: int, max_changes: int = 2) -> int`

One call may:
- Allocate up to `max_changes` detached instances when
  `active_count + idle_count < target_total`, respecting `max_idle`.
- Reclaim up to `max_changes` *idle* instances when the total exceeds
  the target; live/checked-out nodes are never evicted.
- Return a **positive** count for creations, a **negative** count for
  releases or zero for no work.

Limits are `0 <= target_total <= 4096` and
`0 <= max_changes <= 64`; invalid arguments perform no work.
The method prunes stale weak references before making its residency
decision. It does not modify scene gameplay or make streaming requests.

Existing eager `prewarm(target)` remains available and unchanged
for code that intentionally wants immediate allocation (loading screens).

## Albion After

`game/scripts/client/effects.gd` disables `prewarm_on_ready`
when `maintain_residency` exists, then maintains the emitter pool in
`_process()` with quality-dependent budgets:

| Quality | Resident target | Changes/frame |
| --- | ---: | ---: |
| Performance | 2 | 1 |
| Balanced | 4 | 1 |
| High | 8 | 2 |
| Ultra | 12 | 2 |

These values describe **total** cached + active emitters; the target
is not an additional allocation beyond active effects. Independently
of the target, existing `max_idle = 24` and `max_active = 48` limits
still apply. Heavy combat can temporarily exceed the target as needed
within `max_active`. Lowering quality only retires idle instances as
they become available.

The matching `RuntimeNodePool` GDScript implementation keeps the
same return values on stock Godot. Older native engines without the
new method keep the original eager prewarm path.

## Regression

- C++: `tests/scene/test_scene_node_pool.cpp`
- GDScript native/fallback: `game/tests/test_runtime_node_pool.gd`
- Graphics presets: `game/tests/test_fx_scalability_budget.gd`
- Existing CI: `.github/workflows/native-scene-node-pool.yml`

This is a bounded-work change, **not** a measured FPS improvement.
Profile actual frame times and pool statistics on target hardware.
