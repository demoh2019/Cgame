extends RefCounted
## Protect the visible (GroundPlants) grass from regressing to 1-pixel cards.
## Headless: builds procedural mesh and checks tile companion without assets.

const GroundPlants = preload("res://scripts/client/ground_plants.gd")


func run(t) -> void:
	t.current = "visible meadow grass uses actual three-dimensional leaves"
	var mesh: ArrayMesh = GroundPlants.volume_grass_mesh(2, 4)
	t.check(mesh != null, "volume grass mesh is generated")
	t.check(GroundPlants.volume_grass_mesh(2, 4) == mesh,
		"near grass geometry is cached across all tiles")
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	t.eq(vertices.size(), 4 * 3 * 4, "four leaves have three diamond-profile rings each")
	t.eq(indices.size(), 4 * 16 * 3, "four true-volume blades use sixteen triangles each")
	t.eq(normals.size(), vertices.size(), "every leaf corner has a normal")
	t.eq(colors.size(), vertices.size(), "root/middle/tip have vertex color shading")
	var left: Vector3 = vertices[4]
	var front: Vector3 = vertices[5]
	var right: Vector3 = vertices[6]
	var back: Vector3 = vertices[7]
	t.check(left.distance_to(right) > 0.1, "middle of leaf has meaningful lateral width")
	t.check(front.distance_to(back) > 0.06, "middle of leaf has front-to-back depth")
	t.check(absf((right - left).cross(front - left).y) < 0.001,
		"diamond width and depth lie in the same horizontal cross-section")
	for index in indices:
		t.check(index >= 0 and index < vertices.size(), "all volume triangles are valid")
	t.check(GroundPlants.volume_grass_mesh(2, 5).surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()
		> indices.size(), "high-quality grass adds detail without changing tile density")
	t.check(GroundPlants.volume_grass_material().transparency ==
		BaseMaterial3D.TRANSPARENCY_DISABLED,
		"solid blade bodies render opaque without alpha discard")

	t.current = "volumetric grass is integrated into actual spawned scanned plants"
	var scanned := MultiMesh.new()
	scanned.transform_format = MultiMesh.TRANSFORM_3D
	scanned.mesh = BoxMesh.new()
	scanned.instance_count = 2
	scanned.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)))
	scanned.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(5, 6, 7)))
	var scanned_node := MultiMeshInstance3D.new()
	scanned_node.multimesh = scanned
	scanned_node.visibility_range_end = 72.0
	scanned_node.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(16, 5, 16))
	var companion: MultiMeshInstance3D = GroundPlants.volume_grass_companion(scanned_node, 1)
	t.check(companion != null, "scanned tuft gains a near-camera solid mesh")
	if companion != null:
		t.eq(companion.multimesh.instance_count, scanned.instance_count,
			"the opaque blades share the exact scanned tuft count")
		t.eq(companion.multimesh.get_instance_transform(1).origin,
			Vector3(5, 6, 7), "both passes share instance placement")
		t.check(companion.visibility_range_end > 0.0 and
			companion.visibility_range_end <= GroundPlants.VOLUME_GRASS_DISTANCE *
			GroundPlants.distance_scale, "expensive real geometry is near-only")
		t.eq(companion.custom_aabb, scanned_node.custom_aabb,
			"culling retains tile bounds")
		t.check(companion.multimesh.mesh == GroundPlants.volume_grass_mesh(1, 5),
			"High-quality tuft uses the cached 5-blade solid volume")
	t.check((GroundPlants as Script).source_code.contains("volume_grass_companion(") and
		(GroundPlants as Script).source_code.contains("result.append(volume)"),
		"live GroundPlants.build_tile actually attaches the new geometry")
