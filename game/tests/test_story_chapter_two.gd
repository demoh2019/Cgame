extends RefCounted
## Regression for Chapter II with live server dungeon transitions, loot,
## boss death, mutually exclusive endings, save/reload and event isolation.

const ChapterOne = preload("res://scripts/shared/story_campaign.gd")
const ChapterTwo = preload("res://scripts/shared/story_chapter_two.gd")
const Dungeon = preload("res://scripts/shared/dungeon.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Net = preload("res://scripts/shared/net.gd")


func _hub(world, actor) -> void:
	var site: Vector2 = GameServer.WORKBENCH_POSITION
	actor.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)


func _bunker(world) -> Dictionary:
	for rx in range(-10, 11):
		for rz in range(-10, 11):
			var bunker: Dictionary = world.dungeon_bunker(Vector2i(rx, rz))
			if not bunker.is_empty():
				return bunker
	return {}


func _dungeon_content(world, region: Vector2i) -> Dictionary:
	var chest: Dictionary = {}
	var boss: Dictionary = {}
	var encountered: Dictionary = {}
	for room in Dungeon.layout(world.world_seed, region)["rooms"]:
		var center: Vector2 = Dungeon.room_center(region, room)
		var cell: Vector2i = WorldGen.cell_of(center.x, center.y)
		if encountered.has(cell):
			continue
		encountered[cell] = true
		var chunk: Dictionary = world.chunk(cell)
		if chest.is_empty() and not chunk["crates"].is_empty():
			chest = chunk["crates"][0].duplicate(true)
		for candidate in chunk["spawns"]:
			if bool(candidate.get("dungeon_boss", false)):
				boss = candidate.duplicate(true)
	return {"chest": chest, "boss": boss}


func _champion(spawn: Dictionary, sim):
	var enemy := Zombie.new(sim.new_id(), str(spawn["type"]),
		Vector3(float(spawn["x"]), Dungeon.FLOOR_Y, float(spawn["z"])),
		int(spawn["id"]))
	enemy.become_elite()
	enemy.set_meta("_story_dungeon_guardian", true) # Same server-only tag as population spawn.
	sim.zombies[enemy.id] = enemy
	return enemy


