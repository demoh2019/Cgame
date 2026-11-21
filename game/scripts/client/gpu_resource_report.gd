extends RefCounted
## GPU resource diagnostics: walks a node tree and estimates VRAM use of meshes, materials,
## textures and shaders, adds RenderingServer totals and per-viewport render-pass info, and
## keeps a ring-buffer timeline of totals. Byte figures are ESTIMATES (driver padding, tiling and
## compression-on-upload are not visible from script).
## Original code for this project; no third-party code.

const KINDS: Array[String] = ["meshes", "materials", "textures", "shaders"]
const TIMELINE_CAPACITY := 256

## Read back compressed textures through get_image() for exact formats (slow; off by default).
var probe_compressed: bool = false
var timeline_capacity: int = TIMELINE_CAPACITY

var _meshes: Dictionary = {} # instance_id -> entry
var _materials: Dictionary = {}
var _textures: Dictionary = {}
var _shaders: Dictionary = {}
var _node_counts: Dictionary = {}
var _instance_bytes: int = 0
var _passes: Array[Dictionary] = []
var _timeline: Array[Dictionary] = []
var _timeline_head: int = 0
var _timeline_count: int = 0
var _timeline_seq: int = 0


# --- Byte estimation -------------------------------------------------------------------------

## Bits per pixel for an Image.Format, or -1 when unknown.
static func format_bpp(format: int) -> int:
	match format:
		Image.FORMAT_L8, Image.FORMAT_R8:
			return 8
		Image.FORMAT_LA8, Image.FORMAT_RG8, Image.FORMAT_RGBA4444, Image.FORMAT_RGB565, Image.FORMAT_RH:
			return 16
		Image.FORMAT_RGB8:
			return 24
		Image.FORMAT_RGBA8, Image.FORMAT_RF, Image.FORMAT_RGH, Image.FORMAT_RGBE9995:
			return 32
		Image.FORMAT_RGBH:
			return 48
		Image.FORMAT_RGF, Image.FORMAT_RGBAH:
			return 64
		Image.FORMAT_RGBF:
			return 96
		Image.FORMAT_RGBAF:
			return 128
		Image.FORMAT_DXT1, Image.FORMAT_RGTC_R, Image.FORMAT_ETC, Image.FORMAT_ETC2_R11, \
		Image.FORMAT_ETC2_R11S, Image.FORMAT_ETC2_RGB8, Image.FORMAT_ETC2_RGB8A1:
			return 4
		Image.FORMAT_DXT3, Image.FORMAT_DXT5, Image.FORMAT_RGTC_RG, Image.FORMAT_BPTC_RGBA, \
		Image.FORMAT_BPTC_RGBF, Image.FORMAT_BPTC_RGBFU, Image.FORMAT_ETC2_RG11, \
		Image.FORMAT_ETC2_RG11S, Image.FORMAT_ETC2_RGBA8, Image.FORMAT_DXT5_RA_AS_RG, \
		Image.FORMAT_ETC2_RA_AS_RG, Image.FORMAT_ASTC_4x4, Image.FORMAT_ASTC_4x4_HDR:
			return 8
		Image.FORMAT_ASTC_8x8, Image.FORMAT_ASTC_8x8_HDR:
			return 2
	return -1


static func is_block_compressed(format: int) -> bool:
	return format >= Image.FORMAT_DXT1 and format != Image.FORMAT_RGBE9995 and format < Image.FORMAT_MAX


## Estimated bytes for a 2D texture, optionally including the full mip chain.
## `layers` multiplies the result (array / cube / 3D slices).
static func texture_bytes(width: int, height: int, format: int, mipmaps: bool, layers: int = 1) -> int:
	if width <= 0 or height <= 0:
		return 0
	var bpp := format_bpp(format)
	if bpp < 0:
		bpp = 32
	var block := 4 if is_block_compressed(format) else 1
	var w := width
	var h := height
	var total := 0
	while true:
		var bw := maxi(w, block)
		var bh := maxi(h, block)
		total += (bw * bh * bpp + 7) >> 3
		if not mipmaps or (w <= 1 and h <= 1):
			break
		w = maxi(w >> 1, 1)
		h = maxi(h >> 1, 1)
	return total * maxi(layers, 1)


# --- Collection ------------------------------------------------------------------------------

func collect(root: Node) -> Dictionary:
	_meshes.clear()
	_materials.clear()
	_textures.clear()
	_shaders.clear()
	_node_counts.clear()
	_instance_bytes = 0
	_passes.clear()
	if root != null:
		_walk(root)
		_collect_passes(root)
	return snapshot()


