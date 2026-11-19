# Scrap-to-ammunition crafting

The same game project now connects Days After firearms to Albion-style
resource tiers and crafting mastery. Once a survivor reaches crafting
**tier 2**, a workbench can manufacture **12× 9mm cartridges** from:

- **2× scrap**, found through post-apocalyptic scavenging
- **1× T2 metal bar**, refined by a metalworking survivor from T2 ore

Ammo remains obtainable as found loot, so early exploration and combat do not
require a crafting profession. The T2 restriction applies to **manufacturing**,
not to equipping a scavenged pistol or firing cartridges already carried.

The recipe lives in the common `Defs.recipes()` registry and automatically
appears alongside existing local and online crafting recipes. Requests pass
through the existing authoritative `GameServer.cmd_craft()`, which enforces
crafting level, workbench range, quantity and available inventory space.
Ingredient removal and adding rounds use one rollback-safe transaction.
The existing weapon firing command consumes one cartridge per actual shot.

**No engine modifications are necessary**; all required functionality is
already supported by Cgame's shared game simulation and inventory APIs.

Headless test:
```sh
godot --headless --path game --script res://tests/run_all.gd
```
`test_ammunition_loop.gd` covers skill gates, station checks, two-batch
production, full-bag rollback, craft replay, firing a crafted round and saved
character restoration.
