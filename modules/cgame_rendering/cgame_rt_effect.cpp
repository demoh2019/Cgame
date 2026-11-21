/**************************************************************************/
/*  cgame_rt_effect.cpp                                                   */
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

#include "cgame_rt_effect.h"

#include "cgame_rt_shaders.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "scene/resources/mesh.h"
#include "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.h"
#include "servers/rendering/renderer_rd/uniform_set_cache_rd.h"
#include "servers/rendering/rendering_server.h"
#include "servers/rendering/storage/render_data.h"
#include "servers/rendering/storage/render_scene_data.h"

// ---- Pure helpers ------------------------------------------------------------------------------

bool CgameRTEffect::is_supported(RenderingDevice *p_rd) {
	return p_rd != nullptr && p_rd->has_feature(RenderingDevice::SUPPORTS_RAY_QUERY);
}

Dictionary CgameRTEffect::settings(int p_level, const String &p_rendering_method) {
	const int tier = CLAMP(p_level, 0, 3);
	const bool enabled = tier >= 1 && p_rendering_method == "forward_plus";
	Dictionary d;
	d["enabled"] = enabled;
	d["shadows"] = enabled;
	d["ao"] = enabled && tier >= 2;
	d["ao_rays"] = tier == 3 ? 2 : 1;
	d["max_distance"] = tier == 3 ? 60.0 : (tier == 2 ? 45.0 : 30.0);
	d["max_instances"] = tier == 3 ? 768 : (tier == 2 ? 512 : 256);
	d["blas_builds_per_frame"] = tier == 3 ? 4 : 2;
	d["extractions_per_update"] = tier == 3 ? 3 : 2;
	d["update_interval"] = tier == 1 ? 4 : 3;
	d["shadow_tmax"] = tier == 3 ? 120.0 : 80.0;
	d["ao_tmax"] = tier == 3 ? 2.5 : 1.75;
	d["shadow_strength"] = 1.0;
	d["ao_strength"] = 0.85;
	d["temporal_blend"] = 0.9;
	return d;
}

int CgameRTEffect::group_count(int p_pixels, int p_group_size) {
	return (p_pixels + p_group_size - 1) / p_group_size;
}

int CgameRTEffect::builds_this_frame(int p_queued, int p_budget) {
	return MAX(MIN(p_queued, p_budget), 0);
}

int CgameRTEffect::budget_take(int p_pending, int p_per_frame) {
	return MAX(MIN(p_pending, p_per_frame), 0);
}

Vector<int64_t> CgameRTEffect::eviction_candidates_native(const HashMap<int64_t, int64_t> &p_last_used, int64_t p_frame, int p_count, int p_limit) {
	Vector<int64_t> out;
	const int over = p_count - p_limit;
	if (over <= 0) {
		return out;
	}
	struct Aged {
		int64_t key;
		int64_t last_used;
	};
	Vector<Aged> aged;
	for (const KeyValue<int64_t, int64_t> &kv : p_last_used) {
		if (p_frame - kv.value >= EVICT_AGE) {
			aged.push_back({ kv.key, kv.value });
		}
	}
	// Oldest first; ties by key so the order is deterministic.
	struct AgedLess {
		bool operator()(const Aged &p_a, const Aged &p_b) const {
			if (p_a.last_used != p_b.last_used) {
				return p_a.last_used < p_b.last_used;
			}
			return p_a.key < p_b.key;
		}
	};
	aged.sort_custom<AgedLess>();
	for (int i = 0; i < aged.size() && out.size() < over; i++) {
		out.push_back(aged[i].key);
	}
	return out;
}

Array CgameRTEffect::eviction_candidates(const Dictionary &p_last_used, int p_frame, int p_count, int p_limit) {
	HashMap<int64_t, int64_t> last_used;
	for (const KeyValue<Variant, Variant> &kv : p_last_used) {
		last_used[(int64_t)kv.key] = (int64_t)kv.value;
	}
	Array out;
	for (const int64_t key : eviction_candidates_native(last_used, p_frame, p_count, p_limit)) {
		out.push_back(key);
	}
	return out;
}

static void _push_matrix(Vector<float> &r_out, const Projection &p_matrix) {
	for (int c = 0; c < 4; c++) {
		r_out.push_back(p_matrix.columns[c].x);
		r_out.push_back(p_matrix.columns[c].y);
		r_out.push_back(p_matrix.columns[c].z);
		r_out.push_back(p_matrix.columns[c].w);
	}
}

