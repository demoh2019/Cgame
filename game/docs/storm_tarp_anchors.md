# Storm tarp anchors (survival camp specialization)

The craftable **Storm Tarp Anchor Kit** upgrades a personally owned, actively
deployed field tarp without creating any extra fortifications or safe zones.

- Craft a `storm_tarp_anchors` kit at a real workbench from **1 Metal Bar T2,
  2 Fiber T2, and 2 Cloth T2**.
- Place a normal field tarp in the wilderness (2 Cloth T1 + 2 Fiber T1 +
  1 Plank T1). While dismounted and out of combat, stand within **3.2 m**
  and select **Anchor my field tarp**.
- The server selects the **nearest live tarp**, validates its authenticated
  account owner and consumes exactly **one kit** only after all checks pass.
  No client-selected IDs or positions can force another player's upgrade.
- Anchoring is **one-time per tarp**. It extends the tarp expiration by
  **180 seconds** (normally 240 → 420 total seconds), and improves its
  shared exposure reduction from **75% to 90%** for everyone in the 3.5 m
  cover radius.
- Crouch camouflage remains unchanged. Tents are still vulnerable in PvP;
  blood scent, footstep noise, and gunfire still reveal survivors.
- Updated tent life and public anchored flag are shown in interest-limited
  snapshots without exposing owner IDs or accounts. Existing session-only
  cleanup and pack commands also remove upgraded shelters permanently;
  no upgrade survives world restarts or refunds spent materials.

Regression coverage: `game/tests/test_storm_tarp_anchors.gd` in
`game/tests/run_all.gd`. No Godot engine change is required.
