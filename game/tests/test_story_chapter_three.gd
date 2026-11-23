extends RefCounted
## Chapter III: narrative branch continuity, authoritative danger caches and
## caravan completion, private replication, replay protection and save/load.

const ChapterOne = preload("res://scripts/shared/story_campaign.gd")
const ChapterTwo = preload("res://scripts/shared/story_chapter_two.gd")
const ChapterThree = preload("res://scripts/shared/story_chapter_three.gd")
const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Net = preload("res://scripts/shared/net.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


func _at(world, player, x: float, z: float) -> void:
	player.position = Vector3(x, world.height_at(x, z), z)


func _hub(world, player) -> void:
	var station: Vector2 = GameServer.WORKBENCH_POSITION
	_at(world, player, station.x, station.y)


func _danger_cache(world) -> Dictionary:
	for cx in range(8, 30):
		for cz in range(0, 30):
			var chunk: Dictionary = world.chunk(Vector2i(cx, cz))
			if int(chunk.get("zone", -1)) < ChapterThree.MIN_MANIFEST_ZONE:
				continue
			for crate in chunk["crates"]:
				var x: float = float(crate["x"])
				var z: float = float(crate["z"])
				if not bool(crate.get("sunken", false)) and not bool(crate.get("dungeon", false)) \
						and not world.is_water(x, z):
					return crate.duplicate(true)
	return {}


func _merchant_source(world) -> Dictionary:
	for rx in range(-4, 5):
		for rz in range(-4, 5):
			for site in world.poi.sites_in_region(rx, rz):
				if not CaravanRoutes.offer_for(world, site).is_empty():
					return site
	return {}


func run(t) -> void:
	t.current = "Chapter III states reject forged branches and keep earlier ending"
	var fresh: Dictionary = ChapterThree.empty_state()
	t.check(ChapterThree.valid_state(fresh), "new character has valid unclaimed Chapter III")
	t.eq(ChapterThree.public_state(fresh)["transcript"].size(), 1,
		"teaser is visible without leaking the convoy's evidence")
	for bad in [
		{"stage": -1, "source": "", "ending": ""},
		{"stage": 1.0, "source": "seal", "ending": ""},
		{"stage": 1, "source": "", "ending": ""},
		{"stage": 2, "source": "untrusted", "ending": ""},
		{"stage": 3, "source": "seal", "ending": "guide"},
		{"stage": 4, "source": "seal", "ending": ""},
		{"stage": 4, "source": "broadcast", "ending": "fake"},
		{"stage": 4, "source": "broadcast", "ending": "mask", "silver": 9999},
	]:
		t.check(not ChapterThree.valid_state(bad), "invalid source, stage or premature finale rejected")
	for reward in [ChapterThree.GUIDE_REWARD, ChapterThree.MASK_REWARD]:
		for item_id in reward:
			t.check(Defs.is_item(str(item_id)), "chapter reward uses a real item: " + str(item_id))
	t.eq(ChapterThree.begin(fresh, "faked")["reason"], "invalid_previous_ending",
		"chapter can only inherit an authentic Chapter II branch")
	t.eq(ChapterThree.resolve(fresh, Inventory.new(), "guide")["reason"], "incomplete",
		"early finale never pays out")
	t.check(ChapterThree.begin(fresh, "seal")["ok"], "completed seal branch opens third chapter")
	t.eq(fresh["source"], "seal", "old decision becomes permanent Chapter III source")
	t.eq(ChapterThree.begin(fresh, "broadcast")["reason"], "already_started",
		"restarting cannot rewrite the inherited story decision")
	t.check(ChapterThree.current_line(fresh).contains("AFTER THE SEAL"),
		"sealed branch has a unique follow-up recording")
	t.check(not ChapterThree.record_manifest(fresh, -5, 3), "fake crate ID does not count")
	t.check(not ChapterThree.record_manifest(fresh, 77, 1), "safe-area crate does not count")
	t.check(not ChapterThree.record_delivery(fresh), "delivery cannot skip the manifest")
	t.check(ChapterThree.record_manifest(fresh, 77, 2), "real dangerous manifest advances")
	t.check(not ChapterThree.record_manifest(fresh, 77, 2), "same or later cache cannot replay")
	t.eq(fresh["stage"], 2, "after manifest, survivor needs a real caravan delivery")
	t.check(ChapterThree.record_delivery(fresh), "verified delivery restores convoy waypoint")
	t.check(not ChapterThree.record_delivery(fresh), "a second delivery earns nothing")
	t.eq(ChapterThree.public_state(fresh)["transcript"].size(), 4,
		"radio journal includes exactly the unlocked lead, evidence and waypoint")

	t.current = "Chapter III finale is exclusive and inventory-atomic"
	var full := Inventory.new(1)
	full.add("club_1", 1)
	var before: Dictionary = full.to_dict()
	t.eq(ChapterThree.resolve(fresh, full, "mask")["reason"], "no_space",
		"failed reward does not consume the player's choice")
	t.eq(full.to_dict(), before, "no partial reward with full backpack")
	t.eq(fresh["stage"], 3, "full backpack preserves the choice stage")
	var bag := Inventory.new()
	var result: Dictionary = ChapterThree.resolve(fresh, bag, "guide")
	t.check(bool(result.get("ok", false)), "guide choice completes the third chapter")
	for item_id in ChapterThree.GUIDE_REWARD:
		t.eq(bag.count(str(item_id)), int(ChapterThree.GUIDE_REWARD[item_id]),
			"exact one-time guide reward: " + str(item_id))
	t.check(ChapterThree.current_line(fresh).contains("GUIDANCE SENT"),
		"silence-to-guide branch reveals its epilogue")
	t.eq(ChapterThree.resolve(fresh, bag, "mask")["reason"], "already_complete",
		"ending cannot be switched to harvest alternate reward")
	t.eq(ChapterThree.public_state(fresh)["transcript"].size(), 5,
		"epilogue appears only after the one successful finale")
	var other_state: Dictionary = ChapterThree.empty_state()
	t.check(ChapterThree.begin(other_state, "broadcast")["ok"],
		"broadcast branch independently begins")
	other_state["stage"] = 3
	var alternate: Dictionary = ChapterThree.resolve(other_state, Inventory.new(), "mask")
	t.check(bool(alternate.get("ok", false)), "broadcast-to-mask is a supported distinct ending")
	t.check(str(alternate["line"]) != ChapterThree.current_line(fresh),
		"source plus final choice produce meaningfully different epilogues")

	t.current = "Real server requires workbench and a completed Chapter II choice"
	var world := WorldGen.new(205)
	var sim := GameServer.new(world, 205)
	var survivor = sim.add_player(1301, "Courier")
	var bystander = sim.add_player(1302, "Listener")
	_hub(world, survivor)
	_hub(world, bystander)
	t.eq(sim.cmd_story(survivor.id, "trace")["reason"], "chapter_two_incomplete",
		"Chapter III locked until a real saved Chapter II ending")
	survivor.story_state = {"stage": ChapterOne.LAST_STAGE, "kills": ChapterOne.REQUIRED_KILLS}
	survivor.story2_state = {"stage": ChapterTwo.LAST_STAGE, "ending": "broadcast"}
	_at(world, survivor, 120.0, 120.0)
	t.eq(sim.cmd_story(survivor.id, "trace")["reason"], "no_station",
		"third signal is physically restricted to a workbench")
	_hub(world, survivor)
	t.eq(sim.cmd_story(survivor.id, "guide")["reason"], "incomplete",
		"an unearned Chapter III reward cannot be claimed")
	t.check(sim.cmd_story(survivor.id, "trace")["ok"],
		"workbench and previous ending unlock the new chapter")
	t.eq(survivor.story3_state["source"], "broadcast",
		"server captures branch from Chapter II, not a client argument")
	t.check(ChapterThree.current_line(survivor.story3_state).contains("AFTER THE BROADCAST"),
		"broadcast choices affect the actual third-chapter introduction")
	t.eq(sim.snapshot_for(survivor.id)["you"]["story3"]["stage"], 1,
		"owner receives their third journal")
	t.eq(sim.snapshot_for(bystander.id)["you"]["story3"], {},
		"unqualified observer sees no private chapter")
	t.eq(sim.cmd_story(survivor.id, "trace")["reason"], "already_started",
		"repeat signal cannot reset progress")

	t.current = "A verified world loot and a paid NPC caravan are required"
	var cache: Dictionary = _danger_cache(world)
	t.check(not cache.is_empty(), "procedural red/black zone has a physical ruin cache")
	if cache.is_empty():
		return
	var cx: float = float(cache["x"])
	var cz: float = float(cache["z"])
	_at(world, survivor, cx, cz)
	t.eq(sim.cmd_loot(survivor.id, -77)["reason"], "nothing_there",
		"fabricated loot request cannot advance third chapter")
	t.eq(survivor.story3_state["stage"], 1, "rejected loot does not reveal manifest")
	var loot: Dictionary = sim.cmd_loot(survivor.id, int(cache["id"]))
	t.check(bool(loot.get("ok", false)), "genuine unopened cache is looted")
	if not bool(loot.get("ok", false)):
		return
	t.eq(survivor.story3_state["stage"], 2,
		"only real dangerous surface cache recovers the missing manifest")
	t.eq(sim.cmd_loot(survivor.id, int(cache["id"]))["reason"], "empty",
		"repeated crate RPC never replays the milestone")

	var source: Dictionary = _merchant_source(world)
	t.check(not source.is_empty(), "actual merchant route exists")
	if source.is_empty():
		return
	_at(world, survivor, float(source["station_x"]), float(source["station_z"]))
	t.eq(sim.cmd_caravan(survivor.id, "deliver")["reason"], "no_active",
		"missing caravan is not a narrative shortcut")
	var accepted: Dictionary = sim.cmd_caravan(survivor.id, "accept")
	t.check(bool(accepted.get("ok", false)), "NPC offers a real merchant convoy")
	if not bool(accepted.get("ok", false)):
		return
	t.eq(survivor.story3_state["stage"], 2, "accepting alone does not count")
	var route: Dictionary = accepted["route"]
	_at(world, survivor, float(route["dst_x"]), float(route["dst_z"]))
	t.eq(sim.cmd_caravan(survivor.id, "deliver")["reason"], "missing_cargo",
		"arrival without goods does not advance the story")
	t.eq(survivor.story3_state["stage"], 2, "unpaid delivery does not count")
	survivor.inventory.add(str(route["cargo"]), CaravanRoutes.CARGO_COUNT)
	var delivery: Dictionary = sim.cmd_caravan(survivor.id, "deliver")
	t.check(bool(delivery.get("ok", false)), "real supplied delivery succeeds")
	if not bool(delivery.get("ok", false)):
		return
	t.eq(survivor.story3_state["stage"], 3,
		"paid cargo delivery restores the mission's safe route")
	t.eq(sim.cmd_caravan(survivor.id, "deliver")["reason"], "no_active",
		"duplicate delivery does not re-advance the story")

	t.current = "Private events, atomic saves and chapter inheritance survive reload"
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	var third_events := 0
	for event in sim.events:
		if str(event.get("type", "")) == "story3":
			third_events += 1
			t.check(net._event_visible_to(event, survivor.id),
				"owner receives Chapter III milestone")
			t.check(not net._event_visible_to(event, bystander.id),
				"other peers cannot see private voice recordings")
	t.check(third_events >= 3, "trace, discovery and delivery emit private milestones")
	net.free()
	var save: Dictionary = sim.character_data(survivor)
	t.check(sim.valid_character_data(save), "real midchapter character state is valid")
	var tampered: Dictionary = save.duplicate(true)
	tampered["story3"]["source"] = "seal"
	t.check(not sim.valid_character_data(tampered),
		"Chapter III cannot contradict the permanent earlier ending")
	tampered = save.duplicate(true)
	tampered["story2"] = ChapterTwo.empty_state()
	t.check(not sim.valid_character_data(tampered),
		"progress is invalid if previous chapter was never completed")
	var restored := GameServer.new(WorldGen.new(205), 205)
	var from_save = restored.add_player(1399, "Returned Courier", "", save)
	t.eq(from_save.story3_state, survivor.story3_state,
		"third chapter branch and discovered milestones survive account restore")
	var legacy: Dictionary = save.duplicate(true)
	legacy.erase("story3")
	t.check(restored.valid_character_data(legacy),
		"legacy Chapter II saves without Chapter III still load")
	_hub(world, survivor)
	var finale: Dictionary = sim.cmd_story(survivor.id, "mask")
	t.check(bool(finale.get("ok", false)), "real workbench commits permanent final branch")
	t.eq(survivor.story3_state["ending"], "mask", "server persists the final decision")
	t.eq(sim.cmd_story(survivor.id, "guide")["reason"], "already_complete",
		"the alternate ending cannot mint a second reward")
	var final_save: Dictionary = sim.character_data(survivor)
	t.check(sim.valid_character_data(final_save), "final saved Chapter III passes validation")
	var survivor_reloaded = restored.add_player(1400, "Last Receiver", "", final_save)
	t.eq(survivor_reloaded.story3_state, survivor.story3_state,
		"finished third chapter and exclusive ending persist across sessions")
