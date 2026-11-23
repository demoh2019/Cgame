extends RefCounted
## The client's view of the game: the world it generated from the seed, what the server last said,
## and a predicted position for the local player that is corrected whenever the server answers.

const Defs = preload("res://scripts/shared/defs.gd")
const ResourceGathering = preload("res://scripts/shared/resource_gathering.gd")
const HousePieces = preload("res://scripts/shared/house_pieces.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const WadingTravel = preload("res://scripts/shared/wading_travel.gd")
const Skills = preload("res://scripts/shared/skills.gd")
const PartySupplyBeacon = preload("res://scripts/client/party_supply_beacon.gd")
const PcgSpawns = preload("res://scripts/server/pcg_spawns.gd")

signal snapshot_received
signal event_received(event: Dictionary)

var net
var world
var peer_id: int = 0
var welcomed: bool = false
var inventory = Inventory.new()
var skills = Skills.new() # The character's skill sheet, as last reported by the server.
var skill_points: int = 0
var stash = Inventory.new(Defs.STASH_SLOTS)
var you: Dictionary = {}
var players: Dictionary = {} # id -> entity from the latest snapshot
var zombies: Dictionary = {}
var barricades: Dictionary = {} # Nearby defenses from the server.
var campfires: Dictionary = {} # Nearby temporary warmth sources, server-provided.
var farm_plots: Dictionary = {} # Nearby homestead crop plots, server-provided.
var shelters: Dictionary = {} # Replicated temporary weather cover.
var decoys: Dictionary = {} # Ephemeral world lures from the server snapshot.
var smoke_clouds: Dictionary = {} # Interest-limited, temporary visual smoke.
var infected_snares: Dictionary = {} # Server-replicated temporary PvE traps.
var fish_traps: Dictionary = {} # Anonymous public, server-owned shoreline nets.
var lightning_telegraph: Dictionary = {} # Nearby server-authored lightning danger circle.
var raid_telegraph: Dictionary = {} # Current server-authored raid attack warning, if visible.
var raid_interrupt: Dictionary = {} # Anonymous party-only interrupt progress for visible warning.
var raid_cone_telegraph: Dictionary = {} # Interest-limited server-authored cleave sector.
var spit_zones: Dictionary = {} # Only the latest server-issued acid telegraphs.
var acid_pools: Dictionary = {} # Replicated lingering ground hazards.
var ember_pools: Dictionary = {} # Replicated server-owned burning ground.
var outposts: Array = [] # Public server-controlled PvP objectives.
var bags: Dictionary = {}
var depleted: Dictionary = {}
var resource_hits: Dictionary = {} # Server-verified nearby node id -> completed strikes.
var crates_used: Dictionary = {}
var world_state_revision: int = Time.get_ticks_usec() # Geometry and collision visibility only.
var resource_damage_revision: int = 1 # Per-instance mining tint; avoid full chunk visibility scans on every hit.
var server_time: float = 0.0
var snapshots_received: int = 0
var events: Array = [] # Recent events, newest last (for the HUD log).
var supply_beacon: Dictionary = {} # Latest active, private party aid location.
var last_results: Dictionary = {} # command kind -> last result

# Client side prediction.
var predicted: Vector3
var predicted_stamina: float = Defs.MAX_STAMINA
var _seq: int = 0
var _pending: Array = [] # {seq, input, dt}
var correction: Vector3 = Vector3.ZERO # Visual offset that decays, so corrections do not snap.
var yaw: float = 0.0
var total_corrections: int = 0
var worst_error: float = 0.0


func _init(p_net) -> void:
	net = p_net
	net.client = self
	peer_id = 0


func on_welcome(world_seed: int, _tick_rate: int) -> void:
	world = WorldGen.new(world_seed)
	PcgSpawns.attach(world) # Same deterministic crate list as the server; only presentation (the server stays authoritative).
	welcomed = true
	peer_id = net.multiplayer.get_unique_id()
	predicted_stamina = Defs.MAX_STAMINA
	supply_beacon = {} # A reconnect must not reveal previous party markers.


func on_result(kind: String, data: Dictionary) -> void:
	last_results[kind] = data


func active_supply_beacon() -> Dictionary:
	return PartySupplyBeacon.read(supply_beacon, peer_id, you.get("party", {}), server_time)


func on_events(list: Array) -> void:
	for event in list:
		if str(event.get("type", "")) == "gathered" and bool(event.get("strike", false)):
			var node_id: int = int(event.get("node", -1))
			if bool(event.get("final", false)):
				if resource_hits.erase(node_id):
					resource_damage_revision += 1
			else:
				var next_hits: int = int(event.get("hit", 0))
				if int(resource_hits.get(node_id, -1)) != next_hits:
					resource_hits[node_id] = next_hits
					resource_damage_revision += 1
		if str(event.get("type", "")) == "party_supply_request":
			var seen: Dictionary = PartySupplyBeacon.read(
				event, peer_id, you.get("party", {}), server_time)
			if not seen.is_empty() and (supply_beacon.is_empty() or
					float(seen["expires"]) >= float(supply_beacon.get("expires", -INF))):
				supply_beacon = seen
		events.append(event)
		event_received.emit(event)
	while events.size() > 40:
		events.pop_front()


func on_snapshot(snapshot: Dictionary) -> void:
	if world == null:
		return
	snapshots_received += 1
	server_time = float(snapshot["time"])
	you = snapshot["you"]
	supply_beacon = PartySupplyBeacon.read(
		supply_beacon, peer_id, you.get("party", {}), server_time)
	lightning_telegraph = snapshot.get("lightning_telegraph", {}).duplicate(true)
	raid_telegraph = snapshot.get("raid_telegraph", {}).duplicate(true)
	raid_interrupt = snapshot.get("raid_interrupt", {}).duplicate(true)
	raid_cone_telegraph = snapshot.get("raid_cone_telegraph", {}).duplicate(true)
	spit_zones.clear()
	for zone in snapshot.get("spit_zones", []):
		spit_zones[int(zone["id"])] = zone
	acid_pools.clear()
	for pool in snapshot.get("acid_pools", []):
		acid_pools[int(pool["id"])] = pool
	ember_pools.clear()
	for field in snapshot.get("ember_pools", []):
		ember_pools[int(field["id"])] = field
	outposts = snapshot.get("outposts", [])
	if snapshot.has("inventory"):
		inventory.load_dict(snapshot["inventory"])
	if snapshot.has("skills") and skills.load_dict(snapshot["skills"]):
		skill_points = int(snapshot["skills"].get("points", 0))
	if snapshot.has("stash"):
		stash.load_dict(snapshot["stash"])
	players.clear()
	for entity in snapshot["players"]:
		players[entity["id"]] = entity
	zombies.clear()
	for entity in snapshot["zombies"]:
		zombies[entity["id"]] = entity
	infected_snares.clear()
	for entity in snapshot.get("infected_snares", []):
		infected_snares[int(entity["id"])] = entity
	fish_traps.clear()
	for entity in snapshot.get("fish_traps", []):
		fish_traps[int(entity["id"])] = entity
	decoys.clear()
	for entity in snapshot.get("decoys", []):
		decoys[int(entity["id"])] = entity
	smoke_clouds.clear()
	for entity in snapshot.get("smoke_clouds", []):
		smoke_clouds[int(entity["id"])] = entity
	farm_plots.clear()
	for plot in snapshot.get("farm_plots", []):
		farm_plots[int(plot["id"])] = plot
	campfires.clear()
	for entity in snapshot.get("campfires", []):
		campfires[int(entity["id"])] = entity
	shelters.clear()
	for entity in snapshot.get("shelters", []):
		shelters[int(entity["id"])] = entity
	bags.clear()
	for entity in snapshot["bags"]:
		bags[entity["id"]] = entity
	# The client predicts movement against the same structure circles as the
	# server, but only the server can create or damage them.
	if snapshot.has("barricades"):
		barricades.clear()
		world.dynamic_blockers.clear()
		for entity in snapshot["barricades"]:
			var id: int = int(entity["id"])
			barricades[id] = entity
			var piece: String = str(entity.get("piece", ""))
			if HousePieces.valid(piece):
				world.add_structure_blockers(id, HousePieces.blockers_of(entity))
			else:
				world.add_dynamic_blocker(id, float(entity["x"]), float(entity["z"]), 0.85)
	var next_resource_hits: Dictionary = {}
	for entry in snapshot.get("resource_hits", []):
		next_resource_hits[int(entry["id"])] = int(entry["hits"])
	if resource_hits != next_resource_hits:
		resource_damage_revision += 1
	resource_hits = next_resource_hits
	var next_depleted: Dictionary = {}
	for id in snapshot["depleted"]:
		next_depleted[id] = true
	var next_crates: Dictionary = {}
	for id in snapshot["crates_used"]:
		next_crates[id] = true
	if next_depleted != depleted or next_crates != crates_used:
		world_state_revision += 1
		# Prediction must see the same gaps as the server's depleted geometry
		# before replaying input; otherwise mining creates invisible walls.
		if next_depleted != depleted:
			world.sync_depleted_nodes(next_depleted)
	depleted = next_depleted
	crates_used = next_crates
	_reconcile(snapshot)
	snapshot_received.emit()


func _reconcile(snapshot: Dictionary) -> void:
	var authoritative := Vector3(you["x"], you["y"], you["z"])
	if _pending.is_empty() and _seq == 0:
		predicted = authoritative
		predicted_stamina = float(you.get("stamina", Defs.MAX_STAMINA))
		return
	var ack: int = int(snapshot["ack"])
	while not _pending.is_empty() and int(_pending[0]["seq"]) <= ack:
		_pending.pop_front()
	# Replay pending inputs with the last acknowledged stamina value.
	var replayed := authoritative
	var energy := float(you.get("stamina", Defs.MAX_STAMINA))
	for entry in _pending:
		var replay_input: Dictionary = entry["input"].duplicate()
		var duration: float = float(entry["dt"])
		var moving := Vector2(float(replay_input["x"]), float(replay_input["z"])).length_squared() > 0.00001
		replay_input["mounted"] = bool(you.get("mounted", false))
		replay_input["raft"] = inventory.count("raft") > 0
		replay_input["bike_integrity"] = float(you.get("bike_integrity", 100.0))
		replay_input["tire_grip_seconds"] = float(you.get("tire_grip_seconds", 0.0))
		replay_input["cargo_factor"] = BikeCargo.movement_factor(inventory,
			float(you.get("carry_bonus", 0.0)), bool(replay_input["mounted"]))
		var running := bool(replay_input["sprint"]) and not bool(replay_input["mounted"]) and not bool(replay_input.get("crouch", false)) and moving and float(replay_input["cargo_factor"]) >= 0.9999
		running = running and Survival.can_sprint_with(energy, float(you.get("hunger", 100.0)),
				float(you.get("thirst", 100.0)), duration)
		running = running and float(you.get("fracture", 0.0)) <= 0.0
		running = running and WadingTravel.can_sprint(world, replayed)
		replay_input["sprint"] = running
		replay_input["injury_factor"] = Survival.fracture_speed_factor(float(you.get("fracture", 0.0)))
		if running:
			energy = maxf(0.0, energy - Defs.SPRINT_STAMINA_PER_SECOND * duration)
		replayed = Movement.step(world, replayed, replay_input, duration)
	predicted_stamina = energy
	var error := replayed.distance_to(predicted)
	worst_error = maxf(worst_error, error)
	if error > 0.001:
		total_corrections += 1
		if error > 2.5:
			correction = Vector3.ZERO # Too far to smooth: snap.
		else:
			correction += predicted - replayed
	predicted = replayed


## Moves the local player and tells the server. Call once per physics frame.
func send_input(move: Vector2, sprint: bool, face_yaw: float, delta: float, crouch: bool = false) -> void:
	if world == null or not you.has("x") or not bool(you.get("alive", true)):
		return
	_seq += 1
	yaw = face_yaw
	# Prediction uses the same weight calculation as the authoritative server.
	var factor: float = BikeCargo.movement_factor(inventory,
		float(you.get("carry_bonus", 0.0)), bool(you.get("mounted", false)))
	var mounted: bool = bool(you.get("mounted", false)) and not crouch and factor >= 0.9999
	var running := sprint and not mounted and not crouch and move.length_squared() > 0.00001 and factor >= 0.9999
	running = running and Survival.can_sprint_with(predicted_stamina,
			float(you.get("hunger", 100.0)), float(you.get("thirst", 100.0)), delta)
	running = running and float(you.get("fracture", 0.0)) <= 0.0
	running = running and WadingTravel.can_sprint(world, predicted)
	var input := {"x": move.x, "z": move.y, "sprint": running, "mounted": mounted, "crouch": crouch,
		"raft": inventory.count("raft") > 0,
		"cargo_factor": factor, "speed_bonus": float(you.get("speed_bonus", 0.0)),
		"injury_factor": Survival.fracture_speed_factor(float(you.get("fracture", 0.0))),
		"tire_grip_seconds": float(you.get("tire_grip_seconds", 0.0)),
		"bike_integrity": float(you.get("bike_integrity", 100.0)),
		"weather_time": server_time}
	predicted = Movement.step(world, predicted, input, delta)
	if running:
		predicted_stamina = maxf(0.0, predicted_stamina - Defs.SPRINT_STAMINA_PER_SECOND * delta)
	# Pending replay needs the original request, not the previous prediction.
	input["sprint"] = sprint
	_pending.append({"seq": _seq, "input": input, "dt": delta})
	if _pending.size() > 120:
		_pending.pop_front()
	net.c_input.rpc_id(1, _seq, move.x, move.y, sprint, face_yaw, delta, crouch)


func decay_correction(delta: float) -> void:
	correction = correction.lerp(Vector3.ZERO, clampf(delta * 12.0, 0.0, 1.0))


## Where to draw the local player: the prediction plus the fading correction.
func display_position() -> Vector3:
	return predicted + correction


func join(player_name: String, token: String = "", refresh: String = "") -> void:
	net.c_join.rpc_id(1, player_name, token, refresh)


# --- Commands ----------------------------------------------------------------------------------------------

func gather(node_id: int) -> void:
	net.c_gather.rpc_id(1, node_id)


func resource_pickup(node_id: int) -> void:
	net.c_resource_pickup.rpc_id(1, node_id)


func resource_hit(node_id: int, direction: Vector2) -> void:
	net.c_resource_hit.rpc_id(1, node_id, direction.x, direction.y)


func place_fish_trap() -> void:
	net.c_place_fish_trap.rpc_id(1)


func collect_fish_trap(trap_id: int) -> void:
	net.c_collect_fish_trap.rpc_id(1, trap_id)


func nearest_fish_trap(position: Vector3, radius: float = 4.5) -> int:
	var nearest := -1
	var best: float = radius * radius
	if not position.is_finite():
		return nearest
	for trap in fish_traps.values():
		var distance: float = Vector2(position.x, position.z).distance_squared_to(
			Vector2(float(trap["x"]), float(trap["z"])))
		if distance <= best:
			nearest = int(trap["id"])
			best = distance
	return nearest


func fish(baited: bool = false, storm_cast: bool = false) -> void:
	net.c_fish.rpc_id(1, baited, storm_cast)


func enchant(item_id: String) -> void:
	net.c_enchant.rpc_id(1, item_id)


func repair_gear() -> void:
	net.c_repair_gear.rpc_id(1)


func craft(recipe: String, times: int = 1) -> void:
	net.c_craft.rpc_id(1, recipe, times)


## Albion-style focus craft: spends focus at a city workbench to get materials back.
func craft_focus(recipe: String, times: int = 1) -> void:
	net.c_craft_focus.rpc_id(1, recipe, times)


func craft_from_stash(recipe: String, times: int = 1) -> void:
	net.c_craft_from_stash.rpc_id(1, recipe, times)


func salvage_gear(item_id: String) -> void:
	net.c_salvage_gear.rpc_id(1, item_id)


func buy_perk(perk_id: String) -> void:
	net.c_perk.rpc_id(1, perk_id)


func toggle_mount() -> void:
	net.c_toggle_mount.rpc_id(1)


func use_item(item_id: String) -> void:
	net.c_use.rpc_id(1, item_id)


func smart_provision(intent: String) -> void:
	net.c_smart_provision.rpc_id(1, intent)


func quick_medicine() -> void:
	net.c_quick_medicine.rpc_id(1)


func expedition_restock(preset_id: String) -> void:
	net.c_expedition_restock.rpc_id(1, preset_id)


func equipment_preset(action: String, slot: int) -> void:
	net.c_equipment_preset.rpc_id(1, action, slot)


func deposit_materials() -> void:
	net.c_stash_bulk.rpc_id(1)


func move_stash(item_id: String, count: int, deposit: bool) -> void:
	net.c_stash.rpc_id(1, item_id, count, deposit)


## Trade ids and revisions originate from server events. No client-side inventory mutation.
func arena_queue_join() -> void:
	net.c_arena_queue_join.rpc_id(1)


func arena_queue_leave() -> void:
	net.c_arena_queue_leave.rpc_id(1)


func duel_invite(target_id: int, ranked: bool = false) -> void:
	net.c_duel_invite.rpc_id(1, target_id, ranked)


func duel_accept() -> void:
	net.c_duel_accept.rpc_id(1)


func duel_cancel() -> void:
	net.c_duel_cancel.rpc_id(1)


func party_invite(target_id: int) -> void:
	net.c_party_invite.rpc_id(1, target_id)


func party_accept() -> void:
	net.c_party_accept.rpc_id(1)


func party_decline() -> void:
	net.c_party_decline.rpc_id(1)


func party_leave() -> void:
	net.c_party_leave.rpc_id(1)


func party_kick(target_id: int) -> void:
	net.c_party_kick.rpc_id(1, target_id)


func party_feast(item_id: String) -> void:
	net.c_party_feast.rpc_id(1, item_id)


func party_aid(target_id: int, item_id: String) -> void:
	net.c_party_aid.rpc_id(1, target_id, item_id)


func party_provision(target_id: int, kind: String) -> void:
	net.c_party_provision.rpc_id(1, target_id, kind)


func party_supply_request(need: String) -> void:
	net.c_party_supply_request.rpc_id(1, need)


func party_triage() -> void:
	net.c_party_triage.rpc_id(1)


func medic_cover() -> void:
	# Selects no enemy or ally: server chooses the legitimate nearest guardian.
	net.c_medic_cover.rpc_id(1)


func party_ready_start() -> void:
	net.c_party_ready_start.rpc_id(1)


func party_ready_answer(ready: bool) -> void:
	net.c_party_ready_answer.rpc_id(1, ready)


func party_standard() -> void:
	net.c_party_standard.rpc_id(1)


func party_corpse_rescue() -> void:
	net.c_party_corpse_rescue.rpc_id(1)


func party_rally() -> void:
	net.c_party_rally.rpc_id(1)


func party_ping(point: Vector2) -> void:
	if point.is_finite():
		net.c_party_ping.rpc_id(1, point.x, point.y)


func party_focus() -> void:
	net.c_party_focus.rpc_id(1)


func party_loot_mode(mode: String) -> void:
	net.c_party_loot_mode.rpc_id(1, mode)


func raid_vote(bag_id: int, choice: String) -> void:
	net.c_raid_vote.rpc_id(1, bag_id, choice)


func raid_claim_selected(entity_id: int, item_id: String) -> void:
	net.c_raid_claim_selected.rpc_id(1, entity_id, item_id)


func raid_skip_turn(entity_id: int) -> void:
	net.c_raid_skip_turn.rpc_id(1, entity_id)


var _outpost_provision_request_id: int = 0


func outpost_provision(site_id: int) -> void:
	if _outpost_provision_request_id >= 2_147_483_647:
		return
	_outpost_provision_request_id += 1
	net.c_outpost_provision.rpc_id(1, site_id, _outpost_provision_request_id)


var _outpost_fortify_request_id: int = 0


func outpost_fortify(site_id: int) -> void:
	if _outpost_fortify_request_id >= 2_147_483_647:
		return # Reconnect rather than wrap a request identifier.
	_outpost_fortify_request_id += 1
	net.c_outpost_fortify.rpc_id(1, site_id, _outpost_fortify_request_id)


var _outpost_breach_request_id: int = 0


func outpost_breach(site_id: int) -> void:
	if _outpost_breach_request_id >= 2_147_483_647:
		return # Reconnect instead of wrapping a session-specific request ID.
	_outpost_breach_request_id += 1
	net.c_outpost_breach.rpc_id(1, site_id, _outpost_breach_request_id)


var _siege_declare_request_id: int = 0


func siege_declare(site_id: int) -> void:
	if _siege_declare_request_id >= 2_147_483_647:
		return
	_siege_declare_request_id += 1
	net.c_siege_declare.rpc_id(1, site_id, _siege_declare_request_id)


func trade_invite(target_id: int) -> void:
	net.c_trade_invite.rpc_id(1, target_id)


func trade_offer(trade_id: int, item_id: String, quantity: int) -> void:
	net.c_trade_offer.rpc_id(1, trade_id, item_id, quantity)


func trade_accept(trade_id: int, revision: int) -> void:
	net.c_trade_accept.rpc_id(1, trade_id, revision)


func trade_cancel(trade_id: int) -> void:
	net.c_trade_cancel.rpc_id(1, trade_id)


## Listings are advertised stock, not escrow. Only the server changes inventories.
func market_list() -> void:
	net.c_market_list.rpc_id(1)


func market_create(item_id: String, quantity: int, price: int) -> void:
	net.c_market_create.rpc_id(1, item_id, quantity, price)


var _market_buy_request_id: int = 0


func market_buy(listing_id: int, quantity: int) -> void:
	if _market_buy_request_id >= 2_147_483_647:
		return # Reconnect for a new session instead of wrapping an ID.
	_market_buy_request_id += 1
	net.c_market_buy.rpc_id(1, listing_id, quantity, _market_buy_request_id)


func market_cancel(listing_id: int) -> void:
	net.c_market_cancel.rpc_id(1, listing_id)


func vendor(item_id: String, quantity: int, buy: bool) -> void:
	net.c_vendor.rpc_id(1, item_id, quantity, buy)


func rest() -> void:
	net.c_rest.rpc_id(1)


func caravan(action: String) -> void:
	net.c_caravan.rpc_id(1, action)


func contract(action: String) -> void:
	net.c_contract.rpc_id(1, action)


func story(action: String) -> void:
	if action in ["listen", "transmit", "decode", "seal", "broadcast", "trace", "guide", "mask"]:
		net.c_story.rpc_id(1, action)


func outpost_supplies(site_id: int) -> void:
	net.c_outpost_supplies.rpc_id(1, site_id)


func attack(direction: Vector2) -> void:
	net.c_attack.rpc_id(1, direction.x, direction.y)


func power_attack(direction: Vector2, charge: float) -> void:
	net.c_power_attack.rpc_id(1, direction.x, direction.y, charge)


func kick(direction: Vector2) -> void:
	net.c_kick.rpc_id(1, direction.x, direction.y)


func rage() -> void:
	net.c_rage.rpc_id(1)


func skill(direction: Vector2) -> void:
	net.c_skill.rpc_id(1, direction.x, direction.y)


## Weapon ultimate (E): a charged version of the weapon skill with its own cooldown.
func skill_ultimate(direction: Vector2) -> void:
	net.c_skill_ultimate.rpc_id(1, direction.x, direction.y)


## Armor abilities: "armor" (Iron Skin), "head" (Second Wind), "feet" (Sprint).
func gear_skill(slot: String) -> void:
	net.c_gear_skill.rpc_id(1, slot)


func stagger_finisher() -> void:
	# Server picks the real stunned target; clients send no target ID.
	net.c_stagger_finisher.rpc_id(1)


func guardian_taunt() -> void:
	# The server selects all targets; the client sends no enemy IDs.
	net.c_guardian_taunt.rpc_id(1)


func guardian_intercept(ally_id: int) -> void:
	# Only the ally ID is requested; real group, weapon, range, hit and
	# damage are confirmed by the authoritative simulation.
	net.c_guardian_intercept.rpc_id(1, ally_id)


func party_shield_wall() -> void:
	# No targets, positions, durations or damage are accepted from the client.
	net.c_party_shield_wall.rpc_id(1)


func parry() -> void:
	# Facing and equipped weapon are rechecked by the authoritative server.
	net.c_parry.rpc_id(1)


func arcane_bolt(direction: Vector2) -> void:
	net.c_arcane_bolt.rpc_id(1, direction.x, direction.y)


func ultimate() -> void:
	# The server picks every target inside the blast; the client sends nothing else.
	net.c_ultimate.rpc_id(1)


func dodge(direction: Vector2) -> void:
	# Server owns the travel distance and cooldown; reconciliation handles positioning.
	net.c_dodge.rpc_id(1, direction.x, direction.y)


func loot(entity_id: int) -> void:
	net.c_loot.rpc_id(1, entity_id)


func dungeon(down: bool) -> void:
	net.c_dungeon.rpc_id(1, down)


func loot_sweep() -> void:
	# No client-specified target IDs, positions or quantities.
	net.c_loot_sweep.rpc_id(1)


func build(point: Vector2, yaw: float = 0.0) -> void:
	if point.is_finite():
		net.c_build.rpc_id(1, point.x, point.y, yaw)


func toggle_door(id: int) -> void:
	net.c_toggle_door.rpc_id(1, id)


## The nearest door piece within reach, or -1.
func nearest_door(point: Vector3) -> int:
	var best := -1
	var best_distance: float = HousePieces.DOOR_REACH
	for item in barricades.values():
		if str(item.get("piece", "")) != "door":
			continue
		var d := Vector2(float(item["x"]) - point.x, float(item["z"]) - point.z).length()
		if d < best_distance:
			best_distance = d
			best = int(item["id"])
	return best


func build_piece(piece: String, point: Vector2, facing: float = 0.0) -> void:
	if point.is_finite():
		net.c_build_piece.rpc_id(1, piece, point.x, point.y, facing)


func repair(id: int) -> void:
	net.c_repair.rpc_id(1, id)


func refill_canteen(boil: bool = false) -> void:
	net.c_refill_canteen.rpc_id(1, boil)


func survey_ruins() -> void:
	net.c_survey_ruins.rpc_id(1)


func place_infected_snare(point: Vector2) -> void:
	if point.is_finite():
		net.c_place_infected_snare.rpc_id(1, point.x, point.y)


func throw_flash(direction: Vector2) -> void:
	if direction.is_finite() and direction.length_squared() > 0.0001:
		net.c_throw_flash.rpc_id(1, direction.normalized().x, direction.normalized().y)


func throw_ember(direction: Vector2) -> void:
	if direction.is_finite() and is_finite(direction.length_squared()) 			and direction.length_squared() > 0.0001:
		var heading: Vector2 = direction.normalized()
		net.c_throw_ember.rpc_id(1, heading.x, heading.y)


func throw_decoy(direction: Vector2) -> void:
	if direction.is_finite() and direction.length_squared() > 0.0001:
		net.c_throw_decoy.rpc_id(1, direction.normalized().x, direction.normalized().y)


func pitch_shelter(point: Vector2) -> void:
	if point.is_finite():
		net.c_pitch_shelter.rpc_id(1, point.x, point.y)


func pack_shelter(id: int) -> void:
	net.c_pack_shelter.rpc_id(1, id)


func nearest_shelter(point: Vector3, radius: float = 3.2) -> int:
	if not point.is_finite():
		return -1
	var closest := -1
	var distance: float = radius * radius
	for shelter in shelters.values():
		var d2: float = Vector2(point.x, point.z).distance_squared_to(
			Vector2(float(shelter["x"]), float(shelter["z"])))
		if d2 <= distance:
			distance = d2
			closest = int(shelter["id"])
	return closest


func light_campfire(point: Vector2) -> void:
	if point.is_finite():
		net.c_light_campfire.rpc_id(1, point.x, point.y)


func upgrade(id: int) -> void:
	net.c_upgrade.rpc_id(1, id)


func dismantle(id: int) -> void:
	net.c_dismantle.rpc_id(1, id)


func nearest_campfire(point: Vector3, radius: float = 3.2) -> int:
	var closest: int = -1
	var best_squared: float = radius * radius
	for fire in campfires.values():
		var offset := Vector2(point.x - float(fire["x"]), point.z - float(fire["z"]))
		var distance_squared: float = offset.length_squared()
		if distance_squared <= best_squared:
			closest = int(fire["id"])
			best_squared = distance_squared
	return closest


func arm_camp_alarm(id: int) -> void:
	if id >= 0:
		net.c_arm_camp_alarm.rpc_id(1, id)


func refuel_campfire(id: int) -> void:
	if id >= 0:
		net.c_refuel_campfire.rpc_id(1, id)


func extinguish_campfire(id: int) -> void:
	if id >= 0:
		net.c_extinguish_campfire.rpc_id(1, id)


func nearest_barricade(point: Vector3, radius: float = 3.0) -> int:
	var nearest := -1
	var best := radius
	for structure in barricades.values():
		var d := Vector2(point.x - float(structure["x"]), point.z - float(structure["z"])).length()
		if d < best:
			best = d
			nearest = int(structure["id"])
	return nearest


func sample_spores() -> void:
	net.c_sample_spores.rpc_id(1)


func collect_rain() -> void:
	net.c_collect_rain.rpc_id(1)


func drink() -> void:
	net.c_drink.rpc_id(1)


# --- Queries for the UI ---------------------------------------------------------------------------------

## A gatherable node by id, looked up in the chunks around a point (the server only reports ids).
func node_by_id(node_id: int, near: Vector3) -> Dictionary:
	var cell := WorldGen.cell_of(near.x, near.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for node in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["nodes"]:
				if node["id"] == node_id:
					return node
	return {}


## Closest gatherable node (not depleted) within `radius` of a point.
func nearest_node(point: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := radius
	var cell := WorldGen.cell_of(point.x, point.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for node in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["nodes"]:
				if depleted.has(node["id"]):
					continue
				var center_distance: float = Vector2(float(node["x"]) - point.x, float(node["z"]) - point.z).length()
				# Logs and stones are interactable from their solid footprint edge.
				var margin: float = ResourceGathering.reach_margin(node)
				var distance: float = maxf(0.0, center_distance - margin)
				if distance < best_distance:
					best = node
					best_distance = distance
	return best


## Select a mineable node in front of the player's actual swing, ignoring ground pickups.
func nearest_strike_node(point: Vector3, direction: Vector2, radius: float = Defs.REACH + 0.5) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = radius
	var cell: Vector2i = WorldGen.cell_of(point.x, point.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for node in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["nodes"]:
				if depleted.has(node["id"]) or not ResourceGathering.is_strike(str(node["kind"])):
					continue
				if not ResourceGathering.aimed_at(point, node, direction, radius):
					continue
				var center_distance: float = Vector2(float(node["x"]) - point.x,
					float(node["z"]) - point.z).length()
				var margin: float = ResourceGathering.reach_margin(node)
				var distance: float = maxf(0.0, center_distance - margin)
				if distance < best_distance:
					best_distance = distance
					best = node
	return best


## Only true one-press gatherables, not trees, ores, doors or loot crates.
## The held-E collector skips already sent requests until depletion arrives.
func nearest_pickup_node(point: Vector3, radius: float,
		skip_ids: Dictionary = {}) -> Dictionary:
	if world == null:
		return {}
	var best: Dictionary = {}
	var best_distance: float = radius
	var cell: Vector2i = WorldGen.cell_of(point.x, point.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for node in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["nodes"]:
				var node_id: int = int(node["id"])
				if depleted.has(node_id) or skip_ids.has(node_id) \
						or not ResourceGathering.is_pickup(str(node["kind"])):
					continue
				var offset := Vector2(float(node["x"]) - point.x,
					float(node["z"]) - point.z)
				var distance: float = offset.length()
				if distance < best_distance:
					best_distance = distance
					best = node
	return best


func nearest_loot(point: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := radius
	for bag in bags.values():
		var distance := Vector2(bag["x"] - point.x, bag["z"] - point.z).length()
		if distance < best_distance:
			best = {"id": bag["id"], "kind": "bag", "x": bag["x"], "z": bag["z"]}
			best_distance = distance
	var cell := WorldGen.cell_of(point.x, point.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for crate in world.chunk(Vector2i(cell.x + dx, cell.y + dz))["crates"]:
				if crates_used.has(crate["id"]):
					continue
				var distance := Vector2(crate["x"] - point.x, crate["z"] - point.z).length()
				if distance < best_distance:
					best = {"id": crate["id"], "kind": "crate", "x": crate["x"], "z": crate["z"]}
					best_distance = distance
	return best


## Albion-style buy orders (escrowed silver; sellers fill them at the hub).
func market_bid(item_id: String, quantity: int, price: int) -> void:
	net.c_market_bid.rpc_id(1, item_id, quantity, price)


func market_fill(bid_id: int, quantity: int) -> void:
	net.c_market_fill.rpc_id(1, bid_id, quantity)


func market_cancel_bid(bid_id: int) -> void:
	net.c_market_cancel_bid.rpc_id(1, bid_id)


## Faction warfare: "enlist" (with a faction id), "flag", "unflag", "redeem".
func faction(action: String, faction_id: String = "") -> void:
	net.c_faction.rpc_id(1, action, faction_id)


## Homestead farming: plant a carried seed in front of you / harvest your nearest ripe plot.
func plant(seed_id: String) -> void:
	net.c_plant.rpc_id(1, seed_id)


func harvest() -> void:
	net.c_harvest.rpc_id(1)


## Guild bank at the hub: "list", "deposit" (any member) or "withdraw" (officers).
func guild_bank(action: String, item_id: String = "", quantity: int = 0) -> void:
	net.c_guild_bank.rpc_id(1, action, item_id, quantity)


## Guild alliances (leaders, hub): "invite" (target peer), "accept", "leave", "status".
func alliance(action: String, target_peer: int = -1) -> void:
	net.c_alliance.rpc_id(1, action, target_peer)
