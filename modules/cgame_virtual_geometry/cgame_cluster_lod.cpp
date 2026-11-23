/**************************************************************************/
/*  cgame_cluster_lod.cpp                                                 */
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

#include "cgame_cluster_lod.h"

#include "cgame_meshlets.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"
#include "scene/resources/mesh.h"

#include <thirdparty/meshoptimizer/meshoptimizer.h>

namespace {

struct Sphere {
	Vector3 center;
	float radius = 0.0f;
};

struct Cluster {
	LocalVector<int> indices; // Global triangle list.
	LocalVector<int> vertex_ids;
	Vector3 center;
	float radius = 0.0f;
	Vector3 cone_axis;
	float cone_cutoff = 1.0f;
	int level = 0;
	float error = 0.0f;
	Sphere lod;
	float parent_error = Math::INF;
	Sphere parent;
	LocalVector<int> children;
};

// A triangle list re-indexed into a compact local vertex range.
struct LocalMesh {
	LocalVector<float> positions;
	LocalVector<uint32_t> indices;
	LocalVector<uint32_t> local_to_global;
};

void make_local_mesh(const LocalVector<float> &p_positions, const LocalVector<int> &p_global_indices, LocalMesh &r_mesh) {
	HashMap<int, uint32_t> g2l;
	r_mesh.positions.clear();
	r_mesh.indices.clear();
	r_mesh.local_to_global.clear();
	r_mesh.indices.reserve(p_global_indices.size());
	for (uint32_t i = 0; i < p_global_indices.size(); i++) {
		const int g = p_global_indices[i];
		HashMap<int, uint32_t>::Iterator it = g2l.find(g);
		uint32_t l;
		if (it) {
			l = it->value;
		} else {
			l = r_mesh.local_to_global.size();
			g2l.insert(g, l);
			r_mesh.local_to_global.push_back((uint32_t)g);
			r_mesh.positions.push_back(p_positions[g * 3]);
			r_mesh.positions.push_back(p_positions[g * 3 + 1]);
			r_mesh.positions.push_back(p_positions[g * 3 + 2]);
		}
		r_mesh.indices.push_back(l);
	}
}

// Splits a global triangle list into meshlets (re-indexed locally first so the cost does not depend on the whole mesh).
void build_clusters(const LocalVector<float> &p_positions, const LocalVector<int> &p_global_indices, int p_level, float p_error, const Sphere *p_lod, LocalVector<Cluster> &r_clusters, LocalVector<int> &r_new_ids) {
	LocalMesh mesh;
	make_local_mesh(p_positions, p_global_indices, mesh);
	LocalVector<CgameMeshlets::Meshlet> meshlets;
	if (!CgameMeshlets::build_native(mesh.positions.ptr(), mesh.local_to_global.size(), mesh.indices.ptr(), mesh.indices.size(), CgameMeshlets::DEFAULT_MAX_VERTICES, CgameMeshlets::DEFAULT_MAX_TRIANGLES, meshlets)) {
		return;
	}
	for (uint32_t m = 0; m < meshlets.size(); m++) {
		const CgameMeshlets::Meshlet &src = meshlets[m];
		Cluster c;
		c.vertex_ids.resize(src.vertex_ids.size());
		for (uint32_t v = 0; v < src.vertex_ids.size(); v++) {
			c.vertex_ids[v] = (int)mesh.local_to_global[src.vertex_ids[v]];
		}
		c.indices.resize(src.indices.size());
		for (uint32_t i = 0; i < src.indices.size(); i++) {
			c.indices[i] = c.vertex_ids[src.indices[i]];
		}
		c.center = src.bounds_center;
		c.radius = src.bounds_radius;
		c.cone_axis = src.cone_axis;
		c.cone_cutoff = src.cone_cutoff;
		c.level = p_level;
		c.error = p_error;
		if (p_lod) {
			c.lod = *p_lod;
		} else {
			c.lod.center = src.bounds_center;
			c.lod.radius = src.bounds_radius;
		}
		r_new_ids.push_back((int)r_clusters.size());
		r_clusters.push_back(c);
	}
}

Sphere merge_spheres(const Sphere &p_a, const Sphere &p_b) {
	const float d = p_a.center.distance_to(p_b.center);
	if (d + p_b.radius <= p_a.radius) {
		return p_a;
	}
	if (d + p_a.radius <= p_b.radius) {
		return p_b;
	}
	const float r = (d + p_a.radius + p_b.radius) * 0.5f;
	Sphere s;
	s.center = p_a.center + (p_b.center - p_a.center) * ((r - p_a.radius) / d);
	s.radius = r * 1.00001f;
	return s;
}

// Greedily groups up to GROUP_SIZE clusters that share the most vertices.
void group_clusters(const LocalVector<Cluster> &p_clusters, const LocalVector<int> &p_ids, LocalVector<LocalVector<int>> &r_groups) {
	HashMap<int, LocalVector<int>> vmap;
	for (uint32_t i = 0; i < p_ids.size(); i++) {
		const int id = p_ids[i];
		for (uint32_t v = 0; v < p_clusters[id].vertex_ids.size(); v++) {
			vmap[p_clusters[id].vertex_ids[v]].push_back(id);
		}
	}
	HashSet<int> assigned;
	for (uint32_t s = 0; s < p_ids.size(); s++) {
		const int seed = p_ids[s];
		if (assigned.has(seed)) {
			continue;
		}
		LocalVector<int> group;
		group.push_back(seed);
		assigned.insert(seed);
		HashMap<int, int> weights;
		int add_id = seed;
		while (true) {
			const Cluster &ac = p_clusters[add_id];
			for (uint32_t v = 0; v < ac.vertex_ids.size(); v++) {
				const LocalVector<int> &lst = vmap[ac.vertex_ids[v]];
				for (uint32_t k = 0; k < lst.size(); k++) {
					if (!assigned.has(lst[k])) {
						weights[lst[k]] += 1;
					}
				}
			}
			if ((int)group.size() >= CgameClusterLOD::GROUP_SIZE) {
				break;
			}
			int best = -1;
			int best_w = 0;
			for (const KeyValue<int, int> &kv : weights) {
				if (assigned.has(kv.key)) {
					continue;
				}
				if (kv.value > best_w || (kv.value == best_w && best >= 0 && kv.key < best)) {
					best = kv.key;
					best_w = kv.value;
				}
			}
			if (best < 0) {
				break;
			}
			assigned.insert(best);
			group.push_back(best);
			add_id = best;
		}
		r_groups.push_back(group);
	}
}

// Simplifies a global triangle list to p_target_tris with borders locked. Returns the global index list; r_error is absolute.
void simplify_group(const LocalVector<float> &p_positions, const LocalVector<int> &p_tris, int p_target_tris, LocalVector<int> &r_out, float &r_error) {
	LocalMesh mesh;
	make_local_mesh(p_positions, p_tris, mesh);
	LocalVector<uint32_t> dest;
	dest.resize(mesh.indices.size());
	float error = 0.0f;
	const size_t out_count = meshopt_simplify(dest.ptr(), mesh.indices.ptr(), mesh.indices.size(), mesh.positions.ptr(), mesh.local_to_global.size(), sizeof(float) * 3, (size_t)p_target_tris * 3, 1.0e30f, meshopt_SimplifyLockBorder | meshopt_SimplifyErrorAbsolute, &error);
	r_out.resize(out_count);
	for (size_t i = 0; i < out_count; i++) {
		r_out[i] = (int)mesh.local_to_global[dest[i]];
	}
	r_error = error;
}

Dictionary cluster_to_dictionary(const Cluster &p_c) {
	PackedInt32Array indices;
	indices.resize(p_c.indices.size());
	for (uint32_t i = 0; i < p_c.indices.size(); i++) {
		indices.write[i] = p_c.indices[i];
	}
	PackedInt32Array vertex_ids;
	vertex_ids.resize(p_c.vertex_ids.size());
	for (uint32_t i = 0; i < p_c.vertex_ids.size(); i++) {
		vertex_ids.write[i] = p_c.vertex_ids[i];
	}
	PackedInt32Array children;
	children.resize(p_c.children.size());
	for (uint32_t i = 0; i < p_c.children.size(); i++) {
		children.write[i] = p_c.children[i];
	}
	Dictionary d;
	d["indices"] = indices;
	d["vertex_ids"] = vertex_ids;
	d["center"] = p_c.center;
	d["radius"] = p_c.radius;
	d["cone_axis"] = p_c.cone_axis;
	d["cone_cutoff"] = p_c.cone_cutoff;
	d["level"] = p_c.level;
	d["error"] = p_c.error;
	d["lod_center"] = p_c.lod.center;
	d["lod_radius"] = p_c.lod.radius;
	d["parent_error"] = p_c.parent_error;
	d["parent_center"] = p_c.parent.center;
	d["parent_radius"] = p_c.parent.radius;
	d["children"] = children;
	return d;
}

double projected_error(double p_err, const Vector3 &p_center, double p_radius, const Vector3 &p_cam, double p_scale) {
	if (Math::is_inf(p_err)) {
		return Math::INF;
	}
	if (p_err <= 0.0) {
		return 0.0;
	}
	return p_err * p_scale / MAX(p_cam.distance_to(p_center) - p_radius, 1.0e-4);
}

} // namespace

