extends RefCounted
## Blood decal rules.
const BloodDecals = preload("res://scripts/client/blood_decals.gd")


func run(t) -> void:
	t.current = "blood splats on decal-capable renderers"
	t.check(BloodDecals.enabled(2, "forward_plus"), "Forward+ gets splats")
	t.check(not BloodDecals.enabled(3, "gl_compatibility"), "Compatibility has no decals")
	t.check(not BloodDecals.enabled(0, "forward_plus"), "Performance skips them")
	t.check(BloodDecals.tint(true).g > BloodDecals.tint(false).g, "zombie ichor is browner")
	t.check(BloodDecals.splat_texture() == BloodDecals.splat_texture(), "texture is generated once")