Vector<uint8_t> CgameRTEffect::pack_params_native(const Projection &p_inv_proj, const Transform3D &p_cam_to_world, const Projection &p_prev_view_proj, const Vector3 &p_sun_dir, float p_sun_radius, const Size2i &p_size, int p_frame, int p_ao_rays, const Config &p_config) {
	Vector<float> f;
	_push_matrix(f, p_inv_proj);
	_push_matrix(f, Projection(p_cam_to_world));
	_push_matrix(f, p_prev_view_proj);
	const float values[] = {
		p_sun_dir.x, p_sun_dir.y, p_sun_dir.z, p_sun_radius,
		(float)p_size.x, (float)p_size.y, (float)p_frame, (float)p_ao_rays,
		p_config.shadow_tmax, p_config.ao_tmax, 0.04f, 0.0f,
		p_config.shadows ? p_config.shadow_strength : 0.0f, p_config.ao ? p_config.ao_strength : 0.0f, p_config.temporal_blend, 0.0f
	};
	for (const float v : values) {
		f.push_back(v);
	}
	Vector<uint8_t> bytes;
	bytes.resize(f.size() * (int)sizeof(float));
	memcpy(bytes.ptrw(), f.ptr(), bytes.size());
	return bytes;
}

PackedByteArray CgameRTEffect::pack_params(const Projection &p_inv_proj, const Transform3D &p_cam_to_world, const Projection &p_prev_view_proj, const Vector3 &p_sun_dir, float p_sun_radius, const Size2i &p_size, int p_frame, int p_ao_rays, const Dictionary &p_config) {
	const Vector<uint8_t> bytes = pack_params_native(p_inv_proj, p_cam_to_world, p_prev_view_proj, p_sun_dir, p_sun_radius, p_size, p_frame, p_ao_rays, config_from_dictionary(p_config));
	PackedByteArray out;
	out.resize(bytes.size());
	memcpy(out.ptrw(), bytes.ptr(), bytes.size());
	return out;
}

CgameRTEffect::Config CgameRTEffect::config_from_dictionary(const Dictionary &p_config) {
	Config c;
	c.shadows = p_config.get("shadows", true);
	c.ao = p_config.get("ao", true);
	c.ao_rays = p_config.get("ao_rays", 1);
	c.max_instances = p_config.get("max_instances", 256);
	c.blas_builds_per_frame = p_config.get("blas_builds_per_frame", 2);
	c.shadow_tmax = p_config.get("shadow_tmax", 80.0f);
	c.ao_tmax = p_config.get("ao_tmax", 1.75f);
	c.shadow_strength = p_config.get("shadow_strength", 1.0f);
	c.ao_strength = p_config.get("ao_strength", 0.85f);
	c.temporal_blend = p_config.get("temporal_blend", 0.9f);
	return c;
}

String CgameRTEffect::shader_path(const String &p_pass_name) {
	return "res://shaders/compute/" + p_pass_name + ".glsl";
}

String CgameRTEffect::prepare_source(const String &p_pass_source, const String &p_common_source) {
	String src = p_pass_source.replace("#[compute]\n", "");
	return src.replace(CgameRTShaders::RT_COMMON_INCLUDE, p_common_source);
}

String CgameRTEffect::get_pass_source(const String &p_pass_name) {
	if (p_pass_name == "rt_shadows") {
		return CgameRTShaders::RT_SHADOWS_GLSL;
	}
	if (p_pass_name == "rt_ao") {
		return CgameRTShaders::RT_AO_GLSL;
	}
	if (p_pass_name == "rt_denoise") {
		return CgameRTShaders::RT_DENOISE_GLSL;
	}
	return String();
}

String CgameRTEffect::get_common_source() {
	return CgameRTShaders::RT_COMMON_GLSL;
}

// ---- Driver-side helpers -----------------------------------------------------------------------

