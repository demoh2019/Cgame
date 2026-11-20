# Combat-aware animation LOD for crowded raids

Albion After / Cgame Godot fork, `develop`.

The goal is **readable enemy attack telegraphs** even in a crowded world
without spending full animation CPU time on every zombie. Authoritative
server combat, damage, world physics, pathfinding and snapshots are unchanged.

## Comparison with existing game engines

Unreal Engine's Mass Simulation LOD uses distance/significance and
variable-rate updates. Godot's AnimationMixer supports manual advancing
using `ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`; this fork already has a native
AnimationLODController for 1x, 1/2x, 1/4x and off-screen-paused animation.
Unity Animator Culling and GPU instancing are alternative components of
large-crowd optimization. We retain our existing native LOD and only add a
small **gameplay-significance override**.

## Native C++ animation controller

`modules/gameplay_tags/animation_lod_controller.{h,cpp}`:

- Each registered AnimationMixer has a `high_priority` hint, default false.
- `set_mixer_high_priority(mixer, bool)` is reversible and idempotent.
- `is_mixer_high_priority(mixer)` exposes the current hint for testing.
- `max_priority_mixers` is a hard bounded quota clamped to 0–32.
- At most that many eligible high-priority visible mixers get an additional
  full-rate `advance()` cadence when their normal LOD would be 1/2 or 1/4.
- Outside the active frustum, beyond `far_distance`, and on tiers with zero
  budget, actors retain their original cheap/paused animation LOD.
- Inactive or ragdolled animation mixers never spend a priority slot even when
  the network snapshot still carries a boss/elite flag.
- Skeletal modifiers are retained only for eligible high-priority visible
  mixers; ordinary distant IK remains culled.
- Existing mixer phase staggering, max accumulated delta and callback mode
  restoration remain untouched.
- The separate upper-body attack AnimationPlayer is registered as an additional mixer
  so distant enemy attacks no longer run a second 60 Hz animation path by accident.
  Its `manage_modifiers=false` registration ensures **only the primary body mixer**
  controls the skeleton's IK modifiers, avoiding duplicate culling/restore races.
- The priority quota is counted in **mixers**, not characters. A character with
  both locomotion and an upper-body attack layer can consume two priority slots.

A full-rate `advance()` does **not** increase simulation/network tick
frequency, and cannot make a server hit occur earlier.

## Gameplay and graphic quality

`game/scripts/client/combat_animation_priority.gd` selects dangerous poses
from **server-provided state**, not arbitrary client combat authority:

- Raid bosses and enraged raid bosses: prioritized while visible.
- Elite infected in CHASE/ATTACK: prioritized while visible.
- Acid spitters during attack warning: prioritized while visible.
- Staggered zombies during hit reaction: prioritized while visible.
- Idle ordinary zombies, loot and remote players: retain normal LOD.

The slot limits are:

| Graphics preset | Additional full-rate combat mixers |
| --- | ---: |
| Performance | 0 |
| Balanced | 1 |
| High | 4 |
| Ultra | 8 |

`game/scripts/client/entity_view.gd` calls the native setter **only when
the snapshot-selected state changes**. Quality changes update the native
slot budget once. It never adds a second animation controller or calls
`advance()` from GDScript when the native controller owns the mixer.

**Stock Godot fallback:** `character_anim.gd` promotes at most the same
quota of the closest *visible* dangerous combatants to existing full-rate
tier 1, which skips expensive procedural foot IK. It does not add an
AnimationMixer owner and does not change game simulation.

## Regression and real-device validation

- `modules/gameplay_tags/tests/test_gameplay_tags.h`: native registered
  mixer hints and budget bounds.
- `game/tests/test_combat_animation_priority.gd`: player-facing policy,
  4-tier budgets, two-mixer ownership, visual-authority separation, native API/fallback tests.
- `tests/modules/test_combat_animation_budget.py`: lightweight C++/game source
  contracts run by `.github/workflows/combat-animation-budget.yml`.
- `game/tests/run_graphics.gd` and `game/tests/run_all.gd` include the suite.

Rebuild the custom Cgame engine and test a world boss with many zombies
while recording CPU time spent in AnimationMixer/SkeletonModifier3D,
frame-time p95/p99 and at least one actual attack tell at 22–70 m.
Verify camera rotation/off-screen culling, player deaths, ragdoll transitions,
quality switches and boss despawn. A native test build or GPU recording is
required before claiming a measured performance improvement.

Relevant references:
- https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-mass-gameplay-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/MassLOD/FMassSimulationVariableTickParam-
- https://docs.godotengine.org/en/4.4/classes/class_animationmixer.html
