/**************************************************************************/
/*  cgame_gpu_resource_report.cpp                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "cgame_gpu_resource_report.h"

#include "core/object/class_db.h"

#include "core/os/time.h"
#include "scene/3d/gpu_particles_3d.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/multimesh_instance_3d.h"
#include "scene/3d/decal.h"
#include "scene/3d/sprite_3d.h"
#include "scene/main/node.h"
#include "scene/main/viewport.h"
#include "scene/resources/image_texture.h"
#include "scene/resources/material.h"
#include "scene/resources/mesh.h"
#include "scene/resources/multimesh.h"
#include "scene/resources/shader.h"
#include "servers/rendering/rendering_server.h"

// --- Byte estimation ---------------------------------------------------------------------------

int CgameGPUResourceReport::format_bpp(int p_format) {
	switch (p_format) {
		case Image::FORMAT_L8:
		case Image::FORMAT_R8:
			return 8;
		case Image::FORMAT_LA8:
		case Image::FORMAT_RG8:
		case Image::FORMAT_RGBA4444:
		case Image::FORMAT_RGB565:
		case Image::FORMAT_RH:
			return 16;
		case Image::FORMAT_RGB8:
			return 24;
		case Image::FORMAT_RGBA8:
		case Image::FORMAT_RF:
		case Image::FORMAT_RGH:
		case Image::FORMAT_RGBE9995:
			return 32;
		case Image::FORMAT_RGBH:
			return 48;
		case Image::FORMAT_RGF:
		case Image::FORMAT_RGBAH:
			return 64;
		case Image::FORMAT_RGBF:
			return 96;
		case Image::FORMAT_RGBAF:
			return 128;
		case Image::FORMAT_DXT1:
		case Image::FORMAT_RGTC_R:
		case Image::FORMAT_ETC:
		case Image::FORMAT_ETC2_R11:
		case Image::FORMAT_ETC2_R11S:
		case Image::FORMAT_ETC2_RGB8:
		case Image::FORMAT_ETC2_RGB8A1:
			return 4;
		case Image::FORMAT_DXT3:
		case Image::FORMAT_DXT5:
		case Image::FORMAT_RGTC_RG:
		case Image::FORMAT_BPTC_RGBA:
		case Image::FORMAT_BPTC_RGBF:
		case Image::FORMAT_BPTC_RGBFU:
		case Image::FORMAT_ETC2_RG11:
		case Image::FORMAT_ETC2_RG11S:
		case Image::FORMAT_ETC2_RGBA8:
		case Image::FORMAT_DXT5_RA_AS_RG:
		case Image::FORMAT_ETC2_RA_AS_RG:
		case Image::FORMAT_ASTC_4x4:
		case Image::FORMAT_ASTC_4x4_HDR:
			return 8;
		case Image::FORMAT_ASTC_8x8:
		case Image::FORMAT_ASTC_8x8_HDR:
			return 2;
		default:
			break;
	}
	return -1;
}

bool CgameGPUResourceReport::is_block_compressed(int p_format) {
	return p_format >= Image::FORMAT_DXT1 && p_format != Image::FORMAT_RGBE9995 && p_format < Image::FORMAT_MAX;
}

int64_t CgameGPUResourceReport::texture_bytes(int p_width, int p_height, int p_format, bool p_mipmaps, int p_layers) {
	if (p_width <= 0 || p_height <= 0) {
		return 0;
	}
	int64_t bpp = format_bpp(p_format);
	if (bpp < 0) {
		bpp = 32;
	}
	const int64_t block = is_block_compressed(p_format) ? 4 : 1;
	int64_t w = p_width;
	int64_t h = p_height;
	int64_t total = 0;
	while (true) {
		const int64_t bw = MAX(w, block);
		const int64_t bh = MAX(h, block);
		total += (bw * bh * bpp + 7) >> 3;
		if (!p_mipmaps || (w <= 1 && h <= 1)) {
			break;
		}
		w = MAX(w >> 1, (int64_t)1);
		h = MAX(h >> 1, (int64_t)1);
	}
	return total * MAX(p_layers, 1);
}

String CgameGPUResourceReport::format_bytes(int64_t p_bytes) {
	if (p_bytes >= 1048576) {
		return vformat("%.2f MiB", (double)p_bytes / 1048576.0);
	}
	if (p_bytes >= 1024) {
		return vformat("%.1f KiB", (double)p_bytes / 1024.0);
	}
	return vformat("%d B", p_bytes);
}

// --- Collection --------------------------------------------------------------------------------

Dictionary CgameGPUResourceReport::rendering_totals() {
	Dictionary totals;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return totals;
	}
	totals["video_mem"] = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_VIDEO_MEM_USED);
	totals["texture_mem"] = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_TEXTURE_MEM_USED);
	totals["buffer_mem"] = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_BUFFER_MEM_USED);
	totals["draw_calls"] = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME);
	totals["objects"] = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME);
	totals["primitives"] = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME);
	return totals;
}

int64_t CgameGPUResourceReport::_sum_bytes(const Dictionary &p_entries) {
	int64_t total = 0;
	for (const Variant &value : p_entries.values()) {
		const Dictionary entry = value;
		total += (int64_t)entry["bytes"];
	}
	return total;
}

Dictionary CgameGPUResourceReport::collect(Node *p_root) {
	meshes.clear();
	materials.clear();
	textures.clear();
	shaders.clear();
	node_counts.clear();
	instance_bytes = 0;
	passes.clear();
	if (p_root != nullptr) {
		_walk(p_root);
		_collect_passes(p_root);
	}
	return snapshot();
}

Dictionary CgameGPUResourceReport::snapshot() const {
	const int64_t mesh_bytes = _sum_bytes(meshes);
	const int64_t tex_bytes = _sum_bytes(textures);
	int64_t vertices = 0;
	int64_t indices = 0;
	for (const Variant &value : meshes.values()) {
		const Dictionary entry = value;
		vertices += (int64_t)entry["vertices"];
		indices += (int64_t)entry["indices"];
	}
	Dictionary totals;
	totals["mesh_bytes"] = mesh_bytes;
	totals["texture_bytes"] = tex_bytes;
	totals["instance_bytes"] = instance_bytes;
	totals["estimated_bytes"] = mesh_bytes + tex_bytes + instance_bytes;
	totals["vertices"] = vertices;
	totals["indices"] = indices;
	totals["mesh_count"] = meshes.size();
	totals["material_count"] = materials.size();
	totals["texture_count"] = textures.size();
	totals["shader_count"] = shaders.size();

	Dictionary result;
	result["meshes"] = meshes.values();
	result["materials"] = materials.values();
	result["textures"] = textures.values();
	result["shaders"] = shaders.values();
	result["nodes"] = node_counts.duplicate();
	result["passes"] = passes.duplicate();
	result["rendering"] = rendering_totals();
	result["totals"] = totals;
	return result;
}

void CgameGPUResourceReport::_count_node(const String &p_kind) {
	node_counts[p_kind] = (int)node_counts.get(p_kind, 0) + 1;
}

String CgameGPUResourceReport::_res_name(const Ref<Resource> &p_resource) {
	if (!p_resource->get_name().is_empty()) {
		return p_resource->get_name();
	}
	if (!p_resource->get_path().is_empty()) {
		return p_resource->get_path();
	}
	return vformat("%s#%d", p_resource->get_class(), (int64_t)p_resource->get_instance_id());
}

void CgameGPUResourceReport::_walk(Node *p_node) {
	if (MeshInstance3D *mi = Object::cast_to<MeshInstance3D>(p_node)) {
		_count_node("MeshInstance3D");
		_add_mesh(mi->get_mesh());
		_add_geometry_materials(mi, mi->get_mesh());
		for (int i = 0; i < mi->get_surface_override_material_count(); i++) {
			_add_material(mi->get_surface_override_material(i));
		}
	} else if (MultiMeshInstance3D *mmi = Object::cast_to<MultiMeshInstance3D>(p_node)) {
		_count_node("MultiMeshInstance3D");
		Ref<MultiMesh> mm = mmi->get_multimesh();
		if (mm.is_valid()) {
			_add_mesh(mm->get_mesh());
			if (mm->get_mesh().is_valid()) {
				for (int s = 0; s < mm->get_mesh()->get_surface_count(); s++) {
					_add_material(mm->get_mesh()->surface_get_material(s));
				}
			}
			int64_t stride = mm->get_transform_format() == MultiMesh::TRANSFORM_3D ? 12 * 4 : 8 * 4;
			if (mm->is_using_colors()) {
				stride += 4;
			}
			if (mm->is_using_custom_data()) {
				stride += 16;
			}
			instance_bytes += stride * mm->get_instance_count();
		}
		_add_geometry_materials(mmi, Ref<Mesh>());
	} else if (GPUParticles3D *gp = Object::cast_to<GPUParticles3D>(p_node)) {
		_count_node("GPUParticles3D");
		for (int pass_index = 0; pass_index < gp->get_draw_passes(); pass_index++) {
			Ref<Mesh> m = gp->get_draw_pass_mesh(pass_index);
			_add_mesh(m);
			if (m.is_valid()) {
				for (int s = 0; s < m->get_surface_count(); s++) {
					_add_material(m->surface_get_material(s));
				}
			}
		}
		_add_material(gp->get_process_material());
		// Particle state buffer: transform + velocity + color + custom per particle (~96 B).
		instance_bytes += (int64_t)gp->get_amount() * 96;
		_add_geometry_materials(gp, Ref<Mesh>());
	} else if (Decal *dc = Object::cast_to<Decal>(p_node)) {
		_count_node("Decal");
		for (int tt = 0; tt < Decal::TEXTURE_MAX; tt++) {
			_add_texture(dc->get_texture((Decal::DecalTexture)tt), "decal");
		}
	} else if (Sprite3D *sp = Object::cast_to<Sprite3D>(p_node)) {
		_count_node("Sprite3D");
		_add_texture(sp->get_texture(), "sprite");
		_add_geometry_materials(sp, Ref<Mesh>());
	}
	for (int i = 0; i < p_node->get_child_count(); i++) {
		_walk(p_node->get_child(i));
	}
}

void CgameGPUResourceReport::_add_geometry_materials(GeometryInstance3D *p_gi, const Ref<Mesh> &p_mesh) {
	_add_material(p_gi->get_material_override());
	_add_material(p_gi->get_material_overlay());
	if (p_mesh.is_valid()) {
		for (int s = 0; s < p_mesh->get_surface_count(); s++) {
			_add_material(p_mesh->surface_get_material(s));
		}
	}
}

void CgameGPUResourceReport::_add_mesh(const Ref<Mesh> &p_mesh) {
	if (p_mesh.is_null()) {
		return;
	}
	const int64_t id = (int64_t)p_mesh->get_instance_id();
	if (meshes.has(id)) {
		Dictionary entry = meshes[id];
		entry["users"] = (int)entry["users"] + 1;
		return;
	}
	int64_t vertices = 0;
	int64_t indices = 0;
	int64_t bytes = 0;
	for (int s = 0; s < p_mesh->get_surface_count(); s++) {
		Array arrays = p_mesh->surface_get_arrays(s);
		if (arrays.size() <= Mesh::ARRAY_VERTEX) {
			continue;
		}
		const Variant verts = arrays[Mesh::ARRAY_VERTEX];
		const int64_t vcount = verts.get_type() == Variant::PACKED_VECTOR3_ARRAY ? (int64_t)PackedVector3Array(verts).size() : 0;
		const Variant idx = arrays[Mesh::ARRAY_INDEX];
		const int64_t icount = idx.get_type() == Variant::PACKED_INT32_ARRAY ? (int64_t)PackedInt32Array(idx).size() : 0;
		int64_t stride = 12;
		if (arrays[Mesh::ARRAY_NORMAL].get_type() != Variant::NIL) {
			stride += 4;
		}
		if (arrays[Mesh::ARRAY_TANGENT].get_type() != Variant::NIL) {
			stride += 4;
		}
		if (arrays[Mesh::ARRAY_COLOR].get_type() != Variant::NIL) {
			stride += 4;
		}
		if (arrays[Mesh::ARRAY_TEX_UV].get_type() != Variant::NIL) {
			stride += 8;
		}
		if (arrays[Mesh::ARRAY_TEX_UV2].get_type() != Variant::NIL) {
			stride += 8;
		}
		if (arrays[Mesh::ARRAY_BONES].get_type() != Variant::NIL) {
			stride += 16;
		}
		vertices += vcount;
		indices += icount;
		bytes += vcount * stride + icount * (vcount <= 65535 ? 2 : 4);
	}
	Dictionary entry;
	entry["id"] = id;
	entry["name"] = _res_name(p_mesh);
	entry["surfaces"] = p_mesh->get_surface_count();
	entry["vertices"] = vertices;
	entry["indices"] = indices;
	entry["bytes"] = bytes;
	entry["users"] = 1;
	meshes[id] = entry;
}

void CgameGPUResourceReport::_add_material(const Ref<Material> &p_material) {
	if (p_material.is_null()) {
		return;
	}
	const int64_t id = (int64_t)p_material->get_instance_id();
	if (materials.has(id)) {
		return;
	}
	Dictionary entry;
	entry["id"] = id;
	entry["name"] = _res_name(p_material);
	entry["type"] = p_material->get_class();
	entry["shader"] = "";
	entry["textures"] = 0;
	entry["bytes"] = 0;
	materials[id] = entry;
	Vector<int64_t> tex_ids;
	if (BaseMaterial3D *bm = Object::cast_to<BaseMaterial3D>(p_material.ptr())) {
		entry["shader"] = "BaseMaterial3D";
		for (int tp = 0; tp < BaseMaterial3D::TEXTURE_MAX; tp++) {
			Ref<Texture2D> t = bm->get_texture((BaseMaterial3D::TextureParam)tp);
			if (t.is_valid()) {
				_add_texture(t, "material");
				tex_ids.push_back((int64_t)t->get_instance_id());
			}
		}
	} else if (ShaderMaterial *sm = Object::cast_to<ShaderMaterial>(p_material.ptr())) {
		Ref<Shader> shader = sm->get_shader();
		if (shader.is_valid()) {
			entry["shader"] = _add_shader(shader);
			List<PropertyInfo> uniforms;
			shader->get_shader_uniform_list(&uniforms);
			for (const PropertyInfo &u : uniforms) {
				if (u.type != Variant::OBJECT) {
					continue;
				}
				const Variant v = sm->get_shader_parameter(u.name);
				Ref<Texture2D> t = v;
				if (t.is_valid()) {
					_add_texture(t, "material");
					tex_ids.push_back((int64_t)t->get_instance_id());
				}
			}
		}
	}
	int64_t bytes = 0;
	for (const int64_t tid : tex_ids) {
		if (textures.has(tid)) {
			const Dictionary te = textures[tid];
			bytes += (int64_t)te["bytes"];
		}
	}
	entry["textures"] = tex_ids.size();
	entry["bytes"] = bytes; // Bytes of referenced textures (shared textures counted per material).
}

String CgameGPUResourceReport::_add_shader(const Ref<Shader> &p_shader) {
	const int64_t id = (int64_t)p_shader->get_instance_id();
	const String name = _res_name(p_shader);
	if (!shaders.has(id)) {
		List<PropertyInfo> uniforms;
		p_shader->get_shader_uniform_list(&uniforms);
		Dictionary entry;
		entry["id"] = id;
		entry["name"] = name;
		entry["mode"] = (int)p_shader->get_mode();
		entry["uniforms"] = (int)uniforms.size();
		entry["bytes"] = p_shader->get_code().length();
		shaders[id] = entry;
	}
	return name;
}

void CgameGPUResourceReport::_add_texture(const Ref<Texture2D> &p_texture, const String &p_source) {
	if (p_texture.is_null()) {
		return;
	}
	const int64_t id = (int64_t)p_texture->get_instance_id();
	if (textures.has(id)) {
		return;
	}
	const int w = p_texture->get_width();
	const int h = p_texture->get_height();
	int format = Image::FORMAT_RGBA8;
	bool mips = true;
	bool exact = false;
	const int layers = 1;
	Ref<ImageTexture> image_texture = p_texture;
	if (image_texture.is_valid()) {
		format = image_texture->get_format();
		exact = true;
		mips = false; // ImageTexture mip state is not queryable; created without mips unless generated.
	} else if (probe_compressed) {
		Ref<Image> img = p_texture->get_image();
		if (img.is_valid()) {
			format = img->get_format();
			mips = img->has_mipmaps();
			exact = true;
		}
	}
	Dictionary entry;
	entry["id"] = id;
	entry["name"] = _res_name(p_texture);
	entry["width"] = w;
	entry["height"] = h;
	entry["format"] = format;
	entry["mipmaps"] = mips;
	entry["exact"] = exact;
	entry["source"] = p_source;
	entry["bytes"] = texture_bytes(w, h, format, mips, layers);
	textures[id] = entry;
}

void CgameGPUResourceReport::_collect_passes(Node *p_root) {
	if (!p_root->is_inside_tree()) {
		return;
	}
	Viewport *vp = p_root->get_viewport();
	if (vp == nullptr) {
		return;
	}
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return;
	}
	const RID rid = vp->get_viewport_rid();
	const struct {
		const char *name;
		RSE::ViewportRenderInfoType type;
	} pass_types[2] = {
		{ "visible", RSE::VIEWPORT_RENDER_INFO_TYPE_VISIBLE },
		{ "shadow", RSE::VIEWPORT_RENDER_INFO_TYPE_SHADOW },
	};
	for (int i = 0; i < 2; i++) {
		Dictionary entry;
		entry["pass"] = pass_types[i].name;
		entry["objects"] = rs->viewport_get_render_info(rid, pass_types[i].type, RSE::VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME);
		entry["primitives"] = rs->viewport_get_render_info(rid, pass_types[i].type, RSE::VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME);
		entry["draw_calls"] = rs->viewport_get_render_info(rid, pass_types[i].type, RSE::VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME);
		passes.push_back(entry);
	}
}

// --- Top consumers -----------------------------------------------------------------------------

Dictionary CgameGPUResourceReport::_source(const String &p_kind) const {
	if (p_kind == "meshes") {
		return meshes;
	}
	if (p_kind == "materials") {
		return materials;
	}
	if (p_kind == "textures") {
		return textures;
	}
	if (p_kind == "shaders") {
		return shaders;
	}
	return Dictionary();
}

namespace {
struct EntryBytesGreater {
	bool operator()(const Dictionary &p_a, const Dictionary &p_b) const {
		const int64_t ab = p_a["bytes"];
		const int64_t bb = p_b["bytes"];
		if (ab != bb) {
			return ab > bb;
		}
		return String(p_a["name"]) < String(p_b["name"]);
	}
};
} // namespace

TypedArray<Dictionary> CgameGPUResourceReport::top(int p_n, const String &p_kind) const {
	Vector<Dictionary> entries;
	const Dictionary source = _source(p_kind);
	for (const Variant &value : source.values()) {
		entries.push_back(value);
	}
	entries.sort_custom<EntryBytesGreater>();
	TypedArray<Dictionary> result;
	for (int i = 0; i < entries.size(); i++) {
		if (p_n >= 0 && i >= p_n) {
			break;
		}
		result.push_back(entries[i]);
	}
	return result;
}

// --- VRAM timeline -----------------------------------------------------------------------------

Dictionary CgameGPUResourceReport::timeline_push() {
	const Dictionary totals = rendering_totals();
	Dictionary snap;
	snap["seq"] = timeline_seq;
	snap["time_msec"] = (int64_t)Time::get_singleton()->get_ticks_msec();
	snap["video_mem"] = totals.get("video_mem", 0);
	snap["texture_mem"] = totals.get("texture_mem", 0);
	snap["buffer_mem"] = totals.get("buffer_mem", 0);
	snap["draw_calls"] = totals.get("draw_calls", 0);
	snap["estimated_bytes"] = _sum_bytes(meshes) + _sum_bytes(textures) + instance_bytes;
	timeline_seq++;
	const int cap = MAX(timeline_capacity, 1);
	if (timeline_data.size() < cap) {
		timeline_data.push_back(snap);
	} else {
		timeline_head = timeline_head % timeline_data.size();
		timeline_data[timeline_head] = snap;
		timeline_head = (timeline_head + 1) % timeline_data.size();
	}
	return snap;
}

TypedArray<Dictionary> CgameGPUResourceReport::timeline() const {
	TypedArray<Dictionary> result;
	const int n = timeline_data.size();
	for (int i = 0; i < n; i++) {
		result.push_back(timeline_data[(timeline_head + i) % n]);
	}
	return result;
}

int64_t CgameGPUResourceReport::timeline_peak(const String &p_key) const {
	int64_t peak = 0;
	for (int i = 0; i < timeline_data.size(); i++) {
		const Dictionary sample = timeline_data[i];
		peak = MAX(peak, (int64_t)sample.get(p_key, 0));
	}
	return peak;
}

// --- Report ------------------------------------------------------------------------------------

String CgameGPUResourceReport::_detail(const String &p_kind, const Dictionary &p_entry) const {
	if (p_kind == "meshes") {
		return vformat("%d verts, %d idx, %d users", p_entry["vertices"], p_entry["indices"], p_entry["users"]);
	}
	if (p_kind == "textures") {
		return vformat("%dx%d fmt %d%s", p_entry["width"], p_entry["height"], p_entry["format"], (bool)p_entry["exact"] ? "" : " (assumed)");
	}
	if (p_kind == "materials") {
		return vformat("%s, %d textures", p_entry["type"], p_entry["textures"]);
	}
	if (p_kind == "shaders") {
		return vformat("%d uniforms", p_entry["uniforms"]);
	}
	return "";
}

String CgameGPUResourceReport::to_markdown(int p_top_n) const {
	const Dictionary snap = snapshot();
	const Dictionary totals = snap["totals"];
	const Dictionary rend = snap["rendering"];
	Vector<String> lines;
	lines.push_back("# GPU resource report");
	lines.push_back("");
	lines.push_back("## Totals (estimated)");
	lines.push_back(vformat("- Meshes: %d (%s, %d vertices, %d indices)", totals["mesh_count"], format_bytes(totals["mesh_bytes"]), totals["vertices"], totals["indices"]));
	lines.push_back(vformat("- Textures: %d (%s)", totals["texture_count"], format_bytes(totals["texture_bytes"])));
	lines.push_back(vformat("- Materials: %d, Shaders: %d", totals["material_count"], totals["shader_count"]));
	lines.push_back(vformat("- Instance/particle buffers: %s", format_bytes(totals["instance_bytes"])));
	lines.push_back(vformat("- **Estimated total: %s**", format_bytes(totals["estimated_bytes"])));
	lines.push_back("");
	lines.push_back("## RenderingServer");
	lines.push_back(vformat("- Video mem: %s, texture mem: %s, buffer mem: %s", format_bytes(rend.get("video_mem", 0)), format_bytes(rend.get("texture_mem", 0)), format_bytes(rend.get("buffer_mem", 0))));
	lines.push_back(vformat("- Draw calls: %d, objects: %d, primitives: %d", rend.get("draw_calls", 0), rend.get("objects", 0), rend.get("primitives", 0)));
	const TypedArray<Dictionary> pass_list = snap["passes"];
	if (!pass_list.is_empty()) {
		lines.push_back("");
		lines.push_back("## Render passes");
		lines.push_back("| Pass | Objects | Primitives | Draw calls |");
		lines.push_back("|---|---|---|---|");
		for (int i = 0; i < pass_list.size(); i++) {
			const Dictionary p = pass_list[i];
			lines.push_back(vformat("| %s | %d | %d | %d |", p["pass"], p["objects"], p["primitives"], p["draw_calls"]));
		}
	}
	static const char *kinds[4] = { "meshes", "materials", "textures", "shaders" };
	for (int k = 0; k < 4; k++) {
		const String kind = kinds[k];
		const TypedArray<Dictionary> rows = top(p_top_n, kind);
		lines.push_back("");
		lines.push_back("## Top " + kind);
		if (rows.is_empty()) {
			lines.push_back("_none_");
			continue;
		}
		lines.push_back("| Name | Estimated size | Detail |");
		lines.push_back("|---|---|---|");
		for (int i = 0; i < rows.size(); i++) {
			const Dictionary e = rows[i];
			lines.push_back(vformat("| %s | %s | %s |", e["name"], format_bytes(e["bytes"]), _detail(kind, e)));
		}
	}
	const TypedArray<Dictionary> tl = timeline();
	if (!tl.is_empty()) {
		lines.push_back("");
		lines.push_back("## VRAM timeline");
		lines.push_back(vformat("- Samples: %d, peak video mem: %s, peak estimate: %s", tl.size(), format_bytes(timeline_peak("video_mem")), format_bytes(timeline_peak("estimated_bytes"))));
	}
	return String("\n").join(lines) + "\n";
}

void CgameGPUResourceReport::_bind_methods() {
	BIND_CONSTANT(TIMELINE_CAPACITY);
	ClassDB::bind_static_method("CgameGPUResourceReport", D_METHOD("format_bpp", "format"), &CgameGPUResourceReport::format_bpp);
	ClassDB::bind_static_method("CgameGPUResourceReport", D_METHOD("is_block_compressed", "format"), &CgameGPUResourceReport::is_block_compressed);
	ClassDB::bind_static_method("CgameGPUResourceReport", D_METHOD("texture_bytes", "width", "height", "format", "mipmaps", "layers"), &CgameGPUResourceReport::texture_bytes, DEFVAL(1));
	ClassDB::bind_static_method("CgameGPUResourceReport", D_METHOD("format_bytes", "bytes"), &CgameGPUResourceReport::format_bytes);
	ClassDB::bind_static_method("CgameGPUResourceReport", D_METHOD("rendering_totals"), &CgameGPUResourceReport::rendering_totals);

	ClassDB::bind_method(D_METHOD("collect", "root"), &CgameGPUResourceReport::collect);
	ClassDB::bind_method(D_METHOD("snapshot"), &CgameGPUResourceReport::snapshot);
	ClassDB::bind_method(D_METHOD("top", "n", "kind"), &CgameGPUResourceReport::top);
	ClassDB::bind_method(D_METHOD("timeline_push"), &CgameGPUResourceReport::timeline_push);
	ClassDB::bind_method(D_METHOD("timeline"), &CgameGPUResourceReport::timeline);
	ClassDB::bind_method(D_METHOD("timeline_peak", "key"), &CgameGPUResourceReport::timeline_peak);
	ClassDB::bind_method(D_METHOD("to_markdown", "top_n"), &CgameGPUResourceReport::to_markdown, DEFVAL(5));

	ClassDB::bind_method(D_METHOD("set_probe_compressed", "enabled"), &CgameGPUResourceReport::set_probe_compressed);
	ClassDB::bind_method(D_METHOD("get_probe_compressed"), &CgameGPUResourceReport::get_probe_compressed);
	ClassDB::bind_method(D_METHOD("set_timeline_capacity", "capacity"), &CgameGPUResourceReport::set_timeline_capacity);
	ClassDB::bind_method(D_METHOD("get_timeline_capacity"), &CgameGPUResourceReport::get_timeline_capacity);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "probe_compressed"), "set_probe_compressed", "get_probe_compressed");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "timeline_capacity", PROPERTY_HINT_RANGE, "1,65536,1"), "set_timeline_capacity", "get_timeline_capacity");
}