Dictionary CgameRTEffect::extract_triangles(const Ref<Mesh> &p_mesh, int p_surface) {
	Dictionary out;
	out["ok"] = false;
	out["vertices"] = PackedVector3Array();
	out["indices"] = PackedInt32Array();
	if (p_mesh.is_null() || p_surface < 0 || p_surface >= p_mesh->get_surface_count()) {
		return out;
	}
	// Only ArrayMesh reports a primitive type; primitive meshes are always triangles.
	const ArrayMesh *array_mesh = Object::cast_to<ArrayMesh>(p_mesh.ptr());
	if (array_mesh != nullptr && array_mesh->surface_get_primitive_type(p_surface) != Mesh::PRIMITIVE_TRIANGLES) {
		return out;
	}
	const Array arrays = p_mesh->surface_get_arrays(p_surface);
	if (arrays.size() <= Mesh::ARRAY_VERTEX) {
		return out;
	}
	const PackedVector3Array verts = arrays[Mesh::ARRAY_VERTEX];
	if (verts.size() < 3) {
		return out;
	}
	PackedInt32Array indices;
	if (arrays.size() > Mesh::ARRAY_INDEX && arrays[Mesh::ARRAY_INDEX].get_type() == Variant::PACKED_INT32_ARRAY) {
		indices = arrays[Mesh::ARRAY_INDEX];
	}
	if (indices.is_empty()) {
		indices.resize(verts.size());
		for (int i = 0; i < verts.size(); i++) {
			indices.write[i] = i;
		}
	}
	if (indices.size() % 3 != 0 || indices.size() > MAX_TRIANGLES_PER_SURFACE * 3) {
		return out;
	}
	out["ok"] = true;
	out["vertices"] = verts;
	out["indices"] = indices;
	return out;
}

PackedByteArray CgameRTEffect::pack_positions(const PackedVector3Array &p_vertices) {
	PackedByteArray bytes;
	bytes.resize(p_vertices.size() * 12);
	float *dst = reinterpret_cast<float *>(bytes.ptrw());
	for (int i = 0; i < p_vertices.size(); i++) {
		dst[i * 3] = p_vertices[i].x;
		dst[i * 3 + 1] = p_vertices[i].y;
		dst[i * 3 + 2] = p_vertices[i].z;
	}
	return bytes;
}

PackedByteArray CgameRTEffect::pack_indices(const PackedInt32Array &p_indices) {
	PackedByteArray bytes;
	bytes.resize(p_indices.size() * 4);
	if (!p_indices.is_empty()) {
		memcpy(bytes.ptrw(), p_indices.ptr(), bytes.size());
	}
	return bytes;
}

int64_t CgameRTEffect::blas_key(const Ref<Mesh> &p_mesh, int p_surface) {
	return (int64_t)p_mesh->get_instance_id() * 64 + p_surface;
}

TypedArray<Dictionary> CgameRTEffect::select_nearest(const TypedArray<Dictionary> &p_candidates, const Vector3 &p_origin, float p_max_distance, int p_max_count) {
	struct Scored {
		float distance;
		int index;
	};
	Vector<Scored> scored;
	for (int i = 0; i < p_candidates.size(); i++) {
		const Dictionary c = p_candidates[i];
		const Vector3 pos = c["position"];
		const float radius = c["radius"];
		const float d = MAX(p_origin.distance_to(pos) - radius, 0.0f);
		if (d > p_max_distance) {
			continue;
		}
		scored.push_back({ d, i });
	}
	struct ScoredLess {
		bool operator()(const Scored &p_a, const Scored &p_b) const {
			if (p_a.distance == p_b.distance) {
				return p_a.index < p_b.index;
			}
			return p_a.distance < p_b.distance;
		}
	};
	scored.sort_custom<ScoredLess>();
	TypedArray<Dictionary> out;
	for (int i = 0; i < scored.size(); i++) {
		if (out.size() >= p_max_count) {
			break;
		}
		out.push_back(p_candidates[scored[i].index]);
	}
	return out;
}

// ---- Main-thread API ---------------------------------------------------------------------------

void CgameRTEffect::configure(const Dictionary &p_config) {
	MutexLock lock(mutex);
	config = config_from_dictionary(p_config);
}

