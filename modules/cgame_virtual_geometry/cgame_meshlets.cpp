/**************************************************************************/
/*  cgame_meshlets.cpp                                                    */
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

#include "cgame_meshlets.h"

#include "core/math/plane.h"
#include "core/object/class_db.h"

#include <thirdparty/meshoptimizer/meshoptimizer.h>

bool CgameMeshlets::build_native(const float *p_positions, uint32_t p_vertex_count, const uint32_t *p_indices, size_t p_index_count, int p_max_vertices, int p_max_triangles, LocalVector<Meshlet> &r_meshlets) {
	r_meshlets.clear();
	const size_t tri_count = p_index_count / 3;
	if (tri_count == 0 || p_vertex_count == 0) {
		return true;
	}
	const size_t index_count = tri_count * 3;
	for (size_t i = 0; i < index_count; i++) {
		ERR_FAIL_COND_V_MSG(p_indices[i] >= p_vertex_count, false, "CgameMeshlets: index out of range of the vertex array.");
	}
	const size_t max_v = CLAMP(p_max_vertices, 3, LIMIT_MAX_VERTICES);
	const size_t max_t = CLAMP(p_max_triangles, 1, LIMIT_MAX_TRIANGLES);

	const size_t bound = meshopt_buildMeshletsBound(index_count, max_v, max_t);
	LocalVector<meshopt_Meshlet> meshlets;
	meshlets.resize(bound);
	LocalVector<unsigned int> meshlet_vertices;
	meshlet_vertices.resize(index_count);
	LocalVector<unsigned char> meshlet_triangles;
	meshlet_triangles.resize(index_count);

	const size_t count = meshopt_buildMeshlets(meshlets.ptr(), meshlet_vertices.ptr(), meshlet_triangles.ptr(), p_indices, index_count, p_positions, p_vertex_count, sizeof(float) * 3, max_v, max_t, 0.5f);

	r_meshlets.resize(count);
	for (size_t m = 0; m < count; m++) {
		const meshopt_Meshlet &src = meshlets[m];
		Meshlet &dst = r_meshlets[m];
		dst.vertex_ids.resize(src.vertex_count);
		for (unsigned int v = 0; v < src.vertex_count; v++) {
			dst.vertex_ids[v] = (int)meshlet_vertices[src.vertex_offset + v];
		}
		dst.indices.resize((size_t)src.triangle_count * 3);
		for (unsigned int i = 0; i < src.triangle_count * 3; i++) {
			dst.indices[i] = meshlet_triangles[src.triangle_offset + i];
		}
		const meshopt_Bounds b = meshopt_computeMeshletBounds(&meshlet_vertices[src.vertex_offset], &meshlet_triangles[src.triangle_offset], src.triangle_count, p_positions, p_vertex_count, sizeof(float) * 3);
		dst.bounds_center = Vector3(b.center[0], b.center[1], b.center[2]);
		dst.bounds_radius = b.radius;
		// meshoptimizer assumes counter-clockwise front faces; Godot uses clockwise, so its axis is the inward normal.
		dst.cone_axis = Vector3(-b.cone_axis[0], -b.cone_axis[1], -b.cone_axis[2]);
		dst.cone_cutoff = b.cone_cutoff;
		if (dst.cone_axis.length_squared() < 1.0e-12f) {
			dst.cone_axis = Vector3();
			dst.cone_cutoff = 1.0f;
		}
	}
	return true;
}

