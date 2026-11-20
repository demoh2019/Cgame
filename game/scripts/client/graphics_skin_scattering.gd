extends RefCounted
## Skin-only subsurface scattering for imported character bodies and heads.
## Preserves source PBR textures, tints and all existing character wet gear.
## One shared material variant per source+quality. Never touch hair/eyes/cloth.
## On Performance/Balanced/Compatibility, skip BOTH the skin shader variant
## and the expensive screen-space SSS composite.

static var current_level := 1
static var current_method := "gl_compatibility"
static var _applied_plan: Dictionary = {}
static var _variants: Dictionary = {}


static func settings(level: int, method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = method == "forward_plus" and tier >= 2
	return {
		"enabled": enabled,
		"strength": 0.0 if not enabled else (0.19 if tier == 2 else 0.29),
		"quality": (
			RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH if enabled and tier == 3
			else (RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_MEDIUM if enabled
			else RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_DISABLED)),
		"scale": 0.0 if not enabled else (0.65 if tier == 2 else 0.86),
		"depth_scale": 0.0 if not enabled else (0.17 if tier == 2 else 0.22),
	}


## Only explicit skin meshes, not _Body clothing, helmets, hair or robotic
## fallback meshes. Artists can explicitly tag other skin nodes with "skin".
static func is_skin_mesh(mesh: MeshInstance3D) -> bool:
	if mesh == null or mesh.mesh == null:
		return false
	var name: String = str(mesh.name).to_lower()
	if name.begins_with("outfit_") or name.begins_with("gear_") 			or name.contains("hair") or name.contains("eye") 			or name.contains("brow") or name.contains("helmet"):
		return false
	return bool(mesh.get_meta("skin", false)) or name.ends_with("_body")


static func supports(material: StandardMaterial3D) -> bool:
	return material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			and material.metallic < 0.1


## The source is an untouched imported/tinted material. Duplicating shares
## all original normal/ORM/albedo textures and avoids mutating sibling actors.
static func variant(source: StandardMaterial3D, level: int,
		method: String) -> StandardMaterial3D:
	if not supports(source):
		return source
	var p: Dictionary = settings(level, method)
	if not bool(p["enabled"]):
		return source
	var key: String = "%d:%d" % [source.get_instance_id(), clampi(level, 0, 3)]
	if _variants.has(key):
		return _variants[key]
	var skin: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	if skin.has_method("configure_skin_subsurface"):
		skin.call("configure_skin_subsurface", true, float(p["strength"]))
	else:
		# Stock Godot fallback; custom Cgame applies these atomically.
		skin.subsurf_scatter_enabled = true
		skin.subsurf_scatter_skin_mode = true
		skin.subsurf_scatter_strength = float(p["strength"])
	_variants[key] = skin
	return skin


## Only change renderer-global kernel when the requested tier/backend changes.
## New actors pick up current_level/current_method when their model is built.
## Existing actors are updated on preset switches, NEVER on every frame.
static func configure(level: int, method: String, scene_root: Node = null) -> void:
	var normalized: int = clampi(level, 0, 3)
	var profile: Dictionary = settings(normalized, method)
	current_level = normalized
	current_method = method
	if profile == _applied_plan:
		return
	RenderingServer.sub_surface_scattering_set_quality(int(profile["quality"]))
	if bool(profile["enabled"]):
		RenderingServer.sub_surface_scattering_set_scale(
			float(profile["scale"]), float(profile["depth_scale"]))
	_applied_plan = profile
	if scene_root != null and scene_root.is_inside_tree():
		for candidate in scene_root.get_tree().get_nodes_in_group("aa_grounded_characters"):
			if candidate.has_method("apply_skin_quality"):
				candidate.call("apply_skin_quality", current_level, current_method)


static func clear_cache() -> void:
	_variants.clear()