void CgameRTEffect::submit(const Array &p_instances, const Dictionary &p_geometry, const Vector3 &p_sun_dir, float p_sun_radius) {
	LocalVector<Instance> list;
	for (int i = 0; i < p_instances.size(); i++) {
		const Dictionary d = p_instances[i];
		Instance inst;
		inst.key = d["key"];
		inst.transform = d["transform"];
		list.push_back(inst);
	}
	HashMap<int64_t, Geometry> geometry;
	for (const KeyValue<Variant, Variant> &kv : p_geometry) {
		const Dictionary g = kv.value;
		Geometry geo;
		const PackedByteArray vertices = g["vertices"];
		const PackedByteArray indices = g["indices"];
		geo.vertices.resize(vertices.size());
		if (!vertices.is_empty()) {
			memcpy(geo.vertices.ptrw(), vertices.ptr(), vertices.size());
		}
		geo.indices.resize(indices.size());
		if (!indices.is_empty()) {
			memcpy(geo.indices.ptrw(), indices.ptr(), indices.size());
		}
		geo.vertex_count = g["vertex_count"];
		geo.index_count = g["index_count"];
		geometry[(int64_t)kv.key] = geo;
	}
	MutexLock lock(mutex);
	pending_instances = list;
	for (const KeyValue<int64_t, Geometry> &kv : geometry) {
		pending_geometry[kv.key] = kv.value;
	}
	have_snapshot = true;
	sun_dir = p_sun_dir;
	sun_radius = p_sun_radius;
}

Array CgameRTEffect::take_evicted_keys() {
	MutexLock lock(mutex);
	Array out;
	for (const int64_t key : evicted) {
		out.push_back(key);
	}
	evicted.clear();
	return out;
}

// ---- Render thread -----------------------------------------------------------------------------

void CgameRTEffect::_native_render_callback(int p_callback_type, const RenderData *p_render_data) {
	if (failed || p_callback_type != (int)EFFECT_CALLBACK_TYPE_POST_OPAQUE || p_render_data == nullptr) {
		return;
	}
	if (rd == nullptr) {
		_setup();
		if (failed) {
			return;
		}
	}
	Ref<RenderSceneBuffers> base_buffers = p_render_data->get_render_scene_buffers();
	RenderSceneBuffersRD *buffers = Object::cast_to<RenderSceneBuffersRD>(base_buffers.ptr());
	RenderSceneData *scene_data = p_render_data->get_render_scene_data();
	if (buffers == nullptr || scene_data == nullptr) {
		return;
	}
	frame++;
	Config cfg;
	{
		MutexLock lock(mutex);
		cfg = config;
	}
	_ingest();
	_build_budgeted(cfg);
	if (instances_dirty) {
		_rebuild_tlas(cfg);
	}
	if (!tlas.is_valid() || tlas_instance_count == 0) {
		active = false;
		return;
	}
	_trace_and_composite(buffers, scene_data);
	active = true;
}

void CgameRTEffect::_setup() {
	rd = RenderingDevice::get_singleton();
	if (rd == nullptr || !rd->has_feature(RenderingDevice::SUPPORTS_RAY_QUERY)) {
		_fail("ray query not supported");
		return;
	}
	const String common = get_common_source();
	static const char *pass_names[3] = { "rt_shadows", "rt_ao", "rt_denoise" };
	for (int i = 0; i < 3; i++) {
		const String pass_name = pass_names[i];
		const String text = get_pass_source(pass_name);
		String error;
		const Vector<uint8_t> spirv = rd->shader_compile_spirv_from_source(RenderingDevice::SHADER_STAGE_COMPUTE, prepare_source(text, common), RenderingDevice::SHADER_LANGUAGE_GLSL, &error);
		if (spirv.is_empty() || !error.is_empty()) {
			_fail(vformat("%s compile error: %s", pass_name, error));
			return;
		}
		Vector<RenderingDevice::ShaderStageSPIRVData> stages;
		RenderingDevice::ShaderStageSPIRVData stage;
		stage.shader_stage = RenderingDevice::SHADER_STAGE_COMPUTE;
		stage.spirv = spirv;
		stages.push_back(stage);
		RID shader = rd->shader_create_from_spirv(stages, pass_name);
		if (!shader.is_valid()) {
			_fail(vformat("%s shader create failed", pass_name));
			return;
		}
		shaders[pass_name] = shader;
		pipelines[pass_name] = rd->compute_pipeline_create(shader);
	}
	RenderingDevice::SamplerState nearest_state;
	nearest_state.min_filter = RenderingDevice::SAMPLER_FILTER_NEAREST;
	nearest_state.mag_filter = RenderingDevice::SAMPLER_FILTER_NEAREST;
	nearest_sampler = rd->sampler_create(nearest_state);
	RenderingDevice::SamplerState linear_state;
	linear_state.min_filter = RenderingDevice::SAMPLER_FILTER_LINEAR;
	linear_state.mag_filter = RenderingDevice::SAMPLER_FILTER_LINEAR;
	linear_state.repeat_u = RenderingDevice::SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE;
	linear_state.repeat_v = RenderingDevice::SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE;
	linear_sampler = rd->sampler_create(linear_state);
	params_buffer = rd->uniform_buffer_create(PARAMS_SIZE);
	if (!params_buffer.is_valid()) {
		_fail("uniform buffer create failed");
	}
}

