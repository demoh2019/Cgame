# Crafting catalogue: search, availability and bulk batches

The connected game's crafting panel (`C`) now provides:

- **Search** across output item names, recipe IDs and ingredient names;
  searches are case-insensitive, and multiple terms must all match.
- **Materials + level** toggle to show only recipes affordable with the
  player's current inventory, sufficient free slots and crafting level.
  Workbench/fire access still comes from the authoritative server.
- **Craft one** on each recipe, or **MAX xN** where N is the largest safe
  batch between 2 and the established server limit of **50**.
- Every inventory slot contributes to refresh detection, including ore,
  fish, bandages, water and rare crafting ingredients.

The max-batch preview clones inventory, simulates the existing atomic
`Crafting.craft` transaction and finds the largest possible batch.
This handles the real slot edge case where crafting several batches
consumes an entire ingredient stack and frees a slot for output, but
crafting one batch does not.

The client cannot craft for free or bypass stations, mastery, mount
restrictions or server checks: it only sends the already-supported
`c_craft(recipe_id, times)` request. No engine changes are needed.

Regression: `game/tests/test_crafting_catalog.gd` is included in
`game/tests/run_all.gd`. Run it with:

```sh
godot --headless --path game --script res://tests/run_all.gd
```
