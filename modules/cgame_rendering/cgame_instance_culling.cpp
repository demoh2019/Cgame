/**************************************************************************/
/*  cgame_instance_culling.cpp                                            */
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

#include "cgame_instance_culling.h"

#include "core/io/marshalls.h"
#include "core/object/class_db.h"

#include "core/math/aabb.h"
#include "servers/rendering/rendering_server.h"

// GPU per-instance frustum + Hi-Z-lite occlusion culling with visible-index compaction. Mirrors the
// CPU path in this file exactly. The plane/AABB test is the standard "p-vertex" test; Hi-Z follows
// the classic max-depth pyramid idea. Original implementation; no third-party code.
static const char *INSTANCE_CULL_GLSL = R"GLSL(#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct Instance {
	vec4 center;
	vec4 half_ext;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer Instances {
	Instance items[];
} instances;

layout(set = 0, binding = 1, std430) restrict readonly buffer Planes {
	vec4 p[];
} planes;

layout(set = 0, binding = 2, std430) restrict buffer Visible {
	uint count;
	uint group_y;
	uint group_z;
	uint pad;
	uint indices[];
} visible;

layout(set = 0, binding = 3, std430) restrict readonly buffer HiZ {
	mat4 view_proj;
	vec4 dims; // x = width, y = height, z = depth bias
	float depth[];
} hiz;

layout(push_constant, std430) uniform Params {
	uint instance_count;
	uint plane_count;
	uint use_hiz;
	uint pad;
} params;

bool occluded(vec3 c, vec3 h) {
	int wt = int(hiz.dims.x);
	int ht = int(hiz.dims.y);
	vec2 mn = vec2(1.0e9);
	vec2 mx = vec2(-1.0e9);
	float zmin = 1.0e9;
	for (uint k = 0u; k < 8u; k++) {
		vec3 corner = c + h * vec3(((k & 1u) != 0u) ? 1.0 : -1.0, ((k & 2u) != 0u) ? 1.0 : -1.0, ((k & 4u) != 0u) ? 1.0 : -1.0);
		vec4 clip = hiz.view_proj * vec4(corner, 1.0);
		if (clip.w <= 0.00001) {
			return false; // crosses the near plane: stay conservative
		}
		vec3 ndc = clip.xyz / clip.w;
		vec2 uv = ndc.xy * 0.5 + 0.5;
		mn = min(mn, uv);
		mx = max(mx, uv);
		zmin = min(zmin, ndc.z * 0.5 + 0.5);
	}
	if (mx.x < 0.0 || mx.y < 0.0 || mn.x > 1.0 || mn.y > 1.0) {
		return false; // off screen: frustum planes decide
	}
	int x0 = clamp(int(floor(mn.x * float(wt))), 0, wt - 1);
	int y0 = clamp(int(floor(mn.y * float(ht))), 0, ht - 1);
	int x1 = clamp(int(floor(mx.x * float(wt))), 0, wt - 1);
	int y1 = clamp(int(floor(mx.y * float(ht))), 0, ht - 1);
	float far_depth = 0.0;
	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			far_depth = max(far_depth, hiz.depth[y * wt + x]);
		}
	}
	return zmin > far_depth + hiz.dims.z;
}

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= params.instance_count) {
		return;
	}
	vec3 c = instances.items[i].center.xyz;
	vec3 h = instances.items[i].half_ext.xyz;
	for (uint k = 0u; k < params.plane_count; k++) {
		vec4 pl = planes.p[k];
		float d = dot(pl.xyz, c) - pl.w - dot(abs(pl.xyz), h);
		if (d > 0.0) {
			return;
		}
	}
	if (params.use_hiz != 0u && occluded(c, h)) {
		return;
	}
	uint slot = atomicAdd(visible.count, 1u);
	visible.indices[slot] = i;
}
)GLSL";

String CgameInstanceCulling::get_compute_source() {
	return String("#[compute]\n") + INSTANCE_CULL_GLSL;
}

// ---- Pure CPU implementation ------------------------------------------------------------------

bool CgameInstanceCulling::outside_frustum(const Vector3 &p_center, const Vector3 &p_half, const Vector<Plane> &p_planes) {
	for (int i = 0; i < p_planes.size(); i++) {
		const Plane &pl = p_planes[i];
		const Vector3 &n = pl.normal;
		const float d = n.dot(p_center) - pl.d - (Math::abs(n.x) * p_half.x + Math::abs(n.y) * p_half.y + Math::abs(n.z) * p_half.z);
		if (d > 0.0f) {
			return true;
		}
	}
	return false;
}

