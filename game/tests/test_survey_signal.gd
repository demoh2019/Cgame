extends RefCounted
## Confirmed mineral veins may be shared with the squad only after a paid,
## authenticated private survey. Never expose server resource IDs to outsiders.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Prospecting = preload("res://scripts/shared/prospecting_chart.gd")
const SurveySignal = preload("res://scripts/shared/survey_signal.gd")
const Party = preload("res://scripts/shared/party.gd")
const ExpeditionAtlas = preload("res://scripts/shared/expedition_atlas.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


func _vein(world) -> Dictionary:
	for cx in range(8, 18):
		for cz in range(0, 15):
			var nodes: Array = world.chunk(Vector2i(cx, cz))["nodes"]
			for node in nodes:
				if str(node["kind"]) in ["ore", "rock"] and int(node["tier"]) >= 2:
					return node
	return {}


func _near(world, node: Dictionary, offset: float = 0.0) -> Vector3:
	var x: float = float(node["x"]) + offset
	var z: float = float(node["z"])
	return Vector3(x, world.height_at(x, z), z)


func _node_by_id(world, player, sought_id: int) -> Dictionary:
	var cell := WorldGen.cell_of(player.position.x, player.position.z)
	for node in world.chunk(cell)["nodes"]:
		if int(node["id"]) == sought_id:
			return node
	return {}


func run(t) -> void:
	t.current = "field-craftable mineral signal has an actual material cost"
	t.eq(Defs.item(SurveySignal.ITEM_ID).get("kind", ""), "survey_signal",
		"signal is a distinct consumable, not a general GPS location forge")
	var recipe: Dictionary = Defs.recipes().get(SurveySignal.ITEM_ID, {})
	t.eq(recipe.get("station", "missing"), "", "cooperative signal can be crafted on an expedition")
	t.eq(recipe.get("inputs", {}), {"scrap": 2, "cloth_1": 1, "charcoal_filter": 1},
		"signal requires real salvage and a crafted filter")
	var backpack := Inventory.new()
	backpack.add("scrap", 2)
	backpack.add("cloth_1", 1)
	t.eq(Crafting.craft(backpack, SurveySignal.ITEM_ID, false),
		Crafting.Result.MISSING_INPUTS, "missing filter cannot create a free signal")
	t.eq(backpack.count("scrap"), 2, "failed craft does not consume resources")
	backpack.add("charcoal_filter", 1)
	t.eq(Crafting.craft(backpack, SurveySignal.ITEM_ID, false),
		Crafting.Result.OK, "all field materials craft a real signal")
	t.eq(backpack.count(SurveySignal.ITEM_ID), 1, "single-use signal enters backpack")

	t.current = "real server-only survey required before anyone can announce mineral target"
	var world := WorldGen.new(3141)
	var vein: Dictionary = _vein(world)
	t.check(not vein.is_empty(), "seeded world generates high-tier mining targets")
	if vein.is_empty():
		return
	var server := GameServer.new(world, 3141)
	var leader = server.add_player(771, "Leader")
	var scout = server.add_player(772, "Surveyor")
	var outsider = server.add_player(773, "Unaffiliated")
	leader.position = _near(world, vein, 1.0)
	scout.position = _near(world, vein, 2.0)
	outsider.position = _near(world, vein, 3.0)
	t.eq(server.cmd_use(scout.id, SurveySignal.ITEM_ID).get("reason", ""), "not_carried",
		"missing physical signal is immediately rejected")
	scout.inventory.add(SurveySignal.ITEM_ID, 3)
	t.eq(server.cmd_use(scout.id, SurveySignal.ITEM_ID).get("reason", ""), "no_active_survey",
		"cartography cannot skip the paid geological scan")
	t.eq(scout.inventory.count(SurveySignal.ITEM_ID), 3,
		"failed attempt never consumes signal")
	scout.inventory.add(Prospecting.ITEM_ID, 1)
	var scan: Dictionary = server.cmd_use(scout.id, Prospecting.ITEM_ID)
	t.check(bool(scan.get("ok", false)), "verified real server-side ore prospecting succeeds")
	if not bool(scan.get("ok", false)):
		return
	var mark: Dictionary = scout.prospect_mark.duplicate(true)
	t.check(Prospecting.active(mark, server.time, server.depleted),
		"scan marker has a live unique resource ID and deadline")
	t.eq(server.cmd_use(scout.id, SurveySignal.ITEM_ID).get("reason", ""), "not_in_party",
		"lone survivor cannot publish personal exploration discoveries")
	t.check(bool(server.cmd_party_invite(leader.id, scout.id).get("ok", false)),
		"nearby leader can invite a surveyor")
	t.eq(server.cmd_use(scout.id, SurveySignal.ITEM_ID).get("reason", ""),
		"need_party", "unaccepted invitation is not a group membership")
	t.check(bool(server.cmd_party_accept(scout.id).get("ok", false)),
		"real teammate accepts the authenticated invitation")

	t.current = "paid group signal reuses rate-limited group ping without public disclosure"
	scout.attack_timer = 0.4
	t.eq(server.cmd_use(scout.id, SurveySignal.ITEM_ID).get("reason", ""), "in_combat",
		"cannot send a paid signal while actively attacking")
	scout.attack_timer = 0.0
	var first: Dictionary = server.cmd_use(scout.id, SurveySignal.ITEM_ID)
	t.check(bool(first.get("ok", false)) and bool(first.get("survey_signal", false)),
		"valid group broadcast succeeds through server-owned item use")
	t.eq(scout.inventory.count(SurveySignal.ITEM_ID), 2,
		"one successful broadcast consumes exactly one signal kit")
	t.check(scout.dirty_inventory and scout.dirty_character,
		"paid inventory changes are queued for save")
	var leader_view: Dictionary = server.snapshot_for(leader.id)["you"]["party"]["ping"]
	var author_view: Dictionary = server.snapshot_for(scout.id)["you"]["party"]["ping"]
	t.eq(leader_view, author_view, "all authenticated allies see the same verified target")
	t.eq(leader_view.get("kind", ""), "survey", "group pin identifies an actual mineral signal")
	t.eq(leader_view.get("material", ""), mark["kind"], "no client can claim an unrelated material")
	t.eq(leader_view.get("tier", -1), mark["tier"], "squad sees authoritative vein tier")
	t.eq(float(leader_view.get("x", INF)), float(mark["x"]),
		"squad marker uses scanned server coordinate")
	t.eq(float(leader_view.get("z", INF)), float(mark["z"]),
		"squad marker targets real world z")
	t.eq(int(leader_view.get("by", -1)), scout.id, "source identity is verified member")
	t.check(not leader_view.has("node_id") and not leader_view.has("until") and (
			not leader_view.has("source")), "server node ID and absolute deadline never leave backend")
	t.near(float(leader_view.get("remaining", 0.0)), Party.PING_SECONDS, 0.001,
		"party signal is temporary and cannot exceed the shared ping clock")
	t.eq(server.snapshot_for(outsider.id)["you"]["party"]["ping"], {},
		"nearby unaffiliated players learn no rich deposit coordinates")
	for actor in server.snapshot_for(outsider.id)["players"]:
		t.check(not actor.has("prospect_mark") and not actor.has("survey_signal"),
			"public actor snapshots do not expose personal surveys")
	t.eq(ExpeditionAtlas.find(ExpeditionAtlas.objectives(
		server.snapshot_for(leader.id)["you"]), "ping").get("label", ""),
		"T%d %s PARTY VEIN" % [int(mark["tier"]), str(mark["kind"]).to_upper()],
		"full-island atlas displays material tier to group members")
	var radar := Radar.new()
	radar.sim = server
	radar.actor_id = leader.id
	t.eq(radar.current_party_ping(), leader_view, "party radar uses the same private group marker")
	radar.actor_id = outsider.id
	t.eq(radar.current_party_ping(), {}, "non-party radar never sees the signal")
	radar.free()
	t.eq(server.cmd_use(scout.id, SurveySignal.ITEM_ID).get("reason", ""), "cooldown",
		"spam cannot bypass the shared party ping rate limiter")
	t.eq(scout.inventory.count(SurveySignal.ITEM_ID), 2,
		"cooldown keeps subsequent signal inventory intact")

	t.current = "scans near expiry cannot produce an extended group signal"
	server.time += Party.PING_COOLDOWN + 0.1
	scout.prospect_mark["until"] = server.time + 2.0
	var short: Dictionary = server.cmd_use(scout.id, SurveySignal.ITEM_ID)
	t.check(bool(short.get("ok", false)), "valid near-expiry scan may be reported")
	t.near(float(short.get("seconds", 0.0)), 2.0, 0.001,
		"paid group pin cannot outlive the underlying private chart")
	t.eq(scout.inventory.count(SurveySignal.ITEM_ID), 1, "second real broadcast consumes one kit")
	server.time += 2.1
	t.eq(server.snapshot_for(leader.id)["you"]["party"]["ping"], {},
		"expired chart deadline also expires the shared group pin")
	t.eq(server.snapshot_for(outsider.id)["you"]["party"]["ping"], {},
		"expired signal cannot leak old locations to outsiders")

	t.current = "real mining by another party member immediately clears the beacon"
	server.time += Party.PING_COOLDOWN + 0.1
	scout.prospect_mark["until"] = server.time + 20.0
	t.check(bool(server.cmd_use(scout.id, SurveySignal.ITEM_ID).get("ok", false)),
		"new legitimate broadcast refreshes squad destination")
	var active_id: int = int(mark["id"])
	var selected: Dictionary = {}
	for cx in range(-1, 2):
		for cz in range(-1, 2):
			var chunk: Dictionary = world.chunk(
				WorldGen.cell_of(float(mark["x"]), float(mark["z"])) + Vector2i(cx, cz))
			for node in chunk["nodes"]:
				if int(node["id"]) == active_id:
					selected = node
	t.check(not selected.is_empty(), "only a real generated deposit is harvestable")
	if selected.is_empty():
		return
	leader.position = _near(world, selected)
	leader.inventory.add("pickaxe_4", 1)
	leader.progression.gathering_xp["ore"] = 500
	leader.progression.gathering_xp["stone"] = 500
	t.check(bool(server.cmd_gather(leader.id, active_id).get("ok", false)),
		"teammate begins gathering the actual signalled deposit")
	server._finish_gather(leader, selected)
	t.check(server.depleted.has(active_id), "server marks mined node depleted")
	t.eq(server.snapshot_for(scout.id)["you"]["party"]["ping"], {},
		"successful mining immediately removes the obsolete shared marker")
	t.eq(server.snapshot_for(leader.id)["you"]["party"]["ping"], {},
		"leader cannot follow an already exhausted ore deposit")
	t.eq(server.snapshot_for(outsider.id)["you"]["party"]["ping"], {},
		"outsider remains isolated after the deposit is mined")
