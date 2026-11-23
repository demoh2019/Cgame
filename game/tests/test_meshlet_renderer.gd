extends RefCounted
## Meshlet renderer: GPU buffer packing, shader section splitting, CPU culling parity with the
## shared meshlet helpers, and the ArrayMesh / MultiMesh fallback used without mesh shaders.
## The task + mesh shader draw itself needs VK_EXT_mesh_shader hardware and is not covered here.

const MeshletRenderer = preload("res://scripts/client/meshlet_renderer.gd")
const Meshlets = preload("res://scripts/shared/meshlets.gd")
const ClusterLOD = preload("res://scripts/shared/cluster_lod.gd")


## Flat grid in the XZ plane, `n` x `n` quads, two triangles each.
static func _grid(n: int) -> Dictionary:
	var verts := PackedVector3Array()
	for z in n + 1:
		for x in n + 1:
			verts.append(Vector3(float(x), 0.0, float(z)))
	var idx := PackedInt32Array()
	for z in n:
		for x in n:
			var a: int = z * (n + 1) + x
			var b: int = a + 1
			var c: int = a + (n + 1)
			var d: int = c + 1
			idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	return {"vertices": verts, "indices": idx}


@warning_ignore("integer_division")
func run(t) -> void:
	var grid: Dictionary = _grid(16)
	var verts: PackedVector3Array = grid["vertices"]
	var indices: PackedInt32Array = grid["indices"]
	var meshlets: Array = Meshlets.build_meshlets(verts, indices, MeshletRenderer.MAX_MESHLET_VERTICES, MeshletRenderer.MAX_MESHLET_TRIANGLES)

	t.current = "meshlet packing"
	var packed: Dictionary = MeshletRenderer.pack_meshlets(verts, meshlets)
	t.eq(String(packed["error"]), "", "valid meshlets pack without error")
	t.check(meshlets.size() >= 4, "512 triangles split into several meshlets")
	t.eq(int(packed["meshlet_count"]), meshlets.size(), "meshlet count recorded")
	t.eq(int(packed["triangle_count"]), indices.size() / 3, "every triangle is packed exactly once")
	var positions: PackedByteArray = packed["positions"]
	var descriptors: PackedByteArray = packed["descriptors"]
	var vertex_ids: PackedByteArray = packed["vertex_ids"]
	var tris: PackedByteArray = packed["triangles"]
	t.eq(positions.size(), verts.size() * 16, "positions are one vec4 per vertex")
	t.eq(descriptors.size(), meshlets.size() * MeshletRenderer.DESCRIPTOR_STRIDE, "48 byte descriptor per meshlet")
	t.near(positions.decode_float(16 * 5 + 4), verts[5].y, 0.000001, "position y round trips")
	t.near(positions.decode_float(16 * 7), verts[7].x, 0.000001, "position x round trips")
	t.near(positions.decode_float(16 * 7 + 12), 1.0, 0.000001, "position w is 1")

	var vertex_cursor: int = 0
	var triangle_cursor: int = 0
	var layout_ok: bool = true
	var ids_ok: bool = true
	var tris_ok: bool = true
	var bounds_ok: bool = true
	for i in meshlets.size():
		var m: Dictionary = meshlets[i]
		var d: Dictionary = MeshletRenderer.unpack_descriptor(descriptors, i)
		var vids: PackedInt32Array = m["vertex_ids"]
		var lidx: PackedInt32Array = m["indices"]
		if d["vertex_offset"] != vertex_cursor or d["triangle_offset"] != triangle_cursor:
			layout_ok = false
		if d["vertex_count"] != vids.size() or d["triangle_count"] != lidx.size() / 3:
			layout_ok = false
		if d["vertex_count"] > MeshletRenderer.MAX_MESHLET_VERTICES or d["triangle_count"] > MeshletRenderer.MAX_MESHLET_TRIANGLES:
			layout_ok = false
		for k in vids.size():
			if vertex_ids.decode_u32((vertex_cursor + k) * 4) != vids[k]:
				ids_ok = false
		for tri in lidx.size() / 3:
			var word: int = tris.decode_u32((triangle_cursor + tri) * 4)
			if (word & 0xFF) != lidx[tri * 3] or ((word >> 8) & 0xFF) != lidx[tri * 3 + 1] or ((word >> 16) & 0xFF) != lidx[tri * 3 + 2]:
				tris_ok = false
		if not (d["center"] as Vector3).is_equal_approx(m["bounds_center"]) or absf(float(d["radius"]) - float(m["bounds_radius"])) > 0.00001:
			bounds_ok = false
		if not (d["cone_axis"] as Vector3).is_equal_approx(m["cone_axis"]) or absf(float(d["cone_cutoff"]) - float(m["cone_cutoff"])) > 0.00001:
			bounds_ok = false
		vertex_cursor += vids.size()
		triangle_cursor += lidx.size() / 3
	t.check(layout_ok, "descriptor offsets and counts follow the concatenated layout")
	t.check(ids_ok, "meshlet vertex ids are stored in order")
	t.check(tris_ok, "triangles pack as a | b << 8 | c << 16")
	t.check(bounds_ok, "sphere and cone round trip through the descriptor")
	t.eq(int(packed["vertex_slots"]), vertex_cursor, "vertex slot total matches the descriptors")

	var oversized: Array = Meshlets.build_meshlets(verts, indices, 200, 300)
	var rejected: Dictionary = MeshletRenderer.pack_meshlets(verts, oversized)
	t.check(String(rejected["error"]) != "", "meshlets above the mesh shader output limits are rejected")
	t.check(not rejected.has("descriptors"), "a rejected pack uploads nothing")
	var bad_vertex: Array = [{"vertex_ids": PackedInt32Array([0, 1, 9999]), "indices": PackedInt32Array([0, 1, 2]), "bounds_center": Vector3.ZERO, "bounds_radius": 1.0, "cone_axis": Vector3.ZERO, "cone_cutoff": 1.0}]
	t.check(String(MeshletRenderer.pack_meshlets(verts, bad_vertex)["error"]) != "", "out of range vertex ids are rejected")
	var empty: Dictionary = MeshletRenderer.pack_meshlets(verts, [])
	t.eq(String(empty["error"]), "", "no meshlets is valid")
	t.eq(int(empty["meshlet_count"]), 0, "no meshlets packs to zero count")

	t.current = "frame uniform block"
	var planes: Array[Plane] = []
	for p in 6:
		planes.append(Plane(Vector3(0, 0, 1), float(p) + 0.5))
	var model := Transform3D(Basis.from_scale(Vector3(2, 2, 2)), Vector3(1, 2, 3))
	var frame: PackedByteArray = MeshletRenderer.pack_frame_data(Projection.IDENTITY, model, planes, Vector3(4, 5, 6), 77, MeshletRenderer.FLAG_CONE_CULL)
	t.eq(frame.size(), MeshletRenderer.FRAME_DATA_SIZE, "frame block is 256 bytes")
	t.near(frame.decode_float(0), 1.0, 0.000001, "view_proj column 0 starts with 1")
	t.near(frame.decode_float(16 + 4), 1.0, 0.000001, "view_proj is column major")
	t.near(frame.decode_float(64), 2.0, 0.000001, "model basis x scale")
	t.near(frame.decode_float(64 + 16 + 4), 2.0, 0.000001, "model basis y scale")
	t.near(frame.decode_float(64 + 48), 1.0, 0.000001, "model origin x")
	t.near(frame.decode_float(64 + 56), 3.0, 0.000001, "model origin z")
	t.near(frame.decode_float(64 + 60), 1.0, 0.000001, "model origin w")
	t.near(frame.decode_float(128 + 3 * 16 + 8), 1.0, 0.000001, "plane normal z")
	t.near(frame.decode_float(128 + 3 * 16 + 12), 3.5, 0.000001, "plane distance")
	t.near(frame.decode_float(224), 4.0, 0.000001, "camera x")
	t.eq(frame.decode_u32(240), 77, "meshlet count")
	t.eq(frame.decode_u32(244), MeshletRenderer.FLAG_CONE_CULL, "cull flags")
	var few: PackedByteArray = MeshletRenderer.pack_frame_data(Projection.IDENTITY, Transform3D.IDENTITY, [], Vector3.ZERO, 0, 3)
	t.check(few.decode_float(128 + 12) > 1.0e20, "missing planes never cull")

	t.current = "shader sections"
	var task_sections: Dictionary = MeshletRenderer.split_shader_sections("#[task]\n#version 450\nvoid main() {}\n")
	t.check(task_sections.has("task"), "section name parsed")
	t.check(String(task_sections["task"]).contains("#version 450"), "section body kept")
	t.check(not String(task_sections["task"]).contains("#[task]"), "marker stripped")
	var task_src: String = MeshletRenderer._read_text(MeshletRenderer.TASK_SHADER_PATH)
	var mesh_src: String = MeshletRenderer._read_text(MeshletRenderer.MESH_SHADER_PATH)
	t.check(task_src != "" and mesh_src != "", "meshlet shader files ship with the game")
	var task_parts: Dictionary = MeshletRenderer.split_shader_sections(task_src)
	var mesh_parts: Dictionary = MeshletRenderer.split_shader_sections(mesh_src)
	t.check(task_parts.has("task") and String(task_parts["task"]).contains("EmitMeshTasksEXT"), "task shader emits mesh tasks")
	t.check(mesh_parts.has("mesh") and String(mesh_parts["mesh"]).contains("SetMeshOutputsEXT"), "mesh shader sets its outputs")
	t.check(mesh_parts.has("fragment"), "mesh file carries the fragment stage")
	t.check(String(mesh_parts["mesh"]).contains("max_vertices = 64") and String(mesh_parts["mesh"]).contains("max_primitives = 124"), "shader output limits match the packer")

	t.current = "fallback path"
	var r := MeshletRenderer.new()
	t.eq(r.choose_path(), MeshletRenderer.DrawPath.NONE, "no path before setup")
	t.check(r.setup_from_mesh(verts, indices), "setup_from_mesh succeeds")
	t.eq(r.last_error, "", "no error after setup")
	t.eq(r.meshlet_count, meshlets.size(), "meshlets uploaded")
	t.check(not r.mesh_shader_supported(), "headless renderer reports no mesh shader support")
	t.eq(r.choose_path(), MeshletRenderer.DrawPath.FALLBACK, "falls back without mesh shaders")
	var full: ArrayMesh = r.build_array_mesh()
	t.eq(full.get_surface_count(), 1, "fallback mesh has one surface")
	var full_arrays: Array = full.surface_get_arrays(0)
	var full_indices: PackedInt32Array = full_arrays[Mesh.ARRAY_INDEX]
	t.eq(full_indices.size(), indices.size(), "fallback mesh keeps every triangle")
	var normals: PackedVector3Array = full_arrays[Mesh.ARRAY_NORMAL]
	t.check(normals.size() > 0 and absf(normals[0].length() - 1.0) < 0.001, "fallback normals are unit length")
	var area: float = 0.0
	var fv: PackedVector3Array = full_arrays[Mesh.ARRAY_VERTEX]
	for ti in full_indices.size() / 3:
		area += (fv[full_indices[ti * 3 + 1]] - fv[full_indices[ti * 3]]).cross(fv[full_indices[ti * 3 + 2]] - fv[full_indices[ti * 3]]).length() * 0.5
	t.near(area, 256.0, 0.001, "fallback mesh covers the 16 x 16 grid")

	var parent := Node3D.new()
	r.model = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	t.eq(r.attach(parent, null), MeshletRenderer.DrawPath.FALLBACK, "attach reports the fallback path")
	t.eq(parent.get_child_count(), 1, "fallback adds one mesh instance")
	var inst: MeshInstance3D = parent.get_child(0) as MeshInstance3D
	t.check(inst != null and inst.mesh != null, "fallback child renders an ArrayMesh")
	t.check(inst != null and inst.transform.origin.is_equal_approx(Vector3(0, 1, 0)), "fallback child uses the model transform")
	parent.free()

	r.force_fallback = true
	t.check(not r.mesh_shader_supported(), "force_fallback disables the mesh shader path")
	r.force_fallback = false
	r.model = Transform3D.IDENTITY

	var transforms: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(0, 0, 9))]
	var mm_inst: MultiMeshInstance3D = r.create_multimesh_instance(transforms)
	t.eq(mm_inst.multimesh.instance_count, 3, "multimesh draws one instance per transform")
	mm_inst.free()

	var broken := MeshletRenderer.new()
	t.check(not broken.setup(verts, oversized), "setup rejects oversized meshlets")
	t.check(broken.last_error != "", "setup reports why it failed")
	t.eq(broken.choose_path(), MeshletRenderer.DrawPath.NONE, "failed setup renders nothing")
	t.eq(broken.build_array_mesh().get_surface_count(), 0, "empty renderer builds an empty mesh")

	t.current = "cpu culling parity"
	var cam := Vector3(8, 20, 8)
	var all_planes: Array[Plane] = []
	t.eq(r.visible_meshlets(cam, all_planes).size(), r.meshlet_count, "no planes and a camera above a flat grid keep everything")
	# The grid is flat (normal cone cutoff well below 1), so cone culling depends only on the side of the camera.
	var cone_match: bool = true
	for pos in [Vector3(8, 20, 8), Vector3(8, -20, 8), Vector3(40, 3, -30)]:
		for i in r.meshlet_count:
			var expected: bool = not Meshlets.cone_cull(meshlets[i], pos)
			if r.is_meshlet_visible(i, pos, all_planes, MeshletRenderer.FLAG_CONE_CULL) != expected:
				cone_match = false
	t.check(cone_match, "cone culling matches Meshlets.cone_cull")
	var above: int = r.visible_meshlets(Vector3(8, 20, 8), all_planes, MeshletRenderer.FLAG_CONE_CULL).size()
	var below: int = r.visible_meshlets(Vector3(8, -20, 8), all_planes, MeshletRenderer.FLAG_CONE_CULL).size()
	t.check(above == 0 or below == 0, "a flat patch is cone-culled from one of its two sides")
	t.check(above + below == r.meshlet_count, "exactly one side sees the front faces of every meshlet")

	var outside: Array[Plane] = [Plane(Vector3(1, 0, 0), -100.0)] # Everything is at x >= -100 -> outside is x > -100.
	t.eq(r.visible_meshlets(cam, outside, MeshletRenderer.FLAG_FRUSTUM_CULL).size(), 0, "a plane behind all geometry culls everything")
	var inside: Array[Plane] = [Plane(Vector3(1, 0, 0), 100.0)]
	t.eq(r.visible_meshlets(cam, inside, MeshletRenderer.FLAG_FRUSTUM_CULL).size(), r.meshlet_count, "a plane in front of all geometry keeps everything")
	var frustum_match: bool = true
	var split: Array[Plane] = [Plane(Vector3(1, 0, 0), 2.0)] # Keeps meshlets whose sphere reaches x <= 2.
	for i in r.meshlet_count:
		var expected_f: bool = not Meshlets.frustum_cull(meshlets[i], split)
		if r.is_meshlet_visible(i, cam, split, MeshletRenderer.FLAG_FRUSTUM_CULL) != expected_f:
			frustum_match = false
	t.check(frustum_match, "frustum culling matches Meshlets.frustum_cull")
	var kept: int = r.visible_meshlets(cam, split, MeshletRenderer.FLAG_FRUSTUM_CULL).size()
	t.check(kept > 0 and kept < r.meshlet_count, "a plane through the grid culls part of it")

	r.model = Transform3D(Basis.IDENTITY, Vector3(-50, 0, 0))
	t.eq(r.visible_meshlets(cam, split, MeshletRenderer.FLAG_FRUSTUM_CULL).size(), r.meshlet_count, "translating the model toward the plane keeps everything")
	r.model = Transform3D(Basis.IDENTITY, Vector3(30, 0, 0))
	t.eq(r.visible_meshlets(cam, split, MeshletRenderer.FLAG_FRUSTUM_CULL).size(), 0, "translating the model away from the plane culls everything")
	r.model = Transform3D(Basis.from_scale(Vector3(0.1, 0.1, 0.1)), Vector3.ZERO)
	t.eq(r.visible_meshlets(cam, split, MeshletRenderer.FLAG_FRUSTUM_CULL).size(), r.meshlet_count, "scaling the model down pulls its bounds inside the plane")
	r.model = Transform3D.IDENTITY
	r.set_view(cam, split)
	var culled_inst: MeshInstance3D = r.create_fallback_instance()
	var culled_idx: PackedInt32Array = culled_inst.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	t.check(culled_idx.size() > 0 and culled_idx.size() < indices.size(), "fallback instance drops culled meshlets")
	culled_inst.free()

	t.current = "material-preserving cluster cut for the actual game mesh fallback"
	var source_arrays: Array = []
	source_arrays.resize(Mesh.ARRAY_MAX)
	source_arrays[Mesh.ARRAY_VERTEX] = verts
	source_arrays[Mesh.ARRAY_INDEX] = indices
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var normals := PackedVector3Array()
	for i in verts.size():
		colors.append(Color(float(i % 3) / 3.0, 0.5, 0.8))
		uv.append(Vector2(float(i % 17) / 17.0, float(i % 11) / 11.0))
		normals.append(Vector3.UP)
	source_arrays[Mesh.ARRAY_COLOR] = colors
	source_arrays[Mesh.ARRAY_TEX_UV] = uv
	source_arrays[Mesh.ARRAY_NORMAL] = normals
	var authored := ArrayMesh.new()
	authored.resource_name = "AlbionTerrainFixture"
	authored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source_arrays)
	var authored_material := StandardMaterial3D.new()
	authored.surface_set_material(0, authored_material)
	var hierarchy: Dictionary = ClusterLOD.build_hierarchy(verts, indices, 4)
	var cut_ids: PackedInt32Array = ClusterLOD.select_cut(
		hierarchy, Vector3(0, 50, 150), 1.0471976, 1080.0, 1.0)
	var output: ArrayMesh = MeshletRenderer.build_material_preserving_cut(
		authored, hierarchy, cut_ids)
	t.check(output != null, "real CPU mesh fallback rebuilds a selected LOD cut")
	if output != null:
		var output_arrays: Array = output.surface_get_arrays(0)
		t.eq(output_arrays[Mesh.ARRAY_VERTEX], verts,
			"the selected cut does not discard source vertex IDs")
		t.eq(output_arrays[Mesh.ARRAY_TEX_UV], uv,
			"UV seams and texture mappings remain unchanged")
		t.eq(output_arrays[Mesh.ARRAY_COLOR], colors,
			"scanned terrain vertex colors survive LOD construction")
		t.eq(output_arrays[Mesh.ARRAY_NORMAL], normals,
			"PBR lighting normals survive the cut")
		t.check((output_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0,
			"chosen clusters are built as indexed triangles")
		t.check((output_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() <= indices.size(),
			"the selected cluster LOD does not add geometry")
		t.check(output.surface_get_material(0) == authored_material,
			"authored terrain material is preserved")
	t.eq(authored.surface_get_arrays(0)[Mesh.ARRAY_INDEX], indices,
		"building the cluster cut never mutates the input mesh")
	t.eq(MeshletRenderer.build_material_preserving_cut(authored, {}, cut_ids), null,
		"invalid hierarchy returns no broken visual geometry")

