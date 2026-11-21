extends RefCounted
## Smoke/fire simulation, volume shader, VFX budget, event bindings and sequences.

const SmokeSim = preload("res://scripts/shared/smoke_sim.gd")
const VfxBudget = preload("res://scripts/client/vfx_budget.gd")
const VfxBindings = preload("res://scripts/client/vfx_bindings.gd")

var _spawned: Array = []


func _spawn(effect: String, pos: Vector3, params: Dictionary) -> void:
	_spawned.append({"effect": effect, "pos": pos, "params": params})


func run(t) -> void:
	_test_smoke(t)
	_test_shader(t)
	_test_budget(t)
	_test_bindings(t)


func _test_smoke(t) -> void:
	t.current = "smoke buoyancy"
	var sim := SmokeSim.new(14)
	for bz in range(5, 10):
		for by in range(2, 5):
			for bx in range(5, 10):
				sim.add_source(Vector3i(bx, by, bz), 1.0, 1.0)
	var y0 := sim.density_centroid().y
	for i in 25:
		sim.step(0.05)
	t.check(sim.density_centroid().y > y0 + 0.5, "hot smoke rises (%f -> %f)" % [y0, sim.density_centroid().y])
	t.check(sim.is_finite_state(), "values stay finite")
	t.check(sim.total_density() > 0.1, "smoke persists")

	t.current = "smoke obstacles"
	var s2 := SmokeSim.new(14)
	for x in 14:
		for z in 14:
			s2.set_obstacle(Vector3i(x, 8, z), true)
			s2.set_obstacle(Vector3i(x, 9, z), true)
	s2.add_source(Vector3i(7, 4, 7), 2.0, 1.0)
	for i in 30:
		s2.add_source(Vector3i(7, 4, 7), 0.2, 0.5)
		s2.step(0.05)
	var above := 0.0
	for z in 14:
		for y in range(10, 14):
			for x in 14:
				above += s2.density[s2.index(x, y, z)]
	t.check(above < 0.001 * maxf(s2.total_density(), 1.0), "slab blocks smoke")
	t.check(s2.total_density() > 0.5, "smoke accumulates under slab")
	t.eq(s2.density[s2.index(3, 8, 3)], 0.0, "obstacle voxels hold no density")
	s2.add_source(Vector3i(3, 8, 3), 5.0)
	t.eq(s2.density[s2.index(3, 8, 3)], 0.0, "cannot add into obstacle")

	t.current = "smoke wind"
	var s3 := SmokeSim.new(16)
	s3.buoyancy = 0.0
	s3.vorticity_strength = 0.0
	s3.wind = Vector3(5.0, 0.0, 0.0)
	s3.add_source(Vector3i(4, 8, 8), 2.0)
	var x0 := s3.density_centroid().x
	for i in 12:
		s3.step(0.05)
	t.check(s3.density_centroid().x > x0 + 1.0, "wind carries smoke downwind")
	t.check(absf(s3.density_centroid().y - 8.0) < 0.5, "wind does not lift smoke")

	t.current = "fire combustion"
	var s4 := SmokeSim.new(12)
	s4.add_source(Vector3i(6, 4, 6), 0.0, 0.6, 1.0)
	var fuel0 := s4.total_fuel()
	var heat0 := s4.total_temperature()
	var dens0 := s4.total_density()
	s4.step(0.05)
	t.check(s4.total_fuel() < fuel0, "fuel burns when hot")
	t.check(s4.total_temperature() > heat0, "burning releases heat")
	t.check(s4.total_density() > dens0, "burning releases smoke")
	var s5 := SmokeSim.new(12)
	s5.add_source(Vector3i(6, 4, 6), 0.0, 0.1, 1.0)
	s5.step(0.05)
	t.near(s5.total_fuel(), 1.0, 0.03, "cold fuel does not ignite")
	for i in 30:
		s4.step(0.05)
	t.check(s4.is_finite_state(), "fire stays finite")

	t.current = "smoke projection"
	var s6 := SmokeSim.new(12)
	for z in 12:
		for y in 12:
			for x in 12:
				var i := s6.index(x, y, z)
				s6.vx[i] = sin(x * 1.3 + y * 0.7) * 3.0
				s6.vy[i] = cos(y * 1.1 + z * 0.9) * 3.0
				s6.vz[i] = sin(z * 0.8 + x * 0.5) * 3.0
	s6.jacobi_iterations = 40
	var before := s6.divergence_rms()
	s6.project()
	var after := s6.divergence_rms()
	t.check(before > 0.1, "test field is divergent")
	t.check(after < before * 0.6, "projection reduces divergence")

	t.current = "smoke textures"
	var slices := sim.density_image_slices()
	t.eq(slices.size(), 14, "one slice per z layer")
	t.eq(slices[0].get_width(), 14, "slice width")
	t.eq(slices[0].get_format(), Image.FORMAT_RGF, "slice format")
	var tex := sim.to_image3d()
	t.check(tex != null, "to_image3d builds an ImageTexture3D")


func _test_shader(t) -> void:
	t.current = "smoke volume shader"
	var sh: Shader = load("res://assets/shaders/smoke_volume.gdshader")
	t.check(sh != null, "shader loads")
	if sh == null:
		return
	var names: Array[String] = []
	for u in sh.get_shader_uniform_list():
		names.append(str((u as Dictionary)["name"]))
	for want in ["volume_tex", "density_scale", "temperature_scale", "emission_strength", "smoke_color", "steps"]:
		t.check(names.has(want), "uniform %s" % want)
	t.check(sh.code.contains("fire_ramp"), "has blackbody ramp")


