extends RefCounted
## GPU compute backends: support decisions, generated GLSL structure, CPU-fallback parity with
## VfxGraph, event routing and instance culling. No GPU execution is required (or attempted when the
## renderer is the headless dummy); the device path is unverified until run on real hardware.

const Backend = preload("res://scripts/client/gpu_particle_backend.gd")
const Culling = preload("res://scripts/client/gpu_instance_culling.gd")
const VfxGraph = preload("res://scripts/client/vfx_graph.gd")


func _box_planes(half: float) -> Array:
	return [
		Plane(Vector3(1, 0, 0), half), Plane(Vector3(-1, 0, 0), half),
		Plane(Vector3(0, 1, 0), half), Plane(Vector3(0, -1, 0), half),
		Plane(Vector3(0, 0, 1), half), Plane(Vector3(0, 0, -1), half),
	]


func _brute(aabbs: Array, planes: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i in aabbs.size():
		var box: AABB = aabbs[i]
		var inside: bool = true
		for p_v in planes:
			var pl: Plane = p_v
			var best: float = INF
			for k in 8:
				var corner: Vector3 = box.get_endpoint(k)
				best = minf(best, pl.normal.dot(corner) - pl.d)
			if best > 0.0:
				inside = false
				break
		if inside:
			out.append(i)
	return out


func run(t) -> void:
	t.current = "supports"
	var good: Dictionary = {
		"max_particles": 64,
		"spawn": [{"type": "lifetime_random", "min": 1.0, "max": 1.0}, {"type": "spawn_burst", "count": 1, "time": 0.0}],
		"update": [{"type": "gravity"}, {"type": "drag", "drag": 0.5}, {"type": "curl_noise"}, {"type": "vortex"},
			{"type": "color_over_life", "stops": [[0.0, Color.WHITE], [1.0, Color.RED]]},
			{"type": "size_over_life", "stops": [[0.0, 1.0], [1.0, 0.0]]},
			{"type": "collide_plane"}, {"type": "kill_below_plane", "offset": -5.0}],
	}
	t.check(Backend.supports(good), "full supported module set is GPU-able")
	t.check(not Backend.supports({"update": [{"type": "attractor"}]}), "attractor is CPU only")
	t.check(not Backend.supports({"update": [{"type": "color_over_life", "gradient": Gradient.new()}]}), "gradient resources are CPU only")
	t.check(not Backend.supports({"update": [], "attributes": {"heat": 1.0}}), "custom attributes are CPU only")
	t.check(not Backend.supports({"spawn": [{"type": "initial_position_sphere"}], "update": []}), "spawn shape modules are CPU only")
	t.check(Backend.unsupported_modules({"update": [{"type": "attractor"}]}).has("attractor"), "unsupported list names the module")
	t.check(Backend.supports_system({"emitters": {"a": good}}), "system of supported emitters")
	t.check(not Backend.supports_system({"emitters": {"a": good, "b": {"update": [{"type": "attractor"}]}}}), "one bad emitter taints the system")

	t.current = "generated source"
	var src: String = Backend.generate_compute_source(good)
	t.check(src.begins_with("#[compute]"), "starts with compute tag")
	t.check(src.contains("#version 450"), "version directive")
	t.check(src.contains("layout(set = 0, binding = 0, std430)"), "particle SSBO binding")
	t.check(src.contains("layout(set = 0, binding = 1, std430)"), "event buffer binding")
	t.check(src.contains("atomicAdd(events.count"), "atomic event append")
	t.check(src.contains("layout(push_constant"), "push constants")
	t.check(src.contains("cn_curl("), "curl helper present")
	t.check(src.contains("exp(-0.50000000 * dt)"), "drag module code baked in")
	t.check(src.contains("color_curve_4(") and src.contains("size_curve_5("), "over-life curves generated per module")
	t.check(src.contains("age = life + 1.0"), "kill plane code")
	t.check(not src.contains("{{"), "all placeholders substituted")
	t.check(src.count("{") == src.count("}"), "balanced braces")
	t.eq(Backend.generate_compute_source({"update": [{"type": "attractor"}]}), "", "unsupported emitter yields no source")
	var plain: String = Backend.generate_compute_source({"update": [{"type": "gravity"}]})
	t.check(not plain.contains("cn_curl"), "curl helper omitted when unused")
	t.check(plain.contains("const bool ROUTE_DEATH = false;"), "no death routing without spec")
	var routed_src: String = Backend.generate_compute_source({"update": [{"type": "collide_plane"}], "events": {"death": {"emitter": "x"}, "collision": {"emitter": "x"}}})
	t.check(routed_src.contains("const bool ROUTE_DEATH = true;") and routed_src.contains("emit_event(1u, p, v);"), "event slots in source")
	var cull_src: String = Culling.new().generate_compute_source()
	t.check(cull_src.begins_with("#[compute]") and cull_src.contains("#version 450"), "cull shader header")
	t.check(cull_src.contains("atomicAdd(visible.count") and cull_src.contains("binding = 3"), "cull shader compaction and hiz binding")
	t.check(cull_src.count("{") == cull_src.count("}"), "cull shader balanced braces")

	t.current = "particle cpu fallback parity"
	var asset: Dictionary = {
		"max_particles": 16,
		"spawn": [
			{"type": "lifetime_random", "min": 100.0, "max": 100.0},
			{"type": "initial_velocity", "direction": Vector3(0, 1, 0), "speed": 3.0},
			{"type": "spawn_burst", "count": 1, "time": 0.0},
		],
		"update": [{"type": "gravity", "gravity": Vector3(0, -9.81, 0)}, {"type": "drag", "drag": 0.7}],
	}
	var be = Backend.new()
	be.force_cpu = true
	t.check(be.create({"emitters": {"e": asset}}, 5), "all emitters supported")
	t.check(not be.device_available(), "force_cpu disables device")
	var sys: Dictionary = VfxGraph.create_system({"emitters": {"e": asset}}, 5)
	for i in 30:
		be.tick(1.0 / 60.0)
		VfxGraph.tick(sys, 1.0 / 60.0)
	t.eq(be.last_path, "cpu", "cpu path reported")
	t.eq(be.count("e"), 1, "one particle")
	var ref_pos: PackedVector3Array = VfxGraph.attribute(sys, "e", "position")
	var ref_vel: PackedVector3Array = VfxGraph.attribute(sys, "e", "velocity")
	var em = be.get_emitter("e")
	t.check(ref_pos.size() == 1 and em.count == 1, "both have the particle")
	t.check(em.pos[0].distance_to(ref_pos[0]) < 0.001, "position matches VfxGraph")
	t.check(em.vel[0].distance_to(ref_vel[0]) < 0.001, "velocity matches VfxGraph")
	t.check(em.pos[0].y > 0.0 and em.vel[0].y < 3.0, "gravity and drag actually acted")

	t.current = "particle modules"
	var mods: Dictionary = {
		"max_particles": 8,
		"spawn": [{"type": "lifetime_random", "min": 2.0, "max": 2.0}, {"type": "initial_color", "color": Color.WHITE}, {"type": "initial_size", "min": 2.0, "max": 2.0}],
		"update": [
			{"type": "color_over_life", "stops": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 0, 0, 0)]]},
			{"type": "size_over_life", "stops": [[0.0, 1.0], [1.0, 0.0]]},
			{"type": "vortex", "strength": 2.0},
			{"type": "curl_noise", "strength": 1.0, "frequency": 0.7},
			{"type": "kill_below_plane", "offset": -100.0},
		],
	}
	var bm = Backend.new()
	bm.force_cpu = true
	bm.create(mods, 1)
	bm.spawn("main", 3, Vector3(1, 2, 3))
	for i in 60:
		bm.tick(1.0 / 60.0)
	var em2 = bm.get_emitter("main")
	t.eq(em2.count, 3, "particles alive at half life")
	t.near(em2.size[0], 1.0, 0.02, "size over life halves 2.0 base")
	t.near(em2.col[0].a, 0.5, 0.02, "color over life fades alpha")
	t.check(em2.vel[0].length() > 0.0, "vortex and curl add velocity")
	t.check(Backend.curl_lite(Vector3(0.3, 0.4, 0.5), 0.7).length() > 0.0, "curl lite non-zero")
	var plane: Dictionary = {"max_particles": 4, "spawn": [{"type": "lifetime_random", "min": 10.0, "max": 10.0}],
		"update": [{"type": "collide_plane", "restitution": 0.5}]}
	var bp = Backend.new()
	bp.force_cpu = true
	bp.create(plane, 1)
	bp.spawn("main", 1, Vector3(0, 0.1, 0), Vector3(0, -10, 0))
	bp.tick(0.1)
	var ep = bp.get_emitter("main")
	t.check(ep.pos[0].y >= -0.0001, "collide plane pushes particle out")
	t.check(ep.vel[0].y > 0.0, "collide plane bounces velocity up")
	var killer: Dictionary = {"max_particles": 4, "spawn": [{"type": "lifetime_random", "min": 10.0, "max": 10.0}],
		"update": [{"type": "kill_below_plane", "offset": 0.0}]}
	var bk = Backend.new()
	bk.force_cpu = true
	bk.create(killer, 1)
	bk.spawn("main", 2, Vector3(0, -1, 0))
	bk.tick(0.01)
	t.eq(bk.count("main"), 0, "kill below plane removes particles")

	t.current = "event routing"
	var routed: Dictionary = {"emitters": {
		"a": {"max_particles": 8,
			"spawn": [{"type": "lifetime_random", "min": 0.05, "max": 0.05}, {"type": "spawn_burst", "count": 2, "time": 0.0}],
			"update": [{"type": "gravity"}],
			"events": {"death": {"emitter": "b", "count": 3, "inherit_velocity": 0.5}}},
		"b": {"max_particles": 32, "spawn": [{"type": "lifetime_random", "min": 5.0, "max": 5.0}], "update": []},
	}}
	var br = Backend.new()
	br.force_cpu = true
	t.check(br.create(routed, 3), "routed system supported")
	br.tick(0.1)
	t.eq(br.count("a"), 2, "burst spawned after first tick")
	t.eq(br.count("b"), 0, "nothing routed yet")
	var delivered: int = br.tick(0.1)
	t.eq(br.count("a"), 0, "parents died")
	t.eq(delivered, 2, "two death events routed")
	t.eq(br.count("b"), 6, "target emitter spawned 2 x 3")
	t.check(br.get_emitter("b").pos[0].distance_to(br.get_emitter("b").pos[0]) == 0.0, "target particles exist")
	var unsup: Dictionary = {"emitters": {"ok": {"update": []}, "bad": {"update": [{"type": "attractor"}]}}}
	var bu = Backend.new()
	bu.force_cpu = true
	t.check(not bu.create(unsup, 1), "create reports unsupported emitters")
	t.eq(bu.unsupported, ["bad"], "unsupported emitter listed")
	t.eq(bu.count("bad"), 0, "unsupported emitter not simulated")

	t.current = "device absent"
	var bd = Backend.new()
	bd.create(asset, 1)
	bd.spawn("main", 1)
	bd.tick(0.016)
	t.check(bd.last_path == "cpu" or bd.last_path == "gpu", "tick runs on some path")
	t.check(bd.count("main") >= 1, "ticks survive without a device")
	bd.shutdown()
	bd.shutdown()
	var cd = Culling.new()
	cd.force_cpu = true
	t.check(not cd.device_available(), "forced cpu has no device")

	t.current = "culling frustum"
	var cu = Culling.new()
	cu.force_cpu = true
	var planes: Array = _box_planes(10.0)
	var boxes: Array = [
		AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)),
		AABB(Vector3(20, 0, 0), Vector3(2, 2, 2)),
		AABB(Vector3(9, 0, 0), Vector3(4, 2, 2)),
		AABB(Vector3(0, 0, -30), Vector3(1, 1, 1)),
		AABB(Vector3(10.1, 0, 0), Vector3(1, 1, 1)),
	]
	var vis: PackedInt32Array = cu.cull(boxes, planes)
	t.eq(Array(vis), [0, 2], "inside and straddling boxes kept, outside rejected")
	t.eq(cu.last_path, "cpu", "cpu path reported")
	t.eq(cu.cull([], planes).size(), 0, "empty input")
	t.eq(cu.cull(boxes, []).size(), boxes.size(), "no planes keeps everything")
	var sph: PackedInt32Array = cu.cull_spheres(PackedVector3Array([Vector3.ZERO, Vector3(30, 0, 0)]), PackedFloat32Array([1.0, 1.0]), planes)
	t.eq(Array(sph), [0], "sphere cull")

	t.current = "culling random vs brute force"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var rand_boxes: Array = []
	for i in 600:
		rand_boxes.append(AABB(Vector3(rng.randf_range(-25, 25), rng.randf_range(-25, 25), rng.randf_range(-25, 25)),
			Vector3(rng.randf_range(0.1, 4), rng.randf_range(0.1, 4), rng.randf_range(0.1, 4))))
	var tilted: Array = [Plane(Vector3(1, 1, 0).normalized(), 12.0), Plane(Vector3(-1, 0.5, 0).normalized(), 9.0),
		Plane(Vector3(0, -1, 1).normalized(), 11.0), Plane(Vector3(0, 0.3, -1).normalized(), 14.0)]
	t.eq(Array(cu.cull(rand_boxes, planes)), Array(_brute(rand_boxes, planes)), "box frustum matches brute force")
	t.eq(Array(cu.cull(rand_boxes, tilted)), Array(_brute(rand_boxes, tilted)), "tilted planes match brute force")
	var many: PackedInt32Array = cu.cull(rand_boxes, planes)
	t.check(many.size() > 0 and many.size() < rand_boxes.size(), "random set is partially visible")

	t.current = "culling hi-z"
	var proj: Projection = Projection.create_orthogonal(-10.0, 10.0, -10.0, 10.0, 0.1, 100.0)
	var wall_clip: Vector4 = proj * Vector4(0, 0, -20, 1)
	var wall_depth: float = wall_clip.z / wall_clip.w * 0.5 + 0.5
	var depth: PackedFloat32Array = PackedFloat32Array()
	depth.resize(16 * 16)
	depth.fill(wall_depth)
	var hiz: Dictionary = {"view_proj": proj, "width": 16, "height": 16, "depth": depth, "bias": 0.0001}
	var occl: Array = [
		AABB(Vector3(-1, -1, -51), Vector3(2, 2, 2)),
		AABB(Vector3(-1, -1, -6), Vector3(2, 2, 2)),
		AABB(Vector3(-1, -1, 4), Vector3(2, 2, 2)),
	]
	var big_planes: Array = [Plane(Vector3(1, 0, 0), 10.0), Plane(Vector3(-1, 0, 0), 10.0), Plane(Vector3(0, 1, 0), 10.0), Plane(Vector3(0, -1, 0), 10.0),
		Plane(Vector3(0, 0, 1), 100.0), Plane(Vector3(0, 0, -1), 100.0)]
	t.eq(Array(cu.cull(occl, big_planes)), [0, 1, 2], "without hi-z everything inside the frustum is kept")
	t.eq(Array(cu.cull(occl, big_planes, hiz)), [1, 2], "box behind the wall is occluded, nearer and near-plane boxes stay")
	depth[8 * 16 + 8] = 1.0
	depth[7 * 16 + 8] = 1.0
	depth[8 * 16 + 7] = 1.0
	depth[7 * 16 + 7] = 1.0
	hiz["depth"] = depth
	t.eq(Array(cu.cull(occl, big_planes, hiz)), [0, 1, 2], "a gap in the occluder reveals the box")
	t.check(cu.cull_packed(PackedVector3Array(), PackedVector3Array(), planes).is_empty(), "packed empty input")
