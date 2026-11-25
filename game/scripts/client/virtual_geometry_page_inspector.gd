extends RefCounted
## P1 Nanite groundwork: inspect compact binary meshlet pages of REAL
## streamed Albion scenery. This is explicitly invoked by a debug hotkey,
## never on the gameplay/rendering frame path. Existing render meshes and
## their PBR vertex/material streams remain fully intact.

const SCENERY_GROUP := "aa_scenery_multimeshes"
const MAX_SCANNED := 96


static func _new_page_builder() -> Object:
	if not ClassDB.class_exists("CgameMeshletPages"):
		return null
	var engine_class: Object = ClassDB.instantiate("CgameMeshletPages")
	if engine_class == null or not engine_class.has_method("build_pages") or \
			not engine_class.has_method("inspect_page"):
		return null
	return engine_class


static func inspect_mesh(mesh: Mesh, max_page_bytes: int = 4096) -> Dictionary:
	var result := {"supported": false, "verified": false,
		"surfaces": 0, "pages": 0, "meshlets": 0, "triangles": 0, "bytes": 0}
	var builder: Object = _new_page_builder()
	if builder == null or mesh == null or not (mesh is ArrayMesh) or \
			max_page_bytes < 1024 or max_page_bytes > 65536:
		return result
	result["supported"] = true
	if mesh.get_surface_count() < 1 or mesh.get_surface_count() > 8:
		return result
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return result
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.size() != Mesh.ARRAY_MAX or not (arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array):
			return result
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.size() < 3 or vertices.size() > 1000000:
			return result
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			if vertices.size() % 3 != 0:
				return result
			indices.resize(vertices.size())
			for i in indices.size():
				indices[i] = i
		if indices.size() < 3 or indices.size() > 3000000 or indices.size() % 3 != 0:
			return result
		var pages: Array = builder.call("build_pages", vertices, indices, max_page_bytes)
		if pages.is_empty():
			return result
		var recovered: int = 0
		var next_meshlet: int = 0
		for page in pages:
			if not (page is PackedByteArray) or page.size() > max_page_bytes:
				return result
			var decoded: Dictionary = builder.call("inspect_page_for_mesh", page, vertices.size()) \
				if builder.has_method("inspect_page_for_mesh") else builder.call("inspect_page", page)
			if (decoded.is_empty() or int(decoded.get("bytes", 0)) != page.size() or
					int(decoded.get("first_meshlet", -1)) != next_meshlet):
				return result
			# Compatibility with older Cgame builds: the old parser only
			# checked the global format limit, not the specific source mesh.
			if not builder.has_method("inspect_page_for_mesh"):
				for descriptor in decoded["meshlets"]:
					for id in descriptor["vertex_ids"]:
						if id < 0 or id >= vertices.size():
							return result
			next_meshlet += int(decoded["meshlet_count"])
			recovered += int(decoded["triangle_count"])
			result["bytes"] = int(result["bytes"]) + page.size()
			result["meshlets"] = int(result["meshlets"]) + int(decoded["meshlet_count"])
		if recovered != int(indices.size() / 3):
			return result
		result["pages"] = int(result["pages"]) + pages.size()
		result["triangles"] = int(result["triangles"]) + recovered
		result["surfaces"] = int(result["surfaces"]) + 1
	result["verified"] = true
	return result


static func inspect_streamed_world(tree: SceneTree, max_meshes: int = 8,
		max_page_bytes: int = 4096) -> Dictionary:
	var result := {"supported": ClassDB.class_exists("CgameMeshletPages"),
		"verified": true, "meshes": 0, "surfaces": 0,
		"pages": 0, "meshlets": 0, "triangles": 0, "bytes": 0}
	if tree == null or not bool(result["supported"]) or \
			max_meshes < 1 or max_meshes > 32:
		result["verified"] = false
		return result
	var seen: Dictionary = {}
	var scanned: int = 0
	for node in tree.get_nodes_in_group(SCENERY_GROUP):
		if scanned >= MAX_SCANNED or int(result["meshes"]) >= max_meshes:
			break
		scanned += 1
		if not (node is MultiMeshInstance3D):
			continue
		var instance := node as MultiMeshInstance3D
		if instance.multimesh == null:
			continue
		var mesh: Mesh = instance.multimesh.mesh
		if mesh == null or seen.has(mesh.get_instance_id()):
			continue
		seen[mesh.get_instance_id()] = true
		var stats: Dictionary = inspect_mesh(mesh, max_page_bytes)
		if not bool(stats["supported"]) or not bool(stats["verified"]):
			continue
		result["meshes"] = int(result["meshes"]) + 1
		for key in ["surfaces", "pages", "meshlets", "triangles", "bytes"]:
			result[key] = int(result[key]) + int(stats[key])
	return result


static func format_report(stats: Dictionary) -> String:
	if not bool(stats.get("supported", false)):
		return "Virtual Geometry: native meshlet pages unavailable."
	if not bool(stats.get("verified", false)):
		return "Virtual Geometry: page validation failed."
	return "Meshlet pages: %d meshes, %d pages, %d meshlets, %d triangles, %d KiB (CPU packed only)." % [
		int(stats.get("meshes", 0)), int(stats.get("pages", 0)),
		int(stats.get("meshlets", 0)), int(stats.get("triangles", 0)),
		int((int(stats.get("bytes", 0)) + 1023) / 1024)]
