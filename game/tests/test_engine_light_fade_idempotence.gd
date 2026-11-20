extends RefCounted
## Public Godot API regression: repeated Light3D profile values remain stable.
## The corresponding engine setters early-return before RenderingServer writes.
const Budget = preload("res://scripts/client/dungeon_light_budget.gd")
const Cookie = preload("res://scripts/client/dungeon_torch_cookie.gd")


func run(t) -> void:
	t.current = "native light distance fade setter contracts"
	var omni := OmniLight3D.new()
	t.check(not omni.distance_fade_enabled,
		"native new light keeps distance fade disabled by default")
	omni.distance_fade_enabled = true
	omni.distance_fade_begin = 29.0
	omni.distance_fade_shadow = 22.0
	omni.distance_fade_length = 7.0
	for i in 100:
		# Previously each assignment called into RenderingServer, even when
		# value was exactly equal to the cached profile on every frame.
		omni.distance_fade_enabled = true
		omni.distance_fade_begin = 29.0
		omni.distance_fade_shadow = 22.0
		omni.distance_fade_length = 7.0
	t.check(omni.distance_fade_enabled, "duplicate updates preserve enabled state")
	t.near(omni.distance_fade_begin, 29.0, 0.00001,
		"duplicate distance writes preserve the real renderer property")
	t.near(omni.distance_fade_shadow, 22.0, 0.00001,
		"duplicate shadow fade writes preserve the GPU range")
	t.near(omni.distance_fade_length, 7.0, 0.00001,
		"duplicate length writes remain stable")
	omni.distance_fade_begin = 21.5
	t.near(omni.distance_fade_begin, 21.5, 0.00001,
		"real numeric changes are still applied")
	omni.distance_fade_enabled = false
	t.check(not omni.distance_fade_enabled,
		"actual light fade toggles are not swallowed")
	Cookie.apply(omni, 0, "gl_compatibility", false)
	t.eq(omni.light_projector, null,
		"null projector on unsupported renderer is a cheap no-op")
	omni.free()

	t.current = "other engine light types also benefit"
	var spot := SpotLight3D.new()
	spot.distance_fade_enabled = true
	spot.distance_fade_begin = 16.0
	spot.distance_fade_shadow = 13.0
	spot.distance_fade_length = 4.5
	for i in 25:
		spot.distance_fade_begin = 16.0
		spot.distance_fade_shadow = 13.0
		spot.distance_fade_length = 4.5
	t.near(spot.distance_fade_begin, 16.0, 0.00001,
		"engine optimization also covers spotlights and flashlights")
	t.near(spot.distance_fade_length, 4.5, 0.00001,
		"spotlight fade profiles remain unchanged")
	spot.free()

	t.current = "high-end torch material cache remains bounded"
	var manager: String = (Budget as Script).source_code
	t.check(manager.contains("if not light.distance_fade_enabled:"),
		"dungeon manager also skips redundant GDScript setter calls")
	t.check(manager.contains("if light.distance_fade_begin != fade_begin:"),
		"world streaming never resubmits an unchanged light fade")
	t.check(manager.contains("if light.distance_fade_length != FADE_DISTANCE:"),
		"fixed fade length is only set on actual profile changes")