void CgameRTEffect::_fail(const String &p_reason) {
	failed = true;
	active = false;
	if (p_reason != "ray query not supported") {
		WARN_PRINT("CgameRTEffect: disabled (" + p_reason + ")");
	}
}

void CgameRTEffect::_ingest() {
	HashMap<int64_t, Geometry> geometry;
	{
		MutexLock lock(mutex);
		geometry = pending_geometry;
		pending_geometry.clear();
		if (have_snapshot) {
			instances = pending_instances;
			instances_dirty = true;
			have_snapshot = false;
		}
	}
	for (const KeyValue<int64_t, Geometry> &kv : geometry) {
		if (blas_entries.has(kv.key)) {
			continue;
		}
		_create_blas(kv.key, kv.value);
	}
}

void CgameRTEffect::_create_blas(int64_t p_key, const Geometry &p_geometry) {
	RID vbuf = rd->vertex_buffer_create(p_geometry.vertices.size(), p_geometry.vertices, RenderingDevice::BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT);
	RID ibuf = rd->index_buffer_create(p_geometry.index_count, RenderingDevice::INDEX_BUFFER_FORMAT_UINT32, p_geometry.indices, false, RenderingDevice::BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT);
	if (!vbuf.is_valid() || !ibuf.is_valid()) {
		if (vbuf.is_valid()) {
			rd->free_rid(vbuf);
		}
		if (ibuf.is_valid()) {
			rd->free_rid(ibuf);
		}
		return;
	}
	RenderingDevice::AccelerationStructureGeometry geo;
	geo.flags = RenderingDevice::ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT;
	geo.vertex_buffer = vbuf;
	geo.vertex_offset = 0;
	geo.vertex_stride = 12;
	geo.vertex_count = p_geometry.vertex_count;
	geo.vertex_format = RenderingDevice::DATA_FORMAT_R32G32B32_SFLOAT;
	geo.index_buffer = ibuf;
	geo.index_offset = 0;
	geo.index_count = p_geometry.index_count;
	Vector<RenderingDevice::AccelerationStructureGeometry> geometries;
	geometries.push_back(geo);
	RID blas = rd->blas_create(geometries, RenderingDevice::ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT);
	if (!blas.is_valid()) {
		rd->free_rid(ibuf);
		rd->free_rid(vbuf);
		return;
	}
	BlasEntry entry;
	entry.blas = blas;
	entry.vbuf = vbuf;
	entry.ibuf = ibuf;
	entry.built = false;
	entry.last_used = frame;
	blas_entries[p_key] = entry;
	build_queue.push_back(p_key);
}

void CgameRTEffect::_build_budgeted(const Config &p_config) {
	const int n = builds_this_frame(build_queue.size(), p_config.blas_builds_per_frame);
	for (int i = 0; i < n; i++) {
		const int64_t key = build_queue.front()->get();
		build_queue.pop_front();
		HashMap<int64_t, BlasEntry>::Iterator it = blas_entries.find(key);
		if (!it) {
			continue;
		}
		if (rd->blas_build(it->value.blas) == OK) {
			it->value.built = true;
			instances_dirty = true;
		}
	}
	// Eviction happens only over the cap and only for long-unused entries.
	HashMap<int64_t, int64_t> last_used;
	for (const KeyValue<int64_t, BlasEntry> &kv : blas_entries) {
		last_used[kv.key] = kv.value.last_used;
	}
	const Vector<int64_t> victims = eviction_candidates_native(last_used, frame, blas_entries.size(), MAX_BLAS);
	if (victims.is_empty()) {
		return;
	}
	for (const int64_t key : victims) {
		_free_blas(key);
	}
	{
		MutexLock lock(mutex);
		evicted.append_array(victims);
	}
	instances_dirty = true;
}