bool CgameInstanceCulling::occluded(const Vector3 &p_center, const Vector3 &p_half, const HiZ &p_hiz) {
	const int wt = p_hiz.width;
	const int ht = p_hiz.height;
	if (wt <= 0 || ht <= 0 || int64_t(wt) * ht > p_hiz.depth.size() ||
			int64_t(wt) * ht > INT32_MAX || !Math::is_finite(p_hiz.bias)) {
		return false;
	}
	Vector2 mn(1.0e9f, 1.0e9f);
	Vector2 mx(-1.0e9f, -1.0e9f);
	float zmin = 1.0e9f;
	for (int k = 0; k < 8; k++) {
		const Vector3 corner = p_center + p_half * Vector3((k & 1) != 0 ? 1.0f : -1.0f, (k & 2) != 0 ? 1.0f : -1.0f, (k & 4) != 0 ? 1.0f : -1.0f);
		const Vector4 clip = p_hiz.view_proj.xform(Vector4(corner.x, corner.y, corner.z, 1.0f));
		if (clip.w <= 0.00001f) {
			return false;
		}
		const Vector3 ndc = Vector3(clip.x, clip.y, clip.z) / clip.w;
		const Vector2 uv = Vector2(ndc.x, ndc.y) * 0.5f + Vector2(0.5f, 0.5f);
		mn = Vector2(MIN(mn.x, uv.x), MIN(mn.y, uv.y));
		mx = Vector2(MAX(mx.x, uv.x), MAX(mx.y, uv.y));
		zmin = MIN(zmin, ndc.z * 0.5f + 0.5f);
	}
	if (mx.x < 0.0f || mx.y < 0.0f || mn.x > 1.0f || mn.y > 1.0f) {
		return false;
	}
	const int x0 = CLAMP((int)Math::floor(mn.x * (float)wt), 0, wt - 1);
	const int y0 = CLAMP((int)Math::floor(mn.y * (float)ht), 0, ht - 1);
	const int x1 = CLAMP((int)Math::floor(mx.x * (float)wt), 0, wt - 1);
	const int y1 = CLAMP((int)Math::floor(mx.y * (float)ht), 0, ht - 1);
	float far_depth = 0.0f;
	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			far_depth = MAX(far_depth, p_hiz.depth[y * wt + x]);
		}
	}
	return zmin > far_depth + p_hiz.bias;
}

Vector<int32_t> CgameInstanceCulling::cull_cpu_native(const Vector<Vector3> &p_centers, const Vector<Vector3> &p_halves, const Vector<Plane> &p_planes, const HiZ &p_hiz) {
	Vector<int32_t> out;
	const int n = MIN(p_centers.size(), p_halves.size());
	for (int i = 0; i < n; i++) {
		if (outside_frustum(p_centers[i], p_halves[i], p_planes)) {
			continue;
		}
		if (p_hiz.enabled && occluded(p_centers[i], p_halves[i], p_hiz)) {
			continue;
		}
		out.push_back(i);
	}
	return out;
}

Vector<int32_t> CgameInstanceCulling::cull_brute_force(const Vector<Vector3> &p_centers, const Vector<Vector3> &p_halves, const Vector<Plane> &p_planes) {
	Vector<int32_t> out;
	const int n = MIN(p_centers.size(), p_halves.size());
	for (int i = 0; i < n; i++) {
		bool culled = false;
		for (int p = 0; p < p_planes.size() && !culled; p++) {
			// Outside a plane when all eight corners lie on its outer side.
			bool all_outside = true;
			for (int k = 0; k < 8 && all_outside; k++) {
				const Vector3 corner = p_centers[i] + p_halves[i] * Vector3((k & 1) != 0 ? 1.0f : -1.0f, (k & 2) != 0 ? 1.0f : -1.0f, (k & 4) != 0 ? 1.0f : -1.0f);
				if (p_planes[p].normal.dot(corner) - p_planes[p].d <= 0.0f) {
					all_outside = false;
				}
			}
			culled = all_outside;
		}
		if (!culled) {
			out.push_back(i);
		}
	}
	return out;
}

// ---- Variant adapters --------------------------------------------------------------------------

