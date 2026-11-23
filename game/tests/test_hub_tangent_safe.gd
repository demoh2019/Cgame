extends RefCounted
## Regression: hub world-space normal mapping works on meshes without tangents.

const HubView = preload("res://scripts/client/hub_view.gd")


func run(t) -> void:
	t.current = "hub plaza and fountain shaders do not require tangent attributes"
	t.check(not HubView.PLAZA_SHADER.contains("NORMAL_MAP"),
		"plaza shader writes a reconstructed world-space NORMAL instead of NORMAL_MAP")
	t.check(not HubView.FOUNTAIN_SHADER.contains("NORMAL_MAP"),
		"fountain shader cannot make Forward+ request missing tangent arrays")
	t.check(HubView.PLAZA_SHADER.contains("VIEW_MATRIX") and
		HubView.PLAZA_SHADER.contains("world_normal"),
		"plaza normal detail is transformed from world space to view space")
	t.check(HubView.FOUNTAIN_SHADER.contains("weights = abs(world_normal)") and
		HubView.FOUNTAIN_SHADER.contains("mapped_normal"),
		"fountain keeps triplanar normal detail on all three axes")