Dictionary CgameClusterLOD::build_hierarchy(const PackedVector3Array &p_vertices, const PackedInt32Array &p_indices, int p_levels) {
	Dictionary result;
	const int vcount = p_vertices.size();
	const int icount = (p_indices.size() / 3) * 3;
	ERR_FAIL_COND_V_MSG(vcount == 0 || icount == 0, result, "CgameClusterLOD: empty mesh.");
	const int levels = CLAMP(p_levels, 1, MAX_LEVELS);

	LocalVector<float> positions;
	positions.resize((uint32_t)vcount * 3);
	const Vector3 *vr = p_vertices.ptr();
	for (int i = 0; i < vcount; i++) {
		positions[i * 3] = (float)vr[i].x;
		positions[i * 3 + 1] = (float)vr[i].y;
		positions[i * 3 + 2] = (float)vr[i].z;
	}
	LocalVector<int> base_indices;
	base_indices.resize(icount);
	const int32_t *ir = p_indices.ptr();
	for (int i = 0; i < icount; i++) {
		ERR_FAIL_INDEX_V_MSG(ir[i], vcount, result, "CgameClusterLOD: index out of range of the vertex array.");
		base_indices[i] = ir[i];
	}

	LocalVector<Cluster> clusters;
	LocalVector<int> cur;
	build_clusters(positions, base_indices, 0, 0.0f, nullptr, clusters, cur);
	int built = 1;

	for (int lvl = 1; lvl < levels; lvl++) {
		if (cur.size() <= 1) {
			break;
		}
		LocalVector<int> next;
		LocalVector<LocalVector<int>> groups;
		group_clusters(clusters, cur, groups);
		for (uint32_t gi = 0; gi < groups.size(); gi++) {
			const LocalVector<int> &group = groups[gi];
			LocalVector<int> tris;
			float child_err = 0.0f;
			Sphere sph;
			for (uint32_t k = 0; k < group.size(); k++) {
				const Cluster &c = clusters[group[k]];
				for (uint32_t i = 0; i < c.indices.size(); i++) {
					tris.push_back(c.indices[i]);
				}
				child_err = MAX(child_err, c.error);
				sph = k == 0 ? c.lod : merge_spheres(sph, c.lod);
			}
			LocalVector<int> sim_idx;
			float sim_err = 0.0f;
			simplify_group(positions, tris, (int)(tris.size() / 3 / 2), sim_idx, sim_err);
			// Nothing gained (locked borders): keep the children as roots instead of duplicating them.
			if (sim_idx.is_empty() || sim_idx.size() >= tris.size()) {
				continue;
			}
			if (!(sim_err > 0.0f)) {
				sim_err = 1.0e-6f; // Keep the parent error strictly larger so the cut rule stays well defined.
			}
			const float group_err = child_err + sim_err;
			for (uint32_t k = 0; k < group.size(); k++) {
				Cluster &c = clusters[group[k]];
				c.parent_error = group_err;
				c.parent = sph;
			}
			LocalVector<int> created;
			build_clusters(positions, sim_idx, lvl, group_err, &sph, clusters, created);
			for (uint32_t k = 0; k < created.size(); k++) {
				clusters[created[k]].children = group;
				next.push_back(created[k]);
			}
		}
		if (next.is_empty()) {
			break;
		}
		cur = next;
		built = lvl + 1;
	}

	Array cluster_array;
	PackedInt32Array roots;
	cluster_array.resize(clusters.size());
	for (uint32_t i = 0; i < clusters.size(); i++) {
		cluster_array[i] = cluster_to_dictionary(clusters[i]);
		if (Math::is_inf(clusters[i].parent_error)) {
			roots.push_back((int)i);
		}
	}
	result["vertices"] = p_vertices;
	result["clusters"] = cluster_array;
	result["levels"] = built;
	result["roots"] = roots;
	return result;
}

