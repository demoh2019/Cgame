extends RefCounted
## Cosmetic physics and world interactivity: debris, blasts, buoyancy, bounce, plant bend/shake, cloth flag, chains.

const PhysicsDebris = preload("res://scripts/client/physics_debris.gd")
const PhysicsWorldFx = preload("res://scripts/client/physics_world_fx.gd")
const PlantInteraction = preload("res://scripts/client/plant_interaction.gd")
const LootDropBounce = preload("res://scripts/client/loot_drop_bounce.gd")
const ClothFlag = preload("res://scripts/client/cloth_flag.gd")
const HangingLantern = preload("res://scripts/client/hanging_lantern.gd")


func run(t) -> void:
	t.current = "debris budgets"
	t.eq(PhysicsDebris.chunk_count(0, 1.0), 0, "Low quality spawns no chunks")
	t.check(PhysicsDebris.chunk_count(3) > PhysicsDebris.chunk_count(1), "chunks grow with quality")
	t.check(PhysicsDebris.chunk_count(3, 99.0) <= PhysicsDebris.chunk_budget(3), "never over the tier cap")
	t.eq(PhysicsDebris.casing_budget(1), 0, "no casings on Balanced")
	t.check(PhysicsDebris.casing_budget(3) > PhysicsDebris.casing_budget(2), "casings grow")
	t.eq(PhysicsDebris.total_budget(-4), 0, "tier clamped")
	for i in 20:
		var s := PhysicsDebris.chunk_size(i)
		t.check(s.x > 0.0 and s.y > 0.0 and s.z > 0.0 and s.z <= 0.5, "chunk size sane %d" % i)

	t.current = "blast field"
	t.near(PhysicsDebris.falloff(0.0, 4.0), 1.0, 0.0001, "full at centre")
	t.eq(PhysicsDebris.falloff(4.0, 4.0), 0.0, "zero at radius")
	t.check(PhysicsDebris.falloff(1.0, 4.0) > PhysicsDebris.falloff(2.0, 4.0), "monotone")
	t.eq(PhysicsDebris.falloff(1.0, 0.0), 0.0, "zero radius is inert")
	t.check(PhysicsWorldFx.blast_for("barricade_broken") != Vector2.ZERO, "barricade break pushes")
	t.eq(PhysicsWorldFx.blast_for("gathered"), Vector2.ZERO, "harvest does not blast")
	t.eq(PhysicsWorldFx.chunk_strength_for("barricade_broken"), 1.0, "barricade makes chunks")

	t.current = "buoyancy"
	t.eq(PhysicsDebris.buoyancy_force(-0.1, 1.0, 0.6), 0.0, "no lift above water")
	t.check(PhysicsDebris.buoyancy_force(0.3, 1.0, 0.6) > 9.8, "wood floats (lift beats weight)")
	t.check(PhysicsDebris.buoyancy_force(0.3, 1.0, 8.5) < 9.8, "brass sinks")
	var a := PhysicsDebris.surface_height(0.0, 0.0, 0.0)
	var b := PhysicsDebris.surface_height(0.0, 0.0, 1.0)
	t.check(a != b and absf(a - b) < 0.1, "surface bobs gently")

	t.current = "retire and pool"
	t.check(not PhysicsDebris.should_retire(1.0, 0.2), "fresh and moving stays")
	t.check(PhysicsDebris.should_retire(1.0, 2.0), "sleeping bodies retire")
	t.check(PhysicsDebris.should_retire(PhysicsDebris.LIFETIME, 0.0), "old bodies retire")
	t.eq(PhysicsDebris.shrink_scale(0.0), 1.0, "starts full")
	t.eq(PhysicsDebris.shrink_scale(5.0), 0.0, "ends at zero")
	var heights := PhysicsDebris.ground_heights(10.0, 20.0, func(x, z): return x + z)
	t.eq(heights.size(), PhysicsDebris.GROUND_SIZE * PhysicsDebris.GROUND_SIZE, "heightmap grid size")
	t.near(heights[heights.size() / 2], 30.0, 0.001, "grid centred on the point")

	t.current = "debris pool runtime"
	var debris := PhysicsDebris.new()
	debris.setup(func(_x, _z): return 0.0, func(_x, _z): return false)
	debris.blast(Vector3(INF, 0, 0), 3.0, 3.0) # Non-finite ignored.
	t.eq(debris.burst_chunks(Vector3(INF, 0, 0)), 0, "non-finite position ignored")
	debris.free()

	t.current = "plant interaction"
	t.eq(PlantInteraction.bend_radius(0), 0.0, "Low leaves grass alone")
	t.check(PlantInteraction.bend_radius(3) > PlantInteraction.bend_radius(1), "radius grows")
	t.check(PlantInteraction.bend_strength(6.0) > PlantInteraction.bend_strength(0.0), "running bends more")
	t.check(PlantInteraction.bend_strength(100.0) <= PlantInteraction.MAX_BEND, "bend capped")
	t.eq(PlantInteraction.bend_strength(NAN), 0.0, "NaN speed safe")
	t.eq(PlantInteraction.shake_envelope(PlantInteraction.SHAKE_SECONDS, 1.0), 0.0, "shake ends")
	t.check(PlantInteraction.shake_envelope(0.1, 0.2) > PlantInteraction.shake_envelope(0.8, 0.2), "shake decays")
	t.check(PlantInteraction.shake_amplitude_for("gathered") > PlantInteraction.shake_amplitude_for("hit"), "harvest shakes harder")
	t.eq(PlantInteraction.shake_amplitude_for("chat"), 0.0, "unrelated events do not shake")
	var bend_global: Dictionary = ProjectSettings.get_setting("shader_globals/aa_plant_bend", {})
	t.eq(bend_global.get("type", ""), "vec4", "bend global declared in project settings")
	t.eq((ProjectSettings.get_setting("shader_globals/aa_plant_shake", {}) as Dictionary).get("type", ""), "vec4", "shake global declared")
	var include := FileAccess.get_file_as_string("res://assets/shaders/plant_interaction.gdshaderinc")
	t.check(include.contains("aa_plant_displacement"), "shader include present")
	t.check(FileAccess.get_file_as_string("res://scripts/client/grass_field.gd").contains("aa_plant_displacement"), "grass uses it")
	t.check(FileAccess.get_file_as_string("res://scripts/client/foliage.gd").contains("aa_plant_displacement"), "foliage uses it")

	t.current = "loot drop bounce"
	t.near(LootDropBounce.height(0.0), LootDropBounce.DROP_HEIGHT, 0.0001, "starts at drop height")
	var fall := sqrt(2.0 * LootDropBounce.DROP_HEIGHT / LootDropBounce.GRAVITY)
	t.near(LootDropBounce.height(fall), 0.0, 0.001, "touches down")
	t.check(LootDropBounce.height(fall + 0.15) > 0.0, "bounces after landing")
	t.eq(LootDropBounce.height(LootDropBounce.settle_time() + 0.1), 0.0, "comes to rest")
	t.check(LootDropBounce.squash(fall + 0.1) < 1.0, "squashes on impact")
	t.eq(LootDropBounce.squash(0.0), 1.0, "no squash in the air")
	var bag := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.scale = Vector3.ONE * 1.8
	bag.add_child(mesh)
	LootDropBounce.apply(bag, 0.016, 3)
	t.check(mesh.position.y > 1.0, "bag mesh starts raised")
	LootDropBounce.apply(bag, 10.0, 3)
	t.near(mesh.position.y, 0.0, 0.001, "bag mesh rests")
	t.near(mesh.scale.y, 1.8, 0.001, "scale restored")
	bag.free()

	t.current = "cloth flag"
	t.eq(ClothFlag.segments(0), 0, "Low keeps the rigid flag")
	t.check(ClothFlag.segments(3) > ClothFlag.segments(1), "more cloth segments with quality")
	var cloth := ClothFlag.build_mesh(6)
	t.eq(cloth.get_surface_count(), 1, "one surface")
	t.eq(cloth.surface_get_array_len(0), 7 * 4, "grid vertex count")
	var flag := MeshInstance3D.new()
	flag.position = Vector3(1.3, 6.1, 0)
	t.check(ClothFlag.upgrade(flag, 0) == null, "Low upgrade is a no-op")
	var material := ClothFlag.upgrade(flag, 2)
	t.check(material != null and flag.material_override == material, "cloth material installed")
	t.near(flag.position.x, 0.1, 0.001, "pinned at the pole")
	t.check(material.shader.code.contains("aa_vegetation_wind"), "driven by the shared wind")
	flag.free()

	t.current = "hanging chain"
	t.eq(HangingLantern.link_count(0), 0, "none on Low")
	t.check(HangingLantern.link_count(3) > HangingLantern.link_count(1), "longer chains on High")
	var pts := PackedVector3Array()
	var prev := PackedVector3Array()
	for i in 6:
		pts.append(Vector3(0, -HangingLantern.LINK_LENGTH * i, 0))
		prev.append(pts[i])
	for _i in 120:
		HangingLantern.step(pts, prev, HangingLantern.LINK_LENGTH, Vector3(1, 0, 1), 1.0 / 60.0)
	t.eq(pts[0], Vector3.ZERO, "anchor pinned")
	t.check(pts[5].x > 0.05, "wind pushes the chain downwind")
	t.check(HangingLantern.swing_angle(pts) > 0.05, "chain swings out")
	t.near(pts[5].distance_to(pts[4]), HangingLantern.LINK_LENGTH, 0.02, "links keep their length")
	var calm_pts := PackedVector3Array([Vector3.ZERO, Vector3(0, -0.18, 0)])
	var calm_prev := calm_pts.duplicate()
	HangingLantern.step(calm_pts, calm_prev, 0.18, Vector3.ZERO, 1.0 / 60.0)
	t.near(calm_pts[1].x, 0.0, 0.0001, "no wind, no drift")

	t.current = "rope sag"
	var rope := HangingLantern.rope_points(Vector3(0, 5, 0), Vector3(4, 5, 0), 0.5, 8)
	t.eq(rope.size(), 9, "n+1 points")
	t.near(rope[4].y, 4.5, 0.0001, "sags at the middle")
	t.eq(rope[0], Vector3(0, 5, 0), "anchored start")
	t.check(HangingLantern.rope_length(rope) > 4.0, "slack rope is longer than the span")
	t.eq(HangingLantern.build_rope_mesh(rope, 0.02).get_surface_count(), 1, "rope mesh built")
