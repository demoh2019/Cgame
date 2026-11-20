# Frontier outpost supply convoys

An authorized owner can deliver **2 canned food, 2 water bottles, and 4
T1 wood** at a captured outpost flag (within **4 m**) to extend its
remaining hold duration by **45 seconds**. A capture accepts at most
**four deliveries (180 seconds total)**: no indefinitely paid monopoly.

- Eligible: the live owning party and verified homogeneous-guild Nakama
  allies, even from another party. The caller cannot set the owner.
- Current rivals inside the flag's capture circle block delivery
  immediately. Expiry, loss, invalid position and missing inputs
  block it without consuming resources.
- Server-stage inventory transactions ensure all-or-nothing payment.
- Every request uses a bounded monotonic nonce and caches its receipt.
  Replays cannot spend food twice or extend ownership repeatedly.
- Current additional hold time is visible on the public outpost map,
  and the client has a new inventory-panel action near the flag.
- Fresh captures and expiry reset the per-capture delivery budget.
  Existing fortification and supply cache mechanics are independent.
- Existing Godot networking, party/guild identity, survival inventory
  and world snapshots are sufficient. No engine patch is necessary.

Regression: `game/tests/test_outpost_provisions.gd` in `run_all.gd`.