func snapshot() -> Dictionary:
	var mesh_bytes := _sum_bytes(_meshes)
	var tex_bytes := _sum_bytes(_textures)
	var vertices := 0
	var indices := 0
	for e: Dictionary in _meshes.values():
		vertices += int(e["vertices"])
		indices += int(e["indices"])
	return {
		"meshes": _meshes.values(),
		"materials": _materials.values(),
		"textures": _textures.values(),
		"shaders": _shaders.values(),
		"nodes": _node_counts.duplicate(),
		"passes": _passes.duplicate(),
		"rendering": rendering_totals(),
		"totals": {
			"mesh_bytes": mesh_bytes,
			"texture_bytes": tex_bytes,
			"instance_bytes": _instance_bytes,
			"estimated_bytes": mesh_bytes + tex_bytes + _instance_bytes,
			"vertices": vertices,
			"indices": indices,
			"mesh_count": _meshes.size(),
			"material_count": _materials.size(),
			"texture_count": _textures.size(),
			"shader_count": _shaders.size(),
		},
	}


static func rendering_totals() -> Dictionary:
	return {
		"video_mem": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		"texture_mem": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)),
		"buffer_mem": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)),
		"draw_calls": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
	}


func _sum_bytes(d: Dictionary) -> int:
	var total := 0
	for e: Dictionary in d.values():
		total += int(e["bytes"])
	return total


func _count_node(kind: String) -> void:
	_node_counts[kind] = int(_node_counts.get(kind, 0)) + 1


