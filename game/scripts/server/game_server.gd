extends RefCounted
## The authoritative simulation of the world: players, zombies, resources, loot and the rules that
## connect them. It has no networking and no scene: the network layer only feeds it commands and
## reads snapshots out of it, so the whole game can be tested by calling it directly.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")
const CombatLogout = preload("res://scripts/shared/combat_logout.gd")
const TrainingDuel = preload("res://scripts/shared/training_duel.gd")
const PvPHonor = preload("res://scripts/shared/pvp_honor.gd")
const PlayerTrade = preload("res://scripts/shared/player_trade.gd")
const Party = preload("res://scripts/shared/party.gd")
const GuildIdentity = preload("res://scripts/shared/guild_identity.gd")
const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")
const LootRights = preload("res://scripts/shared/loot_rights.gd")
const PartyAid = preload("res://scripts/shared/party_aid.gd")
const TerritoryControl = preload("res://scripts/shared/territory_control.gd")
const SiegeContracts = preload("res://scripts/shared/siege_contracts.gd")
const OutpostFortification = preload("res://scripts/shared/outpost_fortification.gd")
const OutpostBreach = preload("res://scripts/shared/outpost_breach.gd")
const MarketBoard = preload("res://scripts/shared/market_board.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const Skills = preload("res://scripts/shared/skills.gd")
const DailyBounties = preload("res://scripts/shared/daily_bounties.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")
const Reputation = preload("res://scripts/shared/reputation.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Evasion = preload("res://scripts/shared/evasion.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Scavenging = preload("res://scripts/shared/scavenging.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const SiegeWaves = preload("res://scripts/shared/siege_waves.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")
const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")
const WardenAura = preload("res://scripts/shared/warden_aura.gd")
const RaidReinforcements = preload("res://scripts/shared/raid_reinforcements.gd")
const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const EliteInfected = preload("res://scripts/shared/elite_infected.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const BloodScent = preload("res://scripts/shared/blood_scent.gd")
const FieldScentMask = preload("res://scripts/shared/field_scent_mask.gd")
const Camouflage = preload("res://scripts/shared/camouflage.gd")
const Progression = preload("res://scripts/shared/progression.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const FieldRest = preload("res://scripts/shared/field_rest.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")
const Fishing = preload("res://scripts/shared/fishing.gd")
const FieldWater = preload("res://scripts/shared/field_water.gd")
const FrontierStim = preload("res://scripts/shared/frontier_stim.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const PartyFeast = preload("res://scripts/shared/party_feast.gd")

const WORKBENCH_POSITION := Vector2(9.0, 0.0)
const WORKBENCH_RANGE := 6.0
const TRADE_RANGE := 6.0
const TRADE_TIMEOUT := 45.0
const MARKET_MAX_REQUEST_ID := 2_147_483_647
const FORTIFY_MAX_REQUEST_ID := 2_147_483_647
const BREACH_MAX_REQUEST_ID := 2_147_483_647
const SIEGE_DECLARE_MAX_REQUEST_ID := 2_147_483_647
const ZOMBIE_ACTIVE_RADIUS := 130.0 # Zombies farther than this from every player are put to sleep.
const ZOMBIE_PACK_ALERT_RADIUS := 18.0
const ZOMBIE_PACK_BUCKET_SIZE := 18.0
const BAG_LIFETIME := 300.0
const MAX_NAME_LENGTH := 20
const SNAPSHOT_REPEAT_SECONDS := 2.5
const SKILL_NOURISH_THRESHOLD := 90.0 # Eating or drinking above this teaches nothing.
const SKILL_METERS_PER_ATHLETICS_XP := 6.0
const SKILL_METERS_PER_EXPLORER_XP := 25.0
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
	var skills # The skill tree: XP in every kind of action, perks, bonuses.
	var pending_xp: Dictionary = {} # skill -> XP gained since the last report to the player
	var pending_levels: Array = [] # [{"skill", "level"}] reached since the last report
	var xp_report_timer: float = 0.0
	var run_meters: float = 0.0 # Sprinted distance not yet turned into XP.
	var travel_meters: float = 0.0
	var dirty_skills: bool = true
	var skills_sent_at: float = -100.0
	var inventory_sent_at: float = -100.0
	var stash_sent_at: float = -100.0
	var contract_state: Dictionary = {} # Server-owned persistent camp contract journal.
	var daily_bounty: Dictionary = {} # Account-persisted UTC daily bounty, never set by clients.
	var renown: int = 0 # Permanent survivor reputation, validated on Nakama loads.
	var rest_cooldown: float = 0.0 # Per-survivor seconds until next camp recovery.
	var party_aid_timer: float = 0.0 # Temporary medical support cooldown.
	var feast_timer: float = 0.0 # Session-only prepared group meal cooldown.
	var guardian_timer: float = 0.0 # Session-only PvE frontline cooldown.
	var guardian_brace: float = 0.0 # Short PvE-only defensive brace after a valid taunt.
	var lake_drink_cooldown: float = 0.0 # Prevents lake hydration spam and relog bypass.
	var stim_cooldown: float = 0.0 # Persistent server-authorized injection cooldown.
	var meal_seconds: float = 0.0 # Remaining server-ticked cooked-fish recovery buff.
	var meal_tier: int = 0 # Zero when no meal buff is active; never client-authored.
	var input_budget: float = 0.0
	var last_input_seq: int = 0
	var attack_timer: float = 0.0
	var skill_timer: float = 0.0
	var dodge_timer: float = 0.0
	var dodge_immunity: float = 0.0
	var combat_energy: float = 100.0
	var noise_radius: float = 0.0
	var noise_timer: float = 0.0
	var decoy_timer: float = 0.0 # Anti-spam timer; no persistent character data.
	var action: Dictionary = {} # Current gathering or fishing: {"remaining": s, "total": s, ...}
	var fish_next_at: float = 0.0
	var respawn_timer: float = 0.0
	var keep_inventory_on_respawn: bool = false
	var last_death_full_loot: bool = false
	var combat_tag_until: float = 0.0 # Only server ticks mark PvP combat, never persisted.
	var kills: int = 0
	var deaths: int = 0
	var pvp_infamy: float = 0.0 # Persistent server-only criminal reputation.
	var defense_target: int = -1 # Last verified PvP aggressor in this session.
	var defense_until: float = 0.0 # Current server-clock expiry; never saved.
	var pvp_kills: int = 0
	var pvp_honor: int = 0
	var zone_notice: int = -1
	var dirty_inventory: bool = true
	var dirty_stash: bool = true
	var user_id: String = "" # Nakama account, empty in offline mode.
	var guild_id: String = "" # Trusted Nakama group membership; session cache only.
	var guild_name: String = "" # Public verified guild name, never loaded from character storage.
	var guild_rank: int = -1 # Nakama rank 0/1/2; -1 means no verified membership.
	var dirty_character: bool = false # Something worth saving changed.

var players: Dictionary = {} # peer id -> Player
var zombies: Dictionary = {} # zombie id -> Zombie
var depleted: Dictionary = {} # node id -> time it comes back
var opened_crates: Dictionary = {} # crate id -> time it refills
var spawn_state: Dictionary = {} # spawn id -> {"zombie": id or -1, "next": time}
var barricades: Dictionary = {}
var siege_last_by_wall: Dictionary = {} # Session timers only; no character persistence.
var last_siege_time: float = -1000000.0
var siege_waves_started: int = 0 # Server-owned structures; authenticated walls may persist.
var raid_boss_id: int = -1
var last_raid_spawn_time: float = -1000000.0
var raid_started_at: float = 0.0
var raid_next_slam_at: float = 0.0
var raid_pending_slam: Dictionary = {} # World position & deadline are server-owned.
var raid_wave: int = 0 # Number of completed reinforcement phases.
var raid_minions: Array[int] = [] # Raid-only infected are cleared with boss.
var campfires: Dictionary = {} # Temporary shared warmth, never checkpointed.
var decoys: Dictionary = {} # Temporary physical sound lures; server-owned, never persisted.
var trades: Dictionary = {} # trade id -> offer/accept/expiry
var market_orders: Dictionary = {} # id -> advertised online stock (not escrow).
var market_sales: Array = [] # Bounded session-only receipts, NOT durable settlement.
var market_buy_requests: Dictionary = {} # Peer -> last request ID, arguments and result.
var trade_by_player: Dictionary = {} # peer -> active trade
var parties = Party.new() # Server-only session groups and short-lived invitations.
var territory # Session outposts generated from this world seed.
var siege_contracts = SiegeContracts.new() # Session-only declared siege windows and honor.
var outpost_fortify_requests: Dictionary = {} # Peer -> last request and cached result.
var outpost_breach_requests: Dictionary = {} # Peer -> last command and cached result.
var training_invites: Dictionary = {} # Target peer -> verified invitation.
var training_matches: Dictionary = {} # Both peer IDs reference the same session.
var training_invite_last: Dictionary = {} # Bounded per peer by disconnect cleanup.
var pvp_honor_ledger: Dictionary = {} # Bounded server-only account/guest kill cooldowns.
var siege_declare_requests: Dictionary = {} # Peer -> last declared request and cached result.
var world_structure_revision: int = 0
var bags: Dictionary = {} # Session loot; optional server-owned PvE reservations
var events: Array = [] # Things that happened this tick, for the network layer to announce.
var _next_id: int = 5_000_000_000


func _init(p_world, p_seed: int = 1) -> void:
	world = p_world
	territory = TerritoryControl.new(p_world)
	rng.seed = p_seed


func new_id() -> int:
	_next_id += 1
	return _next_id


## Called only by the authoritative ENet/Nakama gateway, never an RPC.
## Membership cannot be restored from client saves or assigned to guests.
func set_verified_guild(peer_id: int, backend_result: Dictionary) -> bool:
	var player: Player = players.get(peer_id)
	if player == null or player.user_id.is_empty():
		return false
	var checked: Dictionary = GuildIdentity.normalize(backend_result)
	if checked.is_empty():
		return false
	player.guild_id = checked["guild_id"]
	player.guild_name = checked["guild_name"]
	player.guild_rank = checked["rank"]
	return true


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
	player.skills = Skills.new()
	player.contract_state = Contracts.empty_state()
	player.daily_bounty = DailyBounties.empty_state()
	player.renown = 0
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
		"bleeding": player.survival.bleeding,
		"exposure": player.survival.exposure, "warmth_seconds": player.survival.warmth_seconds,
		"scent_mask_seconds": player.survival.scent_mask_seconds,
		"alive": alive, "kills": player.kills, "deaths": player.deaths,
		"pvp_infamy": player.pvp_infamy,
		"pvp_kills": player.pvp_kills, "pvp_honor": player.pvp_honor,
		"x": player.position.x, "z": player.position.z,
		"inventory": player.inventory.to_dict(),
		"stash": player.stash.to_dict(),
		"progression": player.progression.to_dict(),
		"skills": player.skills.to_dict(),
		"contracts": player.contract_state.duplicate(true),
		"daily_bounty": player.daily_bounty.duplicate(true),
		"renown": player.renown,
		"rest_cooldown": player.rest_cooldown, "lake_drink_cooldown": player.lake_drink_cooldown,
		"stim_cooldown": player.stim_cooldown,
		"meal_seconds": player.meal_seconds, "meal_tier": player.meal_tier,
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
	if not SaveValidation.finite_number(data.get("health", 100.0), 0.0, Defs.MAX_HEALTH + Skills.MAX_HEALTH_BONUS):
		return false
	if not SaveValidation.finite_number(data.get("hunger", 80.0), 0.0, 100.0):
		return false
	if not SaveValidation.finite_number(data.get("thirst", 80.0), 0.0, 100.0):
		return false
	if not SaveValidation.finite_number(data.get("stamina", Defs.MAX_STAMINA), 0.0, Defs.MAX_STAMINA):
		return false
	if not SaveValidation.finite_number(data.get("infection", 0.0), 0.0, Defs.INFECTION_MAX):
		return false
	if not SaveValidation.finite_number(data.get("bleeding", 0.0), 0.0, Defs.BLEEDING_MAX):
		return false
	if not SaveValidation.finite_number(data.get("exposure", 0.0), 0.0, 100.0):
		return false
	if not SaveValidation.finite_number(data.get("warmth_seconds", 0.0), 0.0, Defs.THERMAL_WRAP_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("scent_mask_seconds", 0.0), 0.0, FieldScentMask.DURATION_SECONDS):
		return false
	if not SaveValidation.valid_counter(data.get("kills", 0)):
		return false
	if not SaveValidation.valid_counter(data.get("deaths", 0)):
		return false
	if not PvpInfamy.valid(data.get("pvp_infamy", 0.0)):
		return false
	for key in ["pvp_kills", "pvp_honor"]:
		if not SaveValidation.valid_counter(data.get(key, 0)) or \
				float(data.get(key, 0)) > PvPHonor.MAX_POINTS:
			return false
	if not SaveValidation.finite_number(data.get("rest_cooldown", 0.0), 0.0, CampRest.COOLDOWN):
		return false
	if not SaveValidation.finite_number(data.get("lake_drink_cooldown", 0.0), 0.0, FieldWater.COOLDOWN_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("stim_cooldown", 0.0), 0.0, FrontierStim.COOLDOWN):
		return false
	if not HeartyMeal.valid_state(data.get("meal_seconds", 0.0), data.get("meal_tier", 0)):
		return false
	if not (data.get("alive", true) is bool):
		return false

	var survival = Survival.new()
	survival.health = clampf(float(data.get("health", 100.0)), 1.0, Defs.MAX_HEALTH + Skills.MAX_HEALTH_BONUS)
	survival.hunger = float(data.get("hunger", 80.0))
	survival.thirst = float(data.get("thirst", 80.0))
	# Legacy v1 characters without stamina are restored fully rested.
	survival.stamina = float(data.get("stamina", Defs.MAX_STAMINA))
	# Older version-1 saves without infection remain compatible.
	survival.infection = float(data.get("infection", 0.0))
	# Legacy version-1 accounts predate the persistent wound mechanic.
	survival.bleeding = float(data.get("bleeding", 0.0))
	# Legacy survivors predating regional climate start with no exposure.
	survival.exposure = float(data.get("exposure", 0.0))
	survival.warmth_seconds = float(data.get("warmth_seconds", 0.0))
	survival.scent_mask_seconds = float(data.get("scent_mask_seconds", 0.0))
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
	var loaded_daily: Variant = data.get("daily_bounty", DailyBounties.empty_state())
	if not DailyBounties.valid_state(loaded_daily) \
			or int(loaded_daily["day"]) > DailyBounties.utc_day():
		return false
	# Old version-one characters predate renown and begin at rank zero.
	var loaded_renown: Variant = data.get("renown", 0)
	if not Reputation.valid_points(loaded_renown):
		return false

	# Characters saved before the skill tree start with a blank sheet. A sheet that is present must be consistent.
	var loaded_skills = Skills.new()
	if data.has("skills") and not loaded_skills.load_dict(data["skills"]):
		return false

	# One commit point: a failed parse cannot partially replace the player's
	# inventory, protected stash, progression or survival state.
	player.progression = loaded_progression
	player.skills = loaded_skills
	player.dirty_skills = true
	player.contract_state = (loaded_contracts as Dictionary).duplicate(true)
	player.daily_bounty = (loaded_daily as Dictionary).duplicate(true)
	player.renown = int(loaded_renown)
	player.pvp_infamy = float(data.get("pvp_infamy", 0.0))
	player.pvp_kills = int(data.get("pvp_kills", 0))
	player.pvp_honor = int(data.get("pvp_honor", 0))
	player.rest_cooldown = float(data.get("rest_cooldown", 0.0))
	player.lake_drink_cooldown = float(data.get("lake_drink_cooldown", 0.0))
	player.stim_cooldown = float(data.get("stim_cooldown", 0.0))
	player.meal_seconds = float(data.get("meal_seconds", 0.0))
	player.meal_tier = int(data.get("meal_tier", 0))
	player.inventory = parsed_bag["inventory"]
	player.stash = parsed_stash["inventory"]
	player.kills = int(data.get("kills", 0))
	player.deaths = int(data.get("deaths", 0))
	player.survival = survival
	_apply_skill_bonuses(player)
	survival.health = minf(survival.health, survival.max_health)
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


## Call before building a logout save. A live player disconnecting while
## PvP-tagged in a full-loot zone drops equipment once, then respawns safely.
## This applies to voluntary exits and network loss alike. Safes and PvE are
## exempt; stash and character progression are never dropped.
func prepare_disconnect(peer_id: int) -> bool:
	var player: Player = players.get(peer_id)
	if player == null:
		return false
	var zone: int = world.zone_at(player.position.x, player.position.z) if player.position.is_finite() else -1
	if not CombatLogout.penalize_on_disconnect(player, zone, time):
		return false
	player.combat_tag_until = 0.0 # Idempotent even if remove_player runs later.
	# The same confirmed full-loot death path handles the drops, persistence
	# flags, equipped gear, respawn starter kit and active trades.
	player.survival.hurt(player.survival.health)
	_on_player_death(player, -1)
	_spawn_player(player)
	return true


func remove_player(peer_id: int) -> void:
	_abort_training(peer_id, "disconnected")
	training_invite_last.erase(peer_id)
	# Direct server removals must obey the same rule as authenticated Net.leave.
	prepare_disconnect(peer_id)
	# Prevent a recycled peer ID inheriting another survivor's guilt.
	for survivor in players.values():
		if survivor.defense_target == peer_id:
			survivor.defense_target = -1
			survivor.defense_until = 0.0
	market_buy_requests.erase(peer_id)
	outpost_fortify_requests.erase(peer_id)
	outpost_breach_requests.erase(peer_id)
	siege_declare_requests.erase(peer_id)
	_cancel_market_seller(peer_id)
	_cancel_player_trade(peer_id, "disconnected")
	parties.disconnect_peer(peer_id)
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
	_apply_skill_bonuses(player)
	player.survival.reset()
	player.defense_target = -1
	player.defense_until = 0.0
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
	player.party_aid_timer = 0.0
	player.feast_timer = 0.0
	player.guardian_timer = 0.0
	player.guardian_brace = 0.0
	player.meal_seconds = 0.0
	player.meal_tier = 0
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
		var factor: float = player.inventory.movement_factor(player.skills.bonus("carry_capacity"))
		var moving := move_x * move_x + move_z * move_z > 0.00001
		var sprint_allowed: bool = sprint and moving and factor >= 0.9999 and player.survival.try_sprint(allowed)
		player.position = Movement.step(world, player.position, {
			"x": move_x, "z": move_z, "sprint": sprint_allowed,
			"cargo_factor": factor, "speed_bonus": player.skills.bonus("move_speed"),
		}, allowed)
		var moved: float = Vector2(player.position.x - before_move.x, player.position.z - before_move.z).length()
		# Distance on foot trains athletics (running) and explorer (any travel); never more than the
		# server itself moved the player.
		if moved > 0.0:
			player.travel_meters += moved
			while player.travel_meters >= SKILL_METERS_PER_EXPLORER_XP:
				player.travel_meters -= SKILL_METERS_PER_EXPLORER_XP
				_award(player, "explorer", 1.0)
			if sprint_allowed:
				player.run_meters += moved
				while player.run_meters >= SKILL_METERS_PER_ATHLETICS_XP:
					player.run_meters -= SKILL_METERS_PER_ATHLETICS_XP
					_award(player, "athletics", 1.0)
		if sprint_allowed and player.position.distance_to(before_move) > 0.01:
			player.noise_radius = maxf(player.noise_radius, Defs.SPRINT_NOISE_RADIUS)
			player.noise_timer = maxf(player.noise_timer, Defs.SPRINT_NOISE_SECONDS)
		# Walking away cancels gathering and shoreline fishing.
		if not player.action.is_empty():
			if player.action.has("fish"):
				var cast_at := Vector2(float(player.action["cast_x"]), float(player.action["cast_z"]))
				if Vector2(player.position.x, player.position.z).distance_to(cast_at) > 0.45:
					player.action = {}
			else:
				var node := _find_node(int(player.action["node"]))
				if node.is_empty() or _distance_xz(player.position, node) > Defs.REACH + 0.8:
					player.action = {}


## Fishing is a delayed, cancelable server action; no catch count is supplied
## by clients. Distinct from lake drinking and free berry scavenging.
func cmd_fish(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if not player.action.is_empty():
		return {"ok": false, "reason": "busy"}
	if time < player.fish_next_at:
		return {"ok": false, "reason": "cooldown"}
	var eligibility: Dictionary = Fishing.validate_start(world, player.position,
		player.inventory, player.progression.gathering_level("fishing"))
	if not bool(eligibility.get("ok", false)):
		return eligibility
	player.action = {"fish": true, "cast_x": player.position.x, "cast_z": player.position.z,
		"tier": int(eligibility["tier"]), "catch_id": str(eligibility["item"]),
		"remaining": Fishing.CAST_SECONDS, "total": Fishing.CAST_SECONDS}
	player.fish_next_at = time + Fishing.CAST_SECONDS + Fishing.COOLDOWN_SECONDS
	return {"ok": true, "seconds": Fishing.CAST_SECONDS,
		"tier": int(eligibility["tier"]), "item": str(eligibility["item"])}


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
	var gather_skill := Skills.skill_for_node(String(node["kind"]))
	if gather_skill != "":
		speed *= 1.0 + player.skills.bonus("gather_speed." + gather_skill)
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
	var at_fire: bool = String(recipe["station"]) == "campfire" and FieldCampfire.has_warmth(
			campfires, player.position, time)
	var status: int = Crafting.craft(player.inventory, recipe_id, at_bench, times, at_fire)
	if status == Crafting.Result.OK:
		player.progression.award_craft(recipe_tier, times)
		_award(player, "crafting", 8.0 * float(recipe_tier) * float(times))
		# Skill: each batch may save a unit of one of its materials.
		var input_ids: Array = recipe["inputs"].keys()
		for batch in times:
			if not input_ids.is_empty() and rng.randf() < player.skills.bonus("craft_refund"):
				player.inventory.add(String(input_ids[rng.randi() % input_ids.size()]), 1)
		player.dirty_inventory = true
		player.dirty_character = true
		return {"ok": true}
	return {"ok": false, "reason": ["ok", "unknown_recipe", "missing_inputs", "no_station", "no_space"][status]}


# --- Cooperative survivor parties (classic MMO-style group play) -----------------------
## Invite only a real nearby player. All membership and leadership is
## session-owned; no client supplies a party ID or its member list.

## Mutual, proximity-checked hub sparring: no loot, crimes or PvP rewards.
func cmd_duel_invite(peer_id: int, target_id: int) -> Dictionary:
	var source: Player = players.get(peer_id)
	var target: Player = players.get(target_id)
	var denial: String = TrainingDuel.invitation_reason(world, source, target, time)
	if denial != "":
		return {"ok": false, "reason": denial}
	if training_matches.has(peer_id) or training_matches.has(target_id):
		return {"ok": false, "reason": "already_dueling"}
	if time < float(training_invite_last.get(peer_id, -INF)) + TrainingDuel.INVITE_COOLDOWN:
		return {"ok": false, "reason": "cooldown"}
	if training_invites.has(target_id) and float(training_invites[target_id].get("until", 0.0)) > time:
		return {"ok": false, "reason": "invite_pending"}
	training_invite_last[peer_id] = time
	training_invites[target_id] = {"from": peer_id,
		"until": time + TrainingDuel.INVITE_SECONDS,
		"from_instance": source.get_instance_id(), "to_instance": target.get_instance_id()}
	events.append({"type": "duel", "peer": target_id, "phase": "invited",
		"name": source.name, "by": peer_id})
	return {"ok": true, "phase": "invited"}


func cmd_duel_accept(peer_id: int) -> Dictionary:
	var invite: Dictionary = training_invites.get(peer_id, {})
	if invite.is_empty() or float(invite.get("until", 0.0)) <= time:
		training_invites.erase(peer_id)
		return {"ok": false, "reason": "no_invite"}
	var first: Player = players.get(int(invite["from"]))
	var second: Player = players.get(peer_id)
	if first == null or second == null or first.get_instance_id() != int(invite["from_instance"]) or \
			second.get_instance_id() != int(invite["to_instance"]):
		training_invites.erase(peer_id)
		return {"ok": false, "reason": "stale_invite"}
	var denial: String = TrainingDuel.invitation_reason(world, first, second, time)
	if denial != "" or training_matches.has(first.id) or training_matches.has(second.id):
		training_invites.erase(peer_id)
		return {"ok": false, "reason": denial if denial != "" else "already_dueling"}
	training_invites.erase(peer_id)
	var duel: Dictionary = {"a": first.id, "b": second.id,
		"until": time + TrainingDuel.MATCH_SECONDS,
		"a_hp": first.survival.health, "b_hp": second.survival.health}
	training_matches[first.id] = duel
	training_matches[second.id] = duel
	for member in [first, second]:
		events.append({"type": "duel", "peer": member.id, "phase": "started",
			"opponent": second.name if member.id == first.id else first.name,
			"seconds": TrainingDuel.MATCH_SECONDS})
	return {"ok": true, "phase": "started"}


func cmd_duel_cancel(peer_id: int) -> Dictionary:
	if training_matches.has(peer_id):
		_end_training(peer_id, -1, "cancelled")
		return {"ok": true, "phase": "cancelled"}
	if training_invites.has(peer_id):
		training_invites.erase(peer_id)
		return {"ok": true, "phase": "declined"}
	var found: bool = false
	for target_id in training_invites.keys():
		if int(training_invites[target_id].get("from", -1)) == peer_id:
			training_invites.erase(target_id)
			found = true
	return {"ok": found, "reason": "" if found else "no_duel"}


func _end_training(peer_id: int, winner_id: int, reason: String) -> void:
	var duel: Dictionary = training_matches.get(peer_id, {})
	if duel.is_empty():
		return
	var a: int = int(duel["a"])
	var b: int = int(duel["b"])
	training_matches.erase(a)
	training_matches.erase(b)
	for member_id in [a, b]:
		var member: Player = players.get(member_id)
		if member == null:
			continue
		if _alive(member):
			var initial: float = float(duel["a_hp"] if member_id == a else duel["b_hp"])
			member.survival.health = maxf(member.survival.health, initial)
		events.append({"type": "duel", "peer": member_id, "phase": "finished",
			"winner": winner_id, "reason": reason})


func _abort_training(peer_id: int, reason: String) -> void:
	_end_training(peer_id, -1, reason)
	training_invites.erase(peer_id)
	for target_id in training_invites.keys():
		if int(training_invites[target_id].get("from", -1)) == peer_id:
			training_invites.erase(target_id)


func _tick_training() -> void:
	for peer_id in training_matches.keys():
		var duel: Dictionary = training_matches.get(peer_id, {})
		if duel.is_empty() or int(duel["a"]) != int(peer_id):
			continue
		var first: Player = players.get(int(duel["a"]))
		var second: Player = players.get(int(duel["b"]))
		if not TrainingDuel.active_for(training_matches, world, first, second, time):
			_end_training(int(peer_id), -1, "expired_or_left_hub")
	for peer_id in training_invites.keys():
		if float(training_invites[peer_id]["until"]) <= time:
			training_invites.erase(peer_id)


func _training_snapshot(peer_id: int) -> Dictionary:
	var match_data: Dictionary = training_matches.get(peer_id, {})
	if not match_data.is_empty():
		return {"active": true,
			"opponent": int(match_data["b"]) if peer_id == int(match_data["a"]) else int(match_data["a"]),
			"seconds": maxf(0.0, float(match_data["until"]) - time)}
	var invite: Dictionary = training_invites.get(peer_id, {})
	if not invite.is_empty() and float(invite["until"]) > time:
		return {"active": false, "invite_from": int(invite["from"]),
			"seconds": float(invite["until"]) - time}
	return {}


func cmd_party_invite(peer_id: int, target_id: int) -> Dictionary:
	var source: Player = players.get(peer_id)
	var target: Player = players.get(target_id)
	if source == null or target == null or not _alive(source) or not _alive(target):
		return {"ok": false, "reason": "unavailable"}
	if not _party_invite_in_range(source, target):
		return {"ok": false, "reason": "too_far"}
	return parties.invite(peer_id, target_id, time)


func _party_invite_in_range(first: Player, second: Player) -> bool:
	var a := Vector2(first.position.x, first.position.z)
	var b := Vector2(second.position.x, second.position.z)
	return a.is_finite() and b.is_finite() and a.distance_to(b) <= Party.INVITE_RANGE


func cmd_party_accept(peer_id: int) -> Dictionary:
	var target: Player = players.get(peer_id)
	if target == null or not _alive(target):
		return {"ok": false, "reason": "dead"}
	var invite: Dictionary = parties.invites.get(peer_id, {})
	if invite.is_empty():
		return {"ok": false, "reason": "no_invite"}
	if time >= float(invite["expires"]):
		return parties.accept(peer_id, time)
	var leader: Player = players.get(int(invite["from"]))
	if leader == null or not _alive(leader):
		return {"ok": false, "reason": "leader_offline"}
	if not _party_invite_in_range(leader, target):
		return {"ok": false, "reason": "too_far"}
	return parties.accept(peer_id, time)


func cmd_party_decline(peer_id: int) -> Dictionary:
	return parties.decline(peer_id)


func cmd_party_leave(peer_id: int) -> Dictionary:
	return parties.leave(peer_id)


func cmd_party_kick(peer_id: int, target_id: int) -> Dictionary:
	return parties.kick(peer_id, target_id)


## Item-powered cooperative healing, resolved only by the authoritative server.
func cmd_party_aid(peer_id: int, target_id: int, item_id: String) -> Dictionary:
	var source: Player = players.get(peer_id)
	var recipient: Player = players.get(target_id)
	if source == null or not _alive(source):
		return {"ok": false, "reason": "dead"}
	if peer_id == target_id:
		return {"ok": false, "reason": "self"}
	if recipient == null:
		return {"ok": false, "reason": "invalid_target"}
	if not _alive(recipient):
		return {"ok": false, "reason": "dead"}
	var group: int = parties.group_of(peer_id)
	if group == 0 or parties.group_of(target_id) != group:
		return {"ok": false, "reason": "not_in_party"}
	if not PartyAid.can_reach(source.position, recipient.position):
		return {"ok": false, "reason": "too_far"}
	if source.party_aid_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	var data: Dictionary = Defs.item(item_id)
	if str(data.get("kind", "")) != "medical":
		return {"ok": false, "reason": "not_medical"}
	if source.inventory.count(item_id) < 1:
		return {"ok": false, "reason": "not_carried"}
	if not PartyAid.has_effect(data, recipient.survival.health, recipient.survival.infection, recipient.survival.bleeding):
		return {"ok": false, "reason": "no_effect"}
	var hp_before: float = recipient.survival.health
	var infection_before: float = recipient.survival.infection
	var bleeding_before: float = recipient.survival.bleeding
	if not source.inventory.remove(item_id, 1):
		return {"ok": false, "reason": "not_carried"}
	recipient.survival.heal(float(data.get("heal", 0.0)))
	recipient.survival.treat_infection(float(data.get("cure", 0.0)))
	if bool(data.get("stop_bleeding", false)):
		recipient.survival.stop_bleeding()
	source.party_aid_timer = PartyAid.COOLDOWN
	source.action = {}
	source.dirty_inventory = true
	source.dirty_character = true
	recipient.dirty_character = true
	var healed: float = recipient.survival.health - hp_before
	var cured: float = infection_before - recipient.survival.infection
	var staunched: float = bleeding_before - recipient.survival.bleeding
	events.append({"type": "party_aid", "peer": target_id, "by": peer_id,
		"item": item_id, "heal": healed, "cure": cured,
		"bleeding_stopped": staunched})
	return {"ok": true, "peer": target_id, "item": item_id,
		"heal": healed, "cure": cured, "bleeding_stopped": staunched}


## Expedition support: one real cooked fish per eligible party member.
## The client only picks a recipe, not recipient count, fire or bonus strength.
func cmd_party_feast(peer_id: int, item_id: String) -> Dictionary:
	var source: Player = players.get(peer_id)
	if source == null or not _alive(source):
		return {"ok": false, "reason": "dead"}
	if source.feast_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	var group: Array = parties.members_of(peer_id)
	if group.size() < 2:
		return {"ok": false, "reason": "not_in_party"}
	var tier: int = PartyFeast.food_tier(item_id)
	if tier <= 0:
		return {"ok": false, "reason": "not_prepared_food"}
	var fire: Dictionary = PartyFeast.camp_for(campfires, source.position, time)
	if fire.is_empty():
		return {"ok": false, "reason": "no_fire"}
	var recipients: Array = []
	for member_id in group:
		var member: Player = players.get(int(member_id))
		if member == null or not _alive(member):
			continue
		if not PartyFeast.near_fire(fire, member.position, time):
			continue
		# A low-tier feast must never overwrite a more powerful meal.
		if member.meal_seconds > 0.0 and member.meal_tier > tier:
			continue
		recipients.append(member)
	if recipients.size() < 2:
		return {"ok": false, "reason": "no_companions"}
	var portions: int = recipients.size()
	if source.inventory.count(item_id) < portions:
		return {"ok": false, "reason": "need_food", "portions": portions}
	# This removal is atomic: no teammate is changed on any failed attempt.
	if not source.inventory.remove(item_id, portions):
		return {"ok": false, "reason": "need_food", "portions": portions}
	var seconds: float = HeartyMeal.duration(tier)
	for member in recipients:
		member.survival.eat(float(Defs.item(item_id).get("food", 0.0)) *
			(1.0 + member.skills.bonus("food_power")))
		member.meal_tier = tier
		member.meal_seconds = seconds
		member.dirty_character = true
		events.append({"type": "party_feast", "peer": member.id, "by": peer_id,
			"tier": tier, "seconds": seconds})
	source.feast_timer = PartyFeast.COOLDOWN
	source.action = {}
	source.dirty_inventory = true
	source.dirty_character = true
	return {"ok": true, "served": portions, "tier": tier, "seconds": seconds}


func cmd_party_rally(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	# Position comes from the authoritative player model, not any RPC argument.
	return parties.mark_rally(peer_id, player.position, time)


func _party_state_for(peer_id: int) -> Dictionary:
	var state: Dictionary = parties.state_for(peer_id, time)
	var roster: Array = []
	for id in state["members"]:
		var member: Player = players.get(id)
		if member != null:
			roster.append({"id": int(id), "name": member.name,
				"alive": _alive(member), "health": member.survival.health})
	state["roster"] = roster
	var invite_from: int = int(state["invite_from"])
	var sender: Player = players.get(invite_from)
	state["invite_name"] = sender.name if sender != null else ""
	return state


# --- Outpost fortification: server-authoritative supplies for siege defense. ----------
# Every client command includes a monotonic request ID so an ambiguous response
# cannot cause the same upgrade to spend the player's resources twice.
func cmd_outpost_fortify(peer_id: int, site_id: int, request_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	if request_id < 1 or request_id > FORTIFY_MAX_REQUEST_ID:
		return {"ok": false, "reason": "invalid_request_id"}
	var last: Dictionary = outpost_fortify_requests.get(peer_id, {})
	if not last.is_empty():
		if request_id < int(last["id"]):
			return {"ok": false, "reason": "stale_request"}
		if request_id == int(last["id"]):
			if site_id != int(last["site"]):
				return {"ok": false, "reason": "request_conflict"}
			return (last["result"] as Dictionary).duplicate(true)
	var outcome: Dictionary = _execute_outpost_fortify(peer_id, site_id)
	outcome["request_id"] = request_id
	outpost_fortify_requests[peer_id] = {
		"id": request_id, "site": site_id, "result": outcome.duplicate(true),
	}
	return outcome


func _execute_outpost_fortify(peer_id: int, site_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var site: Dictionary = territory.site_by_id(site_id)
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	var group_id: int = parties.group_of(peer_id)
	var rival_present: bool = territory.contested_by_rivals(site, group_id, players, parties)
	var result: Dictionary = OutpostFortification.fortify(
		site, player.inventory, group_id, player.position, time, rival_present)
	if result.get("ok", false):
		player.dirty_inventory = true
		player.dirty_character = true
		events.append({
			"type": "outpost_fortified", "id": site_id, "level": result["level"],
			"x": site["x"], "z": site["z"], "owner": group_id,
		})
	return result


# --- Siege breaches. A hostile party can spend crafted T2 materials to
# dismantle defensive tiers, countering the permanent defender time bonus.
# Request IDs are monotonic per peer and never accepted twice with new terms.
func cmd_outpost_breach(peer_id: int, site_id: int, request_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	if request_id < 1 or request_id > BREACH_MAX_REQUEST_ID:
		return {"ok": false, "reason": "invalid_request_id"}
	var last: Dictionary = outpost_breach_requests.get(peer_id, {})
	if not last.is_empty():
		if request_id < int(last["id"]):
			return {"ok": false, "reason": "stale_request"}
		if request_id == int(last["id"]):
			if site_id != int(last["site"]):
				return {"ok": false, "reason": "request_conflict"}
			return (last["result"] as Dictionary).duplicate(true)
	var result: Dictionary = _execute_outpost_breach(peer_id, site_id)
	result["request_id"] = request_id
	outpost_breach_requests[peer_id] = {
		"id": request_id, "site": site_id, "result": result.duplicate(true),
	}
	return result


func _execute_outpost_breach(peer_id: int, site_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var site: Dictionary = territory.site_by_id(site_id)
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	if GuildTerritory.same_owner_guild(site, player, players, parties):
		return {"ok": false, "reason": "guild_ally"}
	var attacker_group: int = parties.group_of(peer_id)
	var occupied: Dictionary = territory._occupied_groups(site, players, parties)
	var ally_count: int = int(occupied.get(attacker_group, 0)) if attacker_group > 0 else 0
	var result: Dictionary = OutpostBreach.breach(
		site, player.inventory, attacker_group, player.position, ally_count, time)
	if result.get("ok", false):
		player.dirty_inventory = true
		player.dirty_character = true
		events.append({
			"type": "outpost_breached", "id": site_id, "level": result["level"],
			"x": site["x"], "z": site["z"], "by_group": attacker_group,
		})
	return result


# --- Siege declarations: leadership, preparation and scored territory captures. ---
# Parties remain session-based until authenticated Nakama clan membership exists.
func cmd_siege_declare(peer_id: int, site_id: int, request_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	if request_id < 1 or request_id > SIEGE_DECLARE_MAX_REQUEST_ID:
		return {"ok": false, "reason": "invalid_request_id"}
	var last: Dictionary = siege_declare_requests.get(peer_id, {})
	if not last.is_empty():
		if request_id < int(last["id"]):
			return {"ok": false, "reason": "stale_request"}
		if request_id == int(last["id"]):
			if site_id != int(last["site"]):
				return {"ok": false, "reason": "request_conflict"}
			return (last["result"] as Dictionary).duplicate(true)
	var outcome: Dictionary = _execute_siege_declare(peer_id, site_id)
	outcome["request_id"] = request_id
	siege_declare_requests[peer_id] = {
		"id": request_id, "site": site_id, "result": outcome.duplicate(true),
	}
	return outcome


func _execute_siege_declare(peer_id: int, site_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var site: Dictionary = territory.site_by_id(site_id)
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	if GuildTerritory.same_owner_guild(site, player, players, parties):
		return {"ok": false, "reason": "guild_ally"}
	var group_id: int = parties.group_of(peer_id)
	var is_leader: bool = group_id > 0 and parties.groups.has(group_id) \
		and int(parties.groups[group_id]["leader"]) == peer_id
	var allies_near := 0
	if group_id > 0:
		var point := Vector2(float(site["x"]), float(site["z"]))
		for member_id in parties.members_of(peer_id):
			var ally: Player = players.get(member_id)
			if ally != null and _alive(ally) and ally.position.is_finite() and \
					Vector2(ally.position.x, ally.position.z).distance_squared_to(point) <= \
					SiegeContracts.DECLARE_RADIUS * SiegeContracts.DECLARE_RADIUS:
				allies_near += 1
	var result: Dictionary = siege_contracts.declare(
		site, player.inventory, player.position, group_id, is_leader, allies_near, time)
	if result.get("ok", false):
		player.dirty_inventory = true
		player.dirty_character = true
		events.append({
			"type": "siege_contract_declared", "site": site_id,
			"x": site["x"], "z": site["z"],
			"attacker": group_id, "defender": site["owner"],
		})
	return result


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


# --- Player market board: online-only listings with execution-time inventory checks. ---
# Posting a listing does NOT debit goods. A new durable backend journal is
# required before adding offline listings or player escrow.

func _market_at_hub(player: Player) -> bool:
	if player == null or not _alive(player):
		return false
	var spot := Vector2(player.position.x, player.position.z)
	return spot.is_finite() and _is_safe(player.position) \
		and spot.distance_to(WORKBENCH_POSITION) <= WORKBENCH_RANGE


func _cancel_market_seller(peer_id: int) -> void:
	for listing_id in market_orders.keys():
		if int(market_orders[listing_id]["seller"]) == peer_id:
			market_orders.erase(listing_id)


func _tick_market() -> void:
	for listing_id in market_orders.keys():
		var listing: Dictionary = market_orders[listing_id]
		var seller: Player = players.get(int(listing["seller"]))
		if seller == null or not _market_at_hub(seller) \
				or time >= float(listing["expires"]) \
				or seller.inventory.count(str(listing["item"])) < int(listing["remaining"]):
			market_orders.erase(listing_id)


func cmd_market_list(peer_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	var public_orders: Array = []
	var sorted_ids: Array = market_orders.keys()
	sorted_ids.sort()
	for listing_id in sorted_ids:
		var order: Dictionary = market_orders[listing_id]
		var seller: Player = players.get(int(order["seller"]))
		if seller == null or not _market_at_hub(seller) or seller.inventory.count(str(order["item"])) < int(order["remaining"]):
			continue
		public_orders.append({
			"id": listing_id, "item": order["item"], "quantity": order["remaining"],
			"price": order["price"], "seller_name": seller.name,
			"own": seller.id == peer_id,
		})
	return {"ok": true, "action": "list", "orders": public_orders}


func cmd_market_create(peer_id: int, item_id: String, quantity: int, unit_price: int) -> Dictionary:
	var seller: Player = players.get(peer_id)
	if not _market_at_hub(seller):
		return {"ok": false, "reason": "no_station"}
	var validation: String = MarketBoard.validate_listing(seller.inventory, item_id, quantity, unit_price)
	if validation != "":
		return {"ok": false, "reason": validation}
	if market_orders.size() >= MarketBoard.MAX_LISTINGS:
		return {"ok": false, "reason": "market_full"}
	var count := 0
	for order in market_orders.values():
		if int(order["seller"]) == peer_id:
			count += 1
	if count >= MarketBoard.MAX_PER_SELLER:
		return {"ok": false, "reason": "too_many_listings"}
	var listing_id: int = new_id()
	market_orders[listing_id] = {
		"seller": peer_id, "item": item_id, "remaining": quantity,
		"price": unit_price, "expires": time + MarketBoard.LISTING_LIFETIME,
	}
	return {"ok": true, "action": "created", "id": listing_id}


func cmd_market_cancel(peer_id: int, listing_id: int) -> Dictionary:
	var order: Dictionary = market_orders.get(listing_id, {})
	if order.is_empty():
		return {"ok": false, "reason": "unknown_listing"}
	if int(order["seller"]) != peer_id:
		return {"ok": false, "reason": "not_owner"}
	market_orders.erase(listing_id)
	return {"ok": true, "action": "cancelled", "id": listing_id}


## A market purchase must have a monotonically increasing, session-scoped request ID.
## A retry returns the original result, never a second transfer, even after a partial fill.
## Old IDs are refused rather than evicted and potentially executed a second time.
func cmd_market_buy(peer_id: int, listing_id: int, quantity: int, request_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	if request_id < 1 or request_id > MARKET_MAX_REQUEST_ID:
		return {"ok": false, "reason": "invalid_request_id"}
	var last: Dictionary = market_buy_requests.get(peer_id, {})
	if not last.is_empty():
		var used_id: int = int(last["id"])
		if request_id < used_id:
			return {"ok": false, "reason": "stale_request"}
		if request_id == used_id:
			if int(last["listing"]) != listing_id or int(last["quantity"]) != quantity:
				return {"ok": false, "reason": "request_conflict"}
			var cached: Dictionary = last["result"]
			return cached.duplicate(true)
	var result: Dictionary = _execute_market_buy(peer_id, listing_id, quantity)
	result["request_id"] = request_id
	market_buy_requests[peer_id] = {
		"id": request_id, "listing": listing_id, "quantity": quantity,
		"result": result.duplicate(true),
	}
	return result


func _execute_market_buy(peer_id: int, listing_id: int, quantity: int) -> Dictionary:
	var buyer: Player = players.get(peer_id)
	if not _market_at_hub(buyer):
		return {"ok": false, "reason": "no_station"}
	var listing: Dictionary = market_orders.get(listing_id, {})
	if listing.is_empty():
		return {"ok": false, "reason": "unknown_listing"}
	var seller_id: int = int(listing["seller"])
	var seller: Player = players.get(seller_id)
	if peer_id == seller_id:
		return {"ok": false, "reason": "self_purchase"}
	if seller == null or not _market_at_hub(seller) or time >= float(listing["expires"]):
		market_orders.erase(listing_id)
		return {"ok": false, "reason": "seller_unavailable"}
	# Synchronous on this server's simulation thread; no yield between the
	# balance checks and the two-inventory commit.
	var transaction: Dictionary = MarketBoard.purchase(buyer.inventory, seller.inventory, listing, quantity)
	if not transaction.get("ok", false):
		return transaction
	listing["remaining"] = int(listing["remaining"]) - quantity
	if int(listing["remaining"]) == 0:
		market_orders.erase(listing_id)
	for player in [buyer, seller]:
		player.dirty_inventory = true
		player.dirty_character = true
	var receipt_id: int = new_id()
	market_sales.append({
		"id": receipt_id, "buyer": peer_id, "seller": seller_id,
		"listing": listing_id, "item": listing["item"],
		"quantity": quantity, "total": transaction["total"],
	})
	if market_sales.size() > 128:
		market_sales.pop_front()
	return {
		"ok": true, "action": "bought", "id": listing_id,
		"receipt": receipt_id, "quantity": quantity,
		"item": listing["item"], "total": transaction["total"],
	}


## The safe-hub vendor uses server position and inventory only.
## A rejected trade leaves every item and silver balance unchanged.
func cmd_vendor(peer_id: int, item_id: String, quantity: int, buy: bool) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var location := Vector2(player.position.x, player.position.z)
	if not location.is_finite() or location.distance_to(WORKBENCH_POSITION) > WORKBENCH_RANGE:
		return {"ok": false, "reason": "no_station"}
	var outcome: Dictionary = Vendor.transact(player.inventory, item_id, quantity, buy,
		player.renown, player.pvp_infamy)
	if outcome.get("ok", false):
		player.dirty_inventory = true
		player.dirty_character = true
	return outcome


## Captured frontier outpost supplies: authenticated server-owned ownership,
## exact on-site position, live enemy contest, one account claim per capture.
## No client may specify the reward, party, token, or cache contents.
func cmd_outpost_supplies(peer_id: int, site_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var result: Dictionary = territory.claim_supplies(site_id, player,
		players, parties, world, time)
	if bool(result.get("ok", false)):
		player.dirty_inventory = true
		player.dirty_character = true
	return result


## Only confirmed server events award reputation; no client RPC can submit
## an arbitrary score, rank or vendor discount.
func _earn_renown(player: Player, points: int, source: String) -> void:
	var previous: int = player.renown
	player.renown = Reputation.apply_earned(previous, points)
	if player.renown == previous:
		return
	player.dirty_character = true
	events.append({"type": "renown", "peer": player.id,
		"earned": player.renown - previous,
		"total": player.renown,
		"rank": Reputation.title(player.renown),
		"source": source})


## Camp contracts use the same real hub distance check as the vendor and bank.
## The only client input is accept/claim, never rewards, progress or prices.
## Camp recovery is an authoritative, resource-paid sanctuary action.
## Recent combat and noise lockouts prevent instant healing during danger.
func cmd_rest(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var point := Vector2(player.position.x, player.position.z)
	if not point.is_finite():
		return {"ok": false, "reason": "no_station"}
	var at_hub: bool = _is_safe(player.position) and point.distance_to(WORKBENCH_POSITION) <= WORKBENCH_RANGE
	var at_fire: bool = not at_hub and FieldCampfire.has_warmth(campfires, player.position, time)
	if not at_hub and not at_fire:
		return {"ok": false, "reason": "no_station"}
	if player.rest_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.rest_cooldown}
	if player.attack_timer > 0.0 or player.skill_timer > 0.0 or player.noise_timer > 0.0:
		return {"ok": false, "reason": "in_combat"}
	if not CampRest.needs_recovery(player.survival):
		return {"ok": false, "reason": "fully_rested"}
	if at_fire:
		var threat: String = FieldRest.danger(world, player, players, parties, zombies)
		if not threat.is_empty():
			return {"ok": false, "reason": threat}
		if not FieldRest.has_supplies(player.inventory):
			return {"ok": false, "reason": "missing_items"}
		if not FieldRest.recover(player.inventory, player.survival):
			return {"ok": false, "reason": "transaction_failed"}
	else:
		if not CampRest.has_supplies(player.inventory):
			return {"ok": false, "reason": "missing_items"}
		if not CampRest.recover(player.inventory, player.survival):
			return {"ok": false, "reason": "transaction_failed"}
	player.rest_cooldown = CampRest.COOLDOWN
	player.action = {}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "rested": true, "field": at_fire,
		"cooldown": player.rest_cooldown,
		"health": player.survival.health, "stamina": player.survival.stamina}

## Roll forward once at midnight UTC, persisting a fresh daily journal.
## A backwards-moving host clock cannot revive a previously claimed day.
func _refresh_daily(player: Player) -> int:
	var today: int = DailyBounties.utc_day()
	if DailyBounties.refresh(player.daily_bounty, today):
		player.dirty_character = true
	return today


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
		"daily_claim":
			var today: int = _refresh_daily(player)
			result = DailyBounties.claim(player.inventory, player.daily_bounty, today)
		_: return {"ok": false, "reason": "unknown_action"}
	if bool(result.get("ok", false)):
		player.dirty_character = true
		if action == "claim":
			player.dirty_inventory = true
			_earn_renown(player, Reputation.CONTRACT_RENOWN, "contract")
		elif action == "daily_claim":
			player.dirty_inventory = true
			_earn_renown(player, int(result.get("renown", 0)), "daily_bounty")
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
## The client requests coordinates, but cannot claim warmth, time or a free
## fire. All placement and inventory costs are validated by the server.
## The client supplies a direction, not the position, price or affected NPCs.
## Cost and flight-path validation happen atomically on this simulation.
func cmd_throw_decoy(peer_id: int, direction_x: float, direction_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.decoy_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	if decoys.size() >= NoiseDecoy.MAX_ACTIVE:
		return {"ok": false, "reason": "world_limit"}
	var owned: int = 0
	for lure in decoys.values():
		if int(lure["owner"]) == peer_id and float(lure["expires"]) > time:
			owned += 1
	if owned >= NoiseDecoy.MAX_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	var site: Dictionary = NoiseDecoy.landing(world, player.position,
			Vector2(direction_x, direction_z))
	if site.is_empty():
		return {"ok": false, "reason": "invalid_landing"}
	if player.inventory.count(NoiseDecoy.ITEM_ID) < 1:
		return {"ok": false, "reason": "not_carried"}
	if not player.inventory.remove(NoiseDecoy.ITEM_ID, 1):
		return {"ok": false, "reason": "not_carried"}
	var id: int = new_id()
	decoys[id] = {"id": id, "x": site["x"], "y": site["y"], "z": site["z"],
		"owner": peer_id, "expires": time + NoiseDecoy.DURATION}
	player.decoy_timer = NoiseDecoy.COOLDOWN
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "decoy_thrown", "peer": peer_id,
		"x": site["x"], "z": site["z"]})
	return {"ok": true, "id": id, "seconds": NoiseDecoy.DURATION}


func cmd_light_campfire(peer_id: int, x: float, z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if campfires.size() >= FieldCampfire.MAX_GLOBAL:
		return {"ok": false, "reason": "world_limit"}
	var owned := 0
	for fire in campfires.values():
		if Structures.can_manage(fire, peer_id, player.user_id):
			owned += 1
	if owned >= FieldCampfire.MAX_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	var position := Vector2(x, z)
	var origin := Vector2(player.position.x, player.position.z)
	var reason: String = FieldCampfire.valid_site(world, position, origin, campfires)
	if reason != "":
		return {"ok": false, "reason": reason}
	for other in players.values():
		if _alive(other) and position.distance_to(Vector2(other.position.x, other.position.z)) < (
				FieldCampfire.CAMP_RADIUS + Defs.PLAYER_RADIUS + 0.15):
			return {"ok": false, "reason": "blocked"}
	for infected in zombies.values():
		if infected.is_alive() and position.distance_to(
				Vector2(infected.position.x, infected.position.z)) < FieldCampfire.CAMP_RADIUS + 0.7:
			return {"ok": false, "reason": "blocked"}
	if not player.inventory.has_all(FieldCampfire.COST):
		return {"ok": false, "reason": "missing_materials"}
	for item_id in FieldCampfire.COST:
		player.inventory.remove(str(item_id), int(FieldCampfire.COST[item_id]))
	var id := new_id()
	campfires[id] = {"id": id, "x": x, "y": world.height_at(x, z), "z": z,
		"owner": peer_id, "owner_account": player.user_id,
		"expires": time + FieldCampfire.DURATION}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "id": id, "seconds": FieldCampfire.DURATION}


## Nearby survivors may cooperatively fuel an existing fire. The server
## validates its deadline and charges the correct backpack before extending it.
## The account/session owner can extinguish an ephemeral campfire early.
## Fuel is already burned and never refunded; strangers cannot delete the
## group's heating by guessing a network entity ID.
func cmd_extinguish_campfire(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var camp: Dictionary = campfires.get(id, {})
	if camp.is_empty() or float(camp["expires"]) <= time:
		return {"ok": false, "reason": "no_fire"}
	if not Structures.can_manage(camp, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	if not Structures.within_range(Vector2(player.position.x, player.position.z),
			Vector2(float(camp["x"]), float(camp["z"])), FieldCampfire.REFUEL_RANGE):
		return {"ok": false, "reason": "out_of_range"}
	campfires.erase(id)
	events.append({"type": "campfire_extinguished", "id": id, "peer": peer_id})
	return {"ok": true, "id": id}


func cmd_refuel_campfire(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var camp: Dictionary = campfires.get(id, {})
	var reason: String = FieldCampfire.refuel_reason(camp, player.position, time)
	if reason != "":
		return {"ok": false, "reason": reason}
	if not player.inventory.has_all(FieldCampfire.REFUEL_COST):
		return {"ok": false, "reason": "missing_materials"}
	for item_id in FieldCampfire.REFUEL_COST:
		player.inventory.remove(str(item_id), int(FieldCampfire.REFUEL_COST[item_id]))
	camp["expires"] = minf(time + FieldCampfire.MAX_REMAINING_SECONDS,
			float(camp["expires"]) + FieldCampfire.REFUEL_SECONDS)
	campfires[id] = camp
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "campfire_refueled", "id": id, "peer": peer_id})
	return {"ok": true, "id": id, "remaining": float(camp["expires"]) - time}


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
	siege_last_by_wall.erase(id)
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
		siege_last_by_wall.erase(id)
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
		"stimulant":
			if item_id != FrontierStim.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var reason: String = FrontierStim.ready(player.survival,
				player.combat_energy, player.stim_cooldown)
			if reason != "":
				return {"ok": false, "reason": reason,
					"remaining": player.stim_cooldown}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.combat_energy = FrontierStim.apply(player.survival, player.combat_energy)
			player.stim_cooldown = FrontierStim.COOLDOWN
		"scent_mask":
			if item_id != FieldScentMask.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if not FieldScentMask.can_apply(player.survival):
				return {"ok": false, "reason": "already_masked"}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			FieldScentMask.apply(player.survival)
		"thermal":
			if not player.survival.apply_thermal_wrap():
				return {"ok": false, "reason": "already_warm"}
			player.inventory.remove(item_id, 1)
		"food":
			var was_hungry: bool = player.survival.hunger <= SKILL_NOURISH_THRESHOLD
			player.inventory.remove(item_id, 1)
			player.survival.eat(float(data["food"]) * (1.0 + player.skills.bonus("food_power")))
			# Prepared coastal meals grant a short, non-stacking recovery bonus.
			# Canned food and berries only restore hunger as before.
			var cooked_tier: int = HeartyMeal.tier_for_food(item_id)
			if cooked_tier > 0:
				player.meal_tier = cooked_tier
				player.meal_seconds = HeartyMeal.duration(cooked_tier)
			if was_hungry: # Stuffing yourself while full teaches nothing.
				_award(player, "survivalist", 3.0)
		"drink":
			var was_thirsty: bool = player.survival.thirst <= SKILL_NOURISH_THRESHOLD
			player.inventory.remove(item_id, 1)
			player.survival.drink(float(data["drink"]) * (1.0 + player.skills.bonus("food_power")))
			if was_thirsty:
				_award(player, "survivalist", 3.0)
		"medical":
			var healing: float = float(data.get("heal", 0.0))
			var curing: float = float(data.get("cure", 0.0))
			var staunch: bool = bool(data.get("stop_bleeding", false))
			if (healing <= 0.0 or player.survival.health >= player.survival.max_health) and (
					curing <= 0.0 or player.survival.infection <= 0.0) and (
					not staunch or player.survival.bleeding <= 0.0):
				return {"ok": false, "reason": "no_effect"}
			player.inventory.remove(item_id, 1)
			player.survival.heal(healing * (1.0 + player.skills.bonus("heal_power")))
			player.survival.treat_infection(curing)
			if staunch:
				player.survival.stop_bleeding()
			_award(player, "medic", 6.0)
		"weapon", "armor":
			player.inventory.equip(item_id)
		_:
			return {"ok": false, "reason": "not_usable"}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true}


## Lake water hydrates but can infect: clean bottles remain a risk-free alternative.
## Filtration is item-paid, never a free client flag; no refill or cure is forged.
func cmd_drink_water(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.lake_drink_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.lake_drink_cooldown}
	if not FieldWater.needs_drink(player.survival):
		return {"ok": false, "reason": "not_thirsty"}
	if not FieldWater.can_access_lake(world, player.position):
		return {"ok": false, "reason": "no_water"}
	var filtered: bool = player.inventory.count(FieldWater.FILTER_ITEM) > 0
	if filtered:
		if not player.inventory.remove(FieldWater.FILTER_ITEM, 1):
			return {"ok": false, "reason": "filter_unavailable"}
		player.dirty_inventory = true
	_award(player, "survivalist", 2.0) # needs_drink() above guarantees the player really was thirsty.
	player.survival.drink(FieldWater.THIRST_RESTORED * (1.0 + player.skills.bonus("food_power")))
	if not filtered:
		player.survival.add_infection(FieldWater.UNTREATED_INFECTION)
	player.lake_drink_cooldown = FieldWater.COOLDOWN_SECONDS
	player.dirty_character = true
	return {"ok": true, "filtered": filtered, "infection": player.survival.infection,
		"cooldown": player.lake_drink_cooldown}


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
	# Dropped/stolen gear must not keep its statistics through a stale slot.
	if weapon != "" and player.inventory.count(weapon) < 1:
		weapon = ""
	var kind: String = Defs.item(weapon).get("weapon", "melee") if weapon != "" else "melee"
	player.attack_timer = Combat.weapon_cooldown(weapon)
	player.action = {} # Fighting interrupts gathering.
	player.yaw = atan2(direction.x, direction.y)
	var origin := Vector2(player.position.x, player.position.z)
	var damage: float = Combat.weapon_damage(weapon)
	# Mastery is server-owned. Missing/ghost equipment grants no bonus.
	if weapon != "" and player.inventory.count(weapon) > 0:
		damage *= player.progression.combat_damage_multiplier(weapon)
	var reach: float = Combat.weapon_reach(weapon)
	if kind == "ranged":
		var ammo: String = Defs.item(weapon).get("ammo", "")
		if player.inventory.count(ammo) < 1:
			player.attack_timer = 0.3
			return {"ok": false, "reason": "no_ammo"}
		if rng.randf() >= player.skills.bonus("ammo_save"):
			player.inventory.remove(ammo, 1)
		player.dirty_inventory = true
		# Arrows are much quieter than firearms, but still attract nearby infected.
		var shot_noise: Dictionary = Combat.ranged_noise(weapon)
		player.noise_radius = maxf(player.noise_radius, float(shot_noise["radius"]))
		player.noise_timer = maxf(player.noise_timer, float(shot_noise["seconds"]))
		reach = Combat.ranged_range(weapon)
	var is_ranged := kind == "ranged"
	damage *= 1.0 + player.skills.bonus("ranged_damage" if is_ranged else "melee_damage")
	var crit: bool = not is_ranged and rng.randf() < float(player.skills.bonus("crit_chance"))
	if crit:
		damage *= 1.5 + player.skills.bonus("crit_damage")
	var hit := _find_hit(player, origin, direction, reach, kind == "ranged")
	events.append({"type": "attack", "peer": peer_id, "dir": direction, "ranged": kind == "ranged", "x": player.position.x, "z": player.position.z})
	if hit.is_empty():
		return {"ok": true, "hit": false}
	_damage_target(player, hit, damage, "ranged" if is_ranged else "melee")
	return {"ok": true, "hit": true, "target": hit["kind"], "crit": crit}


## Party frontline role: no client-authored targets, aggro, radius or damage.
func cmd_guardian_taunt(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if _is_safe(player.position):
		return {"ok": false, "reason": "safe_zone"}
	var allies: Array = parties.members_of(peer_id)
	if allies.size() < 2:
		return {"ok": false, "reason": "not_in_party"}
	if not GuardianTaunt.melee_equipped(player.inventory):
		return {"ok": false, "reason": "need_melee"}
	if player.guardian_timer > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.guardian_timer}
	if player.combat_energy < GuardianTaunt.ENERGY_COST:
		return {"ok": false, "reason": "no_energy"}
	var targets: Array = []
	for infected in zombies.values():
		if infected.target_id == peer_id or not GuardianTaunt.eligible_enemy(
				infected, player.position, allies, world):
			continue
		var victim: Player = players.get(infected.target_id)
		if victim == null or not _alive(victim) or _is_safe(victim.position):
			continue
		if world.zone_at(victim.position.x, victim.position.z) != world.zone_at(
				player.position.x, player.position.z):
			continue
		targets.append(infected)
	if targets.is_empty():
		return {"ok": false, "reason": "no_engaged_infected"}
	targets.sort_custom(func(a, b): return a.position.distance_squared_to(
		player.position) < b.position.distance_squared_to(player.position))
	var count := mini(GuardianTaunt.MAX_TARGETS, targets.size())
	for index in count:
		targets[index].force_taunt(peer_id, GuardianTaunt.FOCUS_SECONDS)
	player.combat_energy -= GuardianTaunt.ENERGY_COST
	player.guardian_timer = GuardianTaunt.COOLDOWN
	player.guardian_brace = GuardianTaunt.GUARD_SECONDS
	player.action = {}
	events.append({"type": "guardian_taunt", "peer": peer_id,
		"x": player.position.x, "z": player.position.z, "count": count})
	return {"ok": true, "count": count, "cooldown": player.guardian_timer,
		"brace_seconds": player.guardian_brace, "energy": player.combat_energy}


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
	if not direction.is_finite() or not is_finite(direction.length_squared()) or direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "no_direction"}
	var cost: float = float(skill["energy_cost"])
	if player.combat_energy < cost:
		return {"ok": false, "reason": "no_energy"}
	var ranged: bool = bool(skill.get("ranged", false))
	var ammo: String = str(skill.get("ammo", ""))
	# Validate and consume exactly one physical cartridge before charging energy.
	# A failed shot must not start cooldown, change action, emit noise or cost XP.
	if ranged and (ammo.is_empty() or player.inventory.count(ammo) < 1):
		return {"ok": false, "reason": "no_ammo"}
	if ranged:
		if not player.inventory.remove(ammo, 1):
			return {"ok": false, "reason": "no_ammo"}
		player.dirty_inventory = true
	direction = direction.normalized()
	player.combat_energy -= cost
	player.skill_timer = float(skill["cooldown"])
	player.attack_timer = float(skill["attack_lock"])
	player.action = {}
	player.yaw = atan2(direction.x, direction.y)
	if ranged:
		var shot_noise: Dictionary = Combat.ranged_noise(weapon)
		player.noise_radius = maxf(player.noise_radius, float(shot_noise["radius"]))
		player.noise_timer = maxf(player.noise_timer, float(shot_noise["seconds"]))
	var origin := Vector2(player.position.x, player.position.z)
	events.append({"type": "attack", "peer": peer_id, "dir": direction, "ranged": ranged, "skill": skill["id"], "x": player.position.x, "z": player.position.z})
	# Spear attacks can pierce a narrow forward line. The server selects
	# distinct enemies and retains party / PvP protection for every hit.
	var max_hits: int = clampi(int(skill.get("pierce_targets", 1)), 1, 3)
	var use_line: bool = ranged or max_hits > 1
	var ignored: Dictionary = {}
	var count := 0
	var first_target: String = ""
	var skilled_damage: float = float(skill["damage"]) * player.progression.combat_damage_multiplier(weapon) \
		* (1.0 + player.skills.bonus("ranged_damage" if ranged else "melee_damage"))
	for i in max_hits:
		var hit: Dictionary = _find_hit(player, origin, direction, float(skill["range"]), use_line, ignored)
		if hit.is_empty():
			break
		ignored[str(hit["kind"]) + ":" + str(hit["id"])] = true
		if count == 0:
			first_target = str(hit["kind"])
		_damage_target(player, hit, skilled_damage, "ranged" if ranged else "melee")
		count += 1
	if count == 0:
		return {"ok": true, "hit": false, "hits": 0, "energy": player.combat_energy}
	return {"ok": true, "hit": true, "target": first_target,
		"hits": count, "energy": player.combat_energy}


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
	if not direction.is_finite() or not is_finite(direction.length_squared()) or direction.length_squared() < 0.0001:
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
		# Raid trophies are reserved briefly for the killing group members
		# who actually participated. The server owns the access list and time.
		if not RaidLoot.can_open(bag, player, time):
			return {"ok": false, "reason": "raid_reserved",
				"remaining": RaidLoot.remaining(bag, time)}
		if not LootRights.can_loot(bag, player, time):
			return {"ok": false, "reason": "reserved"}
		var taken_before: int = _item_total(bag["items"])
		var left := _give_items(player, bag["items"])
		if _item_total(left) < taken_before:
			_award(player, "scavenging", 3.0)
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
		var zone: int = int(crate["zone"])
		# Evaluate the bonus at the level earned BEFORE this crate. Only a
		# real reachable unopened world crate can grant XP or extra materials.
		var loot: Dictionary = Scavenging.enriched_loot(zone,
			player.progression.scavenging_level(), Combat.crate_loot(zone, local_rng))
		_apply_loot_skills(player, loot, local_rng)
		_award(player, "scavenging", 12.0 + 4.0 * float(zone))
		var left: Dictionary = _give_items(player, loot)
		if not left.is_empty():
			# Whatever does not fit stays on the ground next to the crate.
			_make_bag(Vector3(crate["x"], crate["y"], crate["z"]), left, peer_id)
		opened_crates[entity_id] = time + 600.0
		var gained_xp: int = player.progression.award_scavenge(zone)
		if gained_xp > 0:
			player.dirty_character = true
			events.append({"type": "scavenging", "peer": peer_id, "xp": gained_xp,
				"level": player.progression.scavenging_level()})
		if Contracts.record_crate(player.contract_state, entity_id):
			player.dirty_character = true
		if DailyBounties.record_crate(player.daily_bounty, _refresh_daily(player), entity_id):
			player.dirty_character = true
		events.append({"type": "crate", "peer": peer_id, "id": entity_id})
		return {"ok": true, "scavenging_xp": gained_xp}
	return {"ok": false, "reason": "nothing_there"}


# --- Skills -------------------------------------------------------------------------------------------------

## Turns the skill sheet into the numbers the survival model uses. Cheap; called whenever a level or perk changes.
func _apply_skill_bonuses(player: Player) -> void:
	var s = player.skills
	var survival = player.survival
	var old_max: float = survival.max_health
	survival.max_health = Defs.MAX_HEALTH + s.bonus("max_health")
	if survival.max_health > old_max:
		survival.health = minf(survival.health + (survival.max_health - old_max), survival.max_health)
	survival.hunger_mult = 1.0 - s.bonus("hunger_rate")
	survival.thirst_mult = 1.0 - s.bonus("thirst_rate")
	survival.stamina_drain_mult = 1.0 - s.bonus("stamina_drain")
	survival.stamina_regen_mult = 1.0 + s.bonus("stamina_regen")
	player.dirty_skills = true


## The one place XP is granted. Callers pass what the action was worth; refused actions never call it.
func _award(player: Player, skill: String, amount: float) -> void:
	var result: Dictionary = player.skills.add_xp(skill, amount)
	if int(result["gained"]) <= 0:
		return
	player.pending_xp[skill] = int(player.pending_xp.get(skill, 0)) + int(result["gained"])
	player.dirty_skills = true
	player.dirty_character = true
	if not result["levels"].is_empty():
		for reached in result["levels"]:
			events.append({"type": "skill_up", "peer": player.id, "skill": skill, "level": int(reached), "points": player.skills.points_available()})
		_apply_skill_bonuses(player)


## Tells the player what they have gained in the last second, in one message.
func _flush_xp(player: Player) -> void:
	if player.pending_xp.is_empty():
		return
	events.append({"type": "xp", "peer": player.id, "gains": player.pending_xp.duplicate()})
	player.pending_xp = {}


func _item_total(items: Dictionary) -> int:
	var total := 0
	for id in items:
		total += int(items[id])
	return total


## Scavenging skill: more silver, and sometimes an extra item, from what a crate holds.
func _apply_loot_skills(player: Player, loot: Dictionary, local_rng: RandomNumberGenerator) -> void:
	if loot.has("silver"):
		loot["silver"] = int(round(float(loot["silver"]) * (1.0 + player.skills.bonus("loot_silver"))))
	if local_rng.randf() < player.skills.bonus("loot_extra"):
		var extras: Array = []
		for id in loot:
			if id != "silver":
				extras.append(id)
		if not extras.is_empty():
			var pick: String = String(extras[local_rng.randi() % extras.size()])
			loot[pick] = int(loot[pick]) + 1


## Damage a player takes: toughness reduces it and trains from it.
func _hurt_player(victim: Player, raw_damage: float) -> float:
	var reduced: float = raw_damage * (1.0 - victim.skills.bonus("damage_reduction"))
	var applied: float = victim.survival.hurt(reduced)
	if applied > 0.0:
		_award(victim, "toughness", minf(applied * 0.4, 6.0))
	return applied


func cmd_perk(peer_id: int, perk_id: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "no_player"}
	var status: int = player.skills.buy_perk(perk_id)
	if status != Skills.Buy.OK:
		return {"ok": false, "reason": ["ok", "unknown_perk", "max_rank", "need_level", "need_perk", "need_points"][status]}
	_apply_skill_bonuses(player)
	player.dirty_character = true
	events.append({"type": "perk", "peer": peer_id, "perk": perk_id, "rank": player.skills.rank(perk_id)})
	return {"ok": true, "rank": player.skills.rank(perk_id), "points": player.skills.points_available()}


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


func _make_bag(position: Vector3, items: Dictionary, owner_peer: int = -1) -> int:
	if items.is_empty():
		return -1
	var bag_id := new_id()
	var bag: Dictionary = {"id": bag_id, "x": position.x, "y": position.y, "z": position.z,
		"items": items.duplicate(), "expires": time + BAG_LIFETIME}
	# Ordinary infected and crate overflow belong to the killer/scavenger's
	# party for a brief window. PvP full-loot and raid bags use other rules.
	if owner_peer > 0 and players.has(owner_peer):
		var participants: Array = [players[owner_peer]]
		for member_id in parties.members_of(owner_peer):
			var member = players.get(int(member_id))
			if member != null:
				participants.append(member)
		bag.merge(LootRights.reservation(participants, time))
	bags[bag_id] = bag
	events.append({"type": "bag", "id": bag_id})
	return bag_id


func _find_hit(attacker: Player, origin: Vector2, direction: Vector2, reach: float,
		ranged: bool, ignored: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	var attacker_zone: int = world.zone_at(attacker.position.x, attacker.position.z)
	# Zombies.
	for zombie in zombies.values():
		if not zombie.is_alive() or ignored.has("zombie:" + str(zombie.id)):
			continue
		var distance := _hit_distance(origin, direction, Vector2(zombie.position.x, zombie.position.z), reach, ranged, 0.55)
		if distance >= 0.0 and distance < best_distance:
			best = {"kind": "zombie", "id": zombie.id}
			best_distance = distance
	# PvP zones remain unchanged; only the mutually accepted hub opponent
	# may be targetable in the otherwise peaceful settlement.
	if ZoneRisk.allows_pvp(attacker_zone) or training_matches.has(attacker.id):
		for other in players.values():
			if other.id == attacker.id or not _alive(other) or ignored.has("player:" + str(other.id)):
				continue
			# Friendly party members do not intercept attacks aimed at enemies.
			var training: bool = TrainingDuel.active_for(training_matches, world, attacker, other, time)
			var group_id: int = parties.group_of(attacker.id)
			if not training and group_id != 0 and parties.group_of(other.id) == group_id:
				continue
			if not training and GuildIdentity.same_guild(attacker, other):
				continue # Verified guildmates cannot intercept PvP attacks.
			if not training and not ZoneRisk.can_pvp(attacker_zone, world.zone_at(other.position.x, other.position.z)):
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


func _damage_target(attacker: Player, hit: Dictionary, damage: float, source: String = "melee") -> void:
	attacker.dirty_character = true
	if hit["kind"] == "zombie":
		var zombie = zombies.get(hit["id"])
		if zombie == null:
			return
		# PvE relic traits are derived from physically carried gear on the server.
		# Never grant these against survivors or for stale equipment IDs.
		var equipped_weapon: String = attacker.inventory.weapon
		var physically_owned: bool = equipped_weapon != "" and attacker.inventory.count(equipped_weapon) > 0
		damage = Combat.against_infected(damage, equipped_weapon, physically_owned)
		damage *= 1.0 + attacker.skills.bonus("zombie_damage")
		# Only real, positive, server-applied hits can qualify for group XP.
		if damage > 0.0 and zombie.is_alive() and (zombie.contributors.size() < 16 or zombie.contributors.has(attacker.id)):
			var equipped: String = attacker.inventory.weapon
			if equipped != "" and attacker.inventory.count(equipped) > 0:
				zombie.contributors[attacker.id] = {"time": time, "weapon": equipped,
					"group": parties.group_of(attacker.id)}
		# A real hit on a living enemy trains the weapon skill (more for heavier hits).
		_award(attacker, "marksman" if source == "ranged" else "melee", 1.0 + damage / 6.0)
		events.append({"type": "hit", "kind": "zombie", "id": zombie.id, "damage": damage, "x": zombie.position.x, "z": zombie.position.z})
		if zombie.take_damage(damage, attacker.id):
			attacker.kills += 1
			_earn_renown(attacker, Reputation.kill_points(zombie.type,
				zombie.elite, zombie.raid_boss), "infected")
			# Award XP once, when a living infected is defeated with owned/equipped
			# gear. Ordinary hits, missed shots and re-killing corpses award none.
			var weapon: String = attacker.inventory.weapon
			if weapon != "" and attacker.inventory.count(weapon) > 0:
				var mastery_xp: int = attacker.progression.award_combat(
					weapon, int(zombie.data.get("xp", 0)))
				if mastery_xp > 0:
					events.append({"type": "mastery", "peer": attacker.id,
						"skill": Progression.combat_skill_for_weapon(weapon),
						"xp": mastery_xp})
			_party_award_assists(attacker, zombie)
			_award(attacker, "slayer", float(Defs.ZOMBIES[zombie.type].get("xp", 5)) * 2.0)
			if Contracts.record_kill(attacker.contract_state):
				attacker.dirty_character = true
			if DailyBounties.record_kill(attacker.daily_bounty, _refresh_daily(attacker)):
				attacker.dirty_character = true
			_on_zombie_death(zombie, attacker)
	else:
		var victim: Player = players.get(hit["id"])
		if victim == null or not _alive(victim):
			return
		if TrainingDuel.active_for(training_matches, world, attacker, victim, time):
			# Nonlethal combat. No PvP points, infamy, deaths, item loss, XP,
			# bleeding or combat logout penalty can originate from sparring.
			var strike: float = maxf(0.0, Combat.apply_armor(damage, victim.inventory.armor))
			strike *= 1.0 - clampf(victim.skills.bonus("damage_reduction"), 0.0, 0.4)
			var previous: float = victim.survival.health
			var applied: float = victim.survival.hurt(minf(strike, maxf(0.0, previous - 1.0)))
			if applied > 0.0:
				victim.dirty_character = true
			if strike >= previous - 1.0 and strike > 0.0:
				_end_training(victim.id, attacker.id, "knockout")
			return
		# Parties are cooperative: do not allow friendly fire in red zones.
		var attacker_party: int = parties.group_of(attacker.id)
		if attacker_party != 0 and attacker_party == parties.group_of(victim.id):
			return
		if GuildIdentity.same_guild(attacker, victim):
			return # Direct damage paths also obey guild alliances.
		if not ZoneRisk.can_pvp(world.zone_at(attacker.position.x, attacker.position.z),
				world.zone_at(victim.position.x, victim.position.z)):
			return
		_award(attacker, "marksman" if source == "ranged" else "melee", 1.0 + damage / 6.0)
		var final_damage: float = Combat.apply_armor(damage, victim.inventory.armor)
		var applied: float = _hurt_player(victim, final_damage)
		if applied > 0.0:
			# Both participants are combat-tagged from actual server-applied PvP
			# damage, including the attacker after a lethal finishing strike.
			CombatLogout.mark(attacker, time)
			CombatLogout.mark(victim, time)
		# Only genuine dangerous-zone player damage grants retaliation.
		# A legally counterattacking victim cannot justify the original
		# initiator's aggression, and wanted outlaws get no immunity.
		if applied > 0.0 and _alive(victim) and not PvpInfamy.is_outlaw(victim.pvp_infamy) 				and not PvpInfamy.can_retaliate(attacker.defense_target,
				attacker.defense_until, victim.id, time):
			var fresh: bool = not PvpInfamy.can_retaliate(victim.defense_target,
				victim.defense_until, attacker.id, time)
			victim.defense_target = attacker.id
			victim.defense_until = time + PvpInfamy.SELF_DEFENSE_SECONDS
			if fresh:
				events.append({"type": "self_defense", "peer": victim.id,
					"seconds": PvpInfamy.SELF_DEFENSE_SECONDS})
		var wielded: String = attacker.inventory.weapon
		if applied > 0.0 and _alive(victim) and wielded != "" and attacker.inventory.count(wielded) > 0 \
				and str(Defs.item(wielded).get("weapon", "")) == "melee":
			if victim.survival.add_bleeding(Defs.PVP_MELEE_BLEEDING_PER_HIT):
				victim.dirty_character = true
				events.append({"type": "bleeding", "peer": victim.id,
					"severity": victim.survival.bleeding, "source": "pvp"})
		events.append({"type": "hit", "kind": "player", "id": victim.id, "damage": final_damage, "by": attacker.id})
		if not _alive(victim):
			attacker.kills += 1
			var lawful: String = PvpInfamy.lawful_kill_reason(victim.pvp_infamy,
				attacker.defense_target, attacker.defense_until, victim.id, time)
			if lawful != "":
				events.append({"type": "justice", "peer": attacker.id, "reason": lawful})
			else:
				var old_score: float = attacker.pvp_infamy
				attacker.pvp_infamy = PvpInfamy.gain_for_kill(old_score)
				if attacker.pvp_infamy > old_score:
					attacker.dirty_character = true
					events.append({"type": "infamy", "peer": attacker.id,
						"score": attacker.pvp_infamy,
						"outlaw": PvpInfamy.is_outlaw(attacker.pvp_infamy)})
			var honor_result: Dictionary = PvPHonor.record(attacker, victim,
				world.zone_at(victim.position.x, victim.position.z), time, pvp_honor_ledger)
			if bool(honor_result.get("ok", false)):
				attacker.dirty_character = true
				events.append({"type": "pvp_honor", "peer": attacker.id,
					"earned": int(honor_result["awarded"]),
					"honor": attacker.pvp_honor,
					"rank": str(honor_result["rank"])})
			_on_player_death(victim, attacker.id)


## Nearby party members gain modest weapon mastery XP only if they personally
## hit this infected in the last 20 seconds. AFK/nonparticipants receive none.
## The killing blow and contract progress still belong to the actual killer.
func _party_award_assists(killer: Player, zombie) -> void:
	var group: Array = parties.members_of(killer.id)
	if group.size() < 2:
		return
	var encounter_zone: int = world.zone_at(zombie.position.x, zombie.position.z)
	var shared_xp: int = Party.assist_xp(int(zombie.data.get("xp", 0)))
	if shared_xp <= 0:
		return
	for member_id in group:
		if int(member_id) == killer.id:
			continue
		var participant: Player = players.get(int(member_id))
		if participant == null or not _alive(participant):
			continue
		if not Party.in_assist_range(participant.position, zombie.position):
			continue
		# Prevent XP being shared across green/red risk zone borders.
		if world.zone_at(participant.position.x, participant.position.z) != encounter_zone:
			continue
		var hit: Dictionary = zombie.contributors.get(int(member_id), {})
		if hit.is_empty() or time - float(hit.get("time", -INF)) > Party.ASSIST_WINDOW:
			continue
		# Only a hit that happened inside THIS party earns an assist reward.
		if int(hit.get("group", 0)) != parties.group_of(killer.id):
			continue
		var used_weapon: String = str(hit.get("weapon", ""))
		if used_weapon.is_empty() or participant.inventory.count(used_weapon) < 1:
			continue
		var actual: int = participant.progression.award_combat(used_weapon, shared_xp)
		if actual > 0:
			participant.dirty_character = true
			events.append({"type": "mastery", "peer": participant.id,
				"skill": Progression.combat_skill_for_weapon(used_weapon),
				"xp": actual, "assist": true})


func _on_zombie_death(zombie, killer: Player) -> void:
	var zone: int = world.zone_at(zombie.position.x, zombie.position.z)
	var loot_rng := RandomNumberGenerator.new()
	loot_rng.seed = WorldGen.mix(zombie.id, int(time * 10.0), world.world_seed, 5)
	var loot: Dictionary = Combat.zombie_loot(zombie.type, zone, loot_rng)
	if zombie.elite:
		loot = EliteInfected.enhanced_loot(loot, zone)
	if loot.has("silver"):
		loot["silver"] = int(round(float(loot["silver"]) * (1.0 + killer.skills.bonus("zombie_silver"))))
	if zombie.raid_boss:
		# Fixed server-side reward bag; no player gets multiple personal copies.
		for item_id in RaidEncounter.treasure(zone):
			loot[item_id] = int(loot.get(item_id, 0)) + int(RaidEncounter.treasure(zone)[item_id])
		raid_boss_id = -1
		raid_pending_slam = {}
		_clear_raid_minions()
		raid_wave = 0
		events.append({"type": "raid_defeated", "id": zombie.id,
			"x": zombie.position.x, "z": zombie.position.z})
	var loot_bag_id: int = _make_bag(zombie.position, loot, -1 if zombie.raid_boss else killer.id)
	if zombie.raid_boss and loot_bag_id >= 0:
		# Entitlements are frozen at the confirmed kill; guests use object
		# identity, accounts survive reconnect. No client-authored loot rights.
		var eligible: Array = RaidLoot.eligible(killer, zombie, players, parties, world, time)
		RaidLoot.reserve(bags[loot_bag_id], eligible, time)
	if spawn_state.has(zombie.spawn_id):
		spawn_state[zombie.spawn_id] = {"zombie": -1, "next": time + (240.0 if zone < 2 else 360.0)}
	events.append({"type": "zombie_died", "id": zombie.id, "x": zombie.position.x, "z": zombie.position.z})


## Full-loot deaths occur in red/black. Green/yellow deaths retain gear.
func _on_player_death(victim: Player, killer: int) -> void:
	_abort_training(victim.id, "death")
	_cancel_market_seller(victim.id)
	_cancel_player_trade(victim.id, "dead")
	victim.deaths += 1
	victim.dirty_character = true
	victim.action = {}
	victim.dodge_immunity = 0.0
	victim.guardian_brace = 0.0
	victim.meal_seconds = 0.0
	victim.meal_tier = 0
	victim.defense_target = -1
	victim.defense_until = 0.0
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
	_tick_market()
	_tick_trades()
	parties.expire(time)
	_tick_players(delta)
	_tick_training()
	var capture_events: Array = territory.tick(delta, time, players, parties)
	events.append_array(capture_events)
	events.append_array(siege_contracts.tick(time, territory.sites, parties, capture_events))
	if tick_count % SiegeWaves.CHECK_EVERY_TICKS == 0:
		_tick_siege_waves()
	_tick_raid_encounter()
	_tick_zombies(delta)
	_tick_world(delta)


func _tick_players(delta: float) -> void:
	for player in players.values():
		player.input_budget = minf(player.input_budget + delta, 0.25)
		var old_infamy: float = player.pvp_infamy
		player.pvp_infamy = PvpInfamy.decay(old_infamy, delta)
		if player.pvp_infamy < old_infamy:
			player.dirty_character = true
		player.rest_cooldown = maxf(0.0, player.rest_cooldown - maxf(0.0, delta))
		player.party_aid_timer = maxf(0.0, player.party_aid_timer - maxf(0.0, delta))
		player.feast_timer = maxf(0.0, player.feast_timer - maxf(0.0, delta))
		player.guardian_timer = maxf(0.0, player.guardian_timer - maxf(0.0, delta))
		player.guardian_brace = maxf(0.0, player.guardian_brace - maxf(0.0, delta))
		# A disconnected teammate or removed weapon cannot prolong protection.
		if player.guardian_brace > 0.0 and (parties.members_of(player.id).size() < 2 or
				not GuardianTaunt.melee_equipped(player.inventory)):
			player.guardian_brace = 0.0
		player.lake_drink_cooldown = maxf(0.0, player.lake_drink_cooldown - maxf(0.0, delta))
		player.stim_cooldown = maxf(0.0, player.stim_cooldown - maxf(0.0, delta))
		player.decoy_timer = maxf(0.0, player.decoy_timer - maxf(0.0, delta))
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
		# Integrate only the fraction of the tick while the cooked meal is active.
		var meal_effect_tier: int = player.meal_tier
		var active_meal: float = HeartyMeal.bonus_seconds(player.meal_seconds, delta)
		var stamina_meal_seconds: float = HeartyMeal.stamina_seconds(
			active_meal, player.survival.stamina_recovery_delay)
		player.meal_seconds = maxf(0.0, player.meal_seconds - maxf(0.0, delta))
		if player.meal_seconds <= 0.0 and player.meal_tier > 0:
			player.meal_tier = 0
		if active_meal > 0.0:
			player.dirty_character = true
		var nourished: bool = player.survival.hunger > 20.0 and player.survival.thirst > 20.0
		var energy_bonus: float = (
			HeartyMeal.energy_per_second(meal_effect_tier) * active_meal) if nourished else 0.0
		player.combat_energy = minf(Defs.COMBAT_ENERGY_MAX,
			player.combat_energy + Defs.COMBAT_ENERGY_REGEN * delta + energy_bonus)
		var had_bleeding: bool = player.survival.bleeding > 0.0
		var had_scent_mask: bool = player.survival.scent_mask_seconds > 0.0
		var damage: float = player.survival.tick(delta)
		if had_scent_mask:
			player.dirty_character = true
		if nourished and stamina_meal_seconds > 0.0:
			player.survival.stamina = minf(Defs.MAX_STAMINA,
				player.survival.stamina +
					HeartyMeal.stamina_per_second(meal_effect_tier) * stamina_meal_seconds)
		# Holding a contested PvP outpost grants a small local rally advantage.
		# Only the server owns party identity, site control and stamina.
		if player.survival.stamina_recovery_delay <= 0.0 and \
				player.survival.hunger > 20.0 and player.survival.thirst > 20.0 and \
				territory.has_rally_bonus(player.id, player.position, parties, time, players):
			player.survival.stamina = minf(Defs.MAX_STAMINA,
				player.survival.stamina + TerritoryControl.RALLY_STAMINA_PER_SECOND * delta)
		var conditions: Dictionary = Weather.conditions(world, player.position.x, player.position.z, time)
		# An old armor ID after an inventory transfer must not provide warmth.
		var worn_armor: String = player.inventory.armor
		if worn_armor != "" and player.inventory.count(worn_armor) <= 0:
			worn_armor = ""
		var weather_severity: float = Weather.effective_severity(conditions, worn_armor)
		if FieldCampfire.has_warmth(campfires, player.position, time):
			weather_severity = 0.0
		damage += player.survival.weather_tick(delta, weather_severity)
		if player.survival.exposure > 0.0 or player.survival.warmth_seconds > 0.0:
			player.dirty_character = true
		if player.survival.infection > 0.0 or had_bleeding or damage > 0.0:
			# Persist the last clotting tick and its health loss, not only active wounds.
			player.dirty_character = true
		if damage > 0.0 and not _alive(player):
			_on_player_death(player, -1)
			continue
		var zone: int = world.zone_at(player.position.x, player.position.z)
		if zone != player.zone_notice:
			player.zone_notice = zone
			events.append({"type": "zone", "peer": player.id, "zone": zone})
			var region_bit: int = 1 << zone
			if zone >= 1 and int(player.skills.zones_seen) & region_bit == 0:
				player.skills.zones_seen = int(player.skills.zones_seen) | region_bit
				_award(player, "explorer", 40.0 * float(zone))
		player.xp_report_timer += delta
		if player.xp_report_timer >= 1.0:
			player.xp_report_timer = 0.0
			_flush_xp(player)
		if not player.action.is_empty():
			if player.action.has("fish"):
				var cast_at := Vector2(float(player.action["cast_x"]), float(player.action["cast_z"]))
				var current_catch: Dictionary = Fishing.validate_start(world, player.position,
					player.inventory, player.progression.gathering_level("fishing"))
				if not bool(current_catch.get("ok", false)) \
						or str(current_catch.get("item", "")) != str(player.action.get("catch_id", "")) \
						or Vector2(player.position.x, player.position.z).distance_to(cast_at) > 0.45:
					player.action = {}
					continue
				player.action["remaining"] = float(player.action["remaining"]) - delta
				if float(player.action["remaining"]) <= 0.0:
					_finish_fishing(player)
			else:
				var node := _find_node(int(player.action["node"]))
				if node.is_empty() or depleted.has(int(player.action["node"])):
					player.action = {}
					continue
				player.action["remaining"] = float(player.action["remaining"]) - delta
				if float(player.action["remaining"]) <= 0.0:
					_finish_gather(player, node)


func _finish_fishing(player: Player) -> void:
	var item_id: String = str(player.action.get("catch_id", Fishing.CATCH_ID))
	var tier: int = int(player.action.get("tier", 1))
	player.action = {}
	if item_id != Fishing.catch_item(tier):
		return # Never trust an inconsistent pending action.
	var amount: int = 1 + (1 if rng.randf() < 0.35 else 0)
	var added: int = amount - player.inventory.add(item_id, amount)
	if added > 0:
		player.progression.award_gather("fishing", tier, added)
		player.dirty_inventory = true
		player.dirty_character = true
	events.append({"type": "fished", "peer": player.id, "item": item_id,
		"amount": added, "tier": tier})


func _finish_gather(player: Player, node: Dictionary) -> void:
	var info := Defs.node_info(node["kind"])
	var item_id: String = info["yield"]
	if item_id in ["wood", "stone", "ore", "fiber"]:
		item_id = "%s_%d" % [item_id, int(node["tier"])]
	var amount: int = int(info["amount"]) + (1 if rng.randf() < 0.3 else 0)
	var gather_skill := Skills.skill_for_node(String(node["kind"]))
	if gather_skill != "" and rng.randf() < player.skills.bonus("gather_yield." + gather_skill):
		amount += 1 # Skill: a lucky harvest.
	var left: int = player.inventory.add(item_id, amount)
	if gather_skill != "" and amount - left > 0:
		_award(player, gather_skill, (3.0 + 2.0 * float(amount - left)) * float(int(node["tier"])))
	# No XP for items that did not fit, nor for repeat attempts on depleted nodes.
	player.progression.award_gather(String(node["kind"]), int(node["tier"]), amount - left)
	player.dirty_inventory = true
	player.dirty_character = true
	player.action = {}
	depleted[int(node["id"])] = time + float(info["respawn"])
	events.append({"type": "gathered", "peer": player.id, "item": item_id, "amount": amount - left, "node": node["id"]})


## Rare dangerous-zone group boss. One live boss per simulation and a 10-minute
## cooldown; normal elite infected and nightly barricade sieges remain separate.
func _tick_raid_encounter() -> void:
	if raid_boss_id != -1:
		var boss = zombies.get(raid_boss_id)
		if boss == null or not boss.is_alive():
			raid_boss_id = -1
			raid_pending_slam = {}
			_clear_raid_minions()
			raid_wave = 0
			return
		var at := Vector2(boss.position.x, boss.position.z)
		if time >= raid_started_at + RaidEncounter.MAX_ENCOUNTER_SECONDS \
				or _nearest_player_distance(at) > ZOMBIE_ACTIVE_RADIUS:
			zombies.erase(raid_boss_id)
			events.append({"type": "raid_expired", "id": raid_boss_id,
				"x": at.x, "z": at.y})
			raid_boss_id = -1
			raid_pending_slam = {}
			_clear_raid_minions()
			raid_wave = 0
			return
		_tick_raid_reinforcements(boss)
		if RaidEncounter.try_enrage(boss):
			# Phase transition is one-time per encounter. Never cancel a
			# telegraphed strike already in flight.
			raid_next_slam_at = minf(raid_next_slam_at,
				time + RaidEncounter.ENRAGE_SLAM_COOLDOWN)
			events.append({"type": "raid_enraged", "id": raid_boss_id,
				"x": at.x, "z": at.y, "hp": boss.health})
		if not raid_pending_slam.is_empty():
			if time >= float(raid_pending_slam["at"]):
				var center := Vector2(float(raid_pending_slam["x"]),
					float(raid_pending_slam["z"]))
				var boss_id: int = int(raid_pending_slam["id"])
				raid_pending_slam = {}
				_resolve_raid_slam(boss_id, center)
			return
		if time >= raid_next_slam_at and boss.target_id != -1:
			raid_pending_slam = {"id": raid_boss_id,
				"x": at.x, "z": at.y,
				"at": time + RaidEncounter.SLAM_WARNING}
			raid_next_slam_at = time + RaidEncounter.slam_cooldown(boss)
			events.append({"type": "raid_warning", "id": raid_boss_id,
				"x": at.x, "z": at.y,
				"radius": RaidEncounter.SLAM_RADIUS,
				"seconds": RaidEncounter.SLAM_WARNING})
		return

	if time < RaidEncounter.START_DELAY or \
			time - last_raid_spawn_time < RaidEncounter.COOLDOWN or \
			zombies.size() >= RaidEncounter.MAX_INFECTED or \
			tick_count % SiegeWaves.CHECK_EVERY_TICKS != 0:
		return
	var leader_id: int = RaidEncounter.eligible_leader(world, players, parties)
	if leader_id == -1:
		return
	var leader: Player = players.get(leader_id)
	var site: Vector2 = RaidEncounter.spawn_site(world, players,
		leader.position, tick_count % RaidEncounter.SPAWN_ANGLES)
	if site == Vector2.INF:
		return
	var spawn_id: int = new_id()
	var boss = Zombie.new(spawn_id, "brute",
		Vector3(site.x, world.height_at(site.x, site.y), site.y), -1)
	RaidEncounter.empower(boss)
	var targets: Dictionary = {}
	targets[leader_id] = {"position": leader.position, "alive": true, "safe": false}
	boss.receive_pack_alert(leader_id, targets)
	zombies[spawn_id] = boss
	raid_boss_id = spawn_id
	raid_wave = 0
	raid_minions.clear()
	raid_started_at = time
	last_raid_spawn_time = time
	raid_next_slam_at = time + 9.0
	events.append({"type": "raid_started", "id": spawn_id,
		"x": site.x, "z": site.y, "zone": world.zone_at(site.x, site.y),
		"health": boss.health})


## Two one-time health phases; no client command may create minions.
## The existing boss enrage and slam remain intact.
func _tick_raid_reinforcements(boss) -> void:
	var phase: int = RaidReinforcements.next_phase(
		boss.health, float(boss.data["health"]), raid_wave)
	var free_slots: int = RaidEncounter.MAX_INFECTED - zombies.size()
	if phase == 0 or free_slots <= 0:
		return
	var points: Array[Vector2] = RaidReinforcements.sites(
		world, players, zombies, boss.position, phase,
		mini(free_slots, RaidReinforcements.MAX_WAVE))
	if points.is_empty():
		return
	var types: Array[String] = RaidReinforcements.kinds(phase)
	var target: Player = players.get(boss.target_id)
	var visible_targets: Dictionary = {}
	if target != null and _alive(target) and not _is_safe(target.position):
		visible_targets[boss.target_id] = {"position": target.position,
			"alive": true, "safe": false}
	for i in points.size():
		var spot: Vector2 = points[i]
		var enemy_id: int = new_id()
		var minion = Zombie.new(enemy_id, types[i],
			Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y), -1)
		if not visible_targets.is_empty():
			minion.receive_pack_alert(boss.target_id, visible_targets)
		zombies[enemy_id] = minion
		raid_minions.append(enemy_id)
	raid_wave = phase
	events.append({"type": "raid_reinforcements", "id": boss.id,
		"x": boss.position.x, "z": boss.position.z,
		"phase": phase, "count": points.size()})


func _clear_raid_minions() -> void:
	for enemy_id in raid_minions:
		zombies.erase(enemy_id)
	raid_minions.clear()


## Shared by infected melee and telegraphed boss hits, never the PvP
## damage branch. Weapon and group are rechecked at hit time.
func _infected_damage_for(victim: Player, armored_damage: float) -> float:
	return GuardianTaunt.brace_damage(armored_damage, victim.guardian_brace,
		GuardianTaunt.melee_equipped(victim.inventory),
		parties.members_of(victim.id).size() >= 2)


func _resolve_raid_slam(boss_id: int, center: Vector2) -> void:
	var boss = zombies.get(boss_id)
	if boss == null or not boss.is_alive() or not boss.raid_boss:
		return
	for survivor in players.values():
		if not _alive(survivor) or _is_safe(survivor.position) \
				or world.zone_at(survivor.position.x, survivor.position.z) < RaidEncounter.MIN_ZONE \
				or not RaidEncounter.in_slam(center, survivor.position):
			continue
		if survivor.dodge_immunity > 0.0:
			events.append({"type": "evaded", "peer": survivor.id, "zombie": boss_id})
			continue
		var damage: float = Combat.apply_armor(RaidEncounter.slam_damage(boss), survivor.inventory.armor)
		damage = _infected_damage_for(survivor, damage)
		survivor.survival.hurt(damage)
		events.append({"type": "hit", "kind": "player", "id": survivor.id,
			"damage": damage, "by": -boss_id})
		if not _alive(survivor):
			_on_player_death(survivor, -boss_id)
	events.append({"type": "raid_slam", "id": boss_id,
		"x": center.x, "z": center.y,
		"radius": RaidEncounter.SLAM_RADIUS})


## Night-only server raids on defended survivors. Neither clients nor
## old persistent-world snapshots get to dictate wave locations or strength.
func _tick_siege_waves() -> void:
	if not WorldCycle.is_night(time) or time - last_siege_time < SiegeWaves.GLOBAL_COOLDOWN:
		return
	if zombies.size() >= SiegeWaves.MAX_ACTIVE_ZOMBIES or barricades.is_empty() or players.is_empty():
		return
	var wall_ids: Array = barricades.keys()
	wall_ids.sort()
	for wall_id in wall_ids:
		if time - float(siege_last_by_wall.get(wall_id, -1000000.0)) < SiegeWaves.WALL_COOLDOWN:
			continue
		var wall: Dictionary = barricades[wall_id]
		for player in players.values():
			if not _alive(player) or _is_safe(player.position):
				continue
			if not SiegeWaves.eligible(wall, player.position, time):
				continue
			var budget: int = mini(SiegeWaves.wave_size(Structures.tier_of(wall)),
				SiegeWaves.MAX_ACTIVE_ZOMBIES - zombies.size())
			var sites: Array[Vector2] = SiegeWaves.spawn_sites(world, wall,
				player.position, budget, rng.randi_range(0, SiegeWaves.SPAWN_ANGLES - 1))
			if sites.is_empty():
				continue
			var target_info: Dictionary = {player.id: {"position": player.position,
				"alive": true, "safe": false}}
			for index in sites.size():
				var at: Vector2 = sites[index]
				var kind := "walker"
				if Structures.tier_of(wall) >= 4 and index == sites.size() - 1:
					kind = "brute"
				elif Structures.tier_of(wall) >= 2 and index % 3 == 2:
					kind = "runner"
				var spawned_id: int = new_id()
				var infected = Zombie.new(spawned_id, kind,
					Vector3(at.x, world.height_at(at.x, at.y), at.y), -1)
				infected.receive_pack_alert(player.id, target_info)
				zombies[spawned_id] = infected
			last_siege_time = time
			siege_last_by_wall[wall_id] = time
			siege_waves_started += 1
			events.append({"type": "siege_started", "id": wall_id,
				"peer": player.id, "x": wall["x"], "z": wall["z"],
				"count": sites.size(), "tier": Structures.tier_of(wall)})
			return # At most one wave per scheduler check.


## Fixed-position corrosive AoE: dodge or walk away during a visible
## 1.4-second telegraph. No target/position/damage comes from the client.
func _resolve_spit_impact(zombie, center: Vector2) -> void:
	if not zombie.is_alive() or zombie.type != "spitter" or not center.is_finite():
		return
	for survivor in players.values():
		if not _alive(survivor) or _is_safe(survivor.position) 				or world.zone_at(survivor.position.x, survivor.position.z) < AcidSpitter.MIN_ZONE 				or not AcidSpitter.hits(center, survivor.position):
			continue
		if survivor.dodge_immunity > 0.0:
			events.append({"type": "evaded", "peer": survivor.id, "zombie": zombie.id})
			continue
		var armor_id: String = survivor.inventory.armor
		var owned: bool = armor_id != "" and survivor.inventory.count(armor_id) > 0
		var impact: float = Combat.apply_armor(float(zombie.data["damage"]),
			armor_id if owned else "")
		impact = _infected_damage_for(survivor, impact)
		var applied: float = _hurt_player(survivor, impact)
		if applied > 0.0 and _alive(survivor):
			var wound: float = Combat.infected_wound_amount(
				AcidSpitter.INFECTION_PER_HIT, armor_id, owned, "infection")
			wound = WardenAura.mitigate_wound(wound,
				WardenAura.active_for(survivor, players, parties, world))
			if survivor.survival.add_infection(wound):
				survivor.dirty_character = true
				events.append({"type": "infection", "peer": survivor.id,
					"severity": survivor.survival.infection, "source": "spitter"})
		events.append({"type": "hit", "kind": "player", "id": survivor.id,
			"damage": impact, "by": -zombie.id})
		if not _alive(survivor):
			_on_player_death(survivor, -zombie.id)
	events.append({"type": "spit_impact", "id": zombie.id, "x": center.x,
		"z": center.y, "radius": AcidSpitter.RADIUS})


func _tick_zombies(delta: float) -> void:
	var info: Dictionary = {}
	for player in players.values():
		info[player.id] = {"position": player.position, "alive": _alive(player),
			"safe": _is_safe(player.position), "noise": player.noise_radius if player.noise_timer > 0.0 else 0.0,
			"notice_multiplier": WorldCycle.notice_multiplier(time),
			"visual_signature": Camouflage.visual_signature(
				player.inventory.armor, player.inventory.armor != "" and
				player.inventory.count(player.inventory.armor) > 0,
				player.noise_timer, _alive(player)),
			# Only actual server wounds contribute; never trust client input.
			"scent": BloodScent.detection_radius(player.survival.bleeding,
				_alive(player), _is_safe(player.position), FieldScentMask.active(player.survival))}
	# Activate spawns near players and put far-away zombies to sleep.
	if tick_count % 20 == 1:
		_manage_zombie_population()
	# Every fourth of a second alert only idle, non-raid infected within
	# hearing range. Active chases and combat threat always take priority.
	if tick_count % 5 == 0 and not decoys.is_empty():
		_alert_noise_decoys()
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
		if result.has("spit_warning"):
			events.append({"type": "spit_warning", "id": zombie.id,
				"x": float(result["x"]), "z": float(result["z"]),
				"seconds": AcidSpitter.WINDUP_SECONDS,
				"radius": AcidSpitter.RADIUS})
			continue
		if result.has("spit_impact"):
			_resolve_spit_impact(zombie, Vector2(float(result["x"]), float(result["z"])))
			continue
		if result.has("hit"):
			var victim: Player = players.get(result["hit"])
			if victim != null and _alive(victim):
				# An active dodge avoids infected wounds; normal PvP attacks still land.
				if victim.dodge_immunity > 0.0:
					events.append({"type": "evaded", "peer": victim.id, "zombie": zombie.id})
					continue
				var armor_id: String = victim.inventory.armor
				var armor_owned: bool = armor_id != "" and victim.inventory.count(armor_id) > 0
				var damage: float = Combat.apply_armor(float(result["damage"]),
					armor_id if armor_owned else "")
				damage = _infected_damage_for(victim, damage)
				var applied: float = _hurt_player(victim, damage)
				# Only real carried armor protects from infected secondary wounds.
				# PvP bleeding continues to follow its ordinary rules.
				var wound_bleeding: float = Combat.infected_wound_amount(
					float(Defs.ZOMBIE_BLEEDING_PER_HIT.get(zombie.type, 0.0)),
					armor_id, armor_owned, "bleeding")
				var wound_infection: float = Combat.infected_wound_amount(
					float(Defs.ZOMBIE_INFECTION_PER_HIT.get(zombie.type, 0.0)),
					armor_id, armor_owned, "infection")
				# Nearby living party guardians wearing BOTH earned relic pieces
				# provide a single nonstacking PvE wound ward. PvP is untouched.
				var warded: bool = WardenAura.active_for(victim, players, parties, world)
				wound_bleeding = WardenAura.mitigate_wound(wound_bleeding, warded)
				wound_infection = WardenAura.mitigate_wound(wound_infection, warded)
				if applied > 0.0 and _alive(victim) and victim.survival.add_bleeding(wound_bleeding):
					victim.dirty_character = true
					events.append({"type": "bleeding", "peer": victim.id,
						"severity": victim.survival.bleeding, "source": zombie.type})
				if victim.survival.add_infection(wound_infection):
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
func _alert_noise_decoys() -> void:
	# One spatial index per four-times-per-second hearing pass, rather than
	# an O(infected * all lures) loop. Never give a decoy active player aggro.
	var buckets: Dictionary = NoiseDecoy.sound_buckets(decoys, time)
	if buckets.is_empty():
		return
	for infected in zombies.values():
		if not infected.is_alive() or infected.raid_boss:
			continue
		var lure: Dictionary = NoiseDecoy.closest_audible(buckets, infected.position, time)
		if not lure.is_empty():
			infected.investigate_decoy(Vector2(float(lure["x"]), float(lure["z"])))


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
			# Only dangerous-zone ruins can roll a deterministic champion.
			if EliteInfected.is_elite_spawn(int(spawn["id"]),
					world.zone_at(float(spawn["x"]), float(spawn["z"])),
					bool(spawn["ruin"]), world.world_seed):
				z.become_elite()
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
	for id in decoys.keys():
		if time >= float(decoys[id]["expires"]):
			decoys.erase(id)
	for id in campfires.keys():
		if time >= float(campfires[id]["expires"]):
			campfires.erase(id)
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
	_refresh_daily(player)
	var here := Vector2(player.position.x, player.position.z)
	var nearby_players: Array = []
	for other in players.values():
		if other.id == peer_id:
			continue
		var p: Vector3 = other.position
		if here.distance_to(Vector2(p.x, p.z)) <= Defs.INTEREST_RADIUS:
			nearby_players.append({"id": other.id, "name": other.name, "x": p.x, "y": p.y, "z": p.z, "yaw": other.yaw,
				"alive": _alive(other), "weapon": other.inventory.weapon,
				"outlaw": PvpInfamy.is_outlaw(other.pvp_infamy),
				"guild": {"id": other.guild_id, "name": other.guild_name},
				"pvp_rank": PvPHonor.rank(other.pvp_honor)})
	var nearby_zombies: Array = []
	for zombie in zombies.values():
		var p: Vector3 = zombie.position
		if zombie.is_alive() and here.distance_to(Vector2(p.x, p.z)) <= Defs.INTEREST_RADIUS:
			nearby_zombies.append({"id": zombie.id, "type": zombie.type, "x": p.x, "y": p.y, "z": p.z, "yaw": zombie.yaw, "hp": zombie.health, "state": zombie.state,
					"elite": zombie.elite, "raid_boss": zombie.raid_boss,
					"raid_enraged": zombie.raid_enraged,
					"max_hp": float(zombie.data.get("health", zombie.health))})
	# Replicate only pending, living spit warnings within sight of this
	# survivor. Client visual effects never authorize an actual hit.
	var spit_zones: Array = []
	for infected in zombies.values():
		if infected.type != "spitter" or not infected.is_alive() or not infected.spit_pending:
			continue
		if here.distance_to(infected.spit_center) <= Defs.INTEREST_RADIUS:
			spit_zones.append({"id": infected.id, "x": infected.spit_center.x,
				"y": world.height_at(infected.spit_center.x, infected.spit_center.y),
				"z": infected.spit_center.y, "radius": AcidSpitter.RADIUS,
				"remaining": infected.spit_seconds})
	var nearby_barricades: Array = []
	for wall in barricades.values():
		if Structures.within_range(here, Vector2(float(wall["x"]), float(wall["z"])), Defs.INTEREST_RADIUS):
			nearby_barricades.append(Structures.public_state(wall))
	var nearby_campfires: Array = FieldCampfire.visible(campfires,
			player.position, time, Defs.INTEREST_RADIUS)
	var nearby_decoys: Array = []
	for lure in decoys.values():
		if NoiseDecoy.is_audible(lure, player.position, time) or (
				here.distance_to(Vector2(float(lure["x"]), float(lure["z"]))) <= Defs.INTEREST_RADIUS and
				float(lure["expires"]) > time):
			nearby_decoys.append(NoiseDecoy.visible_state(lure, time))
	var nearby_bags: Array = []
	for bag in bags.values():
		if here.distance_to(Vector2(bag["x"], bag["z"])) <= Defs.INTEREST_RADIUS:
			var bag_view: Dictionary = LootRights.visible_state(bag, player, time)
			bag_view["raid"] = bag.has("raid_reserved_until")
			if bool(bag_view["raid"]):
				# Raid contribution entitlement supersedes ordinary party looting.
				bag_view["reserved_seconds"] = RaidLoot.remaining(bag, time)
				bag_view["reserved"] = float(bag_view["reserved_seconds"]) > 0.0
				bag_view["can_loot"] = RaidLoot.can_open(bag, player, time)
			nearby_bags.append(bag_view)
	var gone_nodes: Array = []
	for id in depleted:
		gone_nodes.append(id)
	var used_crates: Array = []
	for id in opened_crates:
		used_crates.append(id)
	var snapshot := {
		"tick": tick_count, "time": time, "ack": player.last_input_seq,
		"outposts": siege_contracts.public_state(territory.public_state(time, players, parties), time),
		"you": {
			"party": _party_state_for(peer_id),
			"guild": {"id": player.guild_id, "name": player.guild_name, "rank": player.guild_rank},
			"siege_wins": int(siege_contracts.victories.get(parties.group_of(peer_id), 0)),
			"x": player.position.x, "y": player.position.y, "z": player.position.z, "yaw": player.yaw,
			"health": player.survival.health, "hunger": player.survival.hunger, "thirst": player.survival.thirst,
			"stamina": player.survival.stamina,
			"meal_seconds": player.meal_seconds, "meal_tier": player.meal_tier,
			"alive": _alive(player), "kills": player.kills, "deaths": player.deaths, "zone": player.zone_notice,
			"pvp_infamy": player.pvp_infamy, "outlaw": PvpInfamy.is_outlaw(player.pvp_infamy),
			"combat_tag_seconds": CombatLogout.remaining(player.combat_tag_until, time),
			"duel": _training_snapshot(peer_id),
			"self_defense_seconds": PvpInfamy.defense_remaining(
				player.defense_target, player.defense_until, time),
			"pvp_kills": player.pvp_kills, "pvp_honor": player.pvp_honor,
			"pvp_rank": PvPHonor.rank(player.pvp_honor),
			"action": player.action.duplicate(),
			"infection": player.survival.infection, "bleeding": player.survival.bleeding,
			"blood_scent_radius": BloodScent.detection_radius(player.survival.bleeding,
				_alive(player), _is_safe(player.position), FieldScentMask.active(player.survival)),
			"scent_mask_seconds": player.survival.scent_mask_seconds,
			"exposure": player.survival.exposure,
			"warmth_seconds": player.survival.warmth_seconds,
			"campfire_warm": FieldCampfire.has_warmth(campfires, player.position, time),
			"weather": Weather.conditions(world, player.position.x, player.position.z, time),
			"weather_insulation": Weather.protection(
				player.inventory.armor if player.inventory.count(player.inventory.armor) > 0 else ""),
			"lake_drink_cooldown": player.lake_drink_cooldown,
			"combat_energy": player.combat_energy, "skill_cooldown": player.skill_timer,
			"guardian_cooldown": player.guardian_timer,
			"warden_ward": WardenAura.active_for(player, players, parties, world),
			"guardian_brace": player.guardian_brace,
			"dodge_cooldown": player.dodge_timer, "dodge_immunity": player.dodge_immunity,
			"rest_cooldown": player.rest_cooldown,
			"party_aid_cooldown": player.party_aid_timer, "party_feast_cooldown": player.feast_timer,
			"stim_cooldown": player.stim_cooldown,
			"weapon": player.inventory.weapon, "armor": player.inventory.armor,
			"visual_signature": Camouflage.visual_signature(
				player.inventory.armor, player.inventory.armor != "" and
				player.inventory.count(player.inventory.armor) > 0,
				player.noise_timer, _alive(player)),
			"last_death_full_loot": player.last_death_full_loot,
			"is_night": WorldCycle.is_night(time),
			"gathering_levels": player.progression.levels(), "crafting_level": player.progression.crafting_level(),
			"crafting_xp": player.progression.crafting_xp,
			"fishing_level": player.progression.gathering_level("fishing"),
			"scavenging_level": player.progression.scavenging_level(),
			"scavenging_xp": player.progression.scavenging_xp,
			"combat_levels": player.progression.combat_levels(),
			"contract": player.contract_state.duplicate(true),
			"daily_bounty": player.daily_bounty.duplicate(true),
			"daily_description": DailyBounties.description(player.daily_bounty, DailyBounties.utc_day()),
			"daily_utc_day": DailyBounties.utc_day(),
			"renown": player.renown,
			"renown_rank": Reputation.title(player.renown),
			"vendor_discount": Reputation.discount_percent(player.renown),
			"renown_next": Reputation.next_threshold(player.renown),
			"carry_kg": player.inventory.total_weight(),
			"cargo_factor": player.inventory.movement_factor(player.skills.bonus("carry_capacity")),
			"max_health": player.survival.max_health,
			"speed_bonus": player.skills.bonus("move_speed"), "carry_bonus": player.skills.bonus("carry_capacity"),
		},
		"players": nearby_players, "zombies": nearby_zombies, "bags": nearby_bags,
		"spit_zones": spit_zones,
		"barricades": nearby_barricades, "campfires": nearby_campfires,
		"decoys": nearby_decoys,
		"depleted": gone_nodes, "crates_used": used_crates,
	}
	# Send a ground telegraph only to survivors close enough to see it.
	# The server remains the sole authority on the slam center and deadline.
	if not raid_pending_slam.is_empty():
		var warning_at := Vector2(float(raid_pending_slam["x"]),
			float(raid_pending_slam["z"]))
		if here.distance_to(warning_at) <= Defs.INTEREST_RADIUS:
			snapshot["raid_telegraph"] = {"id": int(raid_pending_slam["id"]),
				"x": warning_at.x,
				"y": world.height_at(warning_at.x, warning_at.y),
				"z": warning_at.y, "radius": RaidEncounter.SLAM_RADIUS,
				"until": float(raid_pending_slam["at"])}
	# The skill sheet is small, but snapshots can be lost: resend it when it changed and every few seconds.
	if player.dirty_skills or time - player.skills_sent_at > SNAPSHOT_REPEAT_SECONDS:
		var sheet: Dictionary = player.skills.to_dict()
		sheet["points"] = player.skills.points_available()
		snapshot["skills"] = sheet
		player.skills_sent_at = time
		player.dirty_skills = false
	# Snapshots are unreliable, so a change that was reported once could be lost for good: repeat the
	# containers every few seconds as well as when they change.
	if player.dirty_inventory or time - player.inventory_sent_at > SNAPSHOT_REPEAT_SECONDS:
		snapshot["inventory"] = player.inventory.to_dict()
		player.dirty_inventory = false
		player.inventory_sent_at = time
	if player.dirty_stash or time - player.stash_sent_at > SNAPSHOT_REPEAT_SECONDS:
		snapshot["stash"] = player.stash.to_dict()
		player.dirty_stash = false
		player.stash_sent_at = time
	return snapshot