void CgameRTEffect::_free_blas(int64_t p_key) {
	HashMap<int64_t, BlasEntry>::Iterator it = blas_entries.find(p_key);
	if (!it) {
		return;
	}
	rd->free_rid(it->value.blas);
	rd->free_rid(it->value.ibuf);
	rd->free_rid(it->value.vbuf);
	blas_entries.remove(it);
	build_queue.erase(p_key);
}

void CgameRTEffect::_rebuild_tlas(const Config &p_config) {
	instances_dirty = false;
	Vector<RenderingDevice::AccelerationStructureInstance> list;
	const int cap = p_config.max_instances * 4; // Surfaces, not nodes.
	for (const Instance &inst : instances) {
		if (list.size() >= cap) {
			break;
		}
		HashMap<int64_t, BlasEntry>::Iterator it = blas_entries.find(inst.key);
		if (!it || !it->value.built) {
			continue;
		}
		it->value.last_used = frame;
		RenderingDevice::AccelerationStructureInstance ri;
		ri.transform = inst.transform;
		ri.id = list.size();
		ri.mask = 0xFF;
		ri.hit_sbt_range = 0;
		ri.flags.set_flag(RenderingDevice::ACCELERATION_STRUCTURE_INSTANCE_FORCE_OPAQUE_BIT);
		ri.flags.set_flag(RenderingDevice::ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT);
		ri.blas = it->value.blas;
		list.push_back(ri);
	}
	tlas_instance_count = list.size();
	if (list.is_empty()) {
		return;
	}
	if (!tlas.is_valid() || tlas_capacity < list.size()) {
		if (tlas.is_valid()) {
			rd->free_rid(tlas);
		}
		tlas_capacity = MAX(cap, (int)list.size());
		tlas = rd->tlas_create(tlas_capacity, RenderingDevice::ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT);
		if (!tlas.is_valid()) {
			_fail("tlas create failed");
			return;
		}
	}
	if (rd->tlas_build(tlas, list) != OK) {
		tlas_instance_count = 0;
	}
}

RID CgameRTEffect::_make_texture(RenderSceneBuffersRD *p_buffers, const StringName &p_name, int p_format, const Size2i &p_size) {
	const uint32_t usage = RenderingDevice::TEXTURE_USAGE_STORAGE_BIT | RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT;
	return p_buffers->create_texture(StringName("rt_effects"), p_name, (RenderingDevice::DataFormat)p_format, usage, RenderingDevice::TEXTURE_SAMPLES_1, p_size, 1, 1, false, false);
}

void CgameRTEffect::_dispatch(const String &p_pass, const LocalVector<RenderingDevice::Uniform> &p_uniforms, int p_groups_x, int p_groups_y) {
	RID shader = shaders[p_pass];
	RID set_rid = UniformSetCacheRD::get_singleton()->get_cache_vec(shader, 0, p_uniforms);
	RenderingDevice::ComputeListID list = rd->compute_list_begin();
	rd->compute_list_bind_compute_pipeline(list, pipelines[p_pass]);
	rd->compute_list_bind_uniform_set(list, set_rid, 0);
	rd->compute_list_dispatch(list, p_groups_x, p_groups_y, 1);
	rd->compute_list_end();
}

static RenderingDevice::Uniform _uniform(RenderingDevice::UniformType p_type, int p_binding, RID p_id) {
	return RenderingDevice::Uniform(p_type, p_binding, p_id);
}

static RenderingDevice::Uniform _uniform2(RenderingDevice::UniformType p_type, int p_binding, RID p_a, RID p_b) {
	Vector<RID> ids;
	ids.push_back(p_a);
	ids.push_back(p_b);
	return RenderingDevice::Uniform(p_type, p_binding, ids);
}

