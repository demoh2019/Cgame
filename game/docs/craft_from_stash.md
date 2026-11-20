# Craft directly from protected bank at the hub workbench

The crafting panel (`C`) now has a **Use bank** checkbox.
When enabled, the recipe list and **MAX xN** count use the combined
materials in the backpack and the protected stash. Click a recipe or MAX
to craft without withdrawing every material manually.

The bank is accessible **only at the hub workbench**. Rural village
benches, captured outpost benches, campfires and field recipes **cannot**
draw on protected stash stock remotely. The server verifies true player
position, life, mount state, ongoing recall and crafting mastery before
starting the operation. Normal backpack-only crafting remains unchanged.

The transaction clones both containers and consumes backpack ingredients
first, then banked ingredients. The finished item goes into the backpack
only; if no room exists or even one ingredient is missing, neither
container changes. Both containers commit only after success. Existing
crafting progression, XP and the ingredient-refund skill remain controlled
by the server; successful bank crafting marks both containers dirty for
snapshot and persistent account saves.

The client only sends `recipe_id` and `times`, constrained to the
existing 50-batch limit; the server ignores any client claims about item
counts or station permissions.

Automated coverage is in `game/tests/test_craft_from_stash.gd`,
registered in `game/tests/run_all.gd`:

```sh
godot --headless --path game --script res://tests/run_all.gd
```
