# Engine: Gameplay Tags and Animation LOD

**Status: NOT YET COMPILED.** The C++ in `modules/gameplay_tags/` was written statically (no scons run). The game
detects the classes at runtime (`ClassDB.class_exists`) and falls back to GDScript on the current editor binary.

## What and equivalents

| Class | Unreal | Unity |
|---|---|---|
| `GameplayTagContainer` (Resource) | Gameplay Tag Container | (none; tags/layers are flat) |
| `GameplayTagQuery` (Resource) | Gameplay Tag Query | n/a |
| `AnimationLODController` (Node) | Animation Update Rate Optimization (URO) | Animator Culling Mode |

## API

`GameplayTagContainer`: `add_tag`, `add_tags`, `remove_tag`, `clear`, `has_tag(tag, exact=false)`,
`has_any(tags, exact=false)`, `has_all(tags, exact=false)`, `get_tag_count`, `is_empty`, property `tags`
(PackedStringArray), and `static tag_matches(tag, query, exact=false)`. A non-exact query matches the tag itself or a
parent on a `.` boundary: `Enemy.Infected.Elite` has `Enemy` but not `Ene`; empty strings never match.

`GameplayTagQuery`: `all_tags`, `any_tags` (ignored when empty), `none_tags`, `exact`, `matches(container)`.

`AnimationLODController`: `register_mixer(AnimationMixer)`, `unregister_mixer`, `clear_mixers`, `get_mixer_count`,
properties `enabled`, `near_distance` (15), `mid_distance` (35), `far_distance` (70), `modifier_cull_distance` (40,
0 = off), `cull_offscreen`, `max_accumulated_delta` (0.5 s), and `static update_interval(distance, visible, near, mid, far)`
returning 1 (<near), 2 (<mid), 4 (<far), else 0 = paused (also 0 when not visible).

Behaviour: registered mixers are set to manual callback mode and advanced every internal-process frame at their interval
(staggered per mixer) with skipped delta accumulated, so animation time stays correct. Distance is camera to the nearest
Node3D ancestor of the mixer. Inactive mixers are not advanced. Beyond `modifier_cull_distance` (or when off-screen) the
`SkeletonModifier3D` nodes under the mixer's root node are disabled and re-enabled afterwards. Original callback modes are
restored on unregister, disable and tree exit. Not active in the editor.

## Game usage

- `scripts/client/engine_features.gd`: `has(class)`, `tag_node(node, tags)` (sets meta `tags` to a container when available).
- `scripts/client/anim_lod.gd`: GDScript fallback with identical thresholds (`update_interval`, `tick` for accumulation),
  scaled by `GraphicsQuality.level()` (x0.7 Performance, 1.0 Balanced, 1.5 High, 2.5 Ultra). It stops managing a model
  once `_dead` is set (ragdoll / death animation need the animator).
- `scripts/client/entity_view.gd`: creates the native controller if present, else `AnimLod`; registers each player/zombie
  `CharacterModel.animator` on creation, unregisters on removal (before the ragdoll attempt); tags nodes
  `Enemy.Infected.<Type>` or `Player`.
- Tests: `game/tests/test_anim_lod.gd` (GDScript fallback, 26 checks); C++ doctests in
  `modules/gameplay_tags/tests/test_gameplay_tags.h` (tag matching, queries, `update_interval`).

## To verify after the next rebuild

Compile `modules/gameplay_tags`, run `--test --test-case="*GameplayTags*,*AnimationLODController*"`, regenerate class
docs, then check in game that distant zombies animate at reduced rate and the native path is chosen.
