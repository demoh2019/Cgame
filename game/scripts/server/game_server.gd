extends RefCounted
## The authoritative simulation of the world: players, zombies, resources, loot and the rules that
## connect them. It has no networking and no scene: the network layer only feeds it commands and
## reads snapshots out of it, so the whole game can be tested by calling it directly.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const PlayerTrade = preload("res://scripts/shared/player_trade.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Evasion = preload("res://scripts/shared/evasion.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const Progression = preload("res://scripts/shared/progression.gd")

const WORKBENCH_POSITION := Vector2(9.0, 0.0)
const WORKBENCH_RANGE := 6.0
const TRADE_RANGE := 6.0
const TRADE_TIMEOUT := 45.0
const ZOMBIE_ACTIVE_RADIUS := 130.0 # Zombies farther than this from every player are put to sleep.
const ZOMBIE_PACK_ALERT_RADIUS := 18.0
const ZOMBIE_PACK_BUCKET_SIZE := 18.0
const BAG_LIFETIME := 300.0
const MAX_NAME_LENGTH := 20
const STARTER_KIT := {"bandage": 2, "canned_food": 2, "water_bottle": 2}

var world
var rng := RandomNumberGenerator.new()
var time: float = 0.0
var tick_count: int = 0

class Player:
	var id: int
	var name: String = ""
	var position: Vector3
	var yaw: float = 0.0
	var inventory
	var stash # Account-bound safe storage; isolated from full-loot death drops.
	var survival
	var progression # Permanent skills; gear is lost on death, not experience.
	var contract_state: Dictionary = {} # Server-owned persistent camp contract journal.
	var input_budget: float = 0.0
	var last_input_seq: int = 0
	var attack_timer: float = 0.0
	var skill_timer: float = 0.0
	var dodge_timer: float = 0.0
	var dodge_immunity: float = 0.0
	var combat_energy: float = 100.0
	var noise_radius: float = 0.0
	var noise_timer: float = 0.0
	var action: Dictionary = {} # Current gathering: {"node": id, "remaining": s, "total": s}
	var respawn_timer: float = 0.0
	var keep_inventory_on_respawn: bool = false
	var last_death_full_loot: bool = false
	var kills: int = 0
	var deaths: int = 0
	var zone_notice: int = -1
	var dirty_inventory: bool = true
	var dirty_stash: bool = true
	var user_id: String = "" # Nakama account, empty in offline mode.
	var dirty_character: bool = false # Something worth saving changed.

var players: Dictionary = {} # peer id -> Player
var zombies: Dictionary = {} # zombie id -> Zombie
var depleted: Dictionary = {} # node id -> time it comes back
var opened_crates: Dictionary = {} # crate id -> time it refills
var spawn_state: Dictionary = {} # spawn id -> {"zombie": id or -1, "next": time}
var barricades: Dictionary = {} # Server-owned structures; authenticated walls may persist.
var trades: Dictionary = {} # trade id -> offer/accept/expiry
var trade_by_player: Dictionary = {} # peer -> active trade
var world_structure_revision: int = 0
var bags: Dictionary = {} # bag id -> {"id", "x","y","z", "items": {id: n}, "expires": t}
var events: Array = [] # Things that happened this tick, for the network layer to announce.
var _next_id: int = 5_000_000_000


func _init(p_world, p_seed: int = 1) -> void:
	world = p_world
	rng.seed = p_seed


func new_id() -> int:
	_next_id += 1
	return _next_id


# --- Players ---------------------------------------------------------------------------------------------

func add_player(peer_id: int, p_name: String, p_user_id: String = "", saved: Dictionary = {}) -> Player:
	var player := Player.new()
	player.id = peer_id
	player.user_id = p_user_id
	player.name = p_name.strip_edges().substr(0, MAX_NAME_LENGTH)
	if player.name == "":
		player.name = "Survivor%d" % (peer_id % 1000)
	player.inventory = Inventory.new()
	player.stash = Inventory.new(Defs.STASH_SLOTS)
	player.survival = Survival.new()
	player.progression = Progression.new()
	player.contract_state = Contracts.empty_state()
	players[peer_id] = player
	# Bind restored account-owned structures to this authenticated session.
	# Never match a stale numerical peer ID in place of the account identity.
	if not p_user_id.is_empty():
		for wall in barricades.values():
			if str(wall.get("owner_account", "")) == p_user_id:
				wall["owner"] = peer_id
	if saved.is_empty() or not apply_character(player, saved):
		_spawn_player(player)
	else:
		events.append({"type": "spawn", "peer": player.id})
	return player


## The part of a player that survives between sessions.
func character_data(player: Player) -> Dictionary:
	var alive := _alive(player)
	return {
		"version": 1,
		"health": player.survival.health, "hunger": player.survival.hunger, "thirst": player.survival.thirst,
		"stamina": player.survival.stamina, "infection": player.survival.infection,
		"alive": alive, "kills": player.kills, "deaths": player.deaths,
		"x": player.position.x, "z": player.position.z,
		"inventory": player.inventory.to_dict(),
		"stash": player.stash.to_dict(),
		"progression": player.progression.to_dict(),
		"contracts": player.contract_state.duplicate(true),
	}


## Restores a saved character. Returns false (and changes nothing) if the data is not usable.
func apply_character(player: Player, data: Dictionary) -> bool:
	if data.get("version", 0) != 1:
		return false
	# Both containers use the same strict parser. Never coerce fractional, textual,
	# unknown or oversized quantities from persisted JSON into valid stacks.
	var parsed_bag: Dictionary = SaveValidation.parse_inventory(data.get("inventory"), Defs.INVENTORY_SLOTS)
	if parsed_bag.is_empty():
		return false
	var parsed_stash: Dictionary = {}
	if data.has("stash"):
		parsed_stash = SaveValidation.parse_inventory(data["stash"], Defs.STASH_SLOTS, false)
	else:
		# Legacy version-1 Nakama characters did not have a protected stash.
		parsed_stash = {"inventory": Inventory.new(Defs.STASH_SLOTS)}
	if parsed_stash.is_empty():
		return false

	# Check all persisted scalar values before changing the live Player.
	if not SaveValidation.finite_number(data.get("health", 100.0), 0.0, Defs.MAX_HEALTH):
		return false
	if not SaveValidation.finite_number(data.get("hunger", 80.0), 0.0, 100.0):
		return false
	if not SaveValidation.finite_number(data.get("thirst", 80.0), 0.0, 100.0):
		return false
	if not SaveValidation.finite_number(data.get("stamina", Defs.MAX_STAMINA), 0.0, Defs.MAX_STAMINA):
		return false
	if not SaveValidation.finite_number(data.get("infection", 0.0), 0.0, Defs.INFECTION_MAX):
		return false
	if not SaveValidation.valid_counter(data.get("kills", 0)):
		return false
	if not SaveValidation.valid_counter(data.get("deaths", 0)):
		return false
	if not (data.get("alive", true) is bool):
		return false

	var survival = Survival.new()
	survival.health = clampf(float(data.get("health", 100.0)), 1.0, Defs.MAX_HEALTH)
	survival.hunger = float(data.get("hunger", 80.0))
	survival.thirst = float(data.get("thirst", 80.0))
	# Legacy v1 characters without stamina are restored fully rested.
	survival.stamina = float(data.get("stamina", Defs.MAX_STAMINA))
	# Older version-1 saves without infection remain compatible.
	survival.infection = float(data.get("infection", 0.0))
	var x: Variant = data.get("x", 0.0)
	var z: Variant = data.get("z", 0.0)
	# Invalid old logout coordinates can still safely fall back to the hub.
	var restore_position := Vector3.ZERO
	var can_restore_position := (
		SaveValidation.finite_number(x, -50000.0, 50000.0)
		and SaveValidation.finite_number(z, -50000.0, 50000.0)
		and absf(float(x)) < 50000.0 and absf(float(z)) < 50000.0
		and bool(data.get("alive", true))
	)
	if can_restore_position and not world.is_water(float(x), float(z)):
		restore_position = Vector3(float(x), world.height_at(float(x), float(z)), float(z))
	else:
		var angle := rng.randf() * TAU
		var spot := Vector2.from_angle(angle) * rng.randf_range(10.0, 22.0)
		restore_position = Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y)
	var loaded_progression = Progression.new()
	if data.has("progression") and not loaded_progression.load_dict(data["progression"]):
		return false
	# Legacy v1 characters without contracts start from the first mission.
	var loaded_contracts: Variant = data.get("contracts", Contracts.empty_state())
	if not Contracts.valid_state(loaded_contracts):
		return false

	# One commit point: a failed parse cannot partially replace the player's
	# inventory, protected stash, progression or survival state.
	player.progression = loaded_progression
	player.contract_state = (loaded_contracts as Dictionary).duplicate(true)
	player.inventory = parsed_bag["inventory"]
	player.stash = parsed_stash["inventory"]
	player.kills = int(data.get("kills", 0))
	player.deaths = int(data.get("deaths", 0))
	player.survival = survival
	player.position = restore_position
	player.dirty_inventory = true
	player.dirty_stash = true
	player.dirty_character = true
	return true