Dictionary CgameMeshlets::meshlet_to_dictionary(const Meshlet &p_meshlet) {
	PackedInt32Array indices;
	indices.resize(p_meshlet.indices.size());
	int32_t *iw = indices.ptrw();
	for (uint32_t i = 0; i < p_meshlet.indices.size(); i++) {
		iw[i] = p_meshlet.indices[i];
	}
	PackedInt32Array vertex_ids;
	vertex_ids.resize(p_meshlet.vertex_ids.size());
	int32_t *vw = vertex_ids.ptrw();
	for (uint32_t i = 0; i < p_meshlet.vertex_ids.size(); i++) {
		vw[i] = p_meshlet.vertex_ids[i];
	}
	Dictionary d;
	d["indices"] = indices;
	d["vertex_ids"] = vertex_ids;
	d["bounds_center"] = p_meshlet.bounds_center;
	d["bounds_radius"] = p_meshlet.bounds_radius;
	d["cone_axis"] = p_meshlet.cone_axis;
	d["cone_cutoff"] = p_meshlet.cone_cutoff;
	return d;
}

Array CgameMeshlets::build_meshlets(const PackedVector3Array &p_vertices, const PackedInt32Array &p_indices, int p_max_vertices, int p_max_triangles) {
	Array result;
	const int vcount = p_vertices.size();
	const int icount = p_indices.size();
	if (vcount == 0 || icount < 3) {
		return result;
	}
	LocalVector<float> positions;
	positions.resize((uint32_t)vcount * 3);
	const Vector3 *vr = p_vertices.ptr();
	for (int i = 0; i < vcount; i++) {
		positions[i * 3] = (float)vr[i].x;
		positions[i * 3 + 1] = (float)vr[i].y;
		positions[i * 3 + 2] = (float)vr[i].z;
	}
	const int32_t *ir = p_indices.ptr();
	for (int i = 0; i < icount; i++) {
		ERR_FAIL_COND_V_MSG(ir[i] < 0, result, "CgameMeshlets: negative index.");
	}
	LocalVector<Meshlet> meshlets;
	if (!build_native(positions.ptr(), (uint32_t)vcount, (const uint32_t *)ir, (size_t)icount, p_max_vertices, p_max_triangles, meshlets)) {
		return result;
	}
	result.resize(meshlets.size());
	for (uint32_t i = 0; i < meshlets.size(); i++) {
		result[i] = meshlet_to_dictionary(meshlets[i]);
	}
	return result;
}

bool CgameMeshlets::cone_cull(const Dictionary &p_meshlet, const Vector3 &p_camera_pos) {
	ERR_FAIL_COND_V(!p_meshlet.has("cone_axis") || !p_meshlet.has("cone_cutoff") || !p_meshlet.has("bounds_center") || !p_meshlet.has("bounds_radius"), false);
	const Vector3 axis = p_meshlet["cone_axis"];
	const real_t cutoff = p_meshlet["cone_cutoff"];
	const Vector3 center = p_meshlet["bounds_center"];
	const real_t radius = p_meshlet["bounds_radius"];
	const Vector3 to_center = center - p_camera_pos;
	return to_center.dot(axis) >= cutoff * to_center.length() + radius;
}

bool CgameMeshlets::frustum_cull(const Dictionary &p_meshlet, const TypedArray<Plane> &p_planes) {
	ERR_FAIL_COND_V(!p_meshlet.has("bounds_center") || !p_meshlet.has("bounds_radius"), false);
	const Vector3 center = p_meshlet["bounds_center"];
	const real_t radius = p_meshlet["bounds_radius"];
	for (int i = 0; i < p_planes.size(); i++) {
		const Plane plane = p_planes[i];
		if (plane.distance_to(center) > radius) {
			return true;
		}
	}
	return false;
}

void CgameMeshlets::_bind_methods() {
	ClassDB::bind_static_method("CgameMeshlets", D_METHOD("build_meshlets", "vertices", "indices", "max_vertices", "max_triangles"), &CgameMeshlets::build_meshlets, DEFVAL(DEFAULT_MAX_VERTICES), DEFVAL(DEFAULT_MAX_TRIANGLES));
	ClassDB::bind_static_method("CgameMeshlets", D_METHOD("cone_cull", "meshlet", "camera_pos"), &CgameMeshlets::cone_cull);
	ClassDB::bind_static_method("CgameMeshlets", D_METHOD("frustum_cull", "meshlet", "planes"), &CgameMeshlets::frustum_cull);
}