void CgameRTEffect::_trace_and_composite(RenderSceneBuffersRD *p_buffers, RenderSceneData *p_scene_data) {
	const Size2i size = p_buffers->get_internal_size();
	if (size.x <= 0 || size.y <= 0) {
		return;
	}
	if (!p_buffers->has_depth_texture()) {
		return;
	}
	const RID depth = p_buffers->get_depth_texture();
	const RID color = p_buffers->get_internal_texture(0);
	const RID raw_shadow = _make_texture(p_buffers, "raw_shadow", RenderingDevice::DATA_FORMAT_R16_SFLOAT, size);
	const RID raw_ao = _make_texture(p_buffers, "raw_ao", RenderingDevice::DATA_FORMAT_R16_SFLOAT, size);
	const RID hist_a = _make_texture(p_buffers, "hist_a", RenderingDevice::DATA_FORMAT_R16G16_SFLOAT, size);
	const RID hist_b = _make_texture(p_buffers, "hist_b", RenderingDevice::DATA_FORMAT_R16G16_SFLOAT, size);
	if (!(depth.is_valid() && color.is_valid() && raw_shadow.is_valid() && raw_ao.is_valid() && hist_a.is_valid() && hist_b.is_valid())) {
		return;
	}
	// Freshly (re)created textures hold garbage: seed them with "fully visible".
	Vector<RID> signature;
	signature.push_back(raw_shadow);
	signature.push_back(raw_ao);
	signature.push_back(hist_a);
	signature.push_back(hist_b);
	if (signature != texture_signature) {
		texture_signature = signature;
		for (const RID &t : signature) {
			rd->texture_clear(t, Color(1, 1, 1, 1), 0, 1, 0, 1);
		}
		have_prev = false;
	}

	const Projection cam_proj = p_scene_data->get_cam_projection();
	const Transform3D cam_xf = p_scene_data->get_cam_transform();
	Config cfg;
	Vector3 sun;
	float radius;
	{
		MutexLock lock(mutex);
		cfg = config;
		sun = sun_dir;
		radius = sun_radius;
	}
	const Projection view_proj = cam_proj * Projection(cam_xf.affine_inverse());
	const Projection prev = have_prev ? prev_view_proj : view_proj;
	const int ao_rays = cfg.ao_rays;
	const Vector<uint8_t> params = pack_params_native(cam_proj.inverse(), cam_xf, prev, sun, radius, size, have_prev ? (int)frame : 0, ao_rays, cfg);
	rd->buffer_update(params_buffer, 0, params.size(), params.ptr());

	const int gx = group_count(size.x);
	const int gy = group_count(size.y);
	const RenderingDevice::Uniform depth_u = _uniform2(RenderingDevice::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, nearest_sampler, depth);
	const RenderingDevice::Uniform params_u = _uniform(RenderingDevice::UNIFORM_TYPE_UNIFORM_BUFFER, 3, params_buffer);
	if (cfg.shadows) {
		LocalVector<RenderingDevice::Uniform> u;
		u.push_back(_uniform(RenderingDevice::UNIFORM_TYPE_ACCELERATION_STRUCTURE, 0, tlas));
		u.push_back(depth_u);
		u.push_back(_uniform(RenderingDevice::UNIFORM_TYPE_IMAGE, 2, raw_shadow));
		u.push_back(params_u);
		_dispatch("rt_shadows", u, gx, gy);
	}
	if (cfg.ao) {
		LocalVector<RenderingDevice::Uniform> u;
		u.push_back(_uniform(RenderingDevice::UNIFORM_TYPE_ACCELERATION_STRUCTURE, 0, tlas));
		u.push_back(depth_u);
		u.push_back(_uniform(RenderingDevice::UNIFORM_TYPE_IMAGE, 2, raw_ao));
		u.push_back(params_u);
		_dispatch("rt_ao", u, gx, gy);
	}

	const RID hist_in = hist_flip ? hist_a : hist_b;
	const RID hist_out = hist_flip ? hist_b : hist_a;
	LocalVector<RenderingDevice::Uniform> u;
	u.push_back(_uniform2(RenderingDevice::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, nearest_sampler, depth));
	u.push_back(_uniform(RenderingDevice::UNIFORM_TYPE_IMAGE, 1, raw_shadow));
	u.push_back(_uniform(RenderingDevice::UNIFORM_TYPE_IMAGE, 2, raw_ao));
	u.push_back(params_u);
	u.push_back(_uniform2(RenderingDevice::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, linear_sampler, hist_in));
	u.push_back(_uniform(RenderingDevice::UNIFORM_TYPE_IMAGE, 5, hist_out));
	u.push_back(_uniform(RenderingDevice::UNIFORM_TYPE_IMAGE, 6, color));
	_dispatch("rt_denoise", u, gx, gy);
	hist_flip = !hist_flip;
	prev_view_proj = view_proj;
	have_prev = true;
}

