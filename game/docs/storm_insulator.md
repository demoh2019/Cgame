# Craftable storm insulation

**Copper Storm Insulation Kit** is assembled at a workbench from 1 Metal Bar T2,
2 Cloth T2 and 2 Scrap. Using the kit through the inventory consumes a real item
and grants **180 seconds** of insulation. Lightning deals **60% less damage** to
the survivor while it lasts (16 → 6.4 damage). Dodging or physically leaving
the visible lightning circle still prevents the entire hit.

The effect does not prevent infected attacks, acid, PvP, rain or wet clothing.
It cannot be refreshed while active. The server alone controls real inventory
consumption, character saves, buff expiry and lightning strike damage.
Invalid timers in saves are rejected; older save versions remain loadable.
The kit is cleared upon death and respawn.

Shared rules: `game/scripts/shared/storm_insulator.gd`.
Tests: `game/tests/test_storm_insulator.gd`, included in `game/tests/run_all.gd`.
No Godot engine patch is necessary.
