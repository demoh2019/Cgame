extends RefCounted
## Billboard/impostor LOD ring: past the real mesh's draw distance, the same
## placements continue as one MultiMesh of baked impostor quads, so distant
## hills keep their bushes and trees instead of popping to bare ground.

const ImpostorBaker = preload("res://scripts/client/impostor_baker.gd")
const META := &"aa_impostor_field"

static var range_factor: float = 2.2 # Impostor end distance relative to the mesh range.


static func configure(level: int) -> void:
	# Performance draws no impostors; higher tiers reach further.
	range_factor = [0.0, 1.8, 2.2, 2.8][clampi(level, 0, 3)]


static func end_distance(mesh_range: float) -> float:
	return mesh_range * range_factor


static func add(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D],
		mesh_range: float, fade_margin: float = 8.0) -> MultiMeshInstance3D:
	if parent == null or mesh == null or transforms.is_empty() or range_factor <= 1.0:
		return null
	var size: Vector2 = ImpostorBaker.frame_size(mesh)
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, size.x)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = transforms.size()
	var box := AABB(transforms[0].origin, Vector3.ZERO)
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		box = box.expand(transforms[i].origin)
	var field := MultiMeshInstance3D.new()
	field.name = "ImpostorField"
	field.multimesh = multimesh
	field.custom_aabb = box.grow(size.x)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.visibility_range_begin = mesh_range
	field.visibility_range_begin_margin = fade_margin
	field.visibility_range_end = end_distance(mesh_range)
	field.visibility_range_end_margin = fade_margin * 2.0
	field.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	field.visible = false # Until its atlas is baked.
	field.set_meta(META, true)
	var weak: WeakRef = weakref(field)
	var on_baked := func(atlas: Texture2D) -> void:
		var node := weak.get_ref() as MultiMeshInstance3D
		if node != null:
			node.material_override = ImpostorBaker.material_for(mesh, atlas)
			node.visible = true
	# Chunks are often built before they join the tree: bake once the field is live.
	field.ready.connect(func() -> void:
		ImpostorBaker.request(mesh, field.get_tree(), on_baked), CONNECT_ONE_SHOT)
	parent.add_child(field)
	return field