func _walk(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		_count_node("MeshInstance3D")
		_add_mesh(mi.mesh, mi.get_surface_override_material_count())
		_add_geometry_materials(mi, mi.mesh)
		for i in mi.get_surface_override_material_count():
			_add_material(mi.get_surface_override_material(i))
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		_count_node("MultiMeshInstance3D")
		var mm := mmi.multimesh
		if mm != null:
			_add_mesh(mm.mesh, 0)
			if mm.mesh != null:
				for s in mm.mesh.get_surface_count():
					_add_material(mm.mesh.surface_get_material(s))
			var stride := 12 * 4 if mm.transform_format == MultiMesh.TRANSFORM_3D else 8 * 4
			if mm.use_colors:
				stride += 4
			if mm.use_custom_data:
				stride += 16
			_instance_bytes += stride * mm.instance_count
		_add_geometry_materials(mmi, null)
	elif node is GPUParticles3D:
		var gp := node as GPUParticles3D
		_count_node("GPUParticles3D")
		for pass_index in gp.draw_passes:
			var m := gp.get_draw_pass_mesh(pass_index)
			_add_mesh(m, 0)
			if m != null:
				for s in m.get_surface_count():
					_add_material(m.surface_get_material(s))
		_add_material(gp.process_material)
		# Particle state buffer: transform + velocity + color + custom per particle (~96 B).
		_instance_bytes += gp.amount * 96
		_add_geometry_materials(gp, null)
	elif node is Decal:
		var dc := node as Decal
		_count_node("Decal")
		for tt in Decal.TEXTURE_MAX:
			_add_texture(dc.get_texture(tt as Decal.DecalTexture), "decal")
	elif node is Sprite3D:
		var sp := node as Sprite3D
		_count_node("Sprite3D")
		_add_texture(sp.texture, "sprite")
		_add_geometry_materials(sp, null)
	for child in node.get_children():
		_walk(child)


func _add_geometry_materials(gi: GeometryInstance3D, mesh: Mesh) -> void:
	_add_material(gi.material_override)
	_add_material(gi.material_overlay)
	if mesh != null:
		for s in mesh.get_surface_count():
			_add_material(mesh.surface_get_material(s))


func _add_mesh(mesh: Mesh, _override_count: int) -> void:
	if mesh == null:
		return
	var id := mesh.get_instance_id()
	if _meshes.has(id):
		var e: Dictionary = _meshes[id]
		e["users"] = int(e["users"]) + 1
		return
	var vertices := 0
	var indices := 0
	var bytes := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		var vcount: int = (verts as PackedVector3Array).size() if verts is PackedVector3Array else 0
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var icount: int = (idx as PackedInt32Array).size() if idx is PackedInt32Array else 0
		var stride := 12
		if arrays[Mesh.ARRAY_NORMAL] != null:
			stride += 4
		if arrays[Mesh.ARRAY_TANGENT] != null:
			stride += 4
		if arrays[Mesh.ARRAY_COLOR] != null:
			stride += 4
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			stride += 8
		if arrays[Mesh.ARRAY_TEX_UV2] != null:
			stride += 8
		if arrays[Mesh.ARRAY_BONES] != null:
			stride += 16
		vertices += vcount
		indices += icount
		bytes += vcount * stride + icount * (2 if vcount <= 65535 else 4)
	_meshes[id] = {
		"id": id,
		"name": _res_name(mesh),
		"surfaces": mesh.get_surface_count(),
		"vertices": vertices,
		"indices": indices,
		"bytes": bytes,
		"users": 1,
	}


func _add_material(mat: Material) -> void:
	if mat == null:
		return
	var id := mat.get_instance_id()
	if _materials.has(id):
		return
	var entry := {"id": id, "name": _res_name(mat), "type": mat.get_class(), "shader": "", "textures": 0, "bytes": 0}
	_materials[id] = entry
	var tex_ids: Array[int] = []
	if mat is BaseMaterial3D:
		entry["shader"] = "BaseMaterial3D"
		var bm := mat as BaseMaterial3D
		for tp in BaseMaterial3D.TEXTURE_MAX:
			var t := bm.get_texture(tp as BaseMaterial3D.TextureParam)
			if t != null:
				_add_texture(t, "material")
				tex_ids.append(t.get_instance_id())
	elif mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		if sm.shader != null:
			entry["shader"] = _add_shader(sm.shader)
			for u: Dictionary in sm.shader.get_shader_uniform_list():
				if int(u["type"]) != TYPE_OBJECT:
					continue
				var v: Variant = sm.get_shader_parameter(String(u["name"]))
				if v is Texture2D:
					_add_texture(v as Texture2D, "material")
					tex_ids.append((v as Texture2D).get_instance_id())
	var bytes := 0
	for tid in tex_ids:
		if _textures.has(tid):
			var te: Dictionary = _textures[tid]
			bytes += int(te["bytes"])
	entry["textures"] = tex_ids.size()
	entry["bytes"] = bytes # bytes of referenced textures (shared textures counted per material)


func _add_shader(shader: Shader) -> String:
	var id := shader.get_instance_id()
	var name := _res_name(shader)
	if not _shaders.has(id):
		_shaders[id] = {"id": id, "name": name, "mode": int(shader.get_mode()),
			"uniforms": shader.get_shader_uniform_list().size(), "bytes": shader.code.length()}
	return name


func _add_texture(tex: Texture2D, source: String) -> void:
	if tex == null:
		return
	var id := tex.get_instance_id()
	if _textures.has(id):
		return
	var w := tex.get_width()
	var h := tex.get_height()
	var format := Image.FORMAT_RGBA8
	var mips := true
	var exact := false
	var layers := 1
	if tex is ImageTexture:
		format = (tex as ImageTexture).get_format()
		exact = true
		mips = false # ImageTexture mip state is not queryable; created without mips unless generated
	elif probe_compressed:
		var img := tex.get_image()
		if img != null:
			format = img.get_format()
			mips = img.has_mipmaps()
			exact = true
	_textures[id] = {
		"id": id,
		"name": _res_name(tex),
		"width": w,
		"height": h,
		"format": format,
		"mipmaps": mips,
		"exact": exact,
		"source": source,
		"bytes": texture_bytes(w, h, format, mips, layers),
	}


func _res_name(r: Resource) -> String:
	if r.resource_name != "":
		return r.resource_name
	if r.resource_path != "":
		return r.resource_path
	return "%s#%d" % [r.get_class(), r.get_instance_id()]


func _collect_passes(root: Node) -> void:
	if not root.is_inside_tree():
		return
	var vp := root.get_viewport()
	if vp == null:
		return
	var rid := vp.get_viewport_rid()
	for pass_info: Array in [["visible", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE], ["shadow", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW]]:
		var kind: int = pass_info[1]
		_passes.append({
			"pass": pass_info[0],
			"objects": int(RenderingServer.viewport_get_render_info(rid, kind, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)),
			"primitives": int(RenderingServer.viewport_get_render_info(rid, kind, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)),
			"draw_calls": int(RenderingServer.viewport_get_render_info(rid, kind, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)),
		})


# --- Top consumers ---------------------------------------------------------------------------

## Top `n` entries of `kind` (meshes | materials | textures | shaders) by estimated bytes,
## descending; ties break by name so the order is deterministic.
func top(n: int, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var src: Dictionary = _source(kind)
	for e: Dictionary in src.values():
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ab: int = a["bytes"]
		var bb: int = b["bytes"]
		if ab != bb:
			return ab > bb
		return String(a["name"]) < String(b["name"]))
	if n >= 0 and out.size() > n:
		out.resize(n)
	return out


func _source(kind: String) -> Dictionary:
	match kind:
		"meshes":
			return _meshes
		"materials":
			return _materials
		"textures":
			return _textures
		"shaders":
			return _shaders
	return {}


# --- VRAM timeline ---------------------------------------------------------------------------

## Records one sample: RenderingServer memory totals plus the estimate from the last collect().
func timeline_push() -> Dictionary:
	var totals := rendering_totals()
	var snap: Dictionary = {
		"seq": _timeline_seq,
		"time_msec": Time.get_ticks_msec(),
		"video_mem": totals["video_mem"],
		"texture_mem": totals["texture_mem"],
		"buffer_mem": totals["buffer_mem"],
		"draw_calls": totals["draw_calls"],
		"estimated_bytes": _sum_bytes(_meshes) + _sum_bytes(_textures) + _instance_bytes,
	}
	_timeline_seq += 1
	var cap := maxi(timeline_capacity, 1)
	if _timeline.size() < cap:
		_timeline.append(snap)
		_timeline_count = _timeline.size()
	else:
		_timeline_head = _timeline_head % _timeline.size()
		_timeline[_timeline_head] = snap
		_timeline_head = (_timeline_head + 1) % _timeline.size()
	return snap


## Samples oldest first.
func timeline() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := _timeline.size()
	for i in n:
		out.append(_timeline[(_timeline_head + i) % n])
	return out


func timeline_peak(key: String) -> int:
	var peak := 0
	for s in _timeline:
		peak = maxi(peak, int(s.get(key, 0)))
	return peak


# --- Report ----------------------------------------------------------------------------------

static func format_bytes(b: int) -> String:
	if b >= 1048576:
		return "%.2f MiB" % (float(b) / 1048576.0)
	if b >= 1024:
		return "%.1f KiB" % (float(b) / 1024.0)
	return "%d B" % b


func to_markdown(top_n: int = 5) -> String:
	var snap := snapshot()
	var totals: Dictionary = snap["totals"]
	var rend: Dictionary = snap["rendering"]
	var lines: PackedStringArray = []
	lines.append("# GPU resource report")
	lines.append("")
	lines.append("## Totals (estimated)")
	lines.append("- Meshes: %d (%s, %d vertices, %d indices)" % [totals["mesh_count"], format_bytes(int(totals["mesh_bytes"])), totals["vertices"], totals["indices"]])
	lines.append("- Textures: %d (%s)" % [totals["texture_count"], format_bytes(int(totals["texture_bytes"]))])
	lines.append("- Materials: %d, Shaders: %d" % [totals["material_count"], totals["shader_count"]])
	lines.append("- Instance/particle buffers: %s" % format_bytes(int(totals["instance_bytes"])))
	lines.append("- **Estimated total: %s**" % format_bytes(int(totals["estimated_bytes"])))
	lines.append("")
	lines.append("## RenderingServer")
	lines.append("- Video mem: %s, texture mem: %s, buffer mem: %s" % [format_bytes(int(rend["video_mem"])), format_bytes(int(rend["texture_mem"])), format_bytes(int(rend["buffer_mem"]))])
	lines.append("- Draw calls: %d, objects: %d, primitives: %d" % [rend["draw_calls"], rend["objects"], rend["primitives"]])
	var passes: Array = snap["passes"]
	if not passes.is_empty():
		lines.append("")
		lines.append("## Render passes")
		lines.append("| Pass | Objects | Primitives | Draw calls |")
		lines.append("|---|---|---|---|")
		for p: Dictionary in passes:
			lines.append("| %s | %d | %d | %d |" % [p["pass"], p["objects"], p["primitives"], p["draw_calls"]])
	for kind in KINDS:
		var rows := top(top_n, kind)
		lines.append("")
		lines.append("## Top %s" % kind)
		if rows.is_empty():
			lines.append("_none_")
			continue
		lines.append("| Name | Estimated size | Detail |")
		lines.append("|---|---|---|")
		for e in rows:
			lines.append("| %s | %s | %s |" % [e["name"], format_bytes(int(e["bytes"])), _detail(kind, e)])
	var tl := timeline()
	if not tl.is_empty():
		lines.append("")
		lines.append("## VRAM timeline")
		lines.append("- Samples: %d, peak video mem: %s, peak estimate: %s" % [tl.size(), format_bytes(timeline_peak("video_mem")), format_bytes(timeline_peak("estimated_bytes"))])
	return "\n".join(lines) + "\n"


func _detail(kind: String, e: Dictionary) -> String:
	match kind:
		"meshes":
			return "%d verts, %d idx, %d users" % [e["vertices"], e["indices"], e["users"]]
		"textures":
			return "%dx%d fmt %d%s" % [e["width"], e["height"], e["format"], "" if e["exact"] else " (assumed)"]
		"materials":
			return "%s, %d textures" % [e["type"], e["textures"]]
		"shaders":
			return "%d uniforms" % e["uniforms"]
	return ""
