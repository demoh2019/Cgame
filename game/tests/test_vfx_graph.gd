extends RefCounted
## VFX graph runtime: spawning, forces, over-life curves, collisions, event routing, budget, node.

const VfxGraph = preload("res://scripts/client/vfx_graph.gd")
const VfxGraphNode = preload("res://scripts/client/vfx_graph_node.gd")


func _one(spawn: Array, update: Array, extra: Dictionary = {}) -> Dictionary:
	var em: Dictionary = {"max_particles": 500, "spawn": spawn, "update": update}
	em.merge(extra, true)
	return {"emitters": {"main": em}}


func _life(v: float) -> Dictionary:
	return {"type": "lifetime_random", "min": v, "max": v}


func run(t) -> void:
	t.current = "spawn rate and burst"
	var sys: Dictionary = VfxGraph.create_system(_one([{"type": "spawn_rate", "rate": 10.0}, _life(100.0)], []), 1)
	VfxGraph.tick(sys, 1.0)
	t.eq(VfxGraph.particle_count(sys, "main"), 10, "rate 10/s over 1s")
	VfxGraph.tick(sys, 0.5)
	t.eq(VfxGraph.particle_count(sys, "main"), 15, "fractional accumulation")
	sys = VfxGraph.create_system(_one([{"type": "spawn_burst", "count": 25}, _life(100.0)], []), 1)
	VfxGraph.tick(sys, 0.1)
	VfxGraph.tick(sys, 0.1)
	t.eq(VfxGraph.particle_count(sys, "main"), 25, "burst fires once")

	t.current = "lifetime death"
	sys = VfxGraph.create_system(_one([{"type": "spawn_burst", "count": 5}, _life(0.5)], []), 1)
	VfxGraph.tick(sys, 0.1)
	VfxGraph.tick(sys, 0.3)
	t.eq(VfxGraph.particle_count(sys, "main"), 5, "alive before lifetime")
	VfxGraph.tick(sys, 0.3)
	t.eq(VfxGraph.particle_count(sys, "main"), 0, "dead after lifetime")
	t.check(VfxGraph.is_finished(sys), "system finished")

	t.current = "gravity and drag"
	sys = VfxGraph.create_system(_one([{"type": "spawn_burst", "count": 1}, _life(10.0)], [{"type": "gravity", "gravity": Vector3(0, -10, 0)}]), 1)
	for i in 11:
		VfxGraph.tick(sys, 0.1)
	var v: PackedVector3Array = VfxGraph.attribute(sys, "main", "velocity")
	var p: PackedVector3Array = VfxGraph.attribute(sys, "main", "position")
	t.near(v[0].y, -10.0, 0.001, "gravity integrates velocity")
	t.near(p[0].y, -5.5, 0.001, "gravity integrates position")
	sys = VfxGraph.create_system(_one([{"type": "spawn_burst", "count": 1}, _life(10.0), {"type": "initial_velocity", "direction": Vector3.RIGHT, "speed": 10.0}], [{"type": "drag", "drag": 1.0}]), 1)
	for i in 11:
		VfxGraph.tick(sys, 0.1)
	v = VfxGraph.attribute(sys, "main", "velocity")
	t.near(v[0].x, 10.0 * exp(-1.0), 0.001, "drag decays exponentially")

	t.current = "over life curves"
	sys = VfxGraph.create_system(_one([{"type": "spawn_burst", "count": 1}, _life(1.0)], [
		{"type": "color_over_life", "stops": [[0.0, Color(1, 0, 0, 1)], [1.0, Color(0, 0, 1, 1)]]},
		{"type": "size_over_life", "stops": [[0.0, 1.0], [1.0, 3.0]]}]), 1)
	VfxGraph.tick(sys, 0.0)
	VfxGraph.tick(sys, 0.5)
	var c: PackedColorArray = VfxGraph.attribute(sys, "main", "color")
	var s: PackedFloat32Array = VfxGraph.attribute(sys, "main", "size")
	t.near(c[0].r, 0.5, 0.001, "color red half way")
	t.near(c[0].b, 0.5, 0.001, "color blue half way")
	t.near(s[0], 2.0, 0.001, "size half way")
	var grad := Gradient.new()
	grad.set_color(0, Color.BLACK)
	grad.set_color(1, Color.WHITE)
	sys = VfxGraph.create_system(_one([{"type": "spawn_burst", "count": 1}, _life(1.0)], [{"type": "color_over_life", "gradient": grad}]), 1)
	VfxGraph.tick(sys, 0.0)
	VfxGraph.tick(sys, 0.5)
	c = VfxGraph.attribute(sys, "main", "color")
	t.near(c[0].r, 0.5, 0.01, "gradient resource sampled")

	t.current = "collision and events"
	var asset: Dictionary = {"emitters": {
		"spark": {"max_particles": 10, "spawn": [{"type": "spawn_burst", "count": 1}, _life(5.0),
			{"type": "initial_position_sphere", "radius": 0.0, "center": Vector3(0, 1, 0)},
			{"type": "initial_velocity", "direction": Vector3.DOWN, "speed": 5.0}],
			"update": [{"type": "collide_plane", "normal": Vector3.UP, "offset": 0.0, "restitution": 0.5,
				"on_event": {"emitter": "puff", "count": 3}}]},
		"puff": {"max_particles": 20, "spawn": [_life(5.0)], "update": []}}}
	sys = VfxGraph.create_system(asset, 3)
	VfxGraph.tick(sys, 0.1)
	t.eq(VfxGraph.particle_count(sys, "puff"), 0, "no event before impact")
	VfxGraph.tick(sys, 0.5)
	v = VfxGraph.attribute(sys, "spark", "velocity")
	p = VfxGraph.attribute(sys, "spark", "position")
	t.near(v[0].y, 2.5, 0.001, "bounce reflects with restitution")
	t.near(p[0].y, 0.0, 0.001, "pushed back onto plane")
	t.eq(VfxGraph.particle_count(sys, "puff"), 3, "collision spawns in secondary emitter")
	asset = {"emitters": {
		"a": {"max_particles": 10, "spawn": [{"type": "spawn_burst", "count": 2}, _life(0.1)], "update": [],
			"events": {"death": {"emitter": "b", "count": 4}}},
		"b": {"max_particles": 50, "spawn": [_life(5.0)], "update": []}}}
	sys = VfxGraph.create_system(asset, 3)
	for i in 4:
		VfxGraph.tick(sys, 0.05)
	t.eq(VfxGraph.particle_count(sys, "b"), 8, "death events route to emitter b")
	var kill := VfxGraph.create_system(_one([{"type": "spawn_burst", "count": 3}, _life(10.0), {"type": "initial_position_sphere", "radius": 0.0, "center": Vector3(0, -1, 0)}], [{"type": "kill_below_plane", "offset": 0.0}]), 1)
	VfxGraph.tick(kill, 0.1)
	VfxGraph.tick(kill, 0.1)
	t.eq(VfxGraph.particle_count(kill, "main"), 0, "kill_below_plane removes particles")

	t.current = "cap, determinism, profile"
	sys = VfxGraph.create_system({"emitters": {"main": {"max_particles": 10, "spawn": [{"type": "spawn_burst", "count": 100}, _life(5.0)], "update": []}}}, 1)
	VfxGraph.tick(sys, 0.1)
	t.eq(VfxGraph.particle_count(sys, "main"), 10, "max_particles cap")
	var noisy: Dictionary = _one([{"type": "spawn_rate", "rate": 50.0}, {"type": "lifetime_random", "min": 1.0, "max": 2.0},
		{"type": "initial_position_sphere", "radius": 2.0}, {"type": "initial_velocity", "speed_min": 1.0, "speed_max": 3.0, "spread": 40.0}],
		[{"type": "curl_noise", "strength": 2.0}, {"type": "vortex", "strength": 1.0}, {"type": "attractor", "position": Vector3(1, 1, 1)}, {"type": "gravity"}],
		{"attributes": {"heat": 0.5}})
	var s1: Dictionary = VfxGraph.create_system(noisy, 42)
	var s2: Dictionary = VfxGraph.create_system(noisy, 42)
	var s3: Dictionary = VfxGraph.create_system(noisy, 43)
	for i in 20:
		VfxGraph.tick(s1, 0.05)
		VfxGraph.tick(s2, 0.05)
		VfxGraph.tick(s3, 0.05)
	t.check(VfxGraph.attribute(s1, "main", "position") == VfxGraph.attribute(s2, "main", "position"), "same seed identical")
	t.check(VfxGraph.attribute(s1, "main", "position") != VfxGraph.attribute(s3, "main", "position"), "different seed differs")
	var heat: PackedFloat32Array = VfxGraph.attribute(s1, "main", "heat")
	t.eq(heat.size(), VfxGraph.particle_count(s1, "main"), "custom attribute sized to live count")
	t.near(heat[0], 0.5, 0.0001, "custom attribute default")
	var prof: Dictionary = s1["profile"]
	t.check(prof.size() >= 6, "profile has per-module entries")
	var has_gravity: bool = false
	for key in prof.keys():
		if str(key).contains("gravity"):
			has_gravity = true
		t.check(int(prof[key]) >= 0, "profile usec non-negative")
	t.check(has_gravity, "profile names modules")

	t.current = "node"
	var node: Node3D = VfxGraphNode.new()
	node.setup(_one([{"type": "spawn_burst", "count": 12}, _life(5.0)], []), 7)
	node.step(0.1)
	var mmi: MultiMeshInstance3D = node.get_child(0) as MultiMeshInstance3D
	t.check(mmi != null and mmi.multimesh != null, "node builds a MultiMeshInstance3D")
	t.eq(mmi.multimesh.visible_instance_count, node.particle_count(), "multimesh count matches particles")
	t.eq(node.particle_count(), 12, "node simulated burst")
	node.free()
	var capped: Node3D = VfxGraphNode.new()
	capped.budget_particles = 5
	capped.setup(_one([{"type": "spawn_burst", "count": 20}, _life(5.0)], []), 7)
	capped.step(0.1)
	t.eq(capped.particle_count(), 5, "node budget limits particles")
	capped.free()
	var shot: Node3D = VfxGraphNode.new()
	shot.one_shot = true
	shot.setup(_one([{"type": "spawn_burst", "count": 3}, _life(0.2)], []), 7)
	shot.step(0.1)
	t.check(not shot.is_finished(), "one_shot alive while particles live")
	shot.step(0.2)
	t.check(shot.is_finished(), "one_shot finishes when empty")
	shot.free()
