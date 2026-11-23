# Albion After — Chapter II: Beneath the Island

**Playable continuation** of Chapter I (*The Last Transmission*). This chapter adds a complete underground gameplay arc, two mutually exclusive conclusions and persistent character records without changing or resetting the previous chapter.

## Premise

> "There is a hatch beneath every old bunker. If my signal returns, do not trust what says it is me." — Dr. Mara Voss, Beacon Seven

The second radio transmission is not a rescue signal. It comes from a network of buried quarantine wards. Its original operator never left. The infected guarding the lowest chambers still recognize voices, and the old Protocol ASH is listening for anyone who knows its name.

After collecting the vault log and defeating the guardian, the player chooses whether to **seal the relay** or **broadcast the truth**. Each choice plays a distinct epilogue, commits permanently to the survivor's saved story, and grants one different one-time set of supplies.

## Playable chapter flow

| Stage | Scene and real gameplay | New story recording |
|---|---|---|
| 0 | Finish Chapter I and use **Decode the underground signal** at a real workbench | Introduction to Beacon Seven's second signal |
| 1 | Locate a surface bunker hatch and descend using the existing **Enter dungeon** command | Dr. Voss warns the survivor not to trust the returning voice |
| 2 | Explore a generated dungeon and physically loot **one actual unopened underground chest** | Quarantine ward inscriptions |
| 3 | Find and kill the **real elite dungeon guardian in the deepest room**, while the survivor is still in that dungeon | Vault log reveals that ASH was a listening network |
| 4 | Return to a workbench and select **Seal the signal** or **Broadcast the truth** | The guardian's root key forces a moral choice |
| 5 | Read the exclusive ending in the recovered radio-log journal | Seal: the chambers fall silent; Broadcast: all settlements hear the truth |

**Seal the signal:** the relay is silenced, but an unseen light stays on. Reward: **110 silver and 3 bandages**.

**Broadcast the truth:** the camps hear about Project ASH, and a new voice answers the survivor by name. Reward: **130 silver and 12 rounds of 9 mm ammunition**.

One survivor can claim only one ending and its matching reward. A full backpack refuses the transaction without consuming the ending; players can clear space and retry. Choosing the other ending afterward is rejected.

## UI and controls

The inventory's story section, below the Chapter I journal, now has three buttons: **Decode the underground signal**, **Seal the signal**, and **Broadcast the truth**. The Chapter II journal displays each discovered recording, with the ending shown only after an accepted choice. The illustrated quest card switches from the completed Chapter I to active Chapter II objectives. The F3 detailed HUD also shows the new objective. New plot milestones trigger owner-only banners and radio messages.

Existing dungeon exploration, generated bunkers and physical chests remain unchanged. Players can find bunker sites using their normal world exploration/map; there is no fabricated quest teleport.

## Authority and persistence

- Chapter I's exact existing `story` account field and its stage 4 ending are untouched. Chapter II adds an **optional separate `story2`** field with a strict `{"stage": int, "ending": String}` schema; accounts saved before this release default to a new Chapter II.
- Invalid saves (invalid stage type, fake ending, ending before stage 5, missing completed Chapter I) are rejected in `GameServer.apply_character` **before any state is committed**. A stage 5 ending can be only `seal` or `broadcast`.
- `cmd_story` adds exactly three actions (`decode`, `seal`, `broadcast`) to the existing two Chapter I radio actions. All five verify the real RPC sender, live player and workbench proximity. The new actions additionally require completed Chapter I.
- `cmd_dungeon` awards descent progression only after the actual existing `Dungeon.bunker_at` and `world.dungeon_bunker` checks have succeeded and the server moved the survivor underground.
- `cmd_loot` awards evidence progression only **after** the world-generated real unopened crate is physically looted, and only if the crate is actually marked `dungeon: true` and lies in the player's same underground region. Ordinary surface ruins cannot count.
- The existing procedural `_tick_population` recognizes its `dungeon_boss` world-spawn property and puts a **server-owned marker** on that concrete champion. Chapter II guardian completion is counted only in the existing confirmed lethal PvE damage branch, only if that marker, elite status and the killer's same underground dungeon region are all verified. Ordinary elites, raid bosses, player PvP and missing/dead actors never count.
- Choices use a temporary Inventory copy, validated real item IDs, single atomic reward commit and a permanent ending string. No story money is accepted from the client or paid twice.
- Each player's current chapter and unlocked entries are part of their **own** snapshot, while `story2` events go only to the authenticated owner via the original server event-privacy filter. No other player sees private mission progress, branch decisions or radio logs.

## Verification

New `game/tests/test_story_chapter_two.gd` suite, registered in `game/tests/run_all.gd`, covers linear transitions, forged save rejection, both endings and rewards, full-backpack rollback, true generated dungeon hatch/chest/champion paths, a non-guardian elite false positive, replay protection, private two-player network events, mid-mission saves, completed-branch saves and existing Chapter-I-only accounts.

Run on a machine with Cgame/Godot available:

```bash
godot --headless --path game --script res://tests/run_all.gd
```

**Scope:** Chapter II is fully integrated into existing game interactions; there are no new cinematics, voiced performances, character models, or separate underground map assets included with this change. Chapter III now continues both of these outcomes in [The Missing Convoy](STORY_CAMPAIGN_CHAPTER_3.md), with an inherited ending and new objectives. Native/engine and headless runtime checks must be performed on a Godot/Cgame-capable runner; static inspection alone cannot confirm live execution.
