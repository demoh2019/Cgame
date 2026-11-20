extends RefCounted
## Real server shots can dismantle enemy barricades in dangerous PvP zones.
## Never grant XP, PvP kills or wall damage from forged client targets.

const RangedCover = preload("res://scripts/shared/ranged_cover.gd")
const Ballistics = preload("res://scripts/shared/barricade_ballistics.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Net = preload("res://scripts/shared/net.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


class StubWorld:
	extends RefCounted
	var blocks: Array = []
	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return blocks


func _at(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func _lane(world) -> Vector2:
	for i in 75:
		var x: float = 750.0 + float(i % 5) * 20.0
		var z: float = float(i / 5 - 7) * 25.0
		var p := Vector2(x, z)
		var wall := p + Vector2(8.0, 0.0)
		if world.zone_at(p.x, p.y) != 2 or world.zone_at(wall.x, wall.y) != 2:
			continue
		if world.is_water(p.x, p.y) or world.is_water(wall.x, wall.y) or \
				world.is_water(p.x + 18.0, p.y):
			continue
		if world.normal_at(wall.x, wall.y).y < Structures.MIN_SLOPE_NORMAL_Y:
			continue
		if RangedCover.first_blocker_distance(world, p, Vector2.RIGHT, 27.0) == INF:
			return p
	return Vector2.INF


func run(t) -> void:
	t.current = "collision query carries correct blocker id"
	var fake := StubWorld.new()
	fake.blocks = [
		{"id": 77, "x": 15.0, "z": 0.0, "radius": 1.0, "blocks": true},
		{"id": 33, "x": 7.0, "z": 0.0, "radius": 1.0, "blocks": true}]
	var result: Dictionary = RangedCover.first_blocker(fake, Vector2.ZERO,
		Vector2.RIGHT, 30.0)
	t.eq(int(result.get("id", -1)), 33, "closest wall identity follows closest collision")
	t.near(float(result.get("distance", INF)), 6.0, 0.001,
		"same precise ray entry is returned")
	t.eq(RangedCover.first_blocker_distance(fake, Vector2.ZERO,
		Vector2.RIGHT, 30.0), float(result["distance"]),
		"old distance-only API stays equivalent")
	fake.blocks = [{"id": 77, "x": 9.0, "z": 0.0,
		"radius": 1.0, "blocks": false}]
	t.check(RangedCover.first_blocker(fake, Vector2.ZERO, Vector2.RIGHT,
		30.0).is_empty(), "non-solid scenery cannot receive structural damage")

	t.current = "bounded wall damage and legal target eligibility"
	t.near(Ballistics.raw_damage(18.0), 10.8, 0.001,
		"ordinary improvised pistol produces bounded structural damage")
	t.near(Ballistics.raw_damage(1000000.0), Ballistics.MAX_RAW_DAMAGE,
		0.001, "extreme verified damage has a hard cap")
	for bad in [-1.0, NAN, INF, 0.0]:
		t.near(Ballistics.raw_damage(bad), 0.0, 0.001,
			"invalid raw damage cannot mint wall damage")
	var world := WorldGen.new(310)
	var server := GameServer.new(world, 310)
	var builder = server.add_player(51, "Builder", "owner-acct")
	var shooter = server.add_player(52, "Raider", "raider-acct")
	var ally = server.add_player(53, "Ally", "ally-acct")
	builder.guild_id = "wolf-guild"
	shooter.guild_id = "fox-guild"
	ally.guild_id = "wolf-guild"
	var lane: Vector2 = _lane(world)
	t.check(lane.is_finite(), "procedurally located dry red-zone firing range")
	if not lane.is_finite():
		return
	var wall_site := lane + Vector2(8.0, 0.0)
	builder.position = _at(world, lane + Vector2(5.0, 0.0))
	builder.inventory.add("wood_1", 4)
	builder.inventory.add("stone_1", 2)
	var built: Dictionary = server.cmd_build(builder.id, wall_site.x, wall_site.y)
	t.check(bool(built.get("ok", false)), "real build consumes resources and creates a T1 wall")
	if not built.get("ok", false):
		return
	var wall_id: int = int(built["id"])
	var wall: Dictionary = server.barricades[wall_id]
	t.eq(str(wall.get("owner_guild", "")), "wolf-guild",
		"server records verified guild at construction time")
	var checkpoint: Dictionary = WorldPersistence.capture(server)
	t.eq(str(checkpoint["barricades"][0].get("owner_guild", "")), "wolf-guild",
		"dedicated-server save preserves wall guild affiliation")
	var reboot := GameServer.new(WorldGen.new(310), 310)
	t.check(WorldPersistence.restore(reboot, checkpoint),
		"authenticated world checkpoint restores the real barricade")
	t.eq(str(reboot.barricades[wall_id].get("owner_guild", "")), "wolf-guild",
		"guildmate protection survives server restart")
	var forged: Dictionary = checkpoint.duplicate(true)
	forged["barricades"][0]["owner_guild"] = 42
	t.check(not WorldPersistence.restore(GameServer.new(WorldGen.new(310), 310), forged),
		"invalid guild field is rejected atomically")
	var legacy: Dictionary = checkpoint.duplicate(true)
	legacy["barricades"][0].erase("owner_guild")
	legacy["barricades"][0].erase("yaw") # Snapshots of that time had no facing or upkeep either.
	legacy["barricades"][0].erase("upkeep")
	t.check(WorldPersistence.restore(GameServer.new(WorldGen.new(310), 310), legacy),
		"pre-ballistics world snapshots still load")

	t.check(not Ballistics.can_damage(builder, wall, 2, 2),
		"an owner cannot shoot their own barricade")
	t.check(not Ballistics.can_damage(ally, wall, 2, 2),
		"trusted same-guild survivors cannot shoot allied cover")
	t.check(not Ballistics.can_damage(shooter, wall, 0, 2),
		"shots from green zone cannot harm PvP fortifications")
	t.check(not Ballistics.can_damage(shooter, wall, 2, 1),
		"protected zone walls cannot be attacked")
	t.check(Ballistics.can_damage(shooter, wall, 2, 2),
		"rival accounts may attack red-zone barricades")

	t.current = "ranged PvE targets stay protected behind enemy wall"
	builder.position = _at(world, lane + Vector2(-15.0, 25.0))
	ally.position = _at(world, lane + Vector2(-15.0, -25.0))
	shooter.position = _at(world, lane)
	shooter.inventory.add("suppressed_pistol", 1)
	shooter.inventory.add("ammo_9mm", 18)
	t.check(shooter.inventory.equip("suppressed_pistol"), "attacker owns equipped gun")
	var target := Zombie.new(server.new_id(), "brute",
		_at(world, lane + Vector2(16.0, 0.0)))
	server.zombies[target.id] = target
	var monster_hp: float = target.health
	t.eq(int(RangedCover.first_blocker(world, lane, Vector2.RIGHT,
		30.0).get("id", -1)), wall_id, "actual wall intercepts live line of fire")
	var revision_before: int = server.world_structure_revision
	var shot: Dictionary = server.cmd_attack(shooter.id, 1.0, 0.0)
	t.check(bool(shot.get("ok", false)) and bool(shot.get("cover_hit", false)),
		"server processes first real shot as a wall hit")
	t.check(not bool(shot.get("hit", true)), "covered infected receives no hit")
	t.near(target.health, monster_hp, 0.001, "no infected damage through cover")
	t.near(float(server.barricades[wall_id]["hp"]), 109.2, 0.001,
		"real T1 wall loses 10.8 hp from suppressed pistol")
	t.eq(shooter.inventory.count("ammo_9mm"), 17,
		"real collision consumes exactly one cartridge")
	t.check(server.world_structure_revision > revision_before,
		"wall HP change invalidates world revision for clients")
	var wall_events: Array = server.events.filter(func(event):
		return str(event.get("type", "")) == "barricade_shot")
	t.eq(wall_events.size(), 1, "one server shot creates one damage event")
	if not wall_events.is_empty():
		var net := Net.new()
		net.role = "server"
		net.sim = server
		t.check(net._event_visible_to(wall_events[0], shooter.id),
			"shooter receives private wall hit feedback")
		t.check(not net._event_visible_to(wall_events[0], builder.id),
			"other accounts cannot read private hit feedback")
		net.free()

	t.current = "charged ranged skill damages cover once, with tier resistance"
	shooter.attack_timer = 0.0
	var skill: Dictionary = server.cmd_skill(shooter.id, 1.0, 0.0)
	t.check(bool(skill.get("ok", false)) and bool(skill.get("cover_hit", false)),
		"charged ranged shot resolves against wall")
	t.eq(shooter.inventory.count("ammo_9mm"), 16,
		"ability consumes one further cartridge")
	t.check(shooter.combat_energy < 100.0, "ability costs normal combat energy")
	t.near(target.health, monster_hp, 0.001, "charged shot cannot penetrate wall")
	var after_skill_hp: float = float(server.barricades[wall_id]["hp"])
	t.check(after_skill_hp < 109.2, "charged skill reduces real wall health")
	t.eq(server.cmd_skill(shooter.id, 1.0, 0.0).get("reason"), "cooldown",
		"replayed ability cannot grind wall health")
	t.near(float(server.barricades[wall_id]["hp"]), after_skill_hp, 0.001,
		"cooldown denial leaves wall unchanged")
	server.barricades[wall_id]["tier"] = 4
	server.barricades[wall_id]["hp"] = 600.0
	shooter.skill_timer = 0.0
	shooter.attack_timer = 0.0
	shot = server.cmd_attack(shooter.id, 1.0, 0.0)
	t.check(bool(shot.get("cover_hit", false)), "same gun can damage tier-four armor")
	t.near(float(server.barricades[wall_id]["hp"]), 594.6, 0.001,
		"T4 wall halves the incoming structural damage")
	t.eq(shooter.inventory.count("ammo_9mm"), 15, "tier-four hit still consumes ammo")

	t.current = "owner and guild firing cannot damage their own wall"
	shooter.position = _at(world, lane + Vector2(-15.0, 25.0))
	builder.position = _at(world, lane)
	builder.inventory.add("pistol", 1)
	builder.inventory.add("ammo_9mm", 2)
	t.check(builder.inventory.equip("pistol"), "owner equips physical gun")
	var protected_hp: float = float(server.barricades[wall_id]["hp"])
	shot = server.cmd_attack(builder.id, 1.0, 0.0)
	t.check(not bool(shot.get("cover_hit", true)), "owner shot causes no structural damage")
	t.near(float(server.barricades[wall_id]["hp"]), protected_hp, 0.001,
		"owner's wall HP remains intact")
	builder.position = _at(world, lane + Vector2(-15.0, 25.0))
	ally.position = _at(world, lane)
	ally.inventory.add("pistol", 1)
	ally.inventory.add("ammo_9mm", 2)
	t.check(ally.inventory.equip("pistol"), "guildmate equips gun")
	shot = server.cmd_attack(ally.id, 1.0, 0.0)
	t.check(not bool(shot.get("cover_hit", true)), "same-guild shot causes no structural damage")
	t.near(float(server.barricades[wall_id]["hp"]), protected_hp, 0.001,
		"allied wall remains intact")

	t.current = "breaking barrier opens the shot lane without duplicate rewards"
	shooter.position = _at(world, lane)
	ally.position = _at(world, lane + Vector2(-15.0, -25.0))
	var kills_before: int = shooter.kills
	t.check(server.damage_barricade(wall_id, 100000.0),
		"real server damage can fully destroy an already damaged barricade")
	t.check(not world.dynamic_blockers.has(wall_id),
		"destroyed wall is erased from world collision")
	t.check(server._find_hit(shooter, lane, Vector2.RIGHT, 30.0,
		true).get("id", -1) == target.id, "same firing lane is instantly open")
	t.eq(shooter.kills, kills_before, "wall damage grants no invented PvE kill")