CgameInstanceCulling::HiZ CgameInstanceCulling::_parse_hiz(const Dictionary &p_hiz) {
	HiZ hiz;
	if (p_hiz.is_empty()) {
		return hiz;
	}
	// Invalid depth metadata must disable occlusion on BOTH paths. The
	// shader otherwise indexes an undersized storage buffer; the CPU must
	// also avoid overflowing signed width * height arithmetic.
	const int64_t width = p_hiz.get("width", 0);
	const int64_t height = p_hiz.get("height", 0);
	const PackedFloat32Array depth = p_hiz.get("depth", PackedFloat32Array());
	const float bias = p_hiz.get("bias", 0.0f);
	if (width <= 0 || height <= 0 || width > 16777216 || height > 16777216 ||
			width * height > INT32_MAX || width * height > depth.size() ||
			!Math::is_finite(bias)) {
		return hiz;
	}
	hiz.enabled = true;
	hiz.view_proj = p_hiz.get("view_proj", Projection());
	hiz.width = int(width);
	hiz.height = int(height);
	hiz.depth.resize(depth.size());
	for (int i = 0; i < depth.size(); i++) {
		hiz.depth.write[i] = depth[i];
	}
	hiz.bias = bias;
	return hiz;
}

Vector<Plane> CgameInstanceCulling::_parse_planes(const Array &p_planes) {
	Vector<Plane> planes;
	planes.resize(p_planes.size());
	for (int i = 0; i < p_planes.size(); i++) {
		planes.write[i] = p_planes[i];
	}
	return planes;
}

static Vector<Vector3> _to_vector(const PackedVector3Array &p_array) {
	Vector<Vector3> out;
	out.resize(p_array.size());
	for (int i = 0; i < p_array.size(); i++) {
		out.write[i] = p_array[i];
	}
	return out;
}

static PackedInt32Array _to_packed(const Vector<int32_t> &p_values) {
	PackedInt32Array out;
	out.resize(p_values.size());
	for (int i = 0; i < p_values.size(); i++) {
		out.write[i] = p_values[i];
	}
	return out;
}

PackedInt32Array CgameInstanceCulling::cull(const Array &p_aabbs, const Array &p_frustum_planes, const Dictionary &p_hiz) {
	PackedVector3Array centers;
	PackedVector3Array halves;
	centers.resize(p_aabbs.size());
	halves.resize(p_aabbs.size());
	for (int i = 0; i < p_aabbs.size(); i++) {
		const AABB box = p_aabbs[i];
		centers.write[i] = box.get_center();
		halves.write[i] = box.size * 0.5f;
	}
	return cull_packed(centers, halves, p_frustum_planes, p_hiz);
}

PackedInt32Array CgameInstanceCulling::cull_spheres(const PackedVector3Array &p_centers, const PackedFloat32Array &p_radii, const Array &p_frustum_planes, const Dictionary &p_hiz) {
	PackedVector3Array halves;
	halves.resize(p_centers.size());
	for (int i = 0; i < p_centers.size(); i++) {
		const float r = i < p_radii.size() ? p_radii[i] : 0.0f;
		halves.write[i] = Vector3(r, r, r);
	}
	return cull_packed(p_centers, halves, p_frustum_planes, p_hiz);
}

PackedInt32Array CgameInstanceCulling::cull_packed(const PackedVector3Array &p_centers, const PackedVector3Array &p_halves, const Array &p_frustum_planes, const Dictionary &p_hiz) {
	_try_device();
	const Vector<Vector3> centers = _to_vector(p_centers);
	const Vector<Vector3> halves = _to_vector(p_halves);
	const Vector<Plane> planes = _parse_planes(p_frustum_planes);
	const HiZ hiz = _parse_hiz(p_hiz);
	if (rd != nullptr && !force_cpu && MIN(centers.size(), halves.size()) > 0) {
		const Vector<int32_t> result = _cull_gpu(centers, halves, planes, hiz);
		if (!result.is_empty() || last_gpu_ok) {
			last_path = "gpu";
			return _to_packed(result);
		}
	}
	last_path = "cpu";
	return _to_packed(cull_cpu_native(centers, halves, planes, hiz));
}

PackedInt32Array CgameInstanceCulling::cull_cpu(const PackedVector3Array &p_centers, const PackedVector3Array &p_halves, const Array &p_frustum_planes, const Dictionary &p_hiz) {
	return _to_packed(cull_cpu_native(_to_vector(p_centers), _to_vector(p_halves), _parse_planes(p_frustum_planes), _parse_hiz(p_hiz)));
}

