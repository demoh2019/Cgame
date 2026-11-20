# Supply drops with infected escorts

Every ten minutes, the existing server may create one public T3/T4 loot cache near a survivor in a full-loot zone. The new encounter spawns up to **two ordinary infected (T3)** or **three, including a brute (T4)**. The player is not granted ownership of the drop; competing PvP parties can still fight over it.

- The server computes all escort positions on walkable, dry terrain in the same danger zone. Positions are separated from survivors, existing infected, and other escorts.
- Guards investigate the public crate using existing zombie AI, then can acquire genuine survivor targets; no fake peer or guaranteed damage is created.
- Zombies are capped by the global event budget (90 active), have no persistent spawn slot, and cannot respawn for the same crate.
- If dense terrain or nearby players block every safe position, the public supply crate still arrives **unguarded** rather than clipping enemies into the world.
- Existing cooldown (600 seconds), cache lifetime (420 seconds), ordinary loot and full-loot rights remain intact. No custom engine features or save format migration are needed.
- Online clients receive the global drop coordinates, tier, and the number of infected guards in their HUD message.

Test: `godot --headless --path game --script res://tests/run_all.gd`. See `test_supply_guards.gd` for geometry, capacity, and server integration checks.


## Clearance notification

When the final original escort dies to confirmed server combat, the crate automatically becomes claimable by **any** nearby survivor. The server emits one local `supply_cleared` event with the cache ID and public coordinates. The multiplayer HUD tells nearby rivals that the public cache is now available.

A per-bag clearance latch prevents repeated notifications, including reprocessed deaths. Ordinary bags, unguarded crates, and removed caches emit no clearance event. The server never sends escort IDs or a killer's identity to spectators. Tests cover this, plus compatibility repairs for the earlier supply-drop test suites.
