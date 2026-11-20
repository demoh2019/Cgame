# Ranged cover: bullets stop at solid scenery and player-built walls

The canonical `game/` simulation now checks **server-owned geometry**
before resolving ranged PvE or PvP hits. This fixes the prior behavior where
an accurately aimed projectile could hit through a solid tree, rock, hub
building, ruin prop, or a constructed barricade.

## How it works

- `ranged_cover.gd` computes the nearest ray/circle entry point from the
  existing `world.blockers_near(...)` broadphase. It uses the same static
  procedurally generated and session-built collision blockers used for
  character movement.
- `GameServer._find_hit(..., ranged=true)` checks cover before selecting
  zombies or PvP-eligible players. All standard ranged attacks and ranged
  weapon skills (including bows, ordinary pistols, and special shots)
  already use this shared hit resolver.
- The wall must stand **between the shooter and target**, not behind the
  shooter, beyond weapon range or off the shot trajectory. The nearest
  solid matters if several objects overlap the shot.
- A projectile that hits cover is still fired: it expends real owned
  ammunition, starts the usual cooldown and emits its usual shot noise.
  No health damage, kill rewards, mastery or PvP credit are generated
  through a blocked target.
- Destroying a barricade removes it from the existing world broadphase
  and opens the firing lane instantly, with no extra network state.
- Melee remains governed by its original angle/reach rules. Training
  duels, friendly-fire restrictions and PvP risk-zone checks remain in
  `GameServer` and are not bypassed.
- No client-originated raycast or hit positions are trusted. The server
  uses only player position, equipped weapon metadata and world-owned
  blockers.

## Limits and future refinements

This is a deterministic **horizontal 2D** collision model matching the
current server gameplay simulation, not full-height 3D bullet physics,
penetration, cover destruction or ricochet. Hills, partial-height cover
and muzzle-to-target height should be modeled in a later engine/physics
milestone after a dedicated 3D combat representation is available.

## Tests

`game/tests/test_ranged_cover.gd` covers circular intersection math,
invalid coordinates, off-axis and behind-shooter obstacles, real
player-built world blockers, actual consumed ammunition on blocked
shots, blocked ranged skills, PvP targeting, instant lane reopening and
unmodified melee rules. The suite is registered in
`game/tests/run_all.gd`.

```sh
godot --headless --path game --script res://tests/run_all.gd
```
