# game_client.gd

> The client's view of the game: the world it generated from the seed, what the server last said, and a predicted position for the local player that is correct...

`res://scripts/client/game_client.gd`

## Overview

The client's view of the game: the world it generated from the seed, what the server last said,
and a predicted position for the local player that is corrected whenever the server answers.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const HousePieces = preload("res://scripts/shared/house_pieces.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const Movement = preload("res://scripts/shared/movement.gd")`
- `const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")`
- `const Survival = preload("res://scripts/shared/survival.gd")`
- `const WadingTravel = preload("res://scripts/shared/wading_travel.gd")`
- `const Skills = preload("res://scripts/shared/skills.gd")`
- `const PartySupplyBeacon = preload("res://scripts/client/party_supply_beacon.gd")`
- `const PcgSpawns = preload("res://scripts/server/pcg_spawns.gd")`

## Signals

- `signal snapshot_received`
- `signal event_received(event: Dictionary)`

## Functions

### `on_welcome`

```gdscript
func on_welcome(world_seed: int, _tick_rate: int) -> void
```

### `on_result`

```gdscript
func on_result(kind: String, data: Dictionary) -> void
```

### `active_supply_beacon`

```gdscript
func active_supply_beacon() -> Dictionary
```

### `on_events`

```gdscript
func on_events(list: Array) -> void
```

### `on_snapshot`

```gdscript
func on_snapshot(snapshot: Dictionary) -> void
```

### `send_input`

```gdscript
func send_input(move: Vector2, sprint: bool, face_yaw: float, delta: float, crouch: bool = false) -> void
```

Moves the local player and tells the server. Call once per physics frame.

### `decay_correction`

```gdscript
func decay_correction(delta: float) -> void
```

### `display_position`

```gdscript
func display_position() -> Vector3
```

Where to draw the local player: the prediction plus the fading correction.

### `join`

```gdscript
func join(player_name: String, token: String = "", refresh: String = "") -> void
```

### `gather`

```gdscript
func gather(node_id: int) -> void
```

### `place_fish_trap`

```gdscript
func place_fish_trap() -> void
```

### `collect_fish_trap`

```gdscript
func collect_fish_trap(trap_id: int) -> void
```

### `nearest_fish_trap`

```gdscript
func nearest_fish_trap(position: Vector3, radius: float = 4.5) -> int
```

### `fish`

```gdscript
func fish(baited: bool = false, storm_cast: bool = false) -> void
```

### `enchant`

```gdscript
func enchant(item_id: String) -> void
```

### `repair_gear`

```gdscript
func repair_gear() -> void
```

### `craft`

```gdscript
func craft(recipe: String, times: int = 1) -> void
```

### `craft_focus`

```gdscript
func craft_focus(recipe: String, times: int = 1) -> void
```

Albion-style focus craft: spends focus at a city workbench to get materials back.

### `craft_from_stash`

```gdscript
func craft_from_stash(recipe: String, times: int = 1) -> void
```

### `salvage_gear`

```gdscript
func salvage_gear(item_id: String) -> void
```

### `buy_perk`

```gdscript
func buy_perk(perk_id: String) -> void
```

### `toggle_mount`

```gdscript
func toggle_mount() -> void
```

### `use_item`

```gdscript
func use_item(item_id: String) -> void
```

### `smart_provision`

```gdscript
func smart_provision(intent: String) -> void
```

### `quick_medicine`

```gdscript
func quick_medicine() -> void
```

### `expedition_restock`

```gdscript
func expedition_restock(preset_id: String) -> void
```

### `equipment_preset`

```gdscript
func equipment_preset(action: String, slot: int) -> void
```

### `deposit_materials`

```gdscript
func deposit_materials() -> void
```

### `move_stash`

```gdscript
func move_stash(item_id: String, count: int, deposit: bool) -> void
```

### `arena_queue_join`

```gdscript
func arena_queue_join() -> void
```

Trade ids and revisions originate from server events. No client-side inventory mutation.

### `arena_queue_leave`

```gdscript
func arena_queue_leave() -> void
```

### `duel_invite`

```gdscript
func duel_invite(target_id: int, ranked: bool = false) -> void
```

### `duel_accept`

```gdscript
func duel_accept() -> void
```

### `duel_cancel`

```gdscript
func duel_cancel() -> void
```

### `party_invite`

```gdscript
func party_invite(target_id: int) -> void
```

### `party_accept`

```gdscript
func party_accept() -> void
```

### `party_decline`

```gdscript
func party_decline() -> void
```

### `party_leave`

```gdscript
func party_leave() -> void
```

### `party_kick`

```gdscript
func party_kick(target_id: int) -> void
```

### `party_feast`

```gdscript
func party_feast(item_id: String) -> void
```

### `party_aid`

```gdscript
func party_aid(target_id: int, item_id: String) -> void
```

### `party_provision`

```gdscript
func party_provision(target_id: int, kind: String) -> void
```

### `party_supply_request`

```gdscript
func party_supply_request(need: String) -> void
```

### `party_triage`

```gdscript
func party_triage() -> void
```

### `medic_cover`

```gdscript
func medic_cover() -> void
```

### `party_ready_start`

```gdscript
func party_ready_start() -> void
```

### `party_ready_answer`

```gdscript
func party_ready_answer(ready: bool) -> void
```

### `party_standard`

```gdscript
func party_standard() -> void
```

### `party_corpse_rescue`

```gdscript
func party_corpse_rescue() -> void
```

### `party_rally`

```gdscript
func party_rally() -> void
```

### `party_ping`

```gdscript
func party_ping(point: Vector2) -> void
```

### `party_focus`

```gdscript
func party_focus() -> void
```

### `party_loot_mode`

```gdscript
func party_loot_mode(mode: String) -> void
```

### `raid_vote`

```gdscript
func raid_vote(bag_id: int, choice: String) -> void
```

### `raid_claim_selected`

```gdscript
func raid_claim_selected(entity_id: int, item_id: String) -> void
```

### `raid_skip_turn`

```gdscript
func raid_skip_turn(entity_id: int) -> void
```

### `outpost_provision`

```gdscript
func outpost_provision(site_id: int) -> void
```

### `outpost_fortify`

```gdscript
func outpost_fortify(site_id: int) -> void
```

### `outpost_breach`

```gdscript
func outpost_breach(site_id: int) -> void
```

### `siege_declare`

```gdscript
func siege_declare(site_id: int) -> void
```

### `trade_invite`

```gdscript
func trade_invite(target_id: int) -> void
```

### `trade_offer`

```gdscript
func trade_offer(trade_id: int, item_id: String, quantity: int) -> void
```

### `trade_accept`

```gdscript
func trade_accept(trade_id: int, revision: int) -> void
```

### `trade_cancel`

```gdscript
func trade_cancel(trade_id: int) -> void
```

### `market_list`

```gdscript
func market_list() -> void
```

Listings are advertised stock, not escrow. Only the server changes inventories.

### `market_create`

```gdscript
func market_create(item_id: String, quantity: int, price: int) -> void
```

### `market_buy`

```gdscript
func market_buy(listing_id: int, quantity: int) -> void
```

### `market_cancel`

```gdscript
func market_cancel(listing_id: int) -> void
```

### `vendor`

```gdscript
func vendor(item_id: String, quantity: int, buy: bool) -> void
```

### `rest`

```gdscript
func rest() -> void
```

### `caravan`

```gdscript
func caravan(action: String) -> void
```

### `contract`

```gdscript
func contract(action: String) -> void
```

### `outpost_supplies`

```gdscript
func outpost_supplies(site_id: int) -> void
```

### `attack`

```gdscript
func attack(direction: Vector2) -> void
```

### `power_attack`

```gdscript
func power_attack(direction: Vector2, charge: float) -> void
```

### `kick`

```gdscript
func kick(direction: Vector2) -> void
```

### `rage`

```gdscript
func rage() -> void
```

### `skill`

```gdscript
func skill(direction: Vector2) -> void
```

### `skill_ultimate`

```gdscript
func skill_ultimate(direction: Vector2) -> void
```

Weapon ultimate (E): a charged version of the weapon skill with its own cooldown.

### `gear_skill`

```gdscript
func gear_skill(slot: String) -> void
```

Armor abilities: "armor" (Iron Skin), "head" (Second Wind), "feet" (Sprint).

### `stagger_finisher`

```gdscript
func stagger_finisher() -> void
```

### `guardian_taunt`

```gdscript
func guardian_taunt() -> void
```

### `guardian_intercept`

```gdscript
func guardian_intercept(ally_id: int) -> void
```

### `party_shield_wall`

```gdscript
func party_shield_wall() -> void
```

### `parry`

```gdscript
func parry() -> void
```

### `arcane_bolt`

```gdscript
func arcane_bolt(direction: Vector2) -> void
```

### `ultimate`

```gdscript
func ultimate() -> void
```

### `dodge`

```gdscript
func dodge(direction: Vector2) -> void
```

### `loot`

```gdscript
func loot(entity_id: int) -> void
```

### `dungeon`

```gdscript
func dungeon(down: bool) -> void
```

### `loot_sweep`

```gdscript
func loot_sweep() -> void
```

### `build`

```gdscript
func build(point: Vector2, yaw: float = 0.0) -> void
```

### `toggle_door`

```gdscript
func toggle_door(id: int) -> void
```

### `nearest_door`

```gdscript
func nearest_door(point: Vector3) -> int
```

The nearest door piece within reach, or -1.

### `build_piece`

```gdscript
func build_piece(piece: String, point: Vector2, facing: float = 0.0) -> void
```

### `repair`

```gdscript
func repair(id: int) -> void
```

### `refill_canteen`

```gdscript
func refill_canteen(boil: bool = false) -> void
```

### `survey_ruins`

```gdscript
func survey_ruins() -> void
```

### `place_infected_snare`

```gdscript
func place_infected_snare(point: Vector2) -> void
```

### `throw_flash`

```gdscript
func throw_flash(direction: Vector2) -> void
```

### `throw_ember`

```gdscript
func throw_ember(direction: Vector2) -> void
```

### `throw_decoy`

```gdscript
func throw_decoy(direction: Vector2) -> void
```

### `pitch_shelter`

```gdscript
func pitch_shelter(point: Vector2) -> void
```

### `pack_shelter`

```gdscript
func pack_shelter(id: int) -> void
```

### `nearest_shelter`

```gdscript
func nearest_shelter(point: Vector3, radius: float = 3.2) -> int
```

### `light_campfire`

```gdscript
func light_campfire(point: Vector2) -> void
```

### `upgrade`

```gdscript
func upgrade(id: int) -> void
```

### `dismantle`

```gdscript
func dismantle(id: int) -> void
```

### `nearest_campfire`

```gdscript
func nearest_campfire(point: Vector3, radius: float = 3.2) -> int
```

### `arm_camp_alarm`

```gdscript
func arm_camp_alarm(id: int) -> void
```

### `refuel_campfire`

```gdscript
func refuel_campfire(id: int) -> void
```

### `extinguish_campfire`

```gdscript
func extinguish_campfire(id: int) -> void
```

### `nearest_barricade`

```gdscript
func nearest_barricade(point: Vector3, radius: float = 3.0) -> int
```

### `sample_spores`

```gdscript
func sample_spores() -> void
```

### `collect_rain`

```gdscript
func collect_rain() -> void
```

### `drink`

```gdscript
func drink() -> void
```

### `node_by_id`

```gdscript
func node_by_id(node_id: int, near: Vector3) -> Dictionary
```

A gatherable node by id, looked up in the chunks around a point (the server only reports ids).

### `nearest_node`

```gdscript
func nearest_node(point: Vector3, radius: float) -> Dictionary
```

Closest gatherable node (not depleted) within `radius` of a point.

### `nearest_loot`

```gdscript
func nearest_loot(point: Vector3, radius: float) -> Dictionary
```

### `market_bid`

```gdscript
func market_bid(item_id: String, quantity: int, price: int) -> void
```

Albion-style buy orders (escrowed silver; sellers fill them at the hub).

### `market_fill`

```gdscript
func market_fill(bid_id: int, quantity: int) -> void
```

### `market_cancel_bid`

```gdscript
func market_cancel_bid(bid_id: int) -> void
```

### `faction`

```gdscript
func faction(action: String, faction_id: String = "") -> void
```

Faction warfare: "enlist" (with a faction id), "flag", "unflag", "redeem".

### `plant`

```gdscript
func plant(seed_id: String) -> void
```

Homestead farming: plant a carried seed in front of you / harvest your nearest ripe plot.

### `harvest`

```gdscript
func harvest() -> void
```

### `guild_bank`

```gdscript
func guild_bank(action: String, item_id: String = "", quantity: int = 0) -> void
```

Guild bank at the hub: "list", "deposit" (any member) or "withdraw" (officers).

### `alliance`

```gdscript
func alliance(action: String, target_peer: int = -1) -> void
```

Guild alliances (leaders, hub): "invite" (target peer), "accept", "leave", "status".

_2 private function(s) starting with `_` are not listed._
