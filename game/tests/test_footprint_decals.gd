extends RefCounted
## Renderer and lifetime budgets for pooled GPU-native footprint projectors.
const Tracks = preload("res://scripts/client/footprint_decals.gd")
const Online = preload("res://scripts/client/online_main.gd")
const Offline = preload("res://scripts/client/client_main.gd")


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
	footprints.clear_marks()
	for decal in footprints._decals:
		t.check(not decal.visible, "clearing hides all old projectors")
	footprints.free()

	t.current = "online and offline integration"
	t.check((Online as Script).source_code.contains("_footprints.update_track("),
		"networked player movement renders native decals")
	t.check((Offline as Script).source_code.contains("_footprints.update_track("),
		"local gameplay uses the identical graphics feature")
