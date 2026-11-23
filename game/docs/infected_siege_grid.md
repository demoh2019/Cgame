# Stuck-infected wall targeting and private siege alerts

This change improves **Albion After** server scalability with many walls and
infected and makes a genuine attack on a player's base visible in the HUD.

## Lazy infected wall spatial search

Previously, each infected stuck while pursuing a living survivor iterated
**every barricade** in the world to find the first nearby wall in front of
its approach. With many enemies against a built-up settlement this repeatedly
scanned unrelated walls.

`ZombieWallAttackGrid` constructs a light 8-metre spatial hash **once,
on demand, per infected tick**. It contains only attackable wall centres:
walls, closed or open doors, windows, beds and blocking furniture. Floors and
roofs are excluded, as before. A valid attack query checks the original
melee reach and forward-facing dot product, then restores the original
insertion order before selecting the first eligible wall.

The grid is never saved or networked and it never decides whether an
infected may start an attack. Only existing server-verified stuck/target
state can reach it. If an earlier attacker destroyed a wall in the same
simulation tick, later attackers skip that now-missing ID.

The server exposes `last_zombie_wall_query_stats` for inspection:
`queries` counts local searches, `matches` counts matching nearby wall
IDs, and `walls` reports the current authoritative wall population. These
are diagnostic counts, **not measured FPS gains**.

## Base-under-attack warnings

An infected that really starts damaging a live wall now records a **12-second
server-owned alert**. The existing player-specific `you.base_upkeep`
snapshot includes `under_attack`, the number of owned structures currently
being damaged by infected. The HUD shows **BASE UNDER ATTACK** when positive.

- Only the authenticated owner (or matching guest peer) receives the alert.
- An unrelated player's public building snapshot never contains the timer.
- A later infected hit refreshes the alert; expiry clears the indicator.
- Destroyed and stale IDs are purged periodically, keeping session state
  bounded. This warning does not affect wall HP, attack damage or loot.
- Shots by players and unrelated wall damage do not create an *infected*
  warning, and there is no new client-side RPC or persistence field.

## Tests

`test_zombie_pack.gd` checks the new spatial index against the previous
exhaustive scan across 220 walls and 90 seeded approach scenarios, including
walls behind the attacker, exact reach, flooring exclusion and stable order.

`test_barricades.gd` covers live server attacks, private owner-only
snapshots and warning expiry.

```sh
bin/godot.macos.editor.arm64 --headless --path game --script res://tests/run_one.gd -- test_zombie_pack test_barricades
```
