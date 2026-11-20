# Destructible Barricade Cover — PvP gunfire

The authoritative `game/` world now supports **shooting enemy-built barricades**
in dangerous red and black zones. This extends `ranged_cover.gd`: the server
first resolves a bullet against solid world geometry, then applies controlled
durability damage only if the first obstacle is a real server-owned barricade.

## Combat rules

- Only a real ranged weapon attack or charged ranged weapon skill with
  server-owned ammunition and validated aim can damage an enemy wall.
  Network clients never send a barricade ID, HP delta or arbitrary damage.
- Bullets stop at **the first solid obstacle**; terrain, rocks, houses and
  static props still absorb fire without being destroyed by this gameplay
  system. A barricade *behind* an infected or PvP opponent is not damaged
  when the closer living target was actually hit.
- Destroying the wall removes it from `WorldGen.dynamic_blockers`, so the
  following shot can reach opponents formerly protected behind it.
- Barricade damage is **60% of verified ranged attack damage**, capped at
  48 raw HP per bullet/ability. Existing fortification resistance then
  applies: T1 100%, T2 82%, T3 66%, T4 50% of raw damage.
- Attackers must stand in a red/black PvP zone, and so must the wall.
  Shooting a structure inside green or yellow territory cannot damage it.
- The wall owner is never permitted to damage their own wall with gunfire.
  Guildmates in the same verified guild at wall construction are also
  protected from friendly-fire griefing. Both account ownership and
  build-time guild ownership are server-controlled.
- Shots into cover still consume ammunition, energy (for skills), cooldown
  and normal infected-attracting noise. No player/infected hit, PvP honor,
  criminal infamy, mastery or kill rewards are invented for wall damage.
- Only the shooter receives the private `barricade_shot` feedback (remaining
  wall HP). Public geometry/durability is already replicated through normal
  interest-filtered world snapshots.

## World persistence

The server's `world_persistence.gd` checkpoint records the builder's
verified guild identifier alongside the authenticated owner, tier and HP.
Validation bounds the guild string, rejects forged types and extra fields,
and continues to accept older 5- or 6-field barricade records as legacy
snapshots. New guild data is server-side only; the public barricade
snapshot does not publish account or guild secrets.

## Tests

`game/tests/test_barricade_ballistics.gd` covers nearest-blocker identity,
wall damage caps, real server construction and PvE cover, physical ammunition
usage, charged shots, T4 mitigation, protected owner and guildmate fire,
server checkpoint restoration and corrupted fields, break cleanup and
private feedback. The suite is registered in `game/tests/run_all.gd`.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

**Scope:** This uses the game's existing horizontal 2D circle collision
world; full 3D ballistics, bullet penetration, heights and ricochets
remain separate future features. No engine API extension was necessary.
