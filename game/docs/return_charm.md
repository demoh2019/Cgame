# Settler's Return Charm

A T2 workbench-crafted consumable returns a survivor from green/yellow expeditions to a verified safe settlement. Recipe: **1 Metal Bar T2, 2 Cloth T2 and 30 Silver**. Offline use: **Home** key; multiplayer: **Return charm** inventory button.

The client sends only the existing authenticated `use_item("return_charm")` command. The server owns the eight-second deadline, cast start point, final landing, five-minute cooldown and inventory debit. Only successful completion spends one charm; movement over 0.45m, damage, attacks, infected within 20m, an active duel or a full-loot region all prevent a free escape. The server rechecks hazards after infected/acid damage on the completion tick, and chooses a collision-free location in the safe hub. No movement mastery is granted for teleportation.

Channel progress and success/cancellation messages are delivered only to the owning player. Session-only cast and cooldown fields need no character save migration. This never extracts items from red/black full-loot PvP zones.

Test with `godot --headless --path game --script res://tests/run_all.gd`, including `test_hub_recall.gd`.