void CgameRTEffect::_free_on_render_thread(const Array &p_rids) {
	RenderingDevice *device = RenderingDevice::get_singleton();
	if (device == nullptr) {
		return;
	}
	for (int i = 0; i < p_rids.size(); i++) {
		const RID rid = p_rids[i];
		if (rid.is_valid()) {
			device->free_rid(rid);
		}
	}
}

// ---- Binding / lifecycle -----------------------------------------------------------------------

void CgameRTEffect::_bind_methods() {
	BIND_CONSTANT(PARAMS_SIZE);
	BIND_CONSTANT(MAX_BLAS);
	BIND_CONSTANT(EVICT_AGE);
	BIND_CONSTANT(MAX_TRIANGLES_PER_SURFACE);

	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("is_supported", "rd"), &CgameRTEffect::is_supported);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("settings", "level", "rendering_method"), &CgameRTEffect::settings, DEFVAL("forward_plus"));
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("group_count", "pixels", "group_size"), &CgameRTEffect::group_count, DEFVAL(8));
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("builds_this_frame", "queued", "budget"), &CgameRTEffect::builds_this_frame);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("budget_take", "pending", "per_frame"), &CgameRTEffect::budget_take);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("eviction_candidates", "last_used", "frame", "count", "limit"), &CgameRTEffect::eviction_candidates);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("pack_params", "inv_proj", "cam_to_world", "prev_view_proj", "sun_dir", "sun_radius", "size", "frame", "ao_rays", "config"), &CgameRTEffect::pack_params);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("shader_path", "pass_name"), &CgameRTEffect::shader_path);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("prepare_source", "pass_source", "common_source"), &CgameRTEffect::prepare_source);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("get_pass_source", "pass_name"), &CgameRTEffect::get_pass_source);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("get_common_source"), &CgameRTEffect::get_common_source);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("extract_triangles", "mesh", "surface"), &CgameRTEffect::extract_triangles);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("pack_positions", "vertices"), &CgameRTEffect::pack_positions);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("pack_indices", "indices"), &CgameRTEffect::pack_indices);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("blas_key", "mesh", "surface"), &CgameRTEffect::blas_key);
	ClassDB::bind_static_method("CgameRTEffect", D_METHOD("select_nearest", "candidates", "origin", "max_distance", "max_count"), &CgameRTEffect::select_nearest);

	ClassDB::bind_method(D_METHOD("configure", "config"), &CgameRTEffect::configure);
	ClassDB::bind_method(D_METHOD("submit", "instances", "geometry", "sun_dir", "sun_radius"), &CgameRTEffect::submit);
	ClassDB::bind_method(D_METHOD("take_evicted_keys"), &CgameRTEffect::take_evicted_keys);
	ClassDB::bind_method(D_METHOD("is_active"), &CgameRTEffect::is_active);
	ClassDB::bind_method(D_METHOD("has_failed"), &CgameRTEffect::has_failed);
}

CgameRTEffect::CgameRTEffect() {
	set_effect_callback_type(EFFECT_CALLBACK_TYPE_POST_OPAQUE);
	set_access_resolved_color(false);
	set_access_resolved_depth(false);
	set_needs_motion_vectors(false);
	set_needs_normal_roughness(false);
	// Route the render callback to the native implementation instead of the scripted virtual.
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs != nullptr && get_rid().is_valid()) {
		rs->compositor_effect_set_callback(get_rid(), RSE::COMPOSITOR_EFFECT_CALLBACK_TYPE_POST_OPAQUE, callable_mp(this, &CgameRTEffect::_native_render_callback));
	}
}

CgameRTEffect::~CgameRTEffect() {
	if (rd == nullptr) {
		return;
	}
	Array rids;
	rids.push_back(tlas);
	for (const KeyValue<int64_t, BlasEntry> &kv : blas_entries) {
		rids.push_back(kv.value.blas);
		rids.push_back(kv.value.ibuf);
		rids.push_back(kv.value.vbuf);
	}
	rids.push_back(params_buffer);
	rids.push_back(nearest_sampler);
	rids.push_back(linear_sampler);
	for (const KeyValue<String, RID> &kv : pipelines) {
		rids.push_back(kv.value);
	}
	for (const KeyValue<String, RID> &kv : shaders) {
		rids.push_back(kv.value);
	}
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs != nullptr) {
		rs->call_on_render_thread(callable_mp_static(&CgameRTEffect::_free_on_render_thread).bind(rids));
	}
}