// ---- Device path (UNVERIFIED on hardware) -------------------------------------------------------

bool CgameInstanceCulling::device_available() {
	_try_device();
	return rd != nullptr;
}

void CgameInstanceCulling::_try_device() {
	if (tried_device || force_cpu) {
		return;
	}
	tried_device = true;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs != nullptr) {
		rd = rs->create_local_rendering_device();
	}
}

bool CgameInstanceCulling::_ensure_pipeline() {
	if (pipeline.is_valid()) {
		return true;
	}
	String source = get_compute_source();
	source = source.trim_prefix("#[compute]\n");
	String error;
	const Vector<uint8_t> spirv = rd->shader_compile_spirv_from_source(RenderingDevice::SHADER_STAGE_COMPUTE, source, RenderingDevice::SHADER_LANGUAGE_GLSL, &error);
	if (spirv.is_empty() || !error.is_empty()) {
		return false;
	}
	Vector<RenderingDevice::ShaderStageSPIRVData> stages;
	RenderingDevice::ShaderStageSPIRVData stage;
	stage.shader_stage = RenderingDevice::SHADER_STAGE_COMPUTE;
	stage.spirv = spirv;
	stages.push_back(stage);
	shader = rd->shader_create_from_spirv(stages);
	if (!shader.is_valid()) {
		return false;
	}
	pipeline = rd->compute_pipeline_create(shader);
	return pipeline.is_valid();
}

static Vector<uint8_t> _floats_to_bytes(const Vector<float> &p_floats) {
	Vector<uint8_t> bytes;
	bytes.resize(p_floats.size() * (int)sizeof(float));
	if (!p_floats.is_empty()) {
		memcpy(bytes.ptrw(), p_floats.ptr(), bytes.size());
	}
	return bytes;
}

Vector<int32_t> CgameInstanceCulling::_cull_gpu(const Vector<Vector3> &p_centers, const Vector<Vector3> &p_halves, const Vector<Plane> &p_planes, const HiZ &p_hiz) {
	last_gpu_ok = false;
	if (!_ensure_pipeline()) {
		return Vector<int32_t>();
	}
	const int n = MIN(p_centers.size(), p_halves.size());
	Vector<float> inst;
	inst.resize(n * 8);
	inst.fill(0.0f);
	for (int i = 0; i < n; i++) {
		inst.write[i * 8] = p_centers[i].x;
		inst.write[i * 8 + 1] = p_centers[i].y;
		inst.write[i * 8 + 2] = p_centers[i].z;
		inst.write[i * 8 + 4] = p_halves[i].x;
		inst.write[i * 8 + 5] = p_halves[i].y;
		inst.write[i * 8 + 6] = p_halves[i].z;
	}
	Vector<float> pl;
	pl.resize(MAX(p_planes.size(), 1) * 4);
	pl.fill(0.0f);
	for (int k = 0; k < p_planes.size(); k++) {
		pl.write[k * 4] = p_planes[k].normal.x;
		pl.write[k * 4 + 1] = p_planes[k].normal.y;
		pl.write[k * 4 + 2] = p_planes[k].normal.z;
		pl.write[k * 4 + 3] = p_planes[k].d;
	}
	Vector<float> hz;
	if (p_hiz.enabled) {
		for (int col = 0; col < 4; col++) {
			const Vector4 column = p_hiz.view_proj.columns[col];
			hz.push_back(column.x);
			hz.push_back(column.y);
			hz.push_back(column.z);
			hz.push_back(column.w);
		}
		hz.push_back((float)p_hiz.width);
		hz.push_back((float)p_hiz.height);
		hz.push_back(p_hiz.bias);
		hz.push_back(0.0f);
		hz.append_array(p_hiz.depth);
	} else {
		hz.resize(24);
		hz.fill(0.0f);
	}
	const int out_bytes = HEADER_BYTES + n * 4;
	Vector<uint8_t> zero;
	zero.resize(out_bytes);
	zero.fill(0);
	encode_uint32(1, zero.ptrw() + 4);
	encode_uint32(1, zero.ptrw() + 8);

	const Vector<uint8_t> inst_bytes = _floats_to_bytes(inst);
	const Vector<uint8_t> plane_bytes = _floats_to_bytes(pl);
	const Vector<uint8_t> hiz_bytes = _floats_to_bytes(hz);
	RID b_inst = rd->storage_buffer_create(inst_bytes.size(), inst_bytes);
	RID b_planes = rd->storage_buffer_create(plane_bytes.size(), plane_bytes);
	RID b_out = rd->storage_buffer_create(out_bytes, zero);
	RID b_hiz = rd->storage_buffer_create(hiz_bytes.size(), hiz_bytes);

	Vector<RenderingDevice::Uniform> uniforms;
	uniforms.push_back(RenderingDevice::Uniform(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER, 0, b_inst));
	uniforms.push_back(RenderingDevice::Uniform(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER, 1, b_planes));
	uniforms.push_back(RenderingDevice::Uniform(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER, 2, b_out));
	uniforms.push_back(RenderingDevice::Uniform(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER, 3, b_hiz));
	RID uset = rd->uniform_set_create(uniforms, shader, 0);

	struct PushConstants {
		uint32_t instance_count;
		uint32_t plane_count;
		uint32_t use_hiz;
		uint32_t pad;
	} push = { (uint32_t)n, (uint32_t)p_planes.size(), p_hiz.enabled ? 1u : 0u, 0u };

	RenderingDevice::ComputeListID list = rd->compute_list_begin();
	rd->compute_list_bind_compute_pipeline(list, pipeline);
	rd->compute_list_bind_uniform_set(list, uset, 0);
	rd->compute_list_set_push_constant(list, &push, sizeof(push));
	rd->compute_list_dispatch(list, (n + LOCAL_SIZE - 1) / LOCAL_SIZE, 1, 1);
	rd->compute_list_end();
	rd->submit();
	rd->sync();
	const Vector<uint8_t> data = rd->buffer_get_data(b_out);

	Vector<int32_t> result;
	if (data.size() >= HEADER_BYTES) {
		const int visible_count = MIN((int)decode_uint32(data.ptr()), n);
		const int available = (data.size() - HEADER_BYTES) / 4;
		const int count = MIN(visible_count, available);
		result.resize(count);
		for (int i = 0; i < count; i++) {
			result.write[i] = (int32_t)decode_uint32(data.ptr() + HEADER_BYTES + i * 4);
		}
		result.sort();
	}
	rd->free_rid(uset);
	rd->free_rid(b_inst);
	rd->free_rid(b_planes);
	rd->free_rid(b_out);
	rd->free_rid(b_hiz);
	last_gpu_ok = true;
	return result;
}