## Check a complete saved character without modifying a live player or the spawn RNG.
## The loader refuses corrupt existing accounts instead of minting a new starter kit.
func valid_character_data(data: Dictionary) -> bool:
	var previous_state: int = rng.state
	var probe := Player.new()
	var valid := apply_character(probe, data)
	rng.state = previous_state
	return valid


func remove_player(peer_id: int) -> void:
	_cancel_player_trade(peer_id, "disconnected")
	var player: Player = players.get(peer_id)
	if player != null and not player.user_id.is_empty():
		for wall in barricades.values():
			if str(wall.get("owner_account", "")) == player.user_id:
				wall["owner"] = -1
	players.erase(peer_id)


func _spawn_player(player: Player) -> void:
	var spot := Vector2(12.0, 6.0)
	for attempt in 20: # Not inside the workbench or a building: take the first free spot.
		var candidate := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 22.0)
		var blocked := false
		for blocker in world.blockers_near(candidate.x, candidate.y, Defs.PLAYER_RADIUS + 1.0):
			if Vector2(blocker["x"] - candidate.x, blocker["z"] - candidate.y).length() < Defs.PLAYER_RADIUS + float(blocker["radius"]) + 0.3:
				blocked = true
		if not blocked:
			spot = candidate
			break
	player.position = Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y)
	player.survival.reset()
	var kept_gear: bool = player.keep_inventory_on_respawn
	player.keep_inventory_on_respawn = false
	if not kept_gear:
		player.inventory = Inventory.new()
		for id in STARTER_KIT:
			player.inventory.add(id, STARTER_KIT[id])
	player.action = {}
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	player.dodge_timer = 0.0
	player.dodge_immunity = 0.0
	player.combat_energy = Defs.COMBAT_ENERGY_MAX
	player.noise_radius = 0.0
	player.noise_timer = 0.0
	player.dirty_inventory = true
	events.append({"type": "spawn", "peer": player.id})


func _alive(player: Player) -> bool:
	return player.survival.alive


func _is_safe(position: Vector3) -> bool:
	return world.is_safe(position.x, position.z)


# --- Commands (the network layer calls these) -------------------------------------------------------

## A movement input measured by the client. `dt` is how long the client says it moved. The server
## accepts at most as much movement time as real time has passed, so a modified client cannot speed up.
func submit_input(peer_id: int, seq: int, move_x: float, move_z: float, sprint: bool, yaw: float, dt: float) -> void:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player) or seq <= player.last_input_seq:
		return
	if not (is_finite(move_x) and is_finite(move_z) and is_finite(dt) and is_finite(yaw)):
		return
	player.last_input_seq = seq
	dt = clampf(dt, 0.0, Movement.MAX_DELTA)
	var allowed := minf(dt, player.input_budget)
	player.input_budget -= allowed
	player.yaw = yaw
	if allowed > 0.0:
		# No client-supplied cargo, stamina or sound radius: server owns all three.
		var before_move: Vector3 = player.position
		var factor: float = player.inventory.movement_factor()
		var moving := move_x * move_x + move_z * move_z > 0.00001
		var sprint_allowed: bool = sprint and moving and factor >= 0.9999 and player.survival.try_sprint(allowed)
		player.position = Movement.step(world, player.position, {
			"x": move_x, "z": move_z, "sprint": sprint_allowed,
			"cargo_factor": factor,
		}, allowed)
		if sprint_allowed and player.position.distance_to(before_move) > 0.01:
			player.noise_radius = maxf(player.noise_radius, Defs.SPRINT_NOISE_RADIUS)
			player.noise_timer = maxf(player.noise_timer, Defs.SPRINT_NOISE_SECONDS)
		# Walking away cancels gathering.
		if not player.action.is_empty():
			var node := _find_node(int(player.action["node"]))
			if node.is_empty() or _distance_xz(player.position, node) > Defs.REACH + 0.8:
				player.action = {}


