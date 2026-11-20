extends RefCounted
## Corpse burn-away while a ragdoll sinks: a shared-shader overlay per corpse
## (progress is per corpse) chars the body and glows ember edges. Display-only.

const SHADER := preload("res://assets/shaders/corpse_burn.gdshader")


## Burn progress 0..1 over the corpse's sink phase (settles first, then burns).
static func progress(age: float, settle: float, sink: float) -> float:
	return clampf((age - settle + 0.6) / (sink + 0.6), 0.0, 1.0)


static func start(model: Node) -> ShaderMaterial:
	if model == null or not is_instance_valid(model):
		return null
	var m := ShaderMaterial.new()
	m.shader = SHADER
	for found in model.find_children("*", "GeometryInstance3D", true, false):
		(found as GeometryInstance3D).material_overlay = m
	return m
