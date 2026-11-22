extends RefCounted
## Renderer and lifetime budgets for pooled GPU-native footprint projectors.
const Tracks = preload("res://scripts/client/footprint_decals.gd")
const Online = preload("res://scripts/client/online_main.gd")


class FlatTerrain:
	extends RefCounted
	func height_at(_x: float, _z: float) -> float:
		return 4.0


func run(t) -> void:
	t.current = "native projector budget and ground eligibility"
	t.eq(Tracks.surface_kind(1, "forward_plus", 1.0, "swamp", 12.0,
		false, false), "", "Balanced allocates no decals")
	t.eq(Tracks.surface_kind(3, "gl_compatibility", 1.0, "swamp", 12.0,
		false, false), "", "Compatibility stays on lightweight effects")
	t.eq(Tracks.surface_kind(3, "mobile", 1.0, "swamp", 12.0,
		false, false), "", "Mobile never requests native decal clusters")
	t.eq(Tracks.surface_kind(3, "forward_plus", 0.0, "forest", 12.0,
		false, false), "", "dry ground is not stamped")
	t.eq(Tracks.surface_kind(3, "forward_plus", 0.8, "swamp", 12.0,
		true, false), "", "no interior floor marks")
	t.eq(Tracks.surface_kind(3, "forward_plus", 0.8, "swamp", 12.0,
		false, true), "", "no underwater mark projection")
	t.eq(Tracks.surface_kind(2, "forward_plus", 0.8, "plains", 12.0,
		false, false), "mud", "wet soil supports dark mud footprints")
	t.eq(Tracks.surface_kind(3, "forward_plus", 0.0, "mountain", 90.0,
		false, false), "snow", "high mountain snow retains calm-weather marks")
	t.eq(Tracks.surface_kind(3, "forward_plus", 0.8, "mountain", 60.0,
		false, false), "", "bare rock is not muddied")
	t.eq(Tracks.surface_kind(3, "forward_plus", NAN, "plains", 12.0,
		false, false), "", "corrupt weather is ignored")
	t.check(not Tracks.valid_stride(Vector3.INF, Vector3.ZERO, true),
		"first position cannot generate a footprint")
	t.check(not Tracks.valid_stride(Vector3.ZERO, Vector3(0, 0, 8), true),
		"teleports never stamp the whole path")
	t.check(not Tracks.valid_stride(Vector3.ZERO, Vector3(0, 0, 0.3), false),
		"mounted or stopped avatars do not create tracks")
	t.check(Tracks.valid_stride(Vector3.ZERO, Vector3(0, 0, 0.3), true),
		"local movement creates real ground travel")
	t.check(Tracks.mask_at(Vector2(0.5, 0.5)) > 0.5,
		"the generated tread is opaque near its sole")
	t.near(Tracks.mask_at(Vector2.ZERO), 0.0, 0.00001,
		"procedural texture corners stay fully transparent")

	t.current = "footprint profile and actual terrain height"
	t.eq(Tracks.max_marks(1), 0, "Balanced avoids clustered decals")
	t.eq(Tracks.max_marks(2), 16, "High caps terrain marks to sixteen")
	t.eq(Tracks.max_marks(3), Tracks.MAX_MARKS, "Ultra uses thirty-two marks")
	t.eq(Tracks.surface_kind(3, "forward_plus", 0.0, "swamp", 8.0,
		false, false), "mud", "swamp footprints persist without rainfall")
	var on_slope := Tracks.new()
	on_slope.setup(FlatTerrain.new())
	for i in 20:
		on_slope.update_track(Vector3(0.0, 4.0, float(i) * 0.31), true,
			1.0 / 30.0, 0.0, "swamp", 2, "forward_plus")
	t.check(not on_slope._decals.is_empty(), "real terrain produces tracks")
	if not on_slope._decals.is_empty():
		t.near(on_slope._decals[0].global_position.y, 4.2, 0.001,
			"footprint follows the exact heightmap under the shoe")
	var count_before: int = on_slope._decals.size()
	for i in 20:
		on_slope.update_track(Vector3(0.0, 10.0, 9.0 + float(i) * 0.31), true,
			1.0 / 30.0, 0.0, "swamp", 2, "forward_plus")
	t.eq(on_slope._decals.size(), count_before,
		"falling characters never project footprints from the sky")
	on_slope.free()

	t.current = "pooled real Godot Decal nodes"
	var footprints := Tracks.new()
	footprints.update_track(Vector3.ZERO, true, 1.0 / 30.0,
		0.8, "swamp", 3, "forward_plus")
	t.eq(footprints._decals.size(), 0, "first frame allocates no resources")
	for i in 180:
		footprints.update_track(Vector3(0.0, 2.0, float(i) * 0.31), true,
			1.0 / 30.0, 0.8, "swamp", 3, "forward_plus")
	t.check(footprints._decals.size() > 0 and
		footprints._decals.size() <= Tracks.MAX_MARKS,
		"pool never creates more than 32 projectors")
	t.check(footprints._normal != null,
		"Ultra shares one procedural normal texture for dimensional lighting")
	if not footprints._decals.is_empty():
		var mark: Decal = footprints._decals[0]
		t.check(mark.texture_albedo != null and mark.texture_normal != null,
			"real decal has imported Godot PBR texture slots")
		t.check(mark.distance_fade_enabled,
			"native GPU distance fading is active")
		t.near(mark.distance_fade_begin, 27.0, 0.0001,
			"camera draw cost is capped at the defined visual range")
	footprints.update_track(Vector3(0.0, 2.0, 60.0), false,
		1.0 / 30.0, 0.8, "swamp", 2, "forward_plus")
	for i in range(Tracks.HIGH_MARKS, footprints._decals.size()):
		t.check(not footprints._decals[i].visible,
			"lowering Ultra to High immediately culls excess decals")
	# Weather transitions stop new footprints; they must NOT wipe out
	# previously stamped ground marks at the exact end of the rain.
	footprints.update_track(Vector3(0.0, 2.0, 61.0), false,
		1.0 / 30.0, 0.0, "plains", 2, "forward_plus")
	var drying_marks := 0
	for mark in footprints._decals:
		if mark.visible:
			drying_marks += 1
	t.check(drying_marks > 0, "existing wet prints persist when the storm ends")
	footprints._seconds += Tracks.DURATION
	footprints.update_track(Vector3(0.0, 2.0, 61.0), false,
		0.25, 0.0, "plains", 2, "forward_plus")
	for mark in footprints._decals:
		t.check(not mark.visible, "old imprints disappear only after their lifetime")
	footprints.clear_marks()
	for decal in footprints._decals:
		t.check(not decal.visible, "clearing hides all old projectors")
	footprints.free()

	t.current = "online and offline integration"
	t.check((Online as Script).source_code.contains("_footprints.setup(client.world)"),
		"multiplayer projects imprints onto the streamed terrain heightmap")
	t.check((Online as Script).source_code.contains("_footprints.update_track("),
		"networked player movement renders native decals")
