# Smoked trail fish — travel ration system

Smoked fish makes the existing shoreline fishing, campfire, food, and
survival-skills loops useful during longer expeditions. The rules are shared
between the local playable client and the dedicated server.

## Play

1. Catch real **Raw Fish T1–T4** at the shore or collect it from existing
   fishing traps. Carry **2 matching-tier wood** and **1 T1 fiber**.
2. Light a field campfire (or return to the hub workbench). Use **Alt+0**,
   **Quick smoke** in the inventory's Field actions, or select the ordinary
   **Smoked Fish** recipe. Higher fish tiers retain ordinary crafting mastery
   requirements. No campfire, no ingredients, or a full bag means no crafting
   and no item debit.
3. Eat the finished fish with **Alt+Shift+1** or the **Eat smoked fish**
   Field action. Each meal restores hunger and grants one limited travel
   ration effect. The item is consumed exactly once through the server.
4. A status icon under the portrait and an equipment-panel line show the
   remaining time and savings.

| Fish | Hunger restored | Reduced natural hunger drain | Active for |
| --- | ---: | ---: | ---: |
| T1 | +26 | 25% | 210 seconds |
| T2 | +34 | 30% | 270 seconds |
| T3 | +42 | 35% | 330 seconds |
| T4 | +50 | 40% | 390 seconds |

Smoked fish is safe food: unlike **Raw Fish**, it does not cause new food
poisoning. It grants **no** additional damage, stamina, combat energy, PvP
protection or medical healing. The old **Cooked Fish** hearty-meal recovery
buff and **Camp Fish Stew** remain intact.

Only one ration effect may be active at a time. Eating a ration of the same
or higher tier refreshes/replaces the previous timer; eating a weaker ration
while a stronger one is active restores hunger but **does not** extend or
downgrade the stronger effect. There is no duration stacking.

### Other controls are preserved

**0** cooks normal fish, **Shift+0** cooks stew, **1** eats canned food,
**Shift+1** eats stew, **Alt+1** eats raw fish at a poisoning risk, and
**Ctrl+1** uses automatic safe provisions. Only **Alt+0** (smoking) and
**Alt+Shift+1** (smoked ration) are new.

## Engine and networking integration

- `scripts/shared/defs.gd` registers all four stackable smoked-fish
  items and four fully paid campfire recipes.
- `scripts/shared/trail_ration.gd` owns lookup, timer validation, savings,
  fractional tick integration and craftable-tier selection.
- `scripts/server/game_server.gd` owns item use, inventory debit, effect
  rank and duration, skill-aware hunger drain, expiry, death reset, strict
  version-1 save validation and migration, and owner-only HUD snapshots.
- `scripts/client/hud.gd`, `online_main.gd` and `client_main.gd`
  connect field actions, keyboard shortcuts, result feedback and timers to
  the already existing network and local simulation commands.
- `assets/icons/items/smoked_fish.svg` is a lightweight original scalable
  silhouette compatible with the current icon cache and tier suffix lookup.

This system reuses `cmd_use` and `cmd_craft`: it has **no new client-trusted
numeric arguments**, new RPCs or C++ engine dependencies.

The server multiplies only the hunger loss *during the current survival tick*
and restores the player's trained skill multiplier immediately afterward.
If the timed effect expires halfway through a large tick, only the covered
seconds receive savings. The server persists time remaining and validates its
relationship with the recorded item tier; older accounts receive an inactive
effect by default.

## Verification

Run the regression suite from the repository root:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

`tests/test_trail_ration.gd` checks T1–T4 recipes, fuel/skill requirements,
station validation, server item debits, health-safe nourishment, private HUD
state, exact partial-tick math, stronger/lower-tier replacement, legacy
characters, malicious save rejection, reconnect and respawn cleanup.