void CgameInstanceCulling::shutdown() {
	if (rd != nullptr) {
		if (pipeline.is_valid()) {
			rd->free_rid(pipeline);
		}
		if (shader.is_valid()) {
			rd->free_rid(shader);
		}
		memdelete(rd);
	}
	rd = nullptr;
	pipeline = RID();
	shader = RID();
	tried_device = false;
}

void CgameInstanceCulling::_bind_methods() {
	BIND_CONSTANT(LOCAL_SIZE);
	BIND_CONSTANT(HEADER_BYTES);
	ClassDB::bind_static_method("CgameInstanceCulling", D_METHOD("get_compute_source"), &CgameInstanceCulling::get_compute_source);

	ClassDB::bind_method(D_METHOD("set_force_cpu", "force"), &CgameInstanceCulling::set_force_cpu);
	ClassDB::bind_method(D_METHOD("get_force_cpu"), &CgameInstanceCulling::get_force_cpu);
	ClassDB::bind_method(D_METHOD("get_last_path"), &CgameInstanceCulling::get_last_path);
	ClassDB::bind_method(D_METHOD("generate_compute_source"), &CgameInstanceCulling::generate_compute_source);
	ClassDB::bind_method(D_METHOD("device_available"), &CgameInstanceCulling::device_available);
	ClassDB::bind_method(D_METHOD("cull", "aabbs", "frustum_planes", "hiz"), &CgameInstanceCulling::cull, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("cull_spheres", "centers", "radii", "frustum_planes", "hiz"), &CgameInstanceCulling::cull_spheres, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("cull_packed", "centers", "halves", "frustum_planes", "hiz"), &CgameInstanceCulling::cull_packed, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("cull_cpu", "centers", "halves", "frustum_planes", "hiz"), &CgameInstanceCulling::cull_cpu, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("shutdown"), &CgameInstanceCulling::shutdown);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "force_cpu"), "set_force_cpu", "get_force_cpu");
}

CgameInstanceCulling::CgameInstanceCulling() {
}

CgameInstanceCulling::~CgameInstanceCulling() {
	shutdown();
}