func run(t) -> void:
	t.current = "Chapter II independent strict saved state and mutually exclusive endings"
	var state: Dictionary = ChapterTwo.empty_state()
	t.check(ChapterTwo.valid_state(state), "new chapter state is strictly valid")
	t.eq(ChapterTwo.public_state(state)["transcript"].size(), 1,
		"unstarted story never leaks deeper unrecovered recordings")
	for reward in [ChapterTwo.SEAL_REWARD, ChapterTwo.BROADCAST_REWARD]:
		for item_id in reward:
			t.check(Defs.is_item(str(item_id)), "branch reward is a real item")
	for bad in [
		{"stage": -1, "ending": ""},
		{"stage": 6, "ending": ""},
		{"stage": 1.0, "ending": ""},
		{"stage": 4, "ending": "seal"},
		{"stage": 5, "ending": ""},
		{"stage": 5, "ending": "replay"},
		{"stage": 5, "ending": "seal", "coins": 9999},
	]:
		t.check(not ChapterTwo.valid_state(bad), "invalid or forged stage/branch is refused")
	t.eq(ChapterTwo.resolve(state, Inventory.new(), "broadcast")["reason"], "incomplete",
		"unstarted chapter cannot pay the ending")
	t.check(ChapterTwo.begin(state)["ok"], "server-checked decoding starts new story")
	t.eq(ChapterTwo.begin(state)["reason"], "already_started",
		"players cannot replay the starting broadcast")
	t.eq(ChapterTwo.resolve(state, Inventory.new(), "seal")["reason"], "incomplete",
		"early seal cannot skip the underworld")
	t.check(ChapterTwo.record_descent(state), "verified hatch advances to dungeon objective")
	t.check(not ChapterTwo.record_descent(state), "re-entering a hatch cannot count twice")
	t.check(not ChapterTwo.record_underground_cache(state, -1), "fake chest IDs rejected")
	t.check(ChapterTwo.record_underground_cache(state, 515151), "confirmed chest opens vault recording")
	t.check(not ChapterTwo.record_underground_cache(state, 515151), "second chest cannot replay checkpoint")
	t.check(ChapterTwo.record_guardian(state), "confirmed deepest-room guardian opens final choice")
	t.check(not ChapterTwo.record_guardian(state), "no second guardian credit after stage four")
	var no_room := Inventory.new(1)
	no_room.add("club_1", 1)
	var before: Dictionary = no_room.to_dict()
	t.eq(ChapterTwo.resolve(state, no_room, "seal")["reason"], "no_space",
		"full inventory rejects branch completion without side effects")
	t.eq(no_room.to_dict(), before, "full bag doesn't receive partial reward")
	t.eq(int(state["stage"]), 4, "failed finale leaves branch unlocked")
	var carried := Inventory.new()
	var ending: Dictionary = ChapterTwo.resolve(state, carried, "seal")
	t.check(bool(ending.get("ok", false)), "seal ending can be committed once")
	t.eq(state["ending"], "seal", "choice persists in the chapter journal")
	t.check(ChapterTwo.current_line(state).contains("SIGNAL SEALED"),
		"silence branch unlocks its own exclusive epilogue")
	for item_id in ChapterTwo.SEAL_REWARD:
		t.eq(carried.count(str(item_id)), int(ChapterTwo.SEAL_REWARD[item_id]),
			"seal choice grants exact earned item quantity")
	t.eq(ChapterTwo.resolve(state, carried, "broadcast")["reason"], "already_complete",
		"ending cannot be reversed to farm alternate rewards")
	t.eq(ChapterTwo.public_state(state)["transcript"].size(), 6,
		"only completed chapter reveals its final branch-specific log")
	var alternate: Dictionary = {"stage": 4, "ending": ""}
	var other_bag := Inventory.new()
	t.check(ChapterTwo.resolve(alternate, other_bag, "broadcast")["ok"],
		"independent survivor may choose truth over silence")
	t.check(ChapterTwo.current_line(alternate).contains("TRUTH BROADCAST"),
		"broadcast branch has a distinct narrative outcome")
	t.check(ChapterTwo.current_line(alternate) != ChapterTwo.current_line(state),
		"each ending is meaningfully different")

	t.current = "Actual authenticated workbench decoding requires Chapter I"
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 42)
	var survivor = sim.add_player(202, "Relay Explorer")
	var other = sim.add_player(203, "Fellow Survivor")
	_hub(world, survivor)
	_hub(world, other)
	t.eq(sim.cmd_story(survivor.id, "decode")["reason"], "chapter_one_incomplete",
		"Chapter II is locked until real Chapter I completion")
	# Simulate already-completed Chapter I as restored by the account load.
	survivor.story_state = {"stage": ChapterOne.LAST_STAGE, "kills": ChapterOne.REQUIRED_KILLS}
	sim.players[survivor.id] = survivor
	t.eq(sim.cmd_story(survivor.id, "broadcast")["reason"], "incomplete",
		"there is no reward on skipping directly to the branch choice")
	t.check(sim.cmd_story(survivor.id, "decode")["ok"],
		"real workbench starts the underground chapter")
	t.eq(sim.cmd_story(survivor.id, "decode")["reason"], "already_started",
		"replayed decode does not reset stages")
	t.eq(sim.snapshot_for(survivor.id)["you"]["story2"]["stage"], 1,
		"owner sees earned Chapter II objective")
	t.eq(sim.snapshot_for(other.id)["you"]["story2"], {},
		"unqualified bystander cannot see another survivor's recordings")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	var seen: int = 0
	for event in sim.events:
		if str(event.get("type", "")) == "story2":
			seen += 1
			t.check(net._event_visible_to(event, survivor.id),
				"only verified owner receives decoded underground signal")
			t.check(not net._event_visible_to(event, other.id),
				"unauthorized peers never receive private story milestones")
	t.check(seen > 0, "new stage emits private server event")
	net.free()

	t.current = "Real world dungeon hatch, chest and champion drive actual server milestones"
	var bunker: Dictionary = _bunker(world)
	t.check(not bunker.is_empty(), "deterministic world contains a genuine bunker")
	if bunker.is_empty():
		return
	var region: Vector2i = Dungeon.region_of_site(bunker)
	var hatch: Vector2 = Dungeon.hatch(world, bunker)
	survivor.position = Vector3(0, world.height_at(0, 0), 0)
	t.eq(sim.cmd_dungeon(survivor.id, true)["reason"], "no_hatch",
		"false descent request cannot make story progress")
	t.eq(int(survivor.story2_state["stage"]), 1, "refused hatch entry never changes journal")
	survivor.position = Vector3(hatch.x, world.height_at(hatch.x, hatch.y), hatch.y)
	t.check(bool(sim.cmd_dungeon(survivor.id, true).get("ok", false)),
		"real bunker hatch opens the existing procedural dungeon")
	t.eq(int(survivor.story2_state["stage"]), 2,
		"only successful real server descent opens the search for a core")
	var contents: Dictionary = _dungeon_content(world, region)
	var chest: Dictionary = contents["chest"]
	var spawn: Dictionary = contents["boss"]
	t.check(not chest.is_empty() and not spawn.is_empty(),
		"this very dungeon has a real chest and one champion spawn")
	if chest.is_empty() or spawn.is_empty():
		return
	t.eq(sim.cmd_loot(survivor.id, -4242)["reason"], "nothing_there",
		"fabricated loot request does not advance underground research")
	t.eq(int(survivor.story2_state["stage"]), 2,
		"failure to recover an actual chest never advances plot")
	survivor.position = Vector3(float(chest["x"]), Dungeon.FLOOR_Y, float(chest["z"]))
	var loot: Dictionary = sim.cmd_loot(survivor.id, int(chest["id"]))
	t.check(bool(loot.get("ok", false)), "physical generated dungeon cache contains the key fragment")
	if not bool(loot.get("ok", false)):
		return
	t.eq(int(survivor.story2_state["stage"]), 3, "real opened chest unlocks champion objective")
	t.eq(sim.cmd_loot(survivor.id, int(chest["id"]))["reason"], "empty",
		"replayed crate cannot replay narrative progress")

	var unmarked := Zombie.new(sim.new_id(), "brute",
		Vector3(float(spawn["x"]), Dungeon.FLOOR_Y, float(spawn["z"])))
	unmarked.become_elite()
	sim.zombies[unmarked.id] = unmarked
	survivor.position = unmarked.position + Vector3(3, 0, 0)
	sim._damage_target(survivor, {"kind": "zombie", "id": unmarked.id}, 5000.0)
	t.eq(int(survivor.story2_state["stage"]), 3,
		"ordinary elite without world-spawn guardian identity is not the story boss")
	var guardian = _champion(spawn, sim)
	survivor.position = guardian.position + Vector3(3, 0, 0)
	sim._damage_target(survivor, {"kind": "zombie", "id": guardian.id}, 5000.0)
	t.eq(int(survivor.story2_state["stage"]), 4,
		"actual elite guardian death in its dungeon opens two ending choices")
	sim._damage_target(survivor, {"kind": "zombie", "id": guardian.id}, 5000.0)
	t.eq(int(survivor.story2_state["stage"]), 4,
		"dead guardian cannot count twice")
	t.eq(sim.cmd_story(survivor.id, "seal")["reason"], "no_station",
		"final choice cannot be made remotely from the dungeon")

	t.current = "Cross-chapter saves, finale irreversibility and legacy accounts"
	var saved_mid: Dictionary = sim.character_data(survivor)
	t.check(sim.valid_character_data(saved_mid), "mid-Chapter-II save is accepted")
	var restored_server := GameServer.new(WorldGen.new(42), 42)
	var restored = restored_server.add_player(890, "Restored Relay", "", saved_mid)
	t.eq(restored.story2_state, survivor.story2_state,
		"saved journal survives a full account load during the underground mission")
	t.eq(int(restored.story_state["stage"]), ChapterOne.LAST_STAGE,
		"previous chapter completion remains unchanged")
	var legacy: Dictionary = saved_mid.duplicate(true)
	legacy.erase("story2")
	var old_server := GameServer.new(WorldGen.new(42), 42)
	var old_player = old_server.add_player(891, "Old Account", "", legacy)
	t.eq(old_player.story2_state, ChapterTwo.empty_state(),
		"old Chapter-I-only account continues cleanly at Chapter II stage zero")
	var forged: Dictionary = saved_mid.duplicate(true)
	forged["story2"] = {"stage": 5, "ending": ""}
	t.check(not sim.valid_character_data(forged), "bad completed-ending saves rejected")
	forged = saved_mid.duplicate(true)
	forged["story"] = ChapterOne.empty_state()
	t.check(not sim.valid_character_data(forged),
		"Chapter II checkpoint cannot be loaded without a completed Chapter I")
	_hub(world, survivor)
	var silver_before_final: int = survivor.inventory.count("silver")
	var finish: Dictionary = sim.cmd_story(survivor.id, "broadcast")
	t.check(bool(finish.get("ok", false)), "genuine workbench broadcasts the branch-specific finale")
	if not bool(finish.get("ok", false)):
		return
	t.eq(survivor.story2_state["ending"], "broadcast", "player choice committed permanently")
	t.check(ChapterTwo.current_line(survivor.story2_state).contains("TRUTH BROADCAST"),
		"broadcast choice persists in private recovered radio journal")
	t.eq(sim.cmd_story(survivor.id, "seal")["reason"], "already_complete",
		"switching to alternate branch cannot earn a second reward")
	t.eq(survivor.inventory.count("silver"), silver_before_final + int(ChapterTwo.BROADCAST_REWARD["silver"]),
		"real server adds only the one-time chapter reward to existing dungeon loot")
	var saved_final: Dictionary = sim.character_data(survivor)
	t.check(sim.valid_character_data(saved_final), "chosen ending is a valid account save")
	var final_server := GameServer.new(WorldGen.new(42), 42)
	var final_player = final_server.add_player(892, "Final Receiver", "", saved_final)
	t.eq(final_player.story2_state, survivor.story2_state,
		"final branch ending survives a second full server reload")
