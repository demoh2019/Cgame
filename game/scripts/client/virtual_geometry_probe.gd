extends RefCounted
## Opt-in GPU meshlet residency probe using the ACTUAL Albion After rock mesh.
## Disabled in normal play. It never replaces gameplay rocks, their materials
## or their authoritative collision/mining interactions.
##
## CGAME_MESHLET_PAGE_PROBE=1 enables one extra render-only rock in a Vulkan
## debugging session when VK_EXT_mesh_shader support is reported. Metal and
## other devices use the normal rock rendering path and create no probe.

const MeshletRenderer = preload("res://scripts/client/meshlet_renderer.gd")


static func prepare(mesh: Mesh, max_pages: int = 16,
		uploads_per_frame: int = 2) -> RefCounted:
	if mesh == null or mesh.get_surface_count() != 1 or mesh.get_blend_shape_count() != 0 or \
			mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return null
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.size() != Mesh.ARRAY_MAX:
		return null
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.is_empty() or indices.is_empty() or indices.size() % 3 != 0:
		return null
	var renderer := MeshletRenderer.new()
	renderer.max_resident_pages = clampi(max_pages, 1, 256)
	renderer.max_page_uploads_per_frame = clampi(uploads_per_frame, 1, 64)
	if not renderer.setup_from_mesh(vertices, indices):
		return null
	return renderer


## Creates one extra DEBUG-only meshlet visualization from the canonical
## game rock mesh, keeping every existing rock untouched. The camera is the
## existing online_main camera; no separate scene, server or game is created.
static func attach_for_debug(mesh: Mesh, camera: Camera3D) -> RefCounted:
	if not OS.is_debug_build() or OS.get_environment("CGAME_MESHLET_PAGE_PROBE") != "1" or \
			camera == null or not is_instance_valid(camera):
		return null
	var renderer: RefCounted = prepare(mesh)
	if renderer == null or not renderer.call("mesh_shader_supported"):
		return null
	# The debug-colored stone appears at the camera's initial world focus.
	# Mesh shader draws use world transforms; the normal game rendering is unchanged.
	renderer.set("model", Transform3D(Basis.IDENTITY, Vector3(3, 0, 3)))
	if int(renderer.call("attach", camera.get_parent(), camera)) != 1:
		return null
	return renderer
