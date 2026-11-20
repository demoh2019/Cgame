# Round-robin raid rewards: item choice

Albion After combines MMORPG party rewards with a single shared survival loot bag.

A party leader may select **Round robin** for future raid boss kills. The actual contributors are frozen server-side on the kill. Each active contributor takes at most `ceil(original stack count / contributor count)` of **one** resource type per turn. The next contributor receives the following turn.

- **Q** still picks the first available item type automatically.
- **Claim selected** lets the current contributor choose an available item type, without influencing quantity.
- **Pass raid turn** yields an active turn without picking anything up.
- The 12-second turn timeout and 75-second raid reservation are unchanged.
- After reservation expiry, the normal public-loot rules resume.

Only a current eligible contributor can see the selectable item IDs in their snapshot. No account identity tokens, contributor rotation metadata, or hidden reward choices are replicated to spectators. All claims are checked by the server for distance, player state, item availability, turn ownership and the remaining shared bag inventory.

Regression coverage: `res://tests/test_raid_loot_choice.gd`, `res://tests/test_raid_round_robin_pass.gd` and the shared headless test runner.
