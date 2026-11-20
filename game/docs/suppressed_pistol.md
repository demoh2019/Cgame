# Improvised Suppressed Pistol — stealth scavenger upgrade

The canonical `game/` project supports a craftable tier-three ranged upgrade
for players who find an ordinary pistol while searching ruins. The design
combines risky post-apocalyptic scavenging with classless MMO weapon progression.

## Crafting

An **Improvised Suppressed Pistol** (`suppressed_pistol`) costs:

- 1 looted pistol
- 2 tier-three metal bars
- 2 tier-three cloth
- 6 scrap metal

Craft at a real workbench with **tier-three crafting mastery**. The old
pistol is consumed atomically and the new weapon remains a normal tradable,
droppable inventory item. The recipe does not create a new pistol out of
thin air: it upgrades an actual scavenged one.

## Combat tradeoff

| Property | Regular pistol | Improvised suppressed pistol |
| --- | --- | --- |
| Damage | 22 | 18 |
| Attack interval | 0.45 s | 0.70 s |
| Standard range | 40 m | 32 m |
| Shot noise radius | 32 m | 12 m |
| Noise duration | 3.0 s | 1.1 s |
| Ammunition | One 9 mm cartridge | One 9 mm cartridge |
| Special attack | Focused Shot | Careful Shot |

**Careful Shot:** 32 combat energy, 6.5 s cooldown, 34 m range,
1.55× normal weapon damage; it consumes one 9 mm cartridge. It shares
the existing server-owned hit resolution, PvP safe/party/guild protections,
ranged mastery, and infected detection channels. A failed no-ammo ability
consumes neither energy nor ammunition.

The upgrade is deliberately weaker at direct sustained damage than the
regular pistol: its advantage is **shorter, quieter sound propagation**.
Other detection channels (vision, blood scent, firelight, terrain, and
nearby active enemy pursuit) are unchanged; the suppressor is not
invisibility. Gunshot events remain regular server combat events.

## Tests

`game/tests/test_suppressed_pistol.gd` verifies item metadata, exact
material consumption, mastery/station gating, replay prevention, live
server shooting, range/noise, ability ammunition and cooldown limits,
and character save/load compatibility.

Run with `godot --headless --path game --script res://tests/run_all.gd`.
The existing CI workflow `albion-after-professions.yml` executes this
suite for changes under `game/`.

No engine-level API extension was needed: the game's existing gear
metadata, skill dispatch and infected-hearing systems support this item.
