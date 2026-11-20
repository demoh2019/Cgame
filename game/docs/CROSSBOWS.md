# Salvage Crossbows — ranged crowd control

Craftable salvage crossbows T1–T4 extend the classless post-apocalyptic
survival and MMORPG equipment system. The design is original and uses no
third-party art, characters, or proprietary assets.

- Craft at the workbench from two matching-tier planks, two bars, two
  fibers and one scrap. Higher tiers require existing crafting progression.
- Crossbows use the existing craftable **arrow** ammunition and ranged
  mastery. Ordinary bolts deal 18 / 28 / 38 / 48 base damage,
  have a 25 m maximum range and a slower 1.55 s attack interval.
- Mechanical triggers make more noise than ordinary bows: a 12 m
  infected-attraction radius for 1 second, derived from server-side gear.
- Equip a crossbow, then press **G** for **Pinning Bolt**:
  one physical arrow, 32 combat energy, 7.5-second cooldown,
  1.35-second attack lock, 28 m skill range and 1.35× weapon damage.
- A confirmed skill hit roots one **living infected** for 2 seconds.
  The root prevents movement but **does not disable attacks or spit**.
  Raid bosses are immune, while PvP opponents are never rooted.
  A kill or miss does not create an immobilization effect.
- Immobilization is computed by the authoritative server using the
  existing `Zombie.apply_snare`, ranged ray/cover collision and item
  ownership. The timer is already replicated in enemy snapshots.
  Clients show a **gold tint** and **[PINNED]** label while rooted.
- Ordinary crossbow shots consume arrows but do **not** root enemies.
  Server-controlled combat energy, cooldowns, full-loot PvP zoning,
  guild/party protection and stale equipment rules are unchanged.

No engine-level changes are needed because existing ranged collision,
projectile ammunition, replicated status timers and item crafting are
sufficient.

Regression tests: `game/tests/test_crossbows.gd`, included in
`game/tests/run_all.gd`.

Run all tests when a compatible Godot/Cgame binary is available:

```sh
godot --headless --path game --script res://tests/run_all.gd
```
