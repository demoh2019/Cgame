extends RefCounted
## Verify that authored PBR normals and shading data survive the game art bake.
const MeshPBR = preload("res://scripts/client/mesh_pbr_preservation.gd")
const ModelCatalog = preload("res://scripts/client/model_catalog.gd")


static func _surface() -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP
	])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([
		1.0, 0.0, 0.0, 1.0,
		1.0, 0.0, 0.0, 1.0,
		1.0, 0.0, 0.0, 1.0
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2.ZERO, Vector2.RIGHT, Vector2.UP
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	return arrays


func run(t) -> void:
	t.current = "imported tangent space survives arbitrary transforms"
	var arrays: Array = _surface()
	var basis := Basis(Vector3.UP, PI / 3.0).scaled(Vector3(-2.0, 1.5, 0.65))
	t.check(MeshPBR.transform_frame(arrays, basis), "rotated mirrored nonuniform scale keeps a valid tangent frame")
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	t.eq(tangents.size(), 12, "three tangent frames each retain xyz and bitangent sign")
	for i in normals.size():
		var k: int = i * 4
		var tangent := Vector3(tangents[k], tangents[k + 1], tangents[k + 2])
		t.near(normals[i].length(), 1.0, 0.0001, "normal is normalized")
		t.near(tangent.length(), 1.0, 0.0001, "tangent is normalized")
		t.near(normals[i].dot(tangent), 0.0, 0.0001, "tangent remains orthogonal to normal")
		t.near(tangents[k + 3], -1.0, 0.0001, "mirror flips bitangent handedness")
	var expected_normal: Vector3 = (basis.inverse().transposed() * Vector3.UP).normalized()
	t.check(normals[0].distance_to(expected_normal) < 0.0001, "normals use inverse transpose")

	var simple: Array = _surface()
	t.check(MeshPBR.transform_frame(simple, Basis(Vector3.UP, PI / 5.0)),
			"pure rotation keeps normal mapping enabled")
	var simple_tangents: PackedFloat32Array = simple[Mesh.ARRAY_TANGENT]
	t.near(simple_tangents[3], 1.0, 0.0001, "ordinary rotation keeps bitangent handedness")

	var no_tangent: Array = _surface()
	no_tangent[Mesh.ARRAY_TANGENT] = null
	t.check(not MeshPBR.transform_frame(no_tangent, basis), "missing imported tangents are handled safely")
	var broken: Array = _surface()
	t.check(not MeshPBR.transform_frame(broken, Basis.IDENTITY.scaled(Vector3(0.0, 1.0, 1.0))),
			"singular scene transforms do not generate invalid tangent coordinates")

	t.current = "source PBR survives game material baking"
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.7, 0.4, 0.2)
	source.metallic = 0.87
	source.roughness = 0.27
	source.normal_enabled = true
	var normal_texture := ImageTexture.new()
	var roughness_texture := ImageTexture.new()
	source.normal_texture = normal_texture
	source.roughness_texture = roughness_texture
	var baked: BaseMaterial3D = MeshPBR.material_for_bake(source, true)
	t.check(baked != source, "baking duplicates the material without changing shared art")
	t.check(baked.normal_enabled, "normal maps remain active with valid transformed tangents")
	t.check(baked.normal_texture == normal_texture, "source normal texture stays attached")
	t.check(baked.roughness_texture == roughness_texture, "source roughness map stays attached")
	t.near(baked.metallic, 0.87, 0.0001, "authored metal reflectance is no longer clamped")
	t.near(baked.roughness, 0.27, 0.0001, "authored microfacet roughness is preserved")
	t.check(source.normal_enabled, "original imported material is untouched")
	var fallback: BaseMaterial3D = MeshPBR.material_for_bake(source, false)
	t.check(not fallback.normal_enabled, "normal mapping disables safely without tangents")
	t.check(source.normal_enabled, "fallback never modifies shared source material")
	var dungeon: BaseMaterial3D = MeshPBR.material_for_bake(source, true, true)
	t.near(dungeon.roughness, 1.0, 0.0001, "existing hand-painted dungeon style stays matte")
	t.near(source.roughness, 0.27, 0.0001, "dungeon tuning does not leak into original material")

	var scene_code: String = (ModelCatalog as Script).source_code
	t.check(scene_code.contains("source.get_surface_override_material(surface)"),
			"authored per-instance material overrides are considered")
	t.check(scene_code.contains("MeshPBR.transform_frame(arrays, transform.basis)"),
			"model catalog actually transforms tangents during baking")
	t.check(scene_code.contains("MeshLOD.copy_lods(source.mesh, surface, world_scale)"),
			"normal-map restoration keeps existing distance LODs")
