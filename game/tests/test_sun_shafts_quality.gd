extends RefCounted
## Screen-space sun shafts: quality gating, tint maths and idempotent node setup.
const SunShafts = preload("res://scripts/client/graphics_sun_shafts.gd")


func run(t) -> void:
	t.current = "sun shafts only on desktop Forward+ High/Ultra"
	for method in ["gl_compatibility", "mobile", ""]:
		for tier in 4:
			t.check(not bool(SunShafts.settings(tier, method)["enabled"]),
					"non-Forward+ renderers never draw the shaft pass")
	for tier in [0, 1]:
		t.check(not bool(SunShafts.settings(tier, "forward_plus")["enabled"]),
				"Performance and Balanced skip god rays")
	var high: Dictionary = SunShafts.settings(2, "forward_plus")
	var ultra: Dictionary = SunShafts.settings(3, "forward_plus")
	t.check(bool(high["enabled"]) and bool(ultra["enabled"]), "High/Ultra get god rays")
	t.check(int(ultra["samples"]) > int(high["samples"]), "Ultra marches more samples")
	t.eq(SunShafts.settings(99, "forward_plus"), ultra, "upper quality clamped")

	t.current = "shaft tint follows the sun and fades below the horizon"
	var noon := SunShafts.shaft_color(Color(1, 0.9, 0.8), 1.0, Vector3(0, 1, 0))
	var below := SunShafts.shaft_color(Color(1, 0.9, 0.8), 1.0, Vector3(0, -0.5, 1))
	t.near(noon.r, 1.0, 0.0001, "full sun keeps its colour")
	t.near(below.r + below.g + below.b, 0.0, 0.0001, "sun under horizon casts no shafts")
	var hot := SunShafts.shaft_color(Color(1, 1, 1), 50.0, Vector3(0, 1, 0))
	t.check(hot.r <= 2.0, "light energy is clamped so shafts never blow out")

	t.current = "apply is idempotent and hides the pass when disabled"
	var cam := Camera3D.new()
	var sun := DirectionalLight3D.new()
	SunShafts.apply(cam, sun, 3, "forward_plus")
	SunShafts.apply(cam, sun, 3, "forward_plus")
	t.eq(cam.get_child_count(), 1, "one shaft node per camera")
	var node := cam.get_node("SunShafts") as MeshInstance3D
	t.check(node.visible, "visible on Ultra")
	SunShafts.apply(cam, sun, 1, "forward_plus")
	t.check(not node.visible, "hidden on Balanced")
	SunShafts.apply(cam, sun, 3, "gl_compatibility")
	t.check(not node.visible, "hidden on Compatibility")
	cam.free()
	sun.free()
