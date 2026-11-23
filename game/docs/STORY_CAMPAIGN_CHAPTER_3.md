# Albion After — Chapter III: The Missing Convoy

This is a playable continuation of **Chapter II: Beneath the Island**, inside the canonical `game/` project. It responds to the survivor's permanent **seal** or **broadcast** choice, using existing real scavenging and NPC trade routes rather than separate demo levels or fabricated quest objects.

## The story

A ghost transmission on Frequency 13 reads the names of a missing humanitarian convoy. Dr. Mara Voss is on its manifest. The transmission arrives differently depending on the player's previous choice:

- **Seal:** the underground relay is silent, but an old civilian convoy still knows a forgotten route. A quiet rescue may be possible.
- **Broadcast:** the camps heard the truth, but Project ASH knows the survivor's voice. Rescuing the convoy risks allowing the network to follow.

The survivor recovers a **real high-risk ruin cache** containing the convoy manifest, then completes a **real merchant caravan delivery** between two generated settlements to restore the lost waypoint. Returning to a camp radio forces a new irreversible choice:

- **Guide the missing convoy:** broadcast a safe route and guide its survivors toward the camps. Reward: **160 silver + 3 bandages**. The epilogue changes depending on whether Chapter II was sealed or broadcast.
- **Mask the convoy's route:** flood the network with false coordinates so that neither camps nor ASH can reliably track the convoy. Reward: **140 silver + 16 rounds of 9 mm ammunition**. The epilogue also depends on the prior Chapter II choice.

This produces **four distinct epilogues** from two previous endings and two new choices.

## How to play

| Stage | Game action | Evidence revealed |
|---|---|---|
| 0 | Finish Chapter II; at a camp workbench choose **Trace missing convoy** in the inventory's mission section | Frequency 13 introduction |
| 1 | Loot an unopened, surface-world ruin cache in a **red/black danger zone** | Missing convoy manifest |
| 2 | Accept a merchant caravan at an actual settlement NPC station, carry the requested goods, and **deliver them at its real destination** | Restored trade-road waypoint |
| 3 | Return to a workbench and choose **Guide convoy to safety** or **Mask convoy route** | Exclusive, branch-aware epilogue |
| 4 | Read the recovered logs in the Chapter III journal | Completed narrative and committed reward |

The game does **not** spawn physical survivor NPCs or a new convoy model for this chapter. The story is told through verified world actions, radio transmissions and the existing journal. It is not a cutscene quest.

## Engine / server integration

- `scripts/shared/story_chapter_three.gd` is a deterministic reusable state machine with a strict `{stage: int, source: String, ending: String}` save schema. Stage 0 has an empty source/ending; subsequent stages pin the actual Chapter II ending, and only stage 4 may store `guide` or `mask`.
- `GameServer` stores it separately in optional `story3`, so legacy saves load unmodified. Any save that starts Chapter III without a completed Chapter II or changes the inherited branch is rejected **before** applying changes to the character.
- The existing `cmd_story` permits only `trace`, `guide`, `mask` in addition to previous chapters; the server verifies the live RPC sender, real workbench, and Chapter II completion. The client may not report its own progress.
- Only **successful, physical surface ruin loot** with `crate.zone >= 2` records evidence. Dungeon and underwater shortcuts, fake client IDs, opened crates and low-danger loot cannot advance the quest.
- Only `CaravanEscortRewards.settle` returning success after a real NPC destination and cargo transaction records the delivery. Merely accepting/abandoning a caravan or calling a failed delivery never advances it.
- Every milestone goes into private `story3` events, filtered by authenticated owner. The owner also sees a private `snapshot_for` mission journal and HUD transcript, which is withheld until Chapter II is complete.
- Choice rewards are staged in a temporary Inventory first. A full bag refuses the whole transaction without consuming the ending, and repeat choices can never pay again.
- UI is connected to the actual online/solo client through `game_client.gd`, `net.gd` and `hud.gd`; there is no separate game scene.

## Verification

`game/tests/test_story_chapter_three.gd` is registered in the headless suite. It covers strict save schema and branch inheritance, dialogue exposure, replay protection, atomic rewards, live workbench checks, generated high-risk cache loot, successful NPC merchant deliveries, owner-only events, forged save rejection, and account reload across completion.

Run in a Cgame/Godot-capable checkout:

```bash
bin/godot.macos.editor.arm64 --headless --path game --script res://tests/run_one.gd -- test_story_chapter_three test_story_chapter_two test_story_campaign test_caravan_routes
```

The source was updated through GitHub; live Godot execution is still required where the editor binary is available.
