# net.gd

> The network layer.

`res://scripts/shared/net.gd`

## Overview

The network layer. The same node, with the same name and the same RPC list, exists on the server
and on every client (Godot needs that), and `role` decides which half of it does anything.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const StormLightning = preload("res://scripts/shared/storm_lightning.gd")`
- `const CaravanEscort = preload("res://scripts/shared/caravan_escort.gd")`
- `const GuildIdentity = preload("res://scripts/shared/guild_identity.gd")`
- `const GuildSiegeLedger = preload("res://scripts/shared/guild_siege_ledger.gd")`
- `const SiegeOutbox = preload("res://scripts/server/siege_outbox.gd")`
- `const SoloCharacterStore = preload("res://scripts/server/solo_character_store.gd")`
- `const TradeJournal = preload("res://scripts/server/trade_journal.gd")`
- `const MAX_COMMANDS_PER_SECOND := 80`
- `const SAVE_INTERVAL := 30.0`
- `const GUILD_REFRESH_SECONDS := 45.0`
- `const SIEGE_LEDGER_RETRY_SECONDS := 15.0`
- `const PAIR_COMMIT_ATTEMPTS := 6`

## Signals

- `signal welcomed`
- `signal join_refused(reason: String)`
- `signal result_received(kind: String, data: Dictionary)`

## Functions

### `configure_trade_journal`

```gdscript
func configure_trade_journal(journal_path: String) -> bool
```

Opens the deal journal and replays every deal the backend never confirmed before a crash.

### `configure_siege_outbox`

```gdscript
func configure_siege_outbox(journal_path: String) -> bool
```

### `c_join`

```gdscript
func c_join(player_name: String, token: String = "", refresh: String = "") -> void
```

### `leave`

```gdscript
func leave(peer: int) -> bool
```

Removes the disconnected player immediately but waits for all older saves before persisting
the final state. Failed final saves are retained for retry and block a stale character load.

### `shutdown`

```gdscript
func shutdown() -> bool
```

Called for an orderly server stop, including --quit-after.

### `c_input`

```gdscript
func c_input(seq: int, move_x: float, move_z: float, sprint: bool, yaw: float, dt: float, crouch: bool = false) -> void
```

### `c_toggle_mount`

```gdscript
func c_toggle_mount() -> void
```

### `c_place_fish_trap`

```gdscript
func c_place_fish_trap() -> void
```

### `c_collect_fish_trap`

```gdscript
func c_collect_fish_trap(trap_id: int) -> void
```

### `c_fish`

```gdscript
func c_fish(baited: bool = false, storm_cast: bool = false) -> void
```

### `c_gather`

```gdscript
func c_gather(node_id: int) -> void
```

### `c_craft_from_stash`

```gdscript
func c_craft_from_stash(recipe: String, times: int) -> void
```

### `c_enchant`

```gdscript
func c_enchant(item_id: String) -> void
```

### `c_repair_gear`

```gdscript
func c_repair_gear() -> void
```

### `c_alliance`

```gdscript
func c_alliance(action: String, target_peer: int) -> void
```

### `c_guild_bank`

```gdscript
func c_guild_bank(action: String, item_id: String, quantity: int) -> void
```

### `c_plant`

```gdscript
func c_plant(seed_id: String) -> void
```

### `c_harvest`

```gdscript
func c_harvest() -> void
```

### `c_faction`

```gdscript
func c_faction(action: String, faction_id: String) -> void
```

### `c_market_bid`

```gdscript
func c_market_bid(item_id: String, quantity: int, unit_price: int) -> void
```

### `c_market_fill`

```gdscript
func c_market_fill(bid_id: int, quantity: int) -> void
```

### `c_market_cancel_bid`

```gdscript
func c_market_cancel_bid(bid_id: int) -> void
```

### `c_craft_focus`

```gdscript
func c_craft_focus(recipe: String, times: int) -> void
```

### `c_craft`

```gdscript
func c_craft(recipe: String, times: int) -> void
```

### `c_survey_ruins`

```gdscript
func c_survey_ruins() -> void
```

### `c_salvage_gear`

```gdscript
func c_salvage_gear(item_id: String) -> void
```

### `c_dungeon`

```gdscript
func c_dungeon(down: bool) -> void
```

### `c_build`

```gdscript
func c_build(x: float, z: float, yaw: float = 0.0) -> void
```

### `c_toggle_door`

```gdscript
func c_toggle_door(id: int) -> void
```

### `c_build_piece`

```gdscript
func c_build_piece(piece: String, x: float, z: float, facing: float = 0.0) -> void
```

### `c_place_infected_snare`

```gdscript
func c_place_infected_snare(x: float, z: float) -> void
```

### `c_throw_flash`

```gdscript
func c_throw_flash(direction_x: float, direction_z: float) -> void
```

### `c_throw_ember`

```gdscript
func c_throw_ember(direction_x: float, direction_z: float) -> void
```

### `c_throw_decoy`

```gdscript
func c_throw_decoy(direction_x: float, direction_z: float) -> void
```

### `c_pitch_shelter`

```gdscript
func c_pitch_shelter(x: float, z: float) -> void
```

### `c_pack_shelter`

```gdscript
func c_pack_shelter(shelter_id: int) -> void
```

### `c_light_campfire`

```gdscript
func c_light_campfire(x: float, z: float) -> void
```

### `c_arm_camp_alarm`

```gdscript
func c_arm_camp_alarm(fire_id: int) -> void
```

### `c_refuel_campfire`

```gdscript
func c_refuel_campfire(fire_id: int) -> void
```

### `c_extinguish_campfire`

```gdscript
func c_extinguish_campfire(fire_id: int) -> void
```

### `c_repair`

```gdscript
func c_repair(structure_id: int) -> void
```

### `c_upgrade`

```gdscript
func c_upgrade(structure_id: int) -> void
```

### `c_dismantle`

```gdscript
func c_dismantle(structure_id: int) -> void
```

### `c_expedition_restock`

```gdscript
func c_expedition_restock(preset_id: String) -> void
```

### `c_equipment_preset`

```gdscript
func c_equipment_preset(action: String, slot: int) -> void
```

### `c_stash_bulk`

```gdscript
func c_stash_bulk() -> void
```

### `c_stash`

```gdscript
func c_stash(item_id: String, count: int, deposit: bool) -> void
```

### `c_rest`

```gdscript
func c_rest() -> void
```

### `c_outpost_supplies`

```gdscript
func c_outpost_supplies(site_id: int) -> void
```

### `c_caravan`

```gdscript
func c_caravan(action: String) -> void
```

### `c_contract`

```gdscript
func c_contract(action: String) -> void
```

### `c_arena_queue_join`

```gdscript
func c_arena_queue_join() -> void
```

### `c_arena_queue_leave`

```gdscript
func c_arena_queue_leave() -> void
```

### `c_duel_invite`

```gdscript
func c_duel_invite(target_id: int, ranked: bool = false) -> void
```

### `c_duel_accept`

```gdscript
func c_duel_accept() -> void
```

### `c_duel_cancel`

```gdscript
func c_duel_cancel() -> void
```

### `c_party_invite`

```gdscript
func c_party_invite(target_id: int) -> void
```

### `c_party_accept`

```gdscript
func c_party_accept() -> void
```

### `c_party_decline`

```gdscript
func c_party_decline() -> void
```

### `c_party_leave`

```gdscript
func c_party_leave() -> void
```

### `c_party_ready_start`

```gdscript
func c_party_ready_start() -> void
```

### `c_party_ready_answer`

```gdscript
func c_party_ready_answer(ready: bool) -> void
```

### `c_party_standard`

```gdscript
func c_party_standard() -> void
```

### `c_raid_vote`

```gdscript
func c_raid_vote(bag_id: int, choice: String) -> void
```

### `c_party_loot_mode`

```gdscript
func c_party_loot_mode(mode: String) -> void
```

### `c_party_focus`

```gdscript
func c_party_focus() -> void
```

### `c_party_ping`

```gdscript
func c_party_ping(x: float, z: float) -> void
```

### `c_party_corpse_rescue`

```gdscript
func c_party_corpse_rescue() -> void
```

### `c_party_rally`

```gdscript
func c_party_rally() -> void
```

### `c_party_feast`

```gdscript
func c_party_feast(item_id: String) -> void
```

### `c_party_supply_request`

```gdscript
func c_party_supply_request(need: String) -> void
```

### `c_party_aid`

```gdscript
func c_party_aid(target_id: int, item_id: String) -> void
```

### `c_medic_cover`

```gdscript
func c_medic_cover() -> void
```

### `c_party_provision`

```gdscript
func c_party_provision(target_id: int, kind: String) -> void
```

### `c_party_triage`

```gdscript
func c_party_triage() -> void
```

### `c_party_kick`

```gdscript
func c_party_kick(target_id: int) -> void
```

### `c_outpost_provision`

```gdscript
func c_outpost_provision(site_id: int, request_id: int) -> void
```

### `c_outpost_fortify`

```gdscript
func c_outpost_fortify(site_id: int, request_id: int) -> void
```

### `c_outpost_breach`

```gdscript
func c_outpost_breach(site_id: int, request_id: int) -> void
```

### `c_siege_declare`

```gdscript
func c_siege_declare(site_id: int, request_id: int) -> void
```

### `c_trade_invite`

```gdscript
func c_trade_invite(target_id: int) -> void
```

### `c_trade_offer`

```gdscript
func c_trade_offer(trade_id: int, item_id: String, quantity: int) -> void
```

### `c_trade_accept`

```gdscript
func c_trade_accept(trade_id: int, revision: int) -> void
```

### `c_trade_cancel`

```gdscript
func c_trade_cancel(trade_id: int) -> void
```

### `c_market_list`

```gdscript
func c_market_list() -> void
```

### `c_market_create`

```gdscript
func c_market_create(item_id: String, quantity: int, price: int) -> void
```

### `c_market_buy`

```gdscript
func c_market_buy(listing_id: int, quantity: int, request_id: int) -> void
```

### `c_market_cancel`

```gdscript
func c_market_cancel(listing_id: int) -> void
```

### `c_vendor`

```gdscript
func c_vendor(item_id: String, quantity: int, buy: bool) -> void
```

### `c_perk`

```gdscript
func c_perk(perk_id: String) -> void
```

### `c_use`

```gdscript
func c_use(item_id: String) -> void
```

### `c_smart_provision`

```gdscript
func c_smart_provision(intent: String) -> void
```

### `c_quick_medicine`

```gdscript
func c_quick_medicine() -> void
```

### `c_attack`

```gdscript
func c_attack(dir_x: float, dir_z: float) -> void
```

### `c_party_shield_wall`

```gdscript
func c_party_shield_wall() -> void
```

### `c_guardian_intercept`

```gdscript
func c_guardian_intercept(target_id: int) -> void
```

### `c_guardian_taunt`

```gdscript
func c_guardian_taunt() -> void
```

### `c_skill`

```gdscript
func c_skill(dir_x: float, dir_z: float) -> void
```

### `c_skill_ultimate`

```gdscript
func c_skill_ultimate(dir_x: float, dir_z: float) -> void
```

### `c_gear_skill`

```gdscript
func c_gear_skill(slot: String) -> void
```

### `c_stagger_finisher`

```gdscript
func c_stagger_finisher() -> void
```

### `c_power_attack`

```gdscript
func c_power_attack(dir_x: float, dir_z: float, charge: float) -> void
```

### `c_kick`

```gdscript
func c_kick(dir_x: float, dir_z: float) -> void
```

### `c_rage`

```gdscript
func c_rage() -> void
```

### `c_parry`

```gdscript
func c_parry() -> void
```

### `c_arcane_bolt`

```gdscript
func c_arcane_bolt(dir_x: float, dir_z: float) -> void
```

### `c_ultimate`

```gdscript
func c_ultimate() -> void
```

### `c_dodge`

```gdscript
func c_dodge(dir_x: float, dir_z: float) -> void
```

### `c_loot_sweep`

```gdscript
func c_loot_sweep() -> void
```

### `c_loot`

```gdscript
func c_loot(entity_id: int) -> void
```

### `c_raid_claim_selected`

```gdscript
func c_raid_claim_selected(entity_id: int, item_id: String) -> void
```

### `c_raid_skip_turn`

```gdscript
func c_raid_skip_turn(entity_id: int) -> void
```

### `c_refill_canteen`

```gdscript
func c_refill_canteen(boil: bool = false) -> void
```

### `c_sample_spores`

```gdscript
func c_sample_spores() -> void
```

### `c_collect_rain`

```gdscript
func c_collect_rain() -> void
```

### `c_drink`

```gdscript
func c_drink() -> void
```

### `c_debug`

```gdscript
func c_debug(command: String, args: Dictionary) -> void
```

### `s_welcome`

```gdscript
func s_welcome(world_seed: int, tick_rate: int) -> void
```

### `s_join_refused`

```gdscript
func s_join_refused(reason: String) -> void
```

### `s_snapshot`

```gdscript
func s_snapshot(snapshot: Dictionary) -> void
```

### `s_events`

```gdscript
func s_events(list: Array) -> void
```

### `s_result`

```gdscript
func s_result(kind: String, data: Dictionary) -> void
```

### `server_tick`

```gdscript
func server_tick(delta: float) -> void
```

Runs one simulation tick and sends what changed. Called by the server main loop.

_17 private function(s) starting with `_` are not listed._
