extends RefCounted
## Telegraph visibility, finite seeded storm physics, dodge and server damage.
const StormLightning = preload("res://scripts/shared/storm_lightning.gd")
const LightningVisual = preload("res://scripts/client/storm_lightning_visual.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


func _storm_site(world) -> Dictionary:
	for point in [Vector2(550, 0), Vector2(700, 400), Vector2(900, 100),
			Vector2(1100, 650), Vector2(1200, -200), Vector2(-750, 300)]:
		if world.is_water(point.x, point.y) or world.is_safe(point.x, point.y) or \
				world.zone_at(point.x, point.y) < 1:
			continue
		for phase in range(100):
			var at: float = float(phase) * Weather.CHANGE_SECONDS + 5.0
			var candidate := Vector3(point.x, world.height_at(point.x, point.y), point.y)
			if not StormLightning.create_warning(world, candidate, at).is_empty():
				return {"position": candidate, "time": at}
	return {}


func run(t) -> void:
	t.current = "bounded environmental lightning geometry"
	var world := WorldGen.new(846)
	var situation: Dictionary = _storm_site(world)
	t.check(not situation.is_empty(), "real world has valid storm-grounded lightning")
	if situation.is_empty():
		return
	var pos: Vector3 = situation["position"]
	var now: float = situation["time"]
	var strike: Dictionary = StormLightning.create_warning(world, pos, now)
	t.eq(strike, StormLightning.create_warning(world, pos, now),
		"world seed, time and player location deterministically select the same warning")
	t.near(float(strike["at"]) - now, StormLightning.WARNING_SECONDS, 0.0001,
		"2.8-second telegraph always precedes impact")
	t.check(not StormLightning.in_blast(Vector2(float(strike["x"]),
		float(strike["z"])), pos + Vector3(StormLightning.RADIUS + 10.0, 0, 0)),
		"walking away from bolt circle prevents impact")
	t.check(StormLightning.in_blast(Vector2(float(strike["x"]),
		float(strike["z"])), pos), "storm warning can actually threaten a survivor")
	t.check(StormLightning.create_warning(world, Vector3.INF, now).is_empty(),
		"invalid client coordinates cannot schedule lightning")
	t.check(StormLightning.create_warning(world, Vector3.ZERO, now).is_empty(),
		"hub never creates a lightning strike")
	t.check(not StormLightning.strike_valid(world, strike, now),
		"attack never fires before its announced deadline")
	t.check(StormLightning.strike_valid(world, strike, float(strike["at"])),
		"storm still active at impact authorizes bolt")
	t.check(not StormLightning.strike_valid(world,
		{"x": INF, "z": 0.0, "y": 0.0, "at": now}, now),
		"malformed strike cannot damage players")
	var visual := LightningVisual.new()
	t.check(visual.has_method("set_warning") and visual is Node3D,
		"real 3D ground warning visual exists")
	visual.set_warning({})
	t.check(not visual.visible, "empty snapshot hides visual warning")
	visual.free()
	var radar := Radar.new()
	t.check(radar.has_method("_draw_lightning"),
		"offline and online radar can show grounded warning")
	radar.free()

	t.current = "server schedules one world strike and restricts visibility"
	var sim := GameServer.new(world, 846)
	var victim = sim.add_player(11, "Storm Scout")
	var witness = sim.add_player(12, "Nearby Scout")
	var distant = sim.add_player(13, "Far Away")
	victim.position = pos
	witness.position = pos + Vector3(8, 0, 0)
	distant.position = Vector3.ZERO
	sim.time = now
	sim.next_lightning_at = now
	sim._tick_lightning()
	t.check(not sim.lightning_pending.is_empty(), "server schedules a real warning")
	t.eq(sim.events.filter(func(e): return e.get("type") == "lightning_warning").size(),
		1, "one warning event per bolt, no extra storms")
	t.check(sim.snapshot_for(11).has("lightning_telegraph"),
		"target sees authoritative exact center and deadline")
	t.check(sim.snapshot_for(12).has("lightning_telegraph"),
		"nearby witness can dodge the same storm")
	t.check(not sim.snapshot_for(13).has("lightning_telegraph"),
		"distant players cannot spy on local lightning positions")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	var event: Dictionary = sim.events.back()
	t.check(net._event_visible_to(event, 11), "storm warning reaches impacted player")
	t.check(not net._event_visible_to(event, 13),
		"storm warning is not globally broadcast")
	net.free()
	t.check(sim.next_lightning_at > now + 40.0,
		"global cooldown bounds lightning density for any party size")

	t.current = "impact has counterplay, actual damage and real movement checks"
	var prior: float = victim.survival.health
	sim.time = float(strike["at"])
	sim._tick_lightning()
	t.near(victim.survival.health, prior - StormLightning.DAMAGE, 0.0001,
		"standing inside warning circle applies exactly one server hit")
	t.check(sim.lightning_pending.is_empty(),
		"resolved lightning cannot hit again on repeated tick")
	sim._tick_lightning()
	t.near(victim.survival.health, prior - StormLightning.DAMAGE, 0.0001,
		"replayed tick does not duplicate lightning damage")
	t.check(not sim.snapshot_for(11).has("lightning_telegraph"),
		"resolved strike disappears immediately from snapshots")
	var bolt_center := Vector2(float(strike["x"]), float(strike["z"]))
	victim.position = pos
	victim.dodge_immunity = 1.0
	sim.lightning_pending = StormLightning.create_warning(world, pos, now)
	sim.time = float(sim.lightning_pending["at"])
	var before_dodge: float = victim.survival.health
	sim._tick_lightning()
	t.eq(victim.survival.health, before_dodge,
		"authenticated dodge immunity negates environmental hit")
	victim.dodge_immunity = 0.0
	victim.position += Vector3(StormLightning.RADIUS + 20.0, 0, 0)
	sim.lightning_pending = StormLightning.create_warning(world, pos, now)
	sim.time = float(sim.lightning_pending["at"])
	sim._tick_lightning()
	t.eq(victim.survival.health, before_dodge,
		"moving away from locked bolt position avoids damage")
	t.check(StormLightning.in_blast(bolt_center, Vector3(
		bolt_center.x, world.height_at(bolt_center.x, bolt_center.y), bolt_center.y)),
		"danger area is a real static world circle")
