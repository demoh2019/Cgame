# Improvised siege charges — timed barricade breaching

This feature expands the original Days After-style scavenging and the
Albion/Lineage-style full-loot red/black siege zones. A survivor can turn
refined materials into a real **Improvised Siege Charge**, place it against
a nearby enemy-built barricade and fall back before it explodes.

## Craft and use

- Item: `siege_charge`, tier 3, max stack 5.
- Workbench recipe (one charge): **2 Metal Bars T3**, **8 Scrap**,
  **2 Cloth T2**, **2 Stone T2**.
- Requires the existing tier-three crafting progression.
- The ordinary inventory **Use** action handles the charge in both offline
  simulation and online play via the existing authenticated `c_use` RPC.
  No client may specify a target wall ID, damage, fuse or coordinates.
- The server picks the *nearest* barricade within **3.5 m**, then validates
  that the player and wall are both in PvP zones, the wall belongs to a
  different account and is not protected by their verified guild.
- An intervening static rock, tree, wall or building blocks placement;
  the selected wall must be the first physical obstacle between the
  survivor and its center.
- Invalid attempts do not consume materials. After legal placement, exactly
  **one charge** is removed from authoritative inventory, the placement
  becomes a transient world device and a nearby warning announces the
  remaining fuse.

## Fuse, balance and fairness

- **4-second server-owned fuse.** No moving the charge after planting,
  no indefinite client-controlled countdown, and no refund for a planted charge.
- **160 raw structure damage** on detonation, applied through the existing
  T1–T4 durability resistance. T1 walls (120 HP) can be breached outright;
  T4 walls take only 80 HP loss. A real `barricade_broken` removes the
  obstacle from the shared movement and projectile collision world.
- At most **24 active charges worldwide**, **one active charge per authenticated
  account/guest session** and **one armed charge per wall**. Duplicate/use
  replay packets cannot stack or mint additional explosives.
- Each charge is erased **before** the server applies damage. A wall
  destroyed while the fuse is running causes a harmless fizzle instead of
  another payout, duplicate world mutation or a hit on the next nearby wall.
- Only the target barricade takes damage; charges cannot directly harm
  player HP or award creature kills, PvP honor, bounty silver or mastery.
  The detonation spawns a **2.5-second positional sound lure** at the wall
  (23 m infected-hearing radius), without falsely making nearby survivors
  appear noisy.
- The device is intentionally **session-only**: world checkpoint persistence
  saves account-owned barricades but not transient planted charges. The server
  remains authoritative whether the planter stays, moves or disconnects.
- `siege_charge_armed`, `siege_charge_detonated`, and
  `siege_charge_fizzled` events are routed **only to nearby survivors**, never
  providing remote coordinates to spectators.

## Verification

`game/tests/test_siege_charge.gd` covers a paid craft, exact recipe,
atomic refusal, real procedural red-zone construction, owner/guild immunity,
range and blocker restrictions, world-owner and same-wall caps, nearby
notification privacy, a live server fuse, collision clearing, T4 resistance,
re-arming and safe fizzles after an earlier structure death.

Registered in `game/tests/run_all.gd`, run headless with:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

**Engine scope:** the existing 2D world broadphase, inventory, event system
and HP-based structures already support this mechanic. Three-dimensional
projectile physics, arc height, cinematic explosion models and disarming
animations are beyond this feature; they can be added to the engine and
game later without breaking the authoritative economy.
