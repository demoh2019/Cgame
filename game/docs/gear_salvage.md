# Gear recycling at the survivor workbench

A classless Albion-style item sink / salvage loop for the Days After survival economy.

- **Inventory UI:** select a spare weapon, armor or tool in the recycle selector and press **Recycle gear**.
- The server verifies the survivor is alive, in the safe settlement and within 6 meters of the actual workbench.
- The server accepts only an **item ID**. It independently checks that one unit exists and is not currently equipped.
- For craftable, one-output gear, recover floor(50%) of each ingredient from the current recipe. Zero-quantity inputs are omitted. The reduced refund prevents repeated craft-and-recycle loops from producing new resources.
- For loot-only equipment (e.g. a pistol), or gear whose recipe produces no recoverable ingredients, return a limited amount of scrap by tier. Currency, food, consumables and unrecognized IDs are rejected.
- The operation clones the inventory, spends exactly one piece, tries every refund, and commits only if everything fits. Any failure leaves the backpack unchanged. There is no client-trusted count or amount.
- Existing inventory snapshots, character persistence, quick equipment changes and PvP loot continue to use the same schema; no engine patch is necessary.
- Run: `godot --headless --path game --script res://tests/run_all.gd`. Regression checks live in `test_gear_salvage.gd`.
