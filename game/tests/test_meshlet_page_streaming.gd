extends RefCounted
## CPU contracts for the GPU page layout and bounded upload scheduler. These
## run headless; mesh-shader hardware correctness needs a Vulkan GPU test.

const PagePolicy = preload("res://scripts/shared/meshlet_page_streaming.gd")
const MeshletRenderer = preload("res://scripts/client/meshlet_renderer.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const VirtualGeometryProbe = preload("res://scripts/client/virtual_geometry_probe.gd")


static func make_meshlets(count: int) -> Array:
	var out: Array = []
	for id in count:
		out.append({
			"vertex_ids": PackedInt32Array([0, 1, 2]),
			"indices": PackedInt32Array([0, 1, 2]),
			"bounds_center": Vector3(floorf(float(id) / 32.0) * 20.0, 0.0, 0.0),
			"bounds_radius": 2.0,
			"cone_axis": Vector3.UP,
			"cone_cutoff": 1.0,
		})
	return out


func run(t) -> void:
	t.current = "conservative per-page bounds and stable budget ordering"
	var meshlets: Array = make_meshlets(70)
	var pages: Array[Dictionary] = PagePolicy.build_bounds(meshlets)
	t.eq(pages.size(), 3, "70 meshlets are partitioned into three pages of 32")
	t.eq(int(pages[0]["meshlet_count"]), 32, "full first page")
	t.eq(int(pages[1]["meshlet_count"]), 32, "full second page")
	t.eq(int(pages[2]["meshlet_count"]), 6, "partial last page")
	t.check(float(pages[0]["radius"]) >= 3.0, "page bounds conservatively surround every child sphere")
	var near_zero: PackedInt32Array = PagePolicy.wanted_pages(
		pages, Vector3(0, 0, 0), Transform3D.IDENTITY, 2)
	t.eq(near_zero, PackedInt32Array([0, 1]), "nearer pages are preferred")
	var near_end: PackedInt32Array = PagePolicy.wanted_pages(
		pages, Vector3(60, 0, 0), Transform3D.IDENTITY, 2)
	t.eq(near_end, PackedInt32Array([2, 1]), "camera relocation chooses another page")
	var transformed: PackedInt32Array = PagePolicy.wanted_pages(
		pages, Vector3(200, 0, 0), Transform3D(Basis.IDENTITY, Vector3(180, 0, 0)), 1)
	t.eq(transformed, PackedInt32Array([1]), "residency priorities use the mesh world transform")
	t.eq(PagePolicy.wanted_pages(pages, Vector3.ZERO, Transform3D.IDENTITY).size(),
		3, "zero policy budget means all pages")
	var visible_plane: Array[Plane] = [Plane(Vector3(1, 0, 0), 25.0)]
	var facing: PackedInt32Array = PagePolicy.wanted_pages(
		pages, Vector3(50, 0, 0), Transform3D.IDENTITY, 2, visible_plane)
	t.eq(facing, PackedInt32Array([1, 0]),
		"on-screen pages get precedence over an offscreen page closer to the camera")

	t.current = "GPU page allocation and stable LRU-free eviction"
	var empty := PackedInt32Array([-1, -1])
	var one: Dictionary = PagePolicy.plan(empty, near_zero, 1)
	t.eq(one["slots"], PackedInt32Array([0, -1]), "upload budget limits a frame to one page")
	t.eq((one["uploads"] as Array).size(), 1, "exactly one new upload is scheduled")
	t.eq(int(one["uploads"][0]["slot"]), 0, "vacant slot zero is preferred")
	var two: Dictionary = PagePolicy.plan(one["slots"], near_zero, 1)
	t.eq(two["slots"], PackedInt32Array([0, 1]), "second frame fills the free slot")
	var stable: Dictionary = PagePolicy.plan(two["slots"], near_zero, 5)
	t.eq((stable["uploads"] as Array).size(), 0, "static camera triggers no repeated GPU uploads")
	t.eq(PagePolicy.resident_count(stable["slots"]), 2, "both slots are resident")
	var shifted: Dictionary = PagePolicy.plan(two["slots"], near_end, 1)
	t.eq(shifted["slots"], PackedInt32Array([2, 1]), "only the out-of-budget page is evicted")
	t.eq(shifted["evictions"], PackedInt32Array([0]), "evicted page id is reported")
	t.eq((shifted["uploads"] as Array).size(), 1, "camera movement uploads one replacement")
	var paused: Dictionary = PagePolicy.plan(shifted["slots"], near_zero, 0)
	t.eq(paused["slots"], shifted["slots"], "zero upload budget does not mutate resident buffers")

	t.current = "fixed-slot GPU data layout with no whole-mesh upload"
	var verts := PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 2, 3), Vector3(1, 5, 3)])
	var page: Dictionary = MeshletRenderer.pack_resident_page(verts, meshlets, 1, 2)
	t.eq(String(page.get("error", "error")), "", "one page packs without a device")
	var positions: PackedByteArray = page["positions"]
	var ids: PackedByteArray = page["vertex_ids"]
	var tris: PackedByteArray = page["triangles"]
	var desc: PackedByteArray = page["descriptors"]
	t.eq(positions.size(), PagePolicy.POSITIONS_BYTES, "one fixed-size vertex slot payload")
	t.eq(ids.size(), PagePolicy.VERTEX_IDS_BYTES, "one fixed-size vertex id payload")
	t.eq(tris.size(), PagePolicy.TRIANGLES_BYTES, "one fixed-size local triangle payload")
	t.eq(desc.size(), PagePolicy.DESCRIPTORS_BYTES, "one fixed-size descriptor payload")
	t.near(positions.decode_float(0), 1.0, 0.00001, "position data copied into resident slot")
	t.eq(ids.decode_u32(0), 2 * 32 * 64, "id buffer points to the resident vertex slot")
	t.eq(ids.decode_u32(4), 2 * 32 * 64 + 1, "next vertex is contiguous")
	t.eq(tris.decode_u32(0), 0 | (1 << 8) | (2 << 16), "local triangle packing unchanged")
	t.eq(desc.decode_u32(0), 2 * 32 * 64, "descriptor indexes slot-local vertices")
	t.eq(desc.decode_u32(4), 2 * 32 * 124, "descriptor indexes slot-local triangles")
	t.eq(desc.decode_u32(8), 3, "one meshlet has three vertices")
	t.eq(desc.decode_u32(12), 1, "one triangle per meshlet")
	t.eq(desc.decode_u32(48), 2 * 32 * 64 + 64, "second meshlet has a separate vertex window")
	t.eq(desc.decode_u32(48 + 4), 2 * 32 * 124 + 124, "second meshlet has a separate triangle window")
	var last: Dictionary = MeshletRenderer.pack_resident_page(verts, meshlets, 2, 0)
	var tail: PackedByteArray = last["descriptors"]
	t.eq(int(last["meshlet_count"]), 6, "last page uploads only six live meshlets")
	t.eq(tail.decode_u32(6 * 48 + 12), 0, "unused slots are zeroed to prevent mesh dispatch")
	t.check(String(MeshletRenderer.pack_resident_page(verts, meshlets, 3, 0)["error"]) != "",
		"out of range page is rejected")

	t.current = "runtime retains a safe headless ArrayMesh fallback"
	var renderer := MeshletRenderer.new()
	t.check(renderer.setup(verts, meshlets), "packed meshlets can be submitted to the shared renderer")
	t.eq(renderer.page_count(), 3, "render instance owns three geometry pages")
	t.eq(int(renderer.get_page_stats()["resident_pages"]), 0, "no graphics device means no GPU uploads")
	t.eq(PagePolicy.PAGE_BYTES,
		PagePolicy.POSITIONS_BYTES + PagePolicy.VERTEX_IDS_BYTES + PagePolicy.TRIANGLES_BYTES + PagePolicy.DESCRIPTORS_BYTES,
		"resident GPU byte budget includes every buffer")
	renderer.force_fallback = true
	t.eq(renderer.choose_path(), MeshletRenderer.DrawPath.FALLBACK, "Metal or forced fallback does not invoke mesh shaders")
	var fallback: ArrayMesh = renderer.build_array_mesh()
	t.eq(fallback.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size(), 70 * 3,
		"fallback retains every triangle despite GPU page limits")

	t.current = "canonical game model uses optional GPU page streaming"
	var actual_rock: Mesh = Meshes.get_mesh("rock")
	var game_renderer: RefCounted = VirtualGeometryProbe.prepare(actual_rock, 2, 1)
	t.check(game_renderer != null, "the live Albion rock model can produce GPU meshlets")
	if game_renderer != null:
		t.check(int(game_renderer.call("page_count")) >= 1,
			"real game model generates one or more streamable pages")
		t.check(not game_renderer.call("get_packed").has("positions"),
			"GPU page mode skips the duplicate full-source CPU upload buffer")
		t.eq(int(game_renderer.get("max_resident_pages")), 2,
			"live debug feature applies a bounded resident page budget")
		t.eq(int(game_renderer.get("max_page_uploads_per_frame")), 1,
			"live debug feature applies a transfer-per-frame limit")
	t.check(VirtualGeometryProbe.prepare(null) == null, "null game mesh is safely ignored")
	t.check(VirtualGeometryProbe.prepare(ArrayMesh.new()) == null,
		"missing geometry does not register a GPU draw")
	t.check(VirtualGeometryProbe.attach_for_debug(actual_rock, null) == null,
		"no camera never creates a compositor effect")
	var client_source: String = FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(client_source.contains('VirtualGeometryProbe.attach_for_debug(Meshes.get_mesh("rock"), camera)'),
		"online game calls GPU probe on the canonical rock, not a duplicate game project")
	t.check(client_source.contains('VirtualGeometryProbe.detach_for_debug(_meshlet_page_probe, camera)'),
		"online game releases the page pool on shutdown")

	t.current = "GPU task shaders exclude unresident descriptor slots"
	var task_source: String = MeshletRenderer._read_text(MeshletRenderer.TASK_SHADER_PATH)
	t.check(task_source.contains("m.counts.z == 0u || m.counts.w == 0u"),
		"the GPU task shader refuses zeroed pages")
	var renderer_source: String = (MeshletRenderer as Script).source_code
	t.check(renderer_source.contains("_stream_gpu_pages(cam.origin)"),
		"real render-thread path streams pages before issuing draws")
	t.check(renderer_source.contains("rd.call(\"draw_list_draw_mesh_tasks\", draw_list, _slot_pages.size()"),
		"render thread submits only resident task-group slots")
	t.check(renderer_source.contains("slot * stride"),
		"page uploads target bounded fixed GPU memory windows")
