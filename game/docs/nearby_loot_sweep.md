# Nearby PvE loot sweep

The default online client adds **Shift+E / Shift+Q** and an inventory button
to quickly collect up to **five** authorized, ordinary infected loot bags at
the character's current position. The legacy local client uses **Shift+Q**.

The server selects nearby bags (existing reach + 0.5 m), checks their
original frozen PvE killer/party reservations, and calls the normal
`cmd_loot` transaction for each. There are no client-submitted bag IDs,
coordinates or item quantities. A server-owned 1.5-second cooldown caps
requests, and the HUD reports the actual number of items moved and bags
emptied. Excess items remain on the ground when the inventory is full.

Only ordinary PvE bags are eligible. Boss trophies, round-robin and
Need/Greed bags, public/unowned loot, PvP death gear, guarded supply
drops and unopened world crates remain manual. The operation never
bypasses a lock, creates new items or modifies player-vs-player rights.

Regression tests are registered in `game/tests/run_all.gd`.
Run with `godot --headless --path game --script res://tests/run_all.gd`.