PackedInt32Array CgameClusterLOD::select_cut(const Dictionary &p_hierarchy, const Vector3 &p_camera_pos, real_t p_fov_y, real_t p_screen_height, real_t p_error_pixels) {
	PackedInt32Array cut;
	ERR_FAIL_COND_V(!p_hierarchy.has("clusters"), cut);
	const Array clusters = p_hierarchy["clusters"];
	const double scale = p_screen_height / (2.0 * Math::tan(p_fov_y * 0.5));
	for (int i = 0; i < clusters.size(); i++) {
		const Dictionary c = clusters[i];
		const double own = projected_error(c["error"], c["lod_center"], c["lod_radius"], p_camera_pos, scale);
		if (own > p_error_pixels) {
			continue;
		}
		const double par = projected_error(c["parent_error"], c["parent_center"], c["parent_radius"], p_camera_pos, scale);
		if (par > p_error_pixels) {
			cut.push_back(i);
		}
	}
	return cut;
}

int CgameClusterLOD::triangle_count(const Dictionary &p_hierarchy, const PackedInt32Array &p_cut) {
	ERR_FAIL_COND_V(!p_hierarchy.has("clusters"), 0);
	const Array clusters = p_hierarchy["clusters"];
	int total = 0;
	for (int i = 0; i < p_cut.size(); i++) {
		const int id = p_cut[i];
		ERR_CONTINUE_MSG(id < 0 || id >= clusters.size(), "CgameClusterLOD: cluster id out of range.");
		const Dictionary c = clusters[id];
		const PackedInt32Array indices = c["indices"];
		total += indices.size() / 3;
	}
	return total;
}

