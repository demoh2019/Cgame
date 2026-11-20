extends RefCounted
## Parry timing, position, owner-only results, no PvP immunity or free stamina.
const Defs = preload("res://scripts/shared/defs.gd")
const MeleeParry = preload("res://scripts/shared/melee_parry.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const EvasionTest = preload("res://tests/test_evasion.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	var world := WorldGen.new(2090)
	var site: Vector2 = EvasionTest.new()._clear_red_zone_spot(world)
	t.current = "server-side setup for real infected melee"
	t.check(site.is_finite(), "clear red-zone test site exists")
	if not site.is_finite():
		return
	var server := GameServer.new(world, 2090)
	var survivor = server.add_player(92, "Fencer")
	survivor.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	survivor.yaw = PI / 2.0
	t.eq(server.cmd_parry(999).get("reason", ""), "dead", "unregistered peer cannot parry")
	t.eq(server.cmd_parry(92).get("reason", ""), "need_melee",
		"unarmed defender cannot create a free parry window")
	survivor.inventory.add("pistol", 1)
	survivor.inventory.equip("pistol")
	t.check(not MeleeParry.equipped(survivor.inventory), "ranged weapon cannot block melee")
	t.eq(server.cmd_parry(92).get("reason", ""), "need_melee",
		"pistol cannot parry")
	survivor.inventory.add("club_1", 1)
	t.check(survivor.inventory.equip("club_1"), "real club equipped")
	survivor.survival.stamina = 19.0
	t.eq(server.cmd_parry(92).get("reason", ""), "no_stamina",
		"not enough stamina rejects without cooldown")
	t.eq(survivor.parry_cooldown, 0.0, "invalid parry does not charge cooldown")
	survivor.survival.stamina = 100.0
	t.current = "time-limited, charged and single-use defensive stance"
	var start: Dictionary = server.cmd_parry(92)
	t.check(start.get("ok", false), "real melee survivor can prepare one parry")
	t.near(survivor.survival.stamina, 80.0, 0.001,
		"successful command consumes 20 stamina exactly once")
	t.near(survivor.parry_window, MeleeParry.WINDOW_SECONDS, 0.001,
		"short impact window starts server-side")
	t.eq(server.cmd_parry(92).get("reason", ""), "cooldown",
		"repeat parry cannot stack windows or recharge")
	t.near(float(server.snapshot_for(92)["you"]["parry_cooldown"]),
		MeleeParry.COOLDOWN_SECONDS, 0.001, "owner sees authoritative cooldown")
	t.near(float(server.snapshot_for(92)["you"]["parry_window"]),
		MeleeParry.WINDOW_SECONDS, 0.001, "owner sees active timing")
	var enemy := Zombie.new(server.new_id(), "walker",
		Vector3(site.x + 1.1, world.height_at(site.x + 1.1, site.y), site.y))
	enemy.target_id = 92
	enemy.state = Zombie.State.ATTACK
	enemy.think_timer = 1.0
	server.zombies[enemy.id] = enemy
	t.check(MeleeParry.can_block(survivor, enemy),
		"front-facing genuine infected hit qualifies")
	var before: float = survivor.survival.health
	server._tick_zombies(0.05)
	t.near(survivor.survival.health, before -
		float(enemy.data["damage"]) * MeleeParry.DAMAGE_FACTOR,
		0.001, "actual infected melee damage is reduced 70 percent")
	t.eq(survivor.parry_window, 0.0, "successful parry is consumed by the first hit")
	t.check(enemy.attack_timer >= MeleeParry.STAGGER_SECONDS - 0.001,
		"parried attacker is staggered for one second")
	var parried: Dictionary = {}
	for event in server.events:
		if event.get("type", "") == "parried":
			parried = event
	t.eq(int(parried.get("peer", -1)), 92, "successful parry produces one private event")
	var net := Net.new()
	t.check(net._event_visible_to(parried, 92), "recipient sees event")
	t.check(not net._event_visible_to(parried, 123), "outsider cannot read defense event")
	net.free()
	t.current = "front-only defense never applies from behind"
	survivor.yaw = -PI / 2.0
	survivor.parry_window = MeleeParry.WINDOW_SECONDS
	t.check(not MeleeParry.can_block(survivor, enemy),
		"attacks from behind cannot be blocked")
	enemy.attack_timer = 0.0
	enemy.think_timer = 1.0
	before = survivor.survival.health
	server._tick_zombies(0.05)
	t.near(survivor.survival.health, before - float(enemy.data["damage"]),
		0.001, "rear attack deals ordinary damage")
	t.check(survivor.parry_window > 0.0,
		"unblocked strike does not waste the limited window")
	enemy.raid_boss = true
	survivor.yaw = PI / 2.0
	t.check(not MeleeParry.can_block(survivor, enemy),
		"raid bosses are immune to parry")
	enemy.raid_boss = false
	survivor.inventory.remove("club_1", 1)
	t.check(not MeleeParry.can_block(survivor, enemy),
		"losing equipped weapon invalidates a pending parry")
	t.current = "timers and persistence"
	server._tick_players(0.5)
	t.eq(survivor.parry_window, 0.0, "expired window is never permanent")
	t.check(survivor.parry_cooldown < MeleeParry.COOLDOWN_SECONDS,
		"server ticks down cooldown")
	t.check(not server.character_data(survivor).has("parry_window"),
		"timing is never saved in account records")
	server._spawn_player(survivor)
	t.eq(survivor.parry_window, 0.0, "respawn clears active defense")
	t.eq(survivor.parry_cooldown, 0.0, "respawn clears transient cooldown")
