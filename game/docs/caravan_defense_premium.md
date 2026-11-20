# Defending an infected caravan ambush

Dangerous-zone cargo routes already spawn up to four server-owned infected.
A new 15% NPC danger premium rewards couriers who *actually eliminate every
member of that one scheduled ambush* before it expires and later bring the
required T2 cargo to the destination NPC.

- The authoritative kill callbacks count distinct IDs from the original
  wave. Merely escaping, waiting for the wave to despawn, losing the cargo,
  or claiming another monster's death cannot complete the defense.
- The courier must remain alive and retain the same authenticated route;
  dying forfeits an unpaid defense, including after respawn. Abandoning a
  route, delivering it, or disconnecting removes any leftover wave mobs.
- The earned defense flag persists with the current verified route and is
  validated on character load. Old saves without the field default to false.
  A bonus cannot be attached to an inactive route or one with no ambush.
- On delivery the NPC awards an additional 15% of the **original 50–140
  silver fare**, rounded to whole silver and capped at 21. Escort payments
  are calculated only from the original base fare, never from bonus silver.
- Courier, escort and bonus transfers are staged atomically: if any
  inventory is full, neither the cargo nor any payout is consumed.
- The courier alone receives the completion notice and earned-state status.
  Delivery receipts show the premium separately. No new client RPC exists.

The mechanic uses Godot's existing server simulation, character saving,
inventory, event visibility, and caravan UI. No engine changes are required.

Tests: `game/tests/test_caravan_defense.gd` registered in
`game/tests/run_all.gd`.