func _test_budget(t) -> void:
	t.current = "vfx budget"
	var b := VfxBudget.new(VfxBudget.Tier.LOW)
	var cam := Vector3.ZERO
	var cap_e := b.max_effects("weather")
	var ids: Array[int] = []
	for i in cap_e:
		ids.append(b.request_id("weather", 10, 1.0, Vector3(float(i), 0, 0), cam))
	t.eq(b.active_effects("weather"), cap_e, "fills category cap")
	t.check(not b.request("weather", 10, 0.5, Vector3(0, 0, 30), cam), "low value rejected at cap")
	t.eq(int(b.stats["rejected"]), 1, "rejection counted")
	var vip := b.request_id("weather", 10, 100.0, Vector3(1, 0, 0), cam)
	t.check(vip > 0, "high priority admitted")
	t.eq(b.active_effects("weather"), cap_e, "cap held after eviction")
	t.eq(int(b.stats["evicted"]), 1, "one eviction")
	var evicted_far := 0
	for id in ids:
		if not b.is_live(id):
			evicted_far = id
	t.eq(evicted_far, ids[cap_e - 1], "farthest equal-priority effect evicted")
	t.check(not b.request("weather", 10, 1.0, Vector3(500, 0, 0), cam), "beyond max distance rejected")
	t.check(not b.request("weather", 999999, 100.0, Vector3(1, 0, 0), cam), "oversize cost rejected")
	b.release(vip)
	t.eq(b.active_effects("weather"), cap_e - 1, "release frees a slot")
	var bh := VfxBudget.new(VfxBudget.Tier.ULTRA)
	t.check(bh.max_particles("combat") > b.max_particles("combat"), "higher tier larger cap")
	var bp := VfxBudget.new(VfxBudget.Tier.MEDIUM)
	t.check(bp.request("ui", 300, 1.0, Vector3.ZERO, cam), "fits particle cap")
	t.check(not bp.request("ui", 300, 1.0, Vector3.ZERO, cam), "particle cap blocks equal value")
	t.check(bp.request("ui", 300, 5.0, Vector3.ZERO, cam), "particle cap evicts cheaper value")
	t.eq(bp.active_particles("ui"), 300, "particle total after eviction")


func _test_bindings(t) -> void:
	t.current = "vfx bindings"
	var vb := VfxBindings.new()
	vb.register("hit", {
		"effect": "blood_spark",
		"offset": Vector3(0, 1, 0),
		"params": {
			"intensity": {"from": "damage", "scale": 0.1, "min": 0.0, "max": 1.0},
			"color": "red",
		},
	})
	vb.register("lightning_struck", {"sequence": "strike", "params": {"level": {"from": "level", "default": 1}}})
	vb.register_sequence("strike", [
		{"t": 0.5, "effect": "smoke_puff", "offset": Vector3(0, 2, 0), "params": {"size": 2.0}},
		{"t": 0.0, "effect": "flash"},
		{"t": 1.0, "effect": "embers"},
	])
	t.check(vb.has_binding("hit"), "binding registered")
	_spawned.clear()
	var n := vb.handle({"type": "hit", "position": Vector3(5, 0, 0), "payload": {"damage": 25}}, _spawn)
	t.eq(n, 1, "hit spawns one effect")
	t.eq(_spawned[0]["effect"], "blood_spark", "preset chosen")
	t.check((_spawned[0]["pos"] as Vector3).is_equal_approx(Vector3(5, 1, 0)), "offset applied")
	var p: Dictionary = _spawned[0]["params"]
	t.near(float(p["intensity"]), 1.0, 0.001, "damage mapped and clamped to max")
	t.eq(p["color"], "red", "constant param passes through")
	vb.handle({"type": "hit", "position": Vector3.ZERO, "payload": {"damage": 4}}, _spawn)
	t.near(float(_spawned[1]["params"]["intensity"]), 0.4, 0.001, "damage scaled")
	t.eq(vb.handle({"type": "nothing"}, _spawn), 0, "unknown event ignored")

	t.current = "vfx sequence"
	_spawned.clear()
	vb.handle({"type": "lightning_struck", "position": Vector3(1, 0, 1), "payload": {"level": 3}}, _spawn)
	t.eq(_spawned.size(), 1, "t=0 entry fires immediately")
	t.eq(_spawned[0]["effect"], "flash", "entries sorted by time")
	t.eq(vb.active_sequences(), 1, "sequence running")
	vb.tick(0.4)
	t.eq(_spawned.size(), 1, "nothing before t=0.5")
	vb.tick(0.2)
	t.eq(_spawned.size(), 2, "t=0.5 entry fires")
	t.check((_spawned[1]["pos"] as Vector3).is_equal_approx(Vector3(1, 2, 1)), "sequence offset from origin")
	t.eq(_spawned[1]["params"]["level"], 3, "base params inherited")
	t.near(float(_spawned[1]["params"]["size"]), 2.0, 0.001, "entry params merged")
	vb.tick(0.5)
	t.eq(_spawned.size(), 3, "last entry fires")
	t.eq(vb.active_sequences(), 0, "finished sequence dropped")
	var seq := vb.make_sequence("strike", _spawn)
	t.eq(seq.advance(10.0), 3, "advance fires everything due")
	t.check(seq.is_finished(), "sequence finished")
	t.check(vb.make_sequence("missing", _spawn) == null, "unknown sequence null")