Array CgameClusterLOD::build_cut_surface(const Dictionary &p_hierarchy, const PackedInt32Array &p_cut, const Array &p_source_arrays) {
	Array invalid;
	ERR_FAIL_COND_V_MSG(p_source_arrays.size() != Mesh::ARRAY_MAX, invalid, "CgameClusterLOD: invalid source surface arrays.");
	ERR_FAIL_COND_V_MSG(!p_hierarchy.has("vertices") || !p_hierarchy.has("clusters"), invalid, "CgameClusterLOD: incomplete hierarchy.");
	ERR_FAIL_COND_V_MSG(p_hierarchy["vertices"].get_type() != Variant::PACKED_VECTOR3_ARRAY || p_hierarchy["clusters"].get_type() != Variant::ARRAY, invalid, "CgameClusterLOD: invalid hierarchy types.");
	ERR_FAIL_COND_V_MSG(p_source_arrays[Mesh::ARRAY_VERTEX].get_type() != Variant::PACKED_VECTOR3_ARRAY || p_source_arrays[Mesh::ARRAY_INDEX].get_type() != Variant::PACKED_INT32_ARRAY, invalid, "CgameClusterLOD: requires indexed triangle source.");
	const PackedVector3Array vertices = p_source_arrays[Mesh::ARRAY_VERTEX];
	ERR_FAIL_COND_V_MSG(vertices != (PackedVector3Array)p_hierarchy["vertices"], invalid, "CgameClusterLOD: source vertices differ from hierarchy.");
	const PackedInt32Array source_indices = p_source_arrays[Mesh::ARRAY_INDEX];
	ERR_FAIL_COND_V_MSG(source_indices.is_empty() || source_indices.size() % 3 != 0, invalid, "CgameClusterLOD: source must be indexed triangles.");
	const Array clusters = p_hierarchy["clusters"];
	HashSet<int> seen;
	int total = 0;
	for (int i = 0; i < p_cut.size(); i++) {
		const int id = p_cut[i];
		ERR_FAIL_COND_V_MSG(id < 0 || id >= clusters.size() || seen.has(id), invalid, "CgameClusterLOD: duplicate or invalid cluster id.");
		seen.insert(id);
		ERR_FAIL_COND_V_MSG(clusters[id].get_type() != Variant::DICTIONARY, invalid, "CgameClusterLOD: invalid cluster.");
		const Dictionary cluster = clusters[id];
		ERR_FAIL_COND_V_MSG(!cluster.has("indices") || cluster["indices"].get_type() != Variant::PACKED_INT32_ARRAY, invalid, "CgameClusterLOD: missing triangle indices.");
		const PackedInt32Array indices = cluster["indices"];
		ERR_FAIL_COND_V_MSG(indices.is_empty() || indices.size() % 3 != 0 || indices.size() > source_indices.size() - total, invalid, "CgameClusterLOD: invalid selected triangle count.");
		for (int j = 0; j < indices.size(); j++) {
			ERR_FAIL_COND_V_MSG(indices[j] < 0 || indices[j] >= vertices.size(), invalid, "CgameClusterLOD: cluster index outside source.");
		}
		total += indices.size();
	}
	ERR_FAIL_COND_V_MSG(total == 0, invalid, "CgameClusterLOD: empty selected cut.");
	PackedInt32Array new_indices;
	new_indices.resize(total);
	int32_t *dst = new_indices.ptrw();
	int next = 0;
	for (int i = 0; i < p_cut.size(); i++) {
		const Dictionary cluster = clusters[p_cut[i]];
		const PackedInt32Array indices = cluster["indices"];
		for (int j = 0; j < indices.size(); j++) {
			dst[next++] = indices[j];
		}
	}
	// Reusing original vertex ids preserves UV seams, tangent handedness,
	// custom shader attributes and skinning buffers without interpolation.
	Array output = p_source_arrays.duplicate(false);
	output[Mesh::ARRAY_INDEX] = new_indices;
	return output;
}

void CgameClusterLOD::_bind_methods() {
	ClassDB::bind_static_method("CgameClusterLOD", D_METHOD("build_hierarchy", "vertices", "indices", "levels"), &CgameClusterLOD::build_hierarchy, DEFVAL(4));
	ClassDB::bind_static_method("CgameClusterLOD", D_METHOD("select_cut", "hierarchy", "camera_pos", "fov_y", "screen_height", "error_pixels"), &CgameClusterLOD::select_cut, DEFVAL(1.0));
	ClassDB::bind_static_method("CgameClusterLOD", D_METHOD("triangle_count", "hierarchy", "cut"), &CgameClusterLOD::triangle_count);
	ClassDB::bind_static_method("CgameClusterLOD", D_METHOD("build_cut_surface", "hierarchy", "cut", "source_arrays"), &CgameClusterLOD::build_cut_surface);
}
