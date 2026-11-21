extends RefCounted
## Specialised character shading on top of standard PBR, like UE5 Substrate
## hair/cloth/eye models and HDRP Hair/Fabric/Eye shaders:
## - hair: anisotropic Kajiya-style highlight along strands plus backlit rim;
## - cloth: fuzzy sheen at grazing angles (rim), never glossy;
## - eyes: wet clearcoat cornea over the iris.
## Skin is left to native subsurface scattering (graphics_skin_scattering.gd).

static var _level: int = 1


static func configure(level: int) -> void:
	_level = clampi(level, 0, 3)


static func kind_of(material_name: String) -> String:
	var lower := material_name.to_lower()
	if lower.begins_with("mi_hair") or lower.contains("hair") or lower.contains("brow"):
		return "hair"
	if lower.contains("eye"):
		return "eye"
	if lower.begins_with("mi_regular") or lower.begins_with("mi_superhero") or lower.contains("skin"):
		return "skin"
	return "cloth"


## Mutates a material the caller already owns (a duplicate). Returns true if changed.
static func enhance(material: BaseMaterial3D, kind: String, level: int = -1) -> bool:
	var tier: int = _level if level < 0 else clampi(level, 0, 3)
	if material == null or tier < 2:
		return false
	match kind:
		"hair":
			material.anisotropy_enabled = true
			material.anisotropy = 0.7
			material.roughness = clampf(material.roughness, 0.35, 0.55)
			material.rim_enabled = true
			material.rim = 0.35
			material.rim_tint = 0.8
		"cloth":
			material.rim_enabled = true
			material.rim = 0.22 if tier == 2 else 0.3
			material.rim_tint = 0.65 # Sheen takes the fabric's own color.
			material.roughness = maxf(material.roughness, 0.75)
			material.metallic = minf(material.metallic, 0.1)
		"eye":
			material.clearcoat_enabled = true
			material.clearcoat = 1.0
			material.clearcoat_roughness = 0.04
		_:
			return false
	return true


## Gives every non-skin surface of an assembled character its own enhanced material.
static func enhance_model(root: Node, level: int = -1) -> int:
	var changed := 0
	if root == null:
		return 0
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var instance := found as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var current: Material = instance.get_surface_override_material(surface)
			var owned := current != null
			if current == null:
				current = instance.mesh.surface_get_material(surface)
			var base := current as BaseMaterial3D
			if base == null:
				continue
			var kind := kind_of(str(base.resource_name))
			if kind == "skin":
				continue
			var target: BaseMaterial3D = base if owned else base.duplicate() as BaseMaterial3D
			if enhance(target, kind, level):
				instance.set_surface_override_material(surface, target)
				changed += 1
	return changed
