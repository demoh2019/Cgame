extends RefCounted
## Weather mitigation consumable: server-only use, expiry, persistence and migration.
const Defs = preload("res://scripts/shared/defs.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "insulation reduces real severe weather exposure"
	var baseline := Survival.new()
	var protected := Survival.new()
	t.check(protected.apply_thermal_wrap(), "unbuffed survivor can activate heat pack")
	t.check(not protected.apply_thermal_wrap(), "heat packs cannot stack")
	baseline.weather_tick(50.0, 1.0)
	protected.weather_tick(50.0, 1.0)
	t.check(protected.exposure < baseline.exposure * 0.4, "heat pack mitigates at least 60% of exposure")
	t.near(protected.warmth_seconds, Defs.THERMAL_WRAP_SECONDS - 50.0, 0.0001, "server timer decrements")
	protected.weather_tick(129.0, 1.0)
	t.near(protected.warmth_seconds, 1.0, 0.0001, "one second of protection remains")
	var prior: float = protected.exposure
	protected.weather_tick(2.0, 1.0)
	t.near(protected.warmth_seconds, 0.0, 0.0001, "heat pack expires automatically")
	t.near(protected.exposure - prior, 2.0 * 0.55 * (1.0 - Defs.THERMAL_WRAP_REDUCTION * 0.5), 0.001,
		"partial-tick expiry applies weighted insulation")
	t.check(protected.apply_thermal_wrap(), "another pack can activate after expiry")
	protected.reset()
	t.eq(protected.warmth_seconds, 0.0, "death/respawn clears insulation")
	protected.weather_tick(-1.0, 1.0)
	t.eq(protected.warmth_seconds, 0.0, "negative delta does not mutate timer")

	t.current = "craft, consume once and preserve backpacks transactionally"
	var server := GameServer.new(WorldGen.new(77), 77)
	var player = server.add_player(100, "Cold Ranger")
	t.check(Defs.is_item("thermal_wrap"), "heat pack is a legal inventory item")
	t.eq(server.cmd_use(100, "thermal_wrap")["reason"], "not_carried", "free pack cannot be activated")
	player.inventory.add("fiber_1", 2)
	player.inventory.add("wood_1", 1)
	t.eq(server.cmd_craft(100, "thermal_wrap")["reason"], "missing_inputs", "missing cloth blocks crafting")
	t.eq(player.inventory.count("wood_1"), 1, "failed craft does not consume wood")
	player.inventory.add("cloth_1", 1)
	t.check(server.cmd_craft(100, "thermal_wrap")["ok"], "field heat pack is craftable")
	t.eq(player.inventory.count("thermal_wrap"), 1, "crafted pack enters inventory")
	t.check(server.cmd_use(100, "thermal_wrap")["ok"], "server consumes one pack")
	t.eq(player.inventory.count("thermal_wrap"), 0, "using a pack costs one item")
	t.eq(player.survival.warmth_seconds, Defs.THERMAL_WRAP_SECONDS, "active insulation set by server")
	player.inventory.add("thermal_wrap", 1)
	t.eq(server.cmd_use(100, "thermal_wrap")["reason"], "already_warm", "cannot waste a second pack")
	t.eq(player.inventory.count("thermal_wrap"), 1, "refused use leaves inventory unchanged")
	var snap: Dictionary = server.snapshot_for(100)
	t.eq(snap["you"]["warmth_seconds"], Defs.THERMAL_WRAP_SECONDS, "only owner gets authoritative timer")
	server._tick_players(2.0)
	t.check(player.survival.warmth_seconds < Defs.THERMAL_WRAP_SECONDS, "server advances insulation timer")
	t.eq(player.inventory.count("thermal_wrap"), 1, "timer tick never consumes extra items")

	t.current = "compatible saves and atomic rejection"
	var save: Dictionary = server.character_data(player)
	t.check(save.has("warmth_seconds"), "character persistence includes insulation")
	var expected: float = player.survival.warmth_seconds
	player.survival.warmth_seconds = 0.0
	t.check(server.apply_character(player, save), "saved timer loads")
	t.near(player.survival.warmth_seconds, expected, 0.001, "timer restored without refresh")
	for invalid_value in [-1.0, INF, NAN, Defs.THERMAL_WRAP_SECONDS + 1.0, "180"]:
		var corrupt: Dictionary = save.duplicate(true)
		corrupt["warmth_seconds"] = invalid_value
		t.check(not server.apply_character(player, corrupt), "invalid insulation timer rejected")
		t.near(player.survival.warmth_seconds, expected, 0.001, "failed load never changed timer")
	var legacy: Dictionary = save.duplicate(true)
	legacy.erase("warmth_seconds")
	t.check(server.apply_character(player, legacy), "old version-1 Nakama record remains compatible")
	t.eq(player.survival.warmth_seconds, 0.0, "legacy character starts without heating")
