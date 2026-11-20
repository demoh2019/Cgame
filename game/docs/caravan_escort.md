# Party caravan escort navigation and private ambush alerts

Current, authenticated party members now receive a **private convoy
destination** selected from the courier's genuine NPC contract.
The leader's active route takes priority over another member's route,
followed by the smallest member ID. Only one destination is shared.

- A violet compass pointer marks the courier's destination in the
  north-up 72 m survival radar; distant destinations display edge arrows.
- Party HUD shows cargo, destination settlement, bearing and remaining
  straight-line distance for the escort.
- Infected caravan ambush alerts also reach members of the **original
  current party**, not only the courier. The alert includes no position,
  backpack, private account ID or hostile character identity.
- The server checks current membership on every snapshot and alert;
  departure, disband or a cancelled/completed job revokes visibility.
- No new client RPCs, gold rewards, personal inventory exposure or
  bypasses of full-loot PvP rules. Existing server authority is reused.

Regression: `game/tests/test_caravan_escort.gd` in `run_all.gd`.
