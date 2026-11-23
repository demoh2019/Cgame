# Albion After — Chapter I: The Last Transmission

**Playable story chapter** introduced as an additive narrative campaign. No previous contracts, world generation, PvP rules or economy progression are replaced.

## Premise

The island is officially abandoned. The safe camp's emergency receiver is still pulling a badly fragmented transmission from an old research site known as **Beacon Seven**. The speaker calls herself Dr. **Mara Voss** and claims the containment protocol, **ASH**, was supposed to save lives. But it may have done something entirely different.

> "The cure was never meant to leave this island."

One field log survived in a quarantined research cache. When a survivor recovers it, the infected begin responding to a strange pulse. The survivor must protect the recording long enough to transmit it, revealing a larger mystery beneath the island.

## Playable quest flow

| Stage | Scene | Gameplay objective | Result |
|---|---|---|---|
| 0 — Static | Radio silence | Approach a workbench and choose **Listen to Beacon Seven** | Unlocks Beacon Seven transmission and objective |
| 1 — The cache | A wrong evacuation map | Physically loot **one real, unopened ruin cache in a red/black zone** | Dr. Voss's recovered log and the ASH revelation |
| 2 — Echo carriers | The infected listen | Kill **three genuine infected** with server-authoritative PvE damage | Decodes the relay fragment; unlocks homecoming |
| 3 — Final relay | Back to safety | Return to a workbench, choose **Transmit the recording** | Completes Chapter I, gives one-time reward |
| 4 — Epilogue | The deep signal | Read the final unlocked journal entry | "The island was never the source..." |

Completion reward (one time): **90 silver, 2 bandages, 10 units of 9mm ammunition**. Completion requires free inventory capacity; if items do not fit, neither chapter state nor backpack changes.

## How players experience the story

The **inventory's Camp contracts section** contains two additional actions, *Listen to Beacon Seven* and *Transmit the recording*, and a story journal showing previously unlocked transcripts. The default **illustrated quest HUD** displays the current chapter objective. F3's detailed text interface also shows the objective.

The game generates **private story events** when the radio is activated, evidence is recovered, the final infected carrier falls, or the chapter ends. Network event visibility is checked against the authenticated owner. The server's `snapshot_for` also publishes each character's own title, current stage, objective and only the **unlocked** transmissions; other players never receive the survivor's story state.

## Authoritative rules

- `game/scripts/shared/story_campaign.gd` owns an explicit linear four-transition state machine (stages 0–4). `valid_state` rejects skipped/contradictory/extra checkpoint keys and noninteger stages.
- `GameServer.cmd_story(peer_id, action)` accepts only two strings: `listen` or `transmit`. It checks player life and server-computed distance to a real workbench. Clients **cannot** submit objective progress, target ID, chapter ID or rewards.
- Ruin evidence is recorded **only after** the existing `cmd_loot` server path verifies physical reach, unopened crate, water access, and successful loot, and only when `crate.zone >= 2`.
- Combat progress is recorded **only after** the existing `_damage_target` confirms lethal damage to an infected and credits the server-side player. Damaging the same dead infected twice, PvP, or kills before the evidence stage cannot count.
- The trial-inventory reward transaction mirrors the existing contract reward flow. Failed claims leave carried gear, consumables and story state unchanged. Completed chapters do not pay twice.
- The account's existing version-one `character_data` format now has an optional `story` field. Missing fields in older saved characters default to stage 0; malformed new saves fail validation **before** the server replaces the live character.
- The story chapter is **not** a resettable daily bounty. It does not interact with full-loot PvP, raid loot rights, random world events or active contracts.

## Files and validation

- New campaign: `game/scripts/shared/story_campaign.gd`.
- Server state, persistence, real loot/kill transitions, private snapshot: `game/scripts/server/game_server.gd`.
- Authenticated network action and private event filtering: `game/scripts/shared/net.gd`.
- Client request: `game/scripts/client/game_client.gd`.
- Inventory action buttons, journal and live feedback: `game/scripts/client/hud.gd`.
- Default rendered quest UI: `game/scripts/client/hud_skin.gd`.
- Real campaign regression: `game/tests/test_story_campaign.gd`, registered in `game/tests/run_all.gd`.

Headless command (when a Godot/Cgame executable is available):

```bash
godot --headless --path game --script res://tests/run_all.gd
```

Regression coverage: new/old character loading, strict state validation, partial-progress restart, real danger-zone cache loot, lethal infected kills, objective ordering, owner-only events and snapshots, replay prevention, one-time rewards, insufficient backpack space, and final journal epilogue.

The final transmission is an **explicit hook for Chapter II**; no future chapters or cinematics are falsely claimed to be implemented here.