func cmd_gather(peer_id: int, node_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var node := _find_node(node_id)
	if node.is_empty():
		return {"ok": false, "reason": "no_such_node"}
	if depleted.has(node_id):
		return {"ok": false, "reason": "depleted"}
	if _distance_xz(player.position, node) > Defs.REACH + 0.5:
		return {"ok": false, "reason": "too_far"}
	var info := Defs.node_info(node["kind"])
	var required_tool := Defs.tool_tier_for_node(node["kind"])
	var tool_tier := 0
	var speed := 1.0
	if required_tool != "":
		var tool_id: String = player.inventory.best_tool(required_tool)
		tool_tier = Defs.tier_of(tool_id) if tool_id != "" else 0
		# Hands only manage tier 1; better tools gather faster.
		if tool_tier < int(node["tier"]) and not (tool_tier == 0 and int(node["tier"]) == 1):
			return {"ok": false, "reason": "need_tool", "tier": node["tier"], "tool": required_tool}
		speed = 0.45 if tool_tier == 0 else 1.0 + 0.6 * (tool_tier - 1) + 0.5
	# Tool tier and profession tier are independent: a bought tool is not enough.
	if not player.progression.can_gather(String(node["kind"]), int(node["tier"])):
		return {"ok": false, "reason": "need_skill", "skill": Progression.resource_skill(String(node["kind"])), "tier": node["tier"]}
	var total := float(info["seconds"]) / speed
	player.action = {"node": node_id, "remaining": total, "total": total}
	return {"ok": true, "seconds": total}


func cmd_craft(peer_id: int, recipe_id: String, times: int = 1) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	times = clampi(times, 1, 50)
	var recipe: Dictionary = Defs.recipes().get(recipe_id, {})
	if recipe.is_empty():
		return {"ok": false, "reason": "unknown_recipe"}
	var recipe_tier: int = maxi(1, Defs.tier_of(String(recipe["output"])))
	if not player.progression.can_craft_tier(recipe_tier):
		return {"ok": false, "reason": "need_skill", "skill": "crafting", "tier": recipe_tier}
	var at_bench: bool = Vector2(player.position.x, player.position.z).distance_to(WORKBENCH_POSITION) <= WORKBENCH_RANGE
	var status: int = Crafting.craft(player.inventory, recipe_id, at_bench, times)
	if status == Crafting.Result.OK:
		player.progression.award_craft(recipe_tier, times)
		player.dirty_inventory = true
		player.dirty_character = true
		return {"ok": true}
	return {"ok": false, "reason": ["ok", "unknown_recipe", "missing_inputs", "no_station", "no_space"][status]}


# --- Direct player trade -------------------------------------------------------------------------------
# All operations are synchronous on the authoritative tick; no client-provided
# price, inventory balance or confirmation flag is trusted.

func _trade_available(first_id: int, second_id: int) -> bool:
	var first: Player = players.get(first_id)
	var second: Player = players.get(second_id)
	if first == null or second == null or not _alive(first) or not _alive(second):
		return false
	var first_at := Vector2(first.position.x, first.position.z)
	var second_at := Vector2(second.position.x, second.position.z)
	return first_at.is_finite() and second_at.is_finite() \
		and _is_safe(first.position) and _is_safe(second.position) \
		and first_at.distance_to(second_at) <= TRADE_RANGE


func _get_trade(peer_id: int, trade_id: int) -> Dictionary:
	var trade: Dictionary = trades.get(trade_id, {})
	if trade.is_empty() or (int(trade["a"]) != peer_id and int(trade["b"]) != peer_id):
		return {}
	return trade


func _announce_trade(trade: Dictionary, phase: String, reason: String = "") -> void:
	events.append({
		"type": "trade", "phase": phase, "reason": reason, "id": trade["id"],
		"a": trade["a"], "b": trade["b"], "revision": trade["revision"],
		"offer_a": trade["offers"][trade["a"]].duplicate(),
		"offer_b": trade["offers"][trade["b"]].duplicate(),
		"accepted_a": trade["accepted"][trade["a"]],
		"accepted_b": trade["accepted"][trade["b"]],
	})


func _close_trade(trade: Dictionary, phase: String, reason: String = "") -> void:
	trades.erase(trade["id"])
	trade_by_player.erase(trade["a"])
	trade_by_player.erase(trade["b"])
	_announce_trade(trade, phase, reason)


func _cancel_player_trade(peer_id: int, reason: String) -> void:
	if not trade_by_player.has(peer_id):
		return
	var trade_id: int = int(trade_by_player[peer_id])
	var trade: Dictionary = trades.get(trade_id, {})
	if not trade.is_empty():
		_close_trade(trade, "cancelled", reason)
	else:
		trade_by_player.erase(peer_id)


func cmd_trade_invite(peer_id: int, target_id: int) -> Dictionary:
	if peer_id == target_id or not players.has(peer_id) or not players.has(target_id):
		return {"ok": false, "reason": "invalid_target"}
	if trade_by_player.has(peer_id) or trade_by_player.has(target_id):
		return {"ok": false, "reason": "busy"}
	if not _trade_available(peer_id, target_id):
		return {"ok": false, "reason": "not_in_safe_range"}
	var trade_id := new_id()
	var trade := {
		"id": trade_id, "a": peer_id, "b": target_id,
		"offers": {}, "accepted": {},
		"revision": 0, "expires": time + TRADE_TIMEOUT,
	}
	# Explicit integer keys: identifiers in dictionary literals can be string keys.
	trade["offers"][peer_id] = {}
	trade["offers"][target_id] = {}
	trade["accepted"][peer_id] = false
	trade["accepted"][target_id] = false
	trades[trade_id] = trade
	trade_by_player[peer_id] = trade_id
	trade_by_player[target_id] = trade_id
	_announce_trade(trade, "invited")
	return {"ok": true, "trade_id": trade_id, "revision": 0}


## A zero count removes an offer line. Every change clears BOTH confirmations.
func cmd_trade_offer(peer_id: int, trade_id: int, item_id: String, count: int) -> Dictionary:
	var trade := _get_trade(peer_id, trade_id)
	if trade.is_empty():
		return {"ok": false, "reason": "unknown_trade"}
	if not _trade_available(int(trade["a"]), int(trade["b"])) or time >= float(trade["expires"]):
		_close_trade(trade, "cancelled", "out_of_range")
		return {"ok": false, "reason": "out_of_range"}
	if not Defs.is_item(item_id) or count < 0 or count > Defs.stack_size(item_id):
		return {"ok": false, "reason": "invalid_stack"}
	var offer: Dictionary = trade["offers"][peer_id]
	if count > 0 and players[peer_id].inventory.count(item_id) < count:
		return {"ok": false, "reason": "missing_items"}
	if count > 0 and not offer.has(item_id) and offer.size() >= PlayerTrade.MAX_OFFER_LINES:
		return {"ok": false, "reason": "too_many_items"}
	if count == 0:
		offer.erase(item_id)
	else:
		offer[item_id] = count
	trade["accepted"][trade["a"]] = false
	trade["accepted"][trade["b"]] = false
	trade["revision"] = int(trade["revision"]) + 1
	trade["expires"] = time + TRADE_TIMEOUT
	_announce_trade(trade, "offered")
	return {"ok": true, "trade_id": trade_id, "revision": trade["revision"]}


## The revision is the number from the latest trade event. Stale confirmation
## packets cannot accept a new or changed proposal.
func cmd_trade_accept(peer_id: int, trade_id: int, revision: int) -> Dictionary:
	var trade := _get_trade(peer_id, trade_id)
	if trade.is_empty():
		return {"ok": false, "reason": "unknown_trade"}
	if not _trade_available(int(trade["a"]), int(trade["b"])) or time >= float(trade["expires"]):
		_close_trade(trade, "cancelled", "out_of_range")
		return {"ok": false, "reason": "out_of_range"}
	if revision != int(trade["revision"]):
		return {"ok": false, "reason": "stale_revision", "revision": trade["revision"]}
	if trade["accepted"][peer_id]:
		return {"ok": false, "reason": "already_accepted"}
	trade["accepted"][peer_id] = true
	if not trade["accepted"][trade["a"]] or not trade["accepted"][trade["b"]]:
		_announce_trade(trade, "accepted")
		return {"ok": true, "completed": false, "revision": revision}
	var first: Player = players[int(trade["a"])]
	var second: Player = players[int(trade["b"])]
	var result: Dictionary = PlayerTrade.exchange(
		first.inventory, second.inventory,
		trade["offers"][trade["a"]], trade["offers"][trade["b"]]
	)
	if not result.get("ok", false):
		trade["accepted"][trade["a"]] = false
		trade["accepted"][trade["b"]] = false
		trade["revision"] = int(trade["revision"]) + 1
		_announce_trade(trade, "rejected", str(result["reason"]))
		return {"ok": false, "reason": result["reason"], "revision": trade["revision"]}
	first.dirty_inventory = true
	second.dirty_inventory = true
	first.dirty_character = true
	second.dirty_character = true
	_close_trade(trade, "completed")
	return {"ok": true, "completed": true, "trade_id": trade_id}


func cmd_trade_cancel(peer_id: int, trade_id: int) -> Dictionary:
	var trade := _get_trade(peer_id, trade_id)
	if trade.is_empty():
		return {"ok": false, "reason": "unknown_trade"}
	_close_trade(trade, "cancelled", "by_player")
	return {"ok": true}


func _tick_trades() -> void:
	for trade_id in trades.keys():
		var trade: Dictionary = trades.get(trade_id, {})
		if trade.is_empty():
			continue
		if time >= float(trade["expires"]):
			_close_trade(trade, "cancelled", "expired")
		elif not _trade_available(int(trade["a"]), int(trade["b"])):
			_close_trade(trade, "cancelled", "out_of_range")


## The safe-hub vendor uses server position and inventory only.
## A rejected trade leaves every item and silver balance unchanged.
func cmd_vendor(peer_id: int, item_id: String, quantity: int, buy: bool) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var location := Vector2(player.position.x, player.position.z)
	if not location.is_finite() or location.distance_to(WORKBENCH_POSITION) > WORKBENCH_RANGE:
		return {"ok": false, "reason": "no_station"}
	var outcome: Dictionary = Vendor.transact(player.inventory, item_id, quantity, buy)
	if outcome.get("ok", false):
		player.dirty_inventory = true
		player.dirty_character = true
	return outcome


## Camp contracts use the same real hub distance check as the vendor and bank.
## The only client input is accept/claim, never rewards, progress or prices.
func cmd_contract(peer_id: int, action: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var at: Vector2 = Vector2(player.position.x, player.position.z)
	if not at.is_finite() or at.distance_to(WORKBENCH_POSITION) > WORKBENCH_RANGE:
		return {"ok": false, "reason": "no_station"}
	var result: Dictionary = {}
	match action:
		"accept": result = Contracts.accept(player.contract_state)
		"claim": result = Contracts.claim(player.inventory, player.contract_state)
		_: return {"ok": false, "reason": "unknown_action"}
	if bool(result.get("ok", false)):
		player.dirty_character = true
		if action == "claim":
			player.dirty_inventory = true
	return result


## Authoritative hub bank: move a bounded item stack only when the actual
## server position is near the workbench. A failed operation changes nothing.
func cmd_stash(peer_id: int, item_id: String, count: int, deposit: bool) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var distance: float = Vector2(player.position.x, player.position.z).distance_to(WORKBENCH_POSITION)
	if not is_finite(distance) or distance > WORKBENCH_RANGE:
		return {"ok": false, "reason": "no_station"}
	if not Defs.is_item(item_id) or count < 1 or count > Defs.stack_size(item_id):
		return {"ok": false, "reason": "invalid_stack"}
	var source = player.inventory if deposit else player.stash
	var destination = player.stash if deposit else player.inventory
	if source.count(item_id) < count:
		return {"ok": false, "reason": "missing_items"}
	if destination.free_space_for(item_id) < count:
		return {"ok": false, "reason": "no_space"}
	# Source and destination are exclusively server-owned. The destination
	# has been capacity-checked so these operations cannot partially succeed.
	if not source.remove(item_id, count):
		return {"ok": false, "reason": "missing_items"}
	var left: int = destination.add(item_id, count)
	if left != 0:
		# Defensive rollback if future inventory implementations change.
		destination.remove(item_id, count - left)
		source.add(item_id, count)
		return {"ok": false, "reason": "transaction_failed"}
	if deposit:
		player.inventory.unequip_missing()
	player.dirty_inventory = true
	player.dirty_stash = true
	player.dirty_character = true
	return {"ok": true, "item": item_id, "count": count, "deposit": deposit}


## Validate and build entirely on the authority. Clients only request a location.
## Building is intentionally forbidden inside the town sanctuary.
func cmd_build(peer_id: int, x: float, z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var point := Vector2(x, z)
	var from := Vector2(player.position.x, player.position.z)
	if not point.is_finite() or not from.is_finite():
		return {"ok": false, "reason": "invalid_position"}
	var distance := point.distance_to(from)
	if distance < Structures.MIN_BUILD_DISTANCE or distance > Structures.BUILD_RANGE:
		return {"ok": false, "reason": "out_of_range"}
	if point.length() < Structures.MIN_HUB_DISTANCE:
		return {"ok": false, "reason": "safe_zone"}
	if world.is_water(x, z) or world.normal_at(x, z).y < Structures.MIN_SLOPE_NORMAL_Y:
		return {"ok": false, "reason": "bad_terrain"}
	if barricades.size() >= Structures.MAX_GLOBAL:
		return {"ok": false, "reason": "world_limit"}
	var owned := 0
	for item in barricades.values():
		if Structures.can_manage(item, peer_id, player.user_id):
			owned += 1
	if owned >= Structures.MAX_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	# Check the same blockers the movement solver queries; forbid overlapping
	# players and infected as well, before consuming building materials.
	for blocker in world.blockers_near(x, z, Structures.RADIUS + 1.0):
		var offset := Vector2(x - float(blocker["x"]), z - float(blocker["z"]))
		if offset.length() < Structures.RADIUS + float(blocker["radius"]) + 0.1:
			return {"ok": false, "reason": "blocked"}
	for other in players.values():
		if _alive(other) and Structures.within_range(point, Vector2(other.position.x, other.position.z), Structures.RADIUS + Defs.PLAYER_RADIUS + 0.2):
			return {"ok": false, "reason": "blocked"}
	for infected in zombies.values():
		if infected.is_alive() and Structures.within_range(point, Vector2(infected.position.x, infected.position.z), Structures.RADIUS + 0.65):
			return {"ok": false, "reason": "blocked"}
	if not player.inventory.has_all(Structures.COST):
		return {"ok": false, "reason": "missing_materials"}
	# No action between cost validation and removal: server simulation single thread.
	for item_id in Structures.COST:
		player.inventory.remove(item_id, int(Structures.COST[item_id]))
	var id := new_id()
	var item := {"id": id, "x": x, "y": world.height_at(x, z), "z": z,
		"hp": Structures.MAX_HEALTH, "tier": 1, "owner": peer_id,
		"owner_account": player.user_id}
	barricades[id] = item
	world_structure_revision += 1
	world.add_dynamic_blocker(id, x, z, Structures.RADIUS)
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "barricade_built", "id": id, "peer": peer_id})
	return {"ok": true, "id": id}


func cmd_repair(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var item: Dictionary = barricades.get(id, {})
	if item.is_empty():
		return {"ok": false, "reason": "no_structure"}
	if not Structures.can_manage(item, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	var origin := Vector2(player.position.x, player.position.z)
	var target := Vector2(float(item["x"]), float(item["z"]))
	if not Structures.within_range(origin, target, Structures.REPAIR_RANGE):
		return {"ok": false, "reason": "out_of_range"}
	var tier: int = Structures.tier_of(item)
	var max_hp: float = Structures.max_health(tier)
	var cost: Dictionary = Structures.repair_cost(tier)
	if max_hp <= 0.0:
		return {"ok": false, "reason": "invalid_tier"}
	if float(item["hp"]) >= max_hp:
		return {"ok": false, "reason": "full_health"}
	if not player.inventory.has_all(cost):
		return {"ok": false, "reason": "missing_materials"}
	for item_id in cost:
		player.inventory.remove(str(item_id), int(cost[item_id]))
	item["hp"] = minf(max_hp, float(item["hp"]) + Structures.repair_amount(tier))
	barricades[id] = item
	world_structure_revision += 1
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "id": id, "hp": float(item["hp"]), "tier": tier}


## Upgrade the closest existing wall, not an arbitrary remote structure.
## Item costs are server-derived from the target tier, never RPC parameters.
func cmd_upgrade(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var item: Dictionary = barricades.get(id, {})
	if item.is_empty():
		return {"ok": false, "reason": "no_structure"}
	if not Structures.can_manage(item, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	var origin := Vector2(player.position.x, player.position.z)
	var target := Vector2(float(item["x"]), float(item["z"]))
	if not Structures.within_range(origin, target, Structures.UPGRADE_RANGE):
		return {"ok": false, "reason": "out_of_range"}
	var old_tier: int = Structures.tier_of(item)
	if not Structures.valid_tier(old_tier):
		return {"ok": false, "reason": "invalid_tier"}
	if old_tier >= Structures.MAX_TIER:
		return {"ok": false, "reason": "max_tier"}
	var next_tier: int = old_tier + 1
	var cost: Dictionary = Structures.upgrade_cost(next_tier)
	if not player.inventory.has_all(cost):
		return {"ok": false, "reason": "missing_materials"}
	# Preserve damage ratio: upgrades do not secretly repair the wall.
	var fraction: float = clampf(float(item["hp"]) / Structures.max_health(old_tier), 0.0, 1.0)
	for item_id in cost:
		player.inventory.remove(str(item_id), int(cost[item_id]))
	item["tier"] = next_tier
	item["hp"] = Structures.max_health(next_tier) * fraction
	barricades[id] = item
	world_structure_revision += 1
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "barricade_upgraded", "id": id, "tier": next_tier, "peer": peer_id})
	return {"ok": true, "id": id, "tier": next_tier, "hp": float(item["hp"])}


## Owner-only, local, all-or-nothing structure salvage.
## Never remove a world collider until the inventory accepts the full refund.
func cmd_dismantle(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var structure: Dictionary = barricades.get(id, {})
	if structure.is_empty():
		return {"ok": false, "reason": "no_structure"}
	if not Structures.can_manage(structure, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	var origin := Vector2(player.position.x, player.position.z)
	var target := Vector2(float(structure["x"]), float(structure["z"]))
	if not Structures.within_range(origin, target, Structures.DISMANTLE_RANGE):
		return {"ok": false, "reason": "out_of_range"}
	var salvage: Dictionary = Structures.salvage_for_health(float(structure["hp"]), Structures.tier_of(structure))
	var trial = Inventory.new(player.inventory.slots.size())
	trial.load_dict(player.inventory.to_dict())
	for item_id in salvage:
		if trial.add(str(item_id), int(salvage[item_id])) != 0:
			return {"ok": false, "reason": "no_space"}
	# Atomic gameplay commit: a failed attempt cannot erase a barricade or mint loot.
	player.inventory.load_dict(trial.to_dict())
	barricades.erase(id)
	world_structure_revision += 1
	world.remove_dynamic_blocker(id)
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "barricade_dismantled", "id": id, "peer": peer_id})
	return {"ok": true, "id": id, "salvage": salvage}


func damage_barricade(id: int, damage: float) -> bool:
	# Returns true when the structure breaks. Can be used by zombie AI or
	# future server-side explosions. Never trusts a client-provided damage.
	if not barricades.has(id) or not is_finite(damage) or damage <= 0.0:
		return false
	var item: Dictionary = barricades[id]
	item["hp"] = maxf(0.0, float(item["hp"]) - damage * Structures.damage_factor(Structures.tier_of(item)))
	world_structure_revision += 1
	if float(item["hp"]) <= 0.0:
		barricades.erase(id)
		world.remove_dynamic_blocker(id)
		events.append({"type": "barricade_broken", "id": id})
		return true
	barricades[id] = item
	return false


func cmd_use(peer_id: int, item_id: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var data := Defs.item(item_id)
	if data.is_empty() or player.inventory.count(item_id) < 1:
		return {"ok": false, "reason": "not_carried"}
	match data["kind"]:
		"food":
			player.inventory.remove(item_id, 1)
			player.survival.eat(float(data["food"]))
		"drink":
			player.inventory.remove(item_id, 1)
			player.survival.drink(float(data["drink"]))
		"medical":
			var healing: float = float(data.get("heal", 0.0))
			var curing: float = float(data.get("cure", 0.0))
			if (healing <= 0.0 or player.survival.health >= Defs.MAX_HEALTH) and (
					curing <= 0.0 or player.survival.infection <= 0.0):
				return {"ok": false, "reason": "no_effect"}
			player.inventory.remove(item_id, 1)
			player.survival.heal(healing)
			player.survival.treat_infection(curing)
		"weapon", "armor":
			player.inventory.equip(item_id)
		_:
			return {"ok": false, "reason": "not_usable"}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true}


func cmd_drink_water(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	# Drinking from a lake needs water within reach.
	for angle in 8:
		var spot := Vector2(player.position.x, player.position.z) + Vector2.from_angle(angle * TAU / 8.0) * 3.0
		if world.is_water(spot.x, spot.y):
			player.survival.drink(35.0)
			return {"ok": true}
	return {"ok": false, "reason": "no_water"}


## Attack in the direction the player is facing. Melee hits the closest enemy in range; a pistol
## shoots a ray that hits the first enemy along it.
func cmd_attack(peer_id: int, dir_x: float, dir_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.attack_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	var direction := Vector2(dir_x, dir_z)
	if not direction.is_finite() or direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "no_direction"}
	direction = direction.normalized()
	var weapon: String = player.inventory.weapon
	var kind: String = Defs.item(weapon).get("weapon", "melee") if weapon != "" else "melee"
	player.attack_timer = Combat.weapon_cooldown(weapon)
	player.action = {} # Fighting interrupts gathering.
	player.yaw = atan2(direction.x, direction.y)
	var origin := Vector2(player.position.x, player.position.z)
	var damage := Combat.weapon_damage(weapon)
	var reach := Defs.MELEE_RANGE
	if kind == "ranged":
		var ammo: String = Defs.item(weapon).get("ammo", "")
		if player.inventory.count(ammo) < 1:
			player.attack_timer = 0.3
			return {"ok": false, "reason": "no_ammo"}
		player.inventory.remove(ammo, 1)
		player.dirty_inventory = true
		# Only a real shot with ammunition makes gunshot noise.
		player.noise_radius = maxf(player.noise_radius, Defs.GUNSHOT_NOISE_RADIUS)
		player.noise_timer = maxf(player.noise_timer, Defs.GUNSHOT_NOISE_SECONDS)
		reach = Defs.PISTOL_RANGE
	var hit := _find_hit(player, origin, direction, reach, kind == "ranged")
	events.append({"type": "attack", "peer": peer_id, "dir": direction, "ranged": kind == "ranged", "x": player.position.x, "z": player.position.z})
	if hit.is_empty():
		return {"ok": true, "hit": false}
	_damage_target(player, hit, damage)
	return {"ok": true, "hit": true, "target": hit["kind"]}


## Resolve active combat on the server; the client supplies only aim direction.
func cmd_skill(peer_id: int, dir_x: float, dir_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.attack_timer > 0.0 or player.skill_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	var weapon: String = player.inventory.weapon
	var skill: Dictionary = Combat.active_skill(weapon)
	if skill.is_empty() or player.inventory.count(weapon) < 1:
		return {"ok": false, "reason": "no_skill"}
	var direction := Vector2(dir_x, dir_z)
	if not direction.is_finite() or direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "no_direction"}
	var cost: float = float(skill["energy_cost"])
	if player.combat_energy < cost:
		return {"ok": false, "reason": "no_energy"}
	direction = direction.normalized()
	player.combat_energy -= cost
	player.skill_timer = float(skill["cooldown"])
	player.attack_timer = float(skill["attack_lock"])
	player.action = {}
	player.yaw = atan2(direction.x, direction.y)
	var origin := Vector2(player.position.x, player.position.z)
	var hit := _find_hit(player, origin, direction, float(skill["range"]), false)
	events.append({"type": "attack", "peer": peer_id, "dir": direction, "ranged": false, "skill": skill["id"], "x": player.position.x, "z": player.position.z})
	if hit.is_empty():
		return {"ok": true, "hit": false, "energy": player.combat_energy}
	_damage_target(player, hit, float(skill["damage"]))
	return {"ok": true, "hit": true, "target": hit["kind"], "energy": player.combat_energy}


## Classless evasion: no client-supplied distance, speed, stamina or invulnerability.
## Reuse swept-in-small-steps world collision and restrict zombie immunity to 0.30 s.
func cmd_dodge(peer_id: int, dir_x: float, dir_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.dodge_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	if player.attack_timer > 0.0:
		return {"ok": false, "reason": "attack_lock"}
	var direction := Vector2(dir_x, dir_z)
	if not direction.is_finite() or direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "no_direction"}
	if player.inventory.movement_factor() < 0.9999:
		return {"ok": false, "reason": "overweight"}
	if player.survival.hunger <= 5.0 or player.survival.thirst <= 5.0:
		return {"ok": false, "reason": "exhausted"}
	if player.survival.stamina < Evasion.STAMINA_COST:
		return {"ok": false, "reason": "no_stamina"}
	var new_position: Vector3 = Evasion.destination(world, player.position, direction)
	if Evasion.moved_distance(player.position, new_position) < Evasion.MIN_DISPLACEMENT:
		return {"ok": false, "reason": "blocked"}
	player.position = new_position
	player.yaw = atan2(direction.x, direction.y)
	player.survival.stamina -= Evasion.STAMINA_COST
	player.survival.stamina_recovery_delay = Defs.STAMINA_RECOVERY_DELAY
	player.dodge_timer = Evasion.COOLDOWN
	player.dodge_immunity = Evasion.INVULNERABLE_TO_INFECTED
	player.attack_timer = maxf(player.attack_timer, Evasion.ATTACK_LOCK)
	player.action = {}
	player.noise_radius = Defs.SPRINT_NOISE_RADIUS
	player.noise_timer = Defs.SPRINT_NOISE_SECONDS
	player.dirty_character = true
	events.append({"type": "dodge", "peer": peer_id, "x": new_position.x, "z": new_position.z})
	return {"ok": true, "x": new_position.x, "y": new_position.y,
		"z": new_position.z, "stamina": player.survival.stamina}


func cmd_loot(peer_id: int, entity_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if bags.has(entity_id):
		var bag: Dictionary = bags[entity_id]
		if _distance_xz(player.position, bag) > Defs.REACH + 0.5:
			return {"ok": false, "reason": "too_far"}
		var left := _give_items(player, bag["items"])
		if left.is_empty():
			bags.erase(entity_id)
		else:
			bag["items"] = left
		return {"ok": true, "complete": left.is_empty()}
	var crate := _find_crate(entity_id)
	if not crate.is_empty():
		if opened_crates.has(entity_id):
			return {"ok": false, "reason": "empty"}
		if _distance_xz(player.position, crate) > Defs.REACH + 0.5:
			return {"ok": false, "reason": "too_far"}
		var local_rng := RandomNumberGenerator.new()
		local_rng.seed = WorldGen.mix(entity_id, int(time), world.world_seed, 3)
		var loot := Combat.crate_loot(int(crate["zone"]), local_rng)
		var left := _give_items(player, loot)
		if not left.is_empty():
			# Whatever does not fit stays on the ground next to the crate.
			_make_bag(Vector3(crate["x"], crate["y"], crate["z"]), left)
		opened_crates[entity_id] = time + 600.0
		if Contracts.record_crate(player.contract_state, entity_id):
			player.dirty_character = true
		events.append({"type": "crate", "peer": peer_id, "id": entity_id})
		return {"ok": true}
	return {"ok": false, "reason": "nothing_there"}


# --- Helpers ----------------------------------------------------------------------------------------------

func _distance_xz(position: Vector3, thing: Dictionary) -> float:
	return Vector2(position.x - float(thing["x"]), position.z - float(thing["z"])).length()


func _find_node(node_id: int) -> Dictionary:
	# Ids encode the chunk loosely; look in the chunks around players instead of searching the world.
	for player in players.values():
		var cell := WorldGen.cell_of(player.position.x, player.position.z)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var data: Dictionary = world.chunk(Vector2i(cell.x + dx, cell.y + dz))
				for node in data["nodes"]:
					if node["id"] == node_id:
						return node
	return {}


func _find_crate(crate_id: int) -> Dictionary:
	for player in players.values():
		var cell := WorldGen.cell_of(player.position.x, player.position.z)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var data: Dictionary = world.chunk(Vector2i(cell.x + dx, cell.y + dz))
				for crate in data["crates"]:
					if crate["id"] == crate_id:
						var result: Dictionary = crate.duplicate()
						result["zone"] = data["zone"]
						return result
	return {}


## Moves items into a player's inventory; returns what did not fit.
func _give_items(player: Player, items: Dictionary) -> Dictionary:
	player.dirty_character = true
	var left: Dictionary = {}
	for id in items:
		var remaining: int = player.inventory.add(id, int(items[id]))
		if remaining > 0:
			left[id] = remaining
	player.dirty_inventory = true
	return left


func _make_bag(position: Vector3, items: Dictionary) -> int:
	if items.is_empty():
		return -1
	var bag_id := new_id()
	bags[bag_id] = {"id": bag_id, "x": position.x, "y": position.y, "z": position.z, "items": items.duplicate(), "expires": time + BAG_LIFETIME}
	events.append({"type": "bag", "id": bag_id})
	return bag_id


func _find_hit(attacker: Player, origin: Vector2, direction: Vector2, reach: float, ranged: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	var attacker_zone: int = world.zone_at(attacker.position.x, attacker.position.z)
	# Zombies.
	for zombie in zombies.values():
		if not zombie.is_alive():
			continue
		var distance := _hit_distance(origin, direction, Vector2(zombie.position.x, zombie.position.z), reach, ranged, 0.55)
		if distance >= 0.0 and distance < best_distance:
			best = {"kind": "zombie", "id": zombie.id}
			best_distance = distance
	# Red/black PvP only; zone borders do not permit attacking protected players.
	if ZoneRisk.allows_pvp(attacker_zone):
		for other in players.values():
			if other.id == attacker.id or not _alive(other):
				continue
			if not ZoneRisk.can_pvp(attacker_zone, world.zone_at(other.position.x, other.position.z)):
				continue
			var distance := _hit_distance(origin, direction, Vector2(other.position.x, other.position.z), reach, ranged, 0.5)
			if distance >= 0.0 and distance < best_distance:
				best = {"kind": "player", "id": other.id}
				best_distance = distance
	return best


## Distance along the attack to the target, or -1 if it is missed. Melee needs the target within a
## cone in front; a bullet needs the ray to pass within `radius` of the target.
func _hit_distance(origin: Vector2, direction: Vector2, target: Vector2, reach: float, ranged: bool, radius: float) -> float:
	var to_target := target - origin
	var along := to_target.dot(direction)
	if along < -0.1 or along > reach + radius:
		return -1.0
	if ranged:
		var across := absf(to_target.cross(direction))
		return along if across <= radius else -1.0
	# Melee: within the reach and no more than about 70 degrees off the facing direction.
	var distance := to_target.length()
	if distance > reach + radius:
		return -1.0
	if distance < 0.001:
		return 0.0
	return distance if to_target.normalized().dot(direction) >= 0.34 else -1.0


func _damage_target(attacker: Player, hit: Dictionary, damage: float) -> void:
	attacker.dirty_character = true
	if hit["kind"] == "zombie":
		var zombie = zombies.get(hit["id"])
		if zombie == null:
			return
		events.append({"type": "hit", "kind": "zombie", "id": zombie.id, "damage": damage, "x": zombie.position.x, "z": zombie.position.z})
		if zombie.take_damage(damage):
			attacker.kills += 1
			if Contracts.record_kill(attacker.contract_state):
				attacker.dirty_character = true
			_on_zombie_death(zombie)
	else:
		var victim: Player = players.get(hit["id"])
		if victim == null or not _alive(victim):
			return
		if not ZoneRisk.can_pvp(world.zone_at(attacker.position.x, attacker.position.z),
				world.zone_at(victim.position.x, victim.position.z)):
			return
		var final_damage: float = Combat.apply_armor(damage, victim.inventory.armor)
		victim.survival.hurt(final_damage)
		events.append({"type": "hit", "kind": "player", "id": victim.id, "damage": final_damage, "by": attacker.id})
		if not _alive(victim):
			attacker.kills += 1
			_on_player_death(victim, attacker.id)


func _on_zombie_death(zombie) -> void:
	var zone: int = world.zone_at(zombie.position.x, zombie.position.z)
	var loot_rng := RandomNumberGenerator.new()
	loot_rng.seed = WorldGen.mix(zombie.id, int(time * 10.0), world.world_seed, 5)
	_make_bag(zombie.position, Combat.zombie_loot(zombie.type, zone, loot_rng))
	if spawn_state.has(zombie.spawn_id):
		spawn_state[zombie.spawn_id] = {"zombie": -1, "next": time + (240.0 if zone < 2 else 360.0)}
	events.append({"type": "zombie_died", "id": zombie.id, "x": zombie.position.x, "z": zombie.position.z})


## Full-loot deaths occur in red/black. Green/yellow deaths retain gear.
func _on_player_death(victim: Player, killer: int) -> void:
	_cancel_player_trade(victim.id, "dead")
	victim.deaths += 1
	victim.dirty_character = true
	victim.action = {}
	victim.dodge_immunity = 0.0
	var zone: int = world.zone_at(victim.position.x, victim.position.z)
	var drops_gear: bool = ZoneRisk.full_loot(zone)
	victim.last_death_full_loot = drops_gear
	victim.keep_inventory_on_respawn = not drops_gear
	if drops_gear:
		var everything: Dictionary = victim.inventory.take_everything()
		_make_bag(victim.position, everything)
	victim.respawn_timer = Defs.RESPAWN_SECONDS
	victim.dirty_inventory = true
	events.append({"type": "death", "peer": victim.id, "killer": killer, "full_loot": drops_gear, "zone": zone})


# --- The simulation tick -------------------------------------------------------------------------------

func tick(delta: float) -> void:
	# Events from commands that arrived since the last tick are kept: the network layer drains them.
	if events.size() > 2000:
		events = events.slice(events.size() - 1000)
	time += delta
	tick_count += 1
	_tick_trades()
	_tick_players(delta)
	_tick_zombies(delta)
	_tick_world(delta)


func _tick_players(delta: float) -> void:
	for player in players.values():
		player.input_budget = minf(player.input_budget + delta, 0.25)
		player.attack_timer = maxf(player.attack_timer - delta, 0.0)
		player.skill_timer = maxf(player.skill_timer - delta, 0.0)
		player.dodge_timer = maxf(player.dodge_timer - delta, 0.0)
		player.dodge_immunity = maxf(player.dodge_immunity - delta, 0.0)
		player.noise_timer = maxf(player.noise_timer - delta, 0.0)
		if player.noise_timer <= 0.0:
			player.noise_radius = 0.0
		if not _alive(player):
			player.respawn_timer -= delta
			if player.respawn_timer <= 0.0:
				_spawn_player(player)
			continue
		player.combat_energy = minf(Defs.COMBAT_ENERGY_MAX, player.combat_energy + Defs.COMBAT_ENERGY_REGEN * delta)
		var damage: float = player.survival.tick(delta)
		if player.survival.infection > 0.0:
			player.dirty_character = true
		if damage > 0.0 and not _alive(player):
			_on_player_death(player, -1)
			continue
		var zone: int = world.zone_at(player.position.x, player.position.z)
		if zone != player.zone_notice:
			player.zone_notice = zone
			events.append({"type": "zone", "peer": player.id, "zone": zone})
		if not player.action.is_empty():
			var node := _find_node(int(player.action["node"]))
			if node.is_empty() or depleted.has(int(player.action["node"])):
				player.action = {}
				continue
			player.action["remaining"] = float(player.action["remaining"]) - delta
			if float(player.action["remaining"]) <= 0.0:
				_finish_gather(player, node)


func _finish_gather(player: Player, node: Dictionary) -> void:
	var info := Defs.node_info(node["kind"])
	var item_id: String = info["yield"]
	if item_id in ["wood", "stone", "ore", "fiber"]:
		item_id = "%s_%d" % [item_id, int(node["tier"])]
	var amount: int = int(info["amount"]) + (1 if rng.randf() < 0.3 else 0)
	var left: int = player.inventory.add(item_id, amount)
	# No XP for items that did not fit, nor for repeat attempts on depleted nodes.
	player.progression.award_gather(String(node["kind"]), int(node["tier"]), amount - left)
	player.dirty_inventory = true
	player.dirty_character = true
	player.action = {}
	depleted[int(node["id"])] = time + float(info["respawn"])
	events.append({"type": "gathered", "peer": player.id, "item": item_id, "amount": amount - left, "node": node["id"]})


func _tick_zombies(delta: float) -> void:
	var info: Dictionary = {}
	for player in players.values():
		info[player.id] = {"position": player.position, "alive": _alive(player),
			"safe": _is_safe(player.position), "noise": player.noise_radius if player.noise_timer > 0.0 else 0.0,
			"notice_multiplier": WorldCycle.notice_multiplier(time)}
	# Activate spawns near players and put far-away zombies to sleep.
	if tick_count % 20 == 1:
		_manage_zombie_population()
	for zombie in zombies.values():
		var result: Dictionary = zombie.think(world, info, delta, rng)
		# Zombies chip away at obstacles only while actually stuck pursuing
		# a survivor. No instantaneous destruction or client damage commands.
		if zombie.stuck_time >= 0.12 and zombie.target_id != -1 and zombies.has(zombie.id):
			var chase_target: Player = players.get(zombie.target_id)
			if chase_target != null and _alive(chase_target):
				var here := Vector2(zombie.position.x, zombie.position.z)
				var toward := Vector2(chase_target.position.x, chase_target.position.z) - here
				if toward.length_squared() > 0.01:
					for wall_id in barricades.keys():
						var wall: Dictionary = barricades[wall_id]
						var offset := Vector2(float(wall["x"]), float(wall["z"])) - here
						if offset.length() <= Structures.ZOMBIE_REACH and offset.dot(toward) > 0.0:
							damage_barricade(wall_id, float(zombie.data["damage"]) * delta * 2.0)
							break
		if not result.is_empty():
			var victim: Player = players.get(result["hit"])
			if victim != null and _alive(victim):
				# An active dodge avoids infected wounds; normal PvP attacks still land.
				if victim.dodge_immunity > 0.0:
					events.append({"type": "evaded", "peer": victim.id, "zombie": zombie.id})
					continue
				var damage: float = Combat.apply_armor(float(result["damage"]), victim.inventory.armor)
				victim.survival.hurt(damage)
				if victim.survival.add_infection(float(Defs.ZOMBIE_INFECTION_PER_HIT.get(zombie.type, 0.0))):
					victim.dirty_character = true
					events.append({"type": "infection", "peer": victim.id,
						"severity": victim.survival.infection, "source": zombie.type})
				events.append({"type": "hit", "kind": "player", "id": victim.id, "damage": damage, "by": -zombie.id})
				if not _alive(victim):
					_on_player_death(victim, -zombie.id)
	# Pack communication is authoritative and runs at most four times per second.
	if tick_count % 5 == 0:
		_alert_infected_pack(info)


## Shares target awareness inside a bounded 2D neighborhood. Bucket lookup
## avoids checking every zombie against every other zombie in crowded ruins.
func _alert_infected_pack(player_info: Dictionary) -> void:
	var buckets: Dictionary = {}
	var alert_sources: Array = []
	for infected in zombies.values():
		if not infected.is_alive():
			continue
		var p: Vector3 = infected.position
		var bucket := Vector2i(floori(p.x / ZOMBIE_PACK_BUCKET_SIZE), floori(p.z / ZOMBIE_PACK_BUCKET_SIZE))
		if not buckets.has(bucket):
			buckets[bucket] = []
		buckets[bucket].append(infected)
		if infected.target_id != -1 and (infected.state == Zombie.State.CHASE or infected.state == Zombie.State.ATTACK):
			var target: Dictionary = player_info.get(infected.target_id, {})
			if not target.is_empty() and bool(target.get("alive", false)) and not bool(target.get("safe", true)):
				alert_sources.append(infected)
	# Freeze alert sources before notifying anyone: no instant chain-reaction
	# through an unlimited crowd in one simulation tick.
	for source in alert_sources:
		var p: Vector3 = source.position
		var cell := Vector2i(floori(p.x / ZOMBIE_PACK_BUCKET_SIZE), floori(p.z / ZOMBIE_PACK_BUCKET_SIZE))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var neighbors: Array = buckets.get(cell + Vector2i(dx, dz), [])
				for nearby in neighbors:
					if nearby.id == source.id or nearby.state == Zombie.State.DEAD:
						continue
					var separation: Vector3 = nearby.position - p
					separation.y = 0.0
					if separation.length_squared() <= ZOMBIE_PACK_ALERT_RADIUS * ZOMBIE_PACK_ALERT_RADIUS:
						nearby.receive_pack_alert(source.target_id, player_info)


func _manage_zombie_population() -> void:
	var active_cells: Dictionary = {}
	for player in players.values():
		if not _alive(player):
			continue
		var cell := WorldGen.cell_of(player.position.x, player.position.z)
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				active_cells[Vector2i(cell.x + dx, cell.y + dz)] = true
	for cell in active_cells:
		var data: Dictionary = world.chunk(cell)
		for spawn in data["spawns"]:
			var state: Dictionary = spawn_state.get(spawn["id"], {"zombie": -1, "next": 0.0})
			spawn_state[spawn["id"]] = state
			if state["zombie"] != -1 or time < float(state["next"]):
				continue
			if _nearest_player_distance(Vector2(spawn["x"], spawn["z"])) < 12.0:
				continue # Never appear in front of a player.
			var zombie_id := new_id()
			var z := Zombie.new(zombie_id, spawn["type"], Vector3(spawn["x"], world.height_at(spawn["x"], spawn["z"]), spawn["z"]), spawn["id"])
			zombies[zombie_id] = z
			state["zombie"] = zombie_id
	# Sleeping: remove zombies nobody is near, and let their spawns create them again later.
	var gone: Array = []
	for zombie in zombies.values():
		if not zombie.is_alive():
			gone.append(zombie.id)
		elif _nearest_player_distance(Vector2(zombie.position.x, zombie.position.z)) > ZOMBIE_ACTIVE_RADIUS:
			gone.append(zombie.id)
			if spawn_state.has(zombie.spawn_id):
				spawn_state[zombie.spawn_id] = {"zombie": -1, "next": 0.0}
	for id in gone:
		zombies.erase(id)


func _nearest_player_distance(point: Vector2) -> float:
	var best := INF
	for player in players.values():
		if _alive(player):
			best = minf(best, point.distance_to(Vector2(player.position.x, player.position.z)))
	return best


func _tick_world(_delta: float) -> void:
	for id in depleted.keys():
		if time >= float(depleted[id]):
			depleted.erase(id)
	for id in opened_crates.keys():
		if time >= float(opened_crates[id]):
			opened_crates.erase(id)
	for id in bags.keys():
		if time >= float(bags[id]["expires"]):
			bags.erase(id)


## Returns the events since the last call and forgets them.
func drain_events() -> Array:
	var result := events
	events = []
	return result


# --- Snapshots --------------------------------------------------------------------------------------------------

## What one player is allowed to know: their own full state and nearby entities.
func snapshot_for(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null:
		return {}
	var here := Vector2(player.position.x, player.position.z)
	var nearby_players: Array = []
	for other in players.values():
		if other.id == peer_id:
			continue
		var p: Vector3 = other.position
		if here.distance_to(Vector2(p.x, p.z)) <= Defs.INTEREST_RADIUS:
			nearby_players.append({"id": other.id, "name": other.name, "x": p.x, "y": p.y, "z": p.z, "yaw": other.yaw, "alive": _alive(other), "weapon": other.inventory.weapon})
	var nearby_zombies: Array = []
	for zombie in zombies.values():
		var p: Vector3 = zombie.position
		if zombie.is_alive() and here.distance_to(Vector2(p.x, p.z)) <= Defs.INTEREST_RADIUS:
			nearby_zombies.append({"id": zombie.id, "type": zombie.type, "x": p.x, "y": p.y, "z": p.z, "yaw": zombie.yaw, "hp": zombie.health, "state": zombie.state})
	var nearby_barricades: Array = []
	for wall in barricades.values():
		if Structures.within_range(here, Vector2(float(wall["x"]), float(wall["z"])), Defs.INTEREST_RADIUS):
			nearby_barricades.append(Structures.public_state(wall))
	var nearby_bags: Array = []
	for bag in bags.values():
		if here.distance_to(Vector2(bag["x"], bag["z"])) <= Defs.INTEREST_RADIUS:
			nearby_bags.append({"id": bag["id"], "x": bag["x"], "y": bag["y"], "z": bag["z"]})
	var gone_nodes: Array = []
	for id in depleted:
		gone_nodes.append(id)
	var used_crates: Array = []
	for id in opened_crates:
		used_crates.append(id)
	var snapshot := {
		"tick": tick_count, "time": time, "ack": player.last_input_seq,
		"you": {
			"x": player.position.x, "y": player.position.y, "z": player.position.z, "yaw": player.yaw,
			"health": player.survival.health, "hunger": player.survival.hunger, "thirst": player.survival.thirst,
			"stamina": player.survival.stamina,
			"alive": _alive(player), "kills": player.kills, "deaths": player.deaths, "zone": player.zone_notice,
			"action": player.action.duplicate(),
			"infection": player.survival.infection,
			"combat_energy": player.combat_energy, "skill_cooldown": player.skill_timer,
			"dodge_cooldown": player.dodge_timer, "dodge_immunity": player.dodge_immunity,
			"weapon": player.inventory.weapon, "armor": player.inventory.armor,
			"last_death_full_loot": player.last_death_full_loot,
			"is_night": WorldCycle.is_night(time),
			"gathering_levels": player.progression.levels(), "crafting_level": player.progression.crafting_level(),
			"crafting_xp": player.progression.crafting_xp,
			"contract": player.contract_state.duplicate(true),
			"carry_kg": player.inventory.total_weight(),
			"cargo_factor": player.inventory.movement_factor(),
		},
		"players": nearby_players, "zombies": nearby_zombies, "bags": nearby_bags,
		"barricades": nearby_barricades,
		"depleted": gone_nodes, "crates_used": used_crates,
	}
	if player.dirty_inventory:
		snapshot["inventory"] = player.inventory.to_dict()
		player.dirty_inventory = false
	if player.dirty_stash:
		snapshot["stash"] = player.stash.to_dict()
		player.dirty_stash = false
	return snapshot
