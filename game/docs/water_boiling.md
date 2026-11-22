# Field water gathering and boiling

**Implemented in the canonical `game/` project.** All item transactions are owned
by `GameServer`; the client uses the existing item-use and crafting RPCs.

## Survivor loop

1. Craft **Empty Water Pouch** anywhere: 1 Cloth T1 + 1 Fiber T1.
2. Walk to a genuinely accessible lake shore. Use the pouch from the inventory
   Field action, or press **Shift+2**. One pouch becomes **Unboiled Lake Water**.
   The same 12-second lake-water cooldown used by direct drinking and reusable
   canteen refills applies, even after rejoining.
3. Light a field campfire (3 Wood T1 + 1 Stone T1) or return to the Haven
   workbench. Choose **Boiled Water** in the ordinary crafting interface: one
   unboiled water plus **1 Wood T1** produces one ordinary **Water Bottle**.
   The campfire has to be active and within its warmth range; the recipe cannot
   be completed at a remote cold location.
4. Drink the water via the normal inventory use button or **2**. This bottle
   restores the same thirst as ordinary clean bottles and does not inflict
   direct lake-water contamination. Raw lake water is deliberately unusable.

The existing **reusable field canteen + charcoal filter** route remains an
alternative for players with better supplies. Filling a pouch consumes the
pouch rather than giving a free permanent bottle or duplicate resources.

## Integration and safeguards

- `scripts/shared/defs.gd`: two new item definitions, field pouch recipe,
  and the campfire boiling recipe.
- `scripts/server/game_server.gd`: server checks ownership, living player,
  mounted state, combat, current location, and the existing persisted lake
  cooldown. It atomically swaps pouch for water, even at capacity; failures do
  not spend resources or start the cooldown.
- `scripts/shared/crafting.gd` and existing `FieldCampfire.has_warmth`:
  the original atomic crafting transaction validates fuel, live station,
  capacity and rewards; no new network message or engine change is required.
- `scripts/client/online_main.gd`: Shift+2 support.
  `scripts/client/hud.gd`: discoverable inventory Field action.
- `tests/test_water_boiling.gd`: recipes, shore validation, one-time item
  debit, shared cooldown, persistence, no raw-water drinking, fire requirement,
  safe drinking, inventory-full rollback and freed-slot success.

## Run the full suite

```sh
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/smoke_client_scene.gd
```

These steps rely only on existing Godot scripting, server simulation, item
registry and the client HUD. They do not require a native C++ engine feature.
