extends RefCounted
## Chapter I is played against the actual authoritative server, persistence,
## physical ruin loot, real confirmed zombie kills, and owner-only replication.

const StoryCampaign = preload("res://scripts/shared/story_campaign.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at_hub(sim, player) -> void:
	var point: Vector2 = GameServer.WORKBENCH_POSITION
	player.position = Vector3(point.x, sim.world.height_at(point.x, point.y), point.y)


func _danger_cache(world) -> Dictionary:
	for cx in range(8, 30):
		for cz in range(0, 30):
			var chunk: Dictionary = world.chunk(Vector2i(cx, cz))
			if int(chunk.get("zone", -1)) < StoryCampaign.MIN_RUIN_ZONE:
				continue
			for crate in chunk["crates"]:
				var x: float = float(crate["x"])
				var z: float = float(crate["z"])
				if not bool(crate.get("sunken", false)) and not world.is_water(x, z):
					var confirmed: Dictionary = crate.duplicate(true)
					confirmed["zone"] = int(chunk["zone"])
					return confirmed
	return {}


func run(t) -> void:
	t.current = "Story Chapter I has strictly linear checkpoints and finite transcript"
	var fresh := StoryCampaign.empty_state()
	t.check(StoryCampaign.valid_state(fresh), "new character starts with valid unclaimed story")
	t.eq(StoryCampaign.public_state(fresh)["transcript"].size(), 1,
		"opening emergency broadcast is available without spoiling later logs")
	for reward in StoryCampaign.REWARD:
		t.check(Defs.is_item(str(reward)), "story reward is a registered real item")
	t.check(not StoryCampaign.valid_state({"stage": 4, "kills": 0}),
		"forged completed state without confirmed kills rejected")
	t.check(not StoryCampaign.valid_state({"stage": 3, "kills": 1}),
		"late stage with missing PvE evidence rejected")
	t.check(not StoryCampaign.valid_state({"stage": 2, "kills": 3}),
		"three kills always transition out of the defense milestone")
	t.check(not StoryCampaign.valid_state({"stage": 2.0, "kills": 0}),
		"fractional chapter checkpoints rejected during save validation")
	t.check(not StoryCampaign.valid_state({"stage": 1, "kills": 0, "extra": true}),
		"unknown save keys cannot bypass progression")
	t.eq(StoryCampaign.transmit(fresh, Inventory.new())["reason"], "incomplete",
		"radio reward cannot be claimed before hearing the call")
	t.check(StoryCampaign.listen(fresh)["ok"], "hearing emergency call starts Chapter I")
	t.eq(StoryCampaign.listen(fresh)["reason"], "already_heard",
		"repeated listen requests cannot rewind a started chapter")
	t.check(not StoryCampaign.record_ruin_cache(fresh, -1, 3),
		"negative fake cache IDs never count")
	t.check(not StoryCampaign.record_ruin_cache(fresh, 990, 1),
		"safe and yellow zone caches are not proof of the quarantine lab")
	t.check(not StoryCampaign.record_infected_kill(fresh),
		"kills before recovering Dr. Voss's log do not count")
	t.check(StoryCampaign.record_ruin_cache(fresh, 990, 2),
		"one verified red-zone cache reveals the field log")
	t.eq(fresh["stage"], 2, "defense chapter starts after the clue")
	t.eq(StoryCampaign.public_state(fresh)["transcript"].size(), 3,
		"new journal entry unlocks only after real story checkpoint")
	t.check(not StoryCampaign.record_ruin_cache(fresh, 990, 3),
		"same and subsequent crates cannot replay a one-time story milestone")
	t.check(StoryCampaign.record_infected_kill(fresh), "first infected contributes one kill")
	t.check(StoryCampaign.record_infected_kill(fresh), "second infected contributes one kill")
	t.eq(StoryCampaign.transmit(fresh, Inventory.new())["reason"], "incomplete",
		"two kills are not enough to forge story resolution")
	t.check(StoryCampaign.record_infected_kill(fresh), "third infected reveals coordinates")
	t.eq(fresh["stage"], 3, "return-to-radio stage unlocks at exactly three kills")
	t.check(not StoryCampaign.record_infected_kill(fresh), "later kills cannot duplicate chapter progress")

	t.current = "Story completion reward is atomic under full inventory"
	var single_slot := Inventory.new(1)
	single_slot.add("club_1", 1)
	var packed: Dictionary = single_slot.to_dict()
	t.eq(StoryCampaign.transmit(fresh, single_slot)["reason"], "no_space",
		"cannot complete chapter with an entirely full backpack")
	t.eq(single_slot.to_dict(), packed, "no partial silver or ammo paid on failed claim")
	t.eq(fresh["stage"], 3, "full backpack does not consume the story finale")
	var rewards := Inventory.new()
	var finish: Dictionary = StoryCampaign.transmit(fresh, rewards)
	t.check(finish.get("ok", false), "radio transmission releases one earned reward")
	for item_id in StoryCampaign.REWARD:
		t.eq(rewards.count(str(item_id)), int(StoryCampaign.REWARD[item_id]),
			"radio awards exact real item quantity: " + str(item_id))
	t.eq(fresh["stage"], StoryCampaign.LAST_STAGE, "saved ending marks chapter completed")
	t.eq(StoryCampaign.transmit(fresh, rewards)["reason"], "already_complete",
		"replayed transmission cannot mint a second reward")
	t.eq(StoryCampaign.public_state(fresh)["transcript"].size(), 5,
		"epilogue reveals the underground beacon, not another immediate payout")

	t.current = "Real server radio commands validate player and workbench position"
	var world := WorldGen.new(3100)
	var sim := GameServer.new(world, 3100)
	var survivor = sim.add_player(4501, "Survivor")
	var bystander = sim.add_player(4502, "Bystander")
	survivor.position = Vector3(120, world.height_at(120, 120), 120)
	t.eq(sim.cmd_story(9999, "listen")["reason"], "dead",
		"unregistered peers cannot force an emergency transmission")
	t.eq(sim.cmd_story(survivor.id, "listen")["reason"], "no_station",
		"radio is physically available only near a real workbench")
	_at_hub(sim, survivor)
	t.eq(sim.cmd_story(survivor.id, "force_complete")["reason"], "unknown_action",
		"clients cannot invent server story stages or rewards")
	t.eq(sim.cmd_story(survivor.id, "transmit")["reason"], "incomplete",
		"workbench cannot grant unearned chapter reward")
	t.check(sim.cmd_story(survivor.id, "listen")["ok"],
		"genuine hub transmission starts the same persistent chapter")
	t.eq(sim.cmd_story(survivor.id, "listen")["reason"], "already_heard",
		"server prevents repeated introductory broadcasts")
	t.eq(sim.snapshot_for(survivor.id)["you"]["story"]["stage"], 1,
		"client sees its current mission in private player snapshot")
	t.eq(sim.snapshot_for(bystander.id)["you"]["story"]["stage"], 0,
		"other survivors never inherit another character's discovered chapter")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	var found_private_event := false
	for evt in sim.events:
		if str(evt.get("type", "")) == "story":
			found_private_event = true
			t.check(net._event_visible_to(evt, survivor.id),
				"owner receives recovered radio logs")
			t.check(not net._event_visible_to(evt, bystander.id),
				"other players cannot spy on a story transcript")
	t.check(found_private_event, "starting the chapter creates a private story event")
	net.free()

	t.current = "Only physical server-confirmed dangerous ruin loot unlocks evidence"
	var cache: Dictionary = _danger_cache(world)
	t.check(not cache.is_empty(), "generated world has a valid danger-zone ruin")
	if cache.is_empty():
		return
	var cache_id: int = int(cache["id"])
	var px: float = float(cache["x"])
	var pz: float = float(cache["z"])
	survivor.position = Vector3(px, world.height_at(px, pz), pz)
	t.eq(sim.cmd_loot(survivor.id, -7)["reason"], "nothing_there",
		"client cannot submit a fabricated evidence cache")
	t.eq(survivor.story_state["stage"], 1, "failed loot does not advance plot")
	var result: Dictionary = sim.cmd_loot(survivor.id, cache_id)
	t.check(bool(result.get("ok", false)), "actual unopened dangerous ruin yields loot")
	if not bool(result.get("ok", false)):
		return
	t.eq(survivor.story_state["stage"], 2, "real physical loot unlocks recovered log")
	t.eq(sim.cmd_loot(survivor.id, cache_id)["reason"], "empty",
		"replayed crate loot is refused before story evidence could be awarded again")

	t.current = "Confirmed lethal PvE attacks advance the chapter and persist"
	for i in range(3):
		var target := Zombie.new(sim.new_id(), "walker",
			survivor.position + Vector3(5.0 + i, 0.0, 0.0))
		sim.zombies[target.id] = target
		sim._damage_target(survivor, {"kind": "zombie", "id": target.id}, 1000.0)
		t.eq(int(survivor.story_state["kills"]), i + 1,
			"only actual server death counts one infected carrier")
		if i == 0:
			var halfway: Dictionary = sim.character_data(survivor)
			t.check(sim.valid_character_data(halfway), "Nakama save validates recovered clue and first kill")
			var backup := GameServer.new(WorldGen.new(3100), 3100)
			var recovered = backup.add_player(9501, "Recovered", "", halfway)
			t.eq(recovered.story_state, survivor.story_state,
				"real login checkpoint survives save and restart")
	t.eq(int(survivor.story_state["stage"]), 3,
		"three lethal encounters reveal the final relay coordinates")
	t.eq(sim.cmd_story(survivor.id, "transmit")["reason"], "no_station",
		"final mission cannot be claimed remotely from ruins")
	_at_hub(sim, survivor)
	var server_finish: Dictionary = sim.cmd_story(survivor.id, "transmit")
	t.check(bool(server_finish.get("ok", false)), "return to hub completes story chapter")
	if not bool(server_finish.get("ok", false)):
		return
	t.eq(survivor.story_state["stage"], 4, "completed story checkpoint recorded")
	t.eq(survivor.inventory.count("silver"), 90,
		"one confirmed story payout adds the exact silver reward")
	t.eq(sim.cmd_story(survivor.id, "transmit")["reason"], "already_complete",
		"network request replay cannot create another reward")
	t.eq(survivor.inventory.count("silver"), 90,
		"completed chapter never pays twice")
	var saved: Dictionary = sim.character_data(survivor)
	t.check(sim.valid_character_data(saved), "completed story and reward serialize")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("story")
	var old_world := GameServer.new(WorldGen.new(3100), 3100)
	var old_player = old_world.add_player(8501, "Legacy", "", legacy)
	t.eq(old_player.story_state, StoryCampaign.empty_state(),
		"characters created before this feature start at Chapter I without losing saves")
	var forged: Dictionary = saved.duplicate(true)
	forged["story"] = {"stage": 4, "kills": 0}
	t.check(not sim.valid_character_data(forged),
		"forged completed story journal is refused by account save validation")
