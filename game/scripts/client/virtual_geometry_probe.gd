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
	if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		return null
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty() or vertices.size() > 1000000:
		return null
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		# Procedural rock meshes can have triangle-list vertices without an index stream.
		if vertices.size() % 3 != 0:
			return null
		indices.resize(vertices.size())
		for i in indices.size():
			indices[i] = i
	if indices.size() > 3000000 or indices.size() % 3 != 0:
		return null
	var renderer := MeshletRenderer.new()
	# Keep only source geometry + bounds on CPU. Pack/upload one page at a
	# time instead of duplicating the full global GPU layout in host RAM.
	renderer.gpu_streamed_source_only = true
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


## Remove the debug compositor callback before freeing its GPU page RIDs.
## Renderer resources are created by the render thread, so retire them there.
static func detach_for_debug(renderer: RefCounted, camera: Camera3D) -> void:
	if renderer == null:
		return
	if camera != null and is_instance_valid(camera) and camera.compositor != null:
		var comp: Compositor = camera.compositor
		var effects: Array[CompositorEffect] = comp.compositor_effects
		for effect in effects.duplicate():
			if effect.get("renderer") == renderer:
				effects.erase(effect)
		comp.compositor_effects = effects
	if RenderingServer.has_method("call_on_render_thread"):
		RenderingServer.call_on_render_thread(Callable(renderer, "release"))
	else:
		# A renderer without this API is necessarily on the legacy
		# fallback path, which never allocated the GPU page buffers.
		renderer.call("release")
