extends RefCounted
## Paid silence is footstep-only: noise inheritance, save and expiry are server-controlled.
const Defs = preload("res://scripts/shared/defs.gd")
const Wraps = preload("res://scripts/shared/soft_sole_wraps.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Movement = preload("res://scripts/shared/movement.gd")


func _open_ground(world) -> Vector3:
	for x in range(180, 341, 20):
		for z in range(180, 341, 20):
			var point := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			var moved: Vector3 = Movement.step(world, point, {"x": 1.0, "sprint": true}, 0.1)
			if moved.distance_to(point) > 0.2:
				return point
	return Vector3(200.0, world.height_at(200.0, 200.0), 200.0)


func run(t) -> void:
	t.current = "soft soles: real craft recipe and bounded rules"
	t.eq(Defs.item(Wraps.ITEM_ID).get("kind"), "footstep_wrap", "craftable item registered")
	t.eq(Defs.recipes()[Wraps.ITEM_ID]["station"], "", "wraps can be made in the field")
	t.eq(Defs.recipes()[Wraps.ITEM_ID]["inputs"],
		{"cloth_1": 2, "fiber_1": 2, "scrap": 1}, "cloth and fiber and salvage")
	t.near(Wraps.sprint_noise(Defs.SPRINT_NOISE_RADIUS, 90.0),
		Defs.SPRINT_NOISE_RADIUS * 0.55, 0.001, "footstep radius reduced")
	t.eq(Wraps.sprint_noise(Defs.SPRINT_NOISE_RADIUS, 0.0),
		Defs.SPRINT_NOISE_RADIUS, "expired wraps are normal")
	t.eq(Wraps.sprint_noise(Defs.SPRINT_NOISE_RADIUS, INF),
		Defs.SPRINT_NOISE_RADIUS, "invalid timer grants no stealth")
	t.check(not Wraps.valid_remaining("60"), "string timer cannot forge a buff")
	t.check(not Wraps.valid_remaining(91.0), "too-long buff rejected")
	t.check(not Wraps.valid_remaining(-1.0), "negative duration rejected")

	t.current = "soft soles: inventory payment and combat restrictions"
	var world := WorldGen.new(83)
	var sim := GameServer.new(world, 83)
	var scout = sim.add_player(410, "Scout")
	t.eq(sim.cmd_use(410, Wraps.ITEM_ID).get("reason"), "not_carried",
		"no consumable cannot create noise protection")
	scout.inventory.add(Wraps.ITEM_ID, 2)
	scout.attack_timer = 1.0
	t.eq(sim.cmd_use(410, Wraps.ITEM_ID).get("reason"), "in_combat",
		"cannot prepare while attacking")
	t.eq(scout.inventory.count(Wraps.ITEM_ID), 2, "failed preparation is free")
	scout.attack_timer = 0.0
	t.check(bool(sim.cmd_use(410, Wraps.ITEM_ID).get("ok", false)),
		"server consumes one real item when equipping")
	t.eq(scout.inventory.count(Wraps.ITEM_ID), 1, "single item spent")
	t.near(scout.soft_sole_seconds, Wraps.DURATION_SECONDS, 0.001,
		"server granted exactly the limited duration")
	t.eq(sim.cmd_use(410, Wraps.ITEM_ID).get("reason"), "already_wrapped",
		"cannot top up active wraps")
	t.eq(scout.inventory.count(Wraps.ITEM_ID), 1, "no waste on duplicate use")

	t.current = "soft soles: verified sprint cannot silence older louder sounds"
	scout.position = _open_ground(world)
	scout.input_budget = 0.25
	scout.survival.stamina = Defs.MAX_STAMINA
	sim.submit_input(410, 1, 1.0, 0.0, true, 0.0, 0.1)
	t.check(scout.noise_timer > 0.0, "real server sprint is still audible")
	t.near(scout.noise_radius, Defs.SPRINT_NOISE_RADIUS * Wraps.SPRINT_NOISE_FACTOR,
		0.001, "sprint generates muffled but nonzero sound")
	scout.noise_radius = Defs.SPRINT_NOISE_RADIUS * 2.0
	scout.input_budget = 0.25
	sim.submit_input(410, 2, 1.0, 0.0, true, 0.0, 0.1)
	t.eq(scout.noise_radius, Defs.SPRINT_NOISE_RADIUS * 2.0,
		"fresh muffled steps never erase loud gunshots/vehicle sounds")

	t.current = "soft soles: strict account save, expiry and legacy support"
	var saved: Dictionary = sim.character_data(scout)
	t.check(sim.valid_character_data(saved), "legitimate paid buff can be saved")
	t.eq(float(saved["soft_sole_seconds"]), Wraps.DURATION_SECONDS,
		"saved seconds do not refill after logout")
	scout.soft_sole_seconds = 0.0
	t.check(sim.apply_character(scout, saved), "restores server-validated buff")
	t.eq(scout.soft_sole_seconds, Wraps.DURATION_SECONDS,
		"remaining duration restored")
	var forged := saved.duplicate(true)
	forged["soft_sole_seconds"] = 99999.0
	t.check(not sim.apply_character(scout, forged), "save cannot forge greater duration")
	t.eq(scout.soft_sole_seconds, Wraps.DURATION_SECONDS, "failed save is atomic")
	forged = saved.duplicate(true)
	forged["soft_sole_seconds"] = "90"
	t.check(not sim.apply_character(scout, forged), "text seconds rejected")
	sim._tick_players(1.0)
	t.near(scout.soft_sole_seconds, Wraps.DURATION_SECONDS - 1.0,
		0.001, "server time tick decrements rather than refreshes duration")
	t.near(float(sim.snapshot_for(410)["you"]["soft_sole_seconds"]),
		Wraps.DURATION_SECONDS - 1.0, 0.001, "private owner status is available")
	sim._spawn_player(scout)
	t.eq(scout.soft_sole_seconds, 0.0, "respawn clears temporary wraps")
	var legacy: Dictionary = sim.character_data(scout)
	legacy.erase("soft_sole_seconds")
	t.check(sim.apply_character(scout, legacy), "legacy version 1 save loads")
	t.eq(scout.soft_sole_seconds, 0.0, "legacy save grants no free stealth")
