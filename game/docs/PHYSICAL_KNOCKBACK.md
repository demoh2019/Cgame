# Collision-swept infected knockback

A heavy salvage sledgehammer now combines its existing **Concussive Blow**
(35 combat energy, 9-second ability cooldown, 1.3 s stagger) with a
**two-metre physical shove** when the server confirms a melee hit.

The displacement extends existing game-level locomotion physics:

- `Movement.sweep_displacement` advances an impulse in at most 0.2-m
  segments, reusing `Movement.move` and its collidable blockers,
  sliding and deep-water checks.
- No large single-step teleport: a wall, tree or shoreline can stop
  movement before the full impulse distance is reached.
- Direct `Zombie.apply_knockback` validates positions, strength,
  target life, root state and enemy type. Elite infected move at
  half the normal distance. Raid bosses and corpses are immovable.
  A zombie rooted in a physical snare or by a pinning bolt remains
  anchored.
- Only a real, physically owned hammer and a confirmed server-side
  infected hit can apply the push. Misses, protected PvP targets,
  stale gear and invalid attacks cannot force-move other players.
- The server emits a `knockback` world effect with the **actual**
  displacement. Existing zombie snapshots replicate the new enemy
  position, which clients already interpolate.
- No separate client motion authority, freely supplied impulse or
  new C++ engine primitive is required. The shared movement layer
  gains a reusable bounded physics sweep for future attacks and world
  events.

Regression suite: `game/tests/test_knockback_physics.gd`, included in
`game/tests/run_all.gd`. Covers collidable synthetic terrain,
deep water, elite mass, bosses, anchored enemies, dead targets, limits,
and authoritative server hit/snapshot integration.

```sh
godot --headless --path game --script res://tests/run_all.gd
```
