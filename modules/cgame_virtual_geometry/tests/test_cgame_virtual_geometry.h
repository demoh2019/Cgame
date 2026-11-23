/**************************************************************************/
/*  test_cgame_virtual_geometry.h                                         */
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

#pragma once

#include "../cgame_cluster_lod.h"
#include "../cgame_meshlets.h"
#include "../cgame_occlusion_raster.h"

#include "core/math/math_funcs.h"
#include "core/math/plane.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "scene/resources/mesh.h"
#include "tests/test_macros.h"

#include <algorithm>
#include <cstdint>

namespace TestCgameVirtualGeometry {

struct Mesh {
	PackedVector3Array vertices;
	PackedInt32Array indices;
};

// Appends a triangle with clockwise-front (Godot) winding that faces away from the origin.
static void add_tri(Mesh &m, int a, int b, int c) {
	const Vector3 va = m.vertices[a];
	const Vector3 vb = m.vertices[b];
	const Vector3 vc = m.vertices[c];
	const Vector3 n = (vc - va).cross(vb - va);
	const Vector3 cen = (va + vb + vc) / 3.0;
	if (n.dot(cen) < 0.0) {
		std::swap(b, c);
	}
	m.indices.push_back(a);
	m.indices.push_back(b);
	m.indices.push_back(c);
}

// UV sphere with single-vertex poles, welded.
static Mesh make_sphere(int p_rings, int p_segs, real_t p_radius) {
	Mesh m;
	m.vertices.push_back(Vector3(0, p_radius, 0));
	for (int r = 1; r < p_rings; r++) {
		const real_t th = Math::PI * real_t(r) / real_t(p_rings);
		for (int s = 0; s < p_segs; s++) {
			const real_t ph = Math::TAU * real_t(s) / real_t(p_segs);
			m.vertices.push_back(Vector3(Math::sin(th) * Math::cos(ph), Math::cos(th), Math::sin(th) * Math::sin(ph)) * p_radius);
		}
	}
	m.vertices.push_back(Vector3(0, -p_radius, 0));
	const int bottom = m.vertices.size() - 1;
	for (int s = 0; s < p_segs; s++) {
		add_tri(m, 0, 1 + s, 1 + (s + 1) % p_segs);
	}
	for (int r = 0; r < p_rings - 2; r++) {
		for (int s = 0; s < p_segs; s++) {
			const int s2 = (s + 1) % p_segs;
			const int a = 1 + r * p_segs + s;
			const int b = 1 + r * p_segs + s2;
			const int c = 1 + (r + 1) * p_segs + s;
			const int d = 1 + (r + 1) * p_segs + s2;
			add_tri(m, a, b, c);
			add_tri(m, b, d, c);
		}
	}
	const int last = 1 + (p_rings - 2) * p_segs;
	for (int s = 0; s < p_segs; s++) {
		add_tri(m, last + s, last + (s + 1) % p_segs, bottom);
	}
	return m;
}

static double surface_area(const PackedVector3Array &p_verts, const PackedInt32Array &p_idx) {
	double total = 0.0;
	for (int f = 0; f < p_idx.size() / 3; f++) {
		const Vector3 a = p_verts[p_idx[f * 3]];
		total += 0.5 * (p_verts[p_idx[f * 3 + 1]] - a).cross(p_verts[p_idx[f * 3 + 2]] - a).length();
	}
	return total;
}

static uint64_t edge_key(int a, int b) {
	const uint64_t lo = (uint64_t)MIN(a, b);
	const uint64_t hi = (uint64_t)MAX(a, b);
	return (lo << 32) | hi;
}

// Returns the number of edges used once (open) and more than twice (over).
static void edge_stats(const PackedInt32Array &p_idx, int &r_open, int &r_over) {
	HashMap<uint64_t, int> counts;
	for (int f = 0; f < p_idx.size() / 3; f++) {
		for (int e = 0; e < 3; e++) {
			counts[edge_key(p_idx[f * 3 + e], p_idx[f * 3 + (e + 1) % 3])] += 1;
		}
	}
	r_open = 0;
	r_over = 0;
	for (const KeyValue<uint64_t, int> &kv : counts) {
		if (kv.value == 1) {
			r_open++;
		} else if (kv.value > 2) {
			r_over++;
		}
	}
}

static PackedInt32Array cut_indices(const Dictionary &p_h, const PackedInt32Array &p_cut) {
	const Array clusters = p_h["clusters"];
	PackedInt32Array out;
	for (int i = 0; i < p_cut.size(); i++) {
		const Dictionary c = clusters[p_cut[i]];
		const PackedInt32Array ci = c["indices"];
		out.append_array(ci);
	}
	return out;
}

static constexpr real_t FOV = 1.0471976; // 60 degrees.
static constexpr real_t SCREEN_H = 1080.0;

TEST_CASE("[CgameMeshlets] Limits, coverage and bounds") {
	const Mesh mesh = make_sphere(36, 48, 1.0);
	const int tri_total = mesh.indices.size() / 3;
	CHECK(tri_total > 3000);

	const Array ml = CgameMeshlets::build_meshlets(mesh.vertices, mesh.indices);
	CHECK(ml.size() >= tri_total / 124);

	HashMap<String, int> seen;
	bool limits_ok = true;
	bool bounds_ok = true;
	int covered = 0;
	for (int i = 0; i < ml.size(); i++) {
		const Dictionary m = ml[i];
		const PackedInt32Array li = m["indices"];
		const PackedInt32Array vids = m["vertex_ids"];
		const int mtris = li.size() / 3;
		if (vids.size() > 64 || mtris > 124) {
			limits_ok = false;
		}
		const Vector3 ctr = m["bounds_center"];
		const real_t rad = m["bounds_radius"];
		for (int v = 0; v < vids.size(); v++) {
			if (mesh.vertices[vids[v]].distance_to(ctr) > rad + 0.0001) {
				bounds_ok = false;
			}
		}
		for (int f = 0; f < mtris; f++) {
			int tri[3] = { vids[li[f * 3]], vids[li[f * 3 + 1]], vids[li[f * 3 + 2]] };
			std::sort(tri, tri + 3);
			seen[vformat("%d_%d_%d", tri[0], tri[1], tri[2])] += 1;
			covered++;
		}
	}
	CHECK_MESSAGE(limits_ok, "meshlets respect 64 vertices / 124 triangles");
	CHECK_MESSAGE(bounds_ok, "bounding spheres contain all meshlet vertices");
	CHECK(covered == tri_total);
	bool once = (int)seen.size() == tri_total;
	for (const KeyValue<String, int> &kv : seen) {
		if (kv.value != 1) {
			once = false;
		}
	}
	CHECK_MESSAGE(once, "each triangle appears in exactly one meshlet");

	const Array small = CgameMeshlets::build_meshlets(mesh.vertices, mesh.indices, 12, 8);
	bool small_ok = !small.is_empty();
	for (int i = 0; i < small.size(); i++) {
		const Dictionary sm = small[i];
		const PackedInt32Array sv = sm["vertex_ids"];
		const PackedInt32Array si = sm["indices"];
		if (sv.size() > 12 || si.size() > 24) {
			small_ok = false;
		}
	}
	CHECK_MESSAGE(small_ok, "custom small limits respected");
}

TEST_CASE("[CgameMeshlets] Empty and invalid input") {
	CHECK(CgameMeshlets::build_meshlets(PackedVector3Array(), PackedInt32Array()).is_empty());
	PackedVector3Array v;
	v.push_back(Vector3());
	v.push_back(Vector3(1, 0, 0));
	v.push_back(Vector3(0, 1, 0));
	CHECK(CgameMeshlets::build_meshlets(v, PackedInt32Array()).is_empty());
	PackedInt32Array bad;
	bad.push_back(0);
	bad.push_back(1);
	bad.push_back(7);
	ERR_PRINT_OFF;
	CHECK(CgameMeshlets::build_meshlets(v, bad).is_empty());
	ERR_PRINT_ON;
	PackedInt32Array good;
	good.push_back(0);
	good.push_back(1);
	good.push_back(2);
	CHECK(CgameMeshlets::build_meshlets(v, good).size() == 1);
}

TEST_CASE("[CgameMeshlets] Cone and frustum culling") {
	const Mesh mesh = make_sphere(36, 48, 1.0);
	const Array ml = CgameMeshlets::build_meshlets(mesh.vertices, mesh.indices);

	const Vector3 cam(0, 0, 5);
	int culled = 0;
	bool cull_valid = true;
	int near_idx = 0;
	real_t near_d = Math::INF;
	for (int i = 0; i < ml.size(); i++) {
		const Dictionary m = ml[i];
		const Vector3 ctr = m["bounds_center"];
		if (ctr.distance_to(cam) < near_d) {
			near_d = ctr.distance_to(cam);
			near_idx = i;
		}
		if (CgameMeshlets::cone_cull(m, cam)) {
			culled++;
			const PackedInt32Array li = m["indices"];
			const PackedInt32Array vids = m["vertex_ids"];
			for (int f = 0; f < li.size() / 3; f++) {
				const Vector3 a = mesh.vertices[vids[li[f * 3]]];
				const Vector3 n = (mesh.vertices[vids[li[f * 3 + 2]]] - a).cross(mesh.vertices[vids[li[f * 3 + 1]]] - a);
				if (n.dot(a - cam) < -0.0001) {
					cull_valid = false;
				}
			}
		}
	}
	CHECK_MESSAGE(culled > ml.size() / 4, "back side meshlets are cone-culled");
	CHECK(culled < ml.size());
	CHECK_MESSAGE(cull_valid, "cone-culled meshlets contain no front-facing triangles");
	CHECK(!CgameMeshlets::cone_cull(ml[near_idx], cam));

	int inside_culled = 0;
	for (int i = 0; i < ml.size(); i++) {
		if (CgameMeshlets::cone_cull(ml[i], Vector3())) {
			inside_culled++;
		}
	}
	CHECK_MESSAGE(inside_culled > 0, "camera inside sees only back faces");

	TypedArray<Plane> box_in;
	box_in.push_back(Plane(Vector3(1, 0, 0), 10.0));
	box_in.push_back(Plane(Vector3(-1, 0, 0), 10.0));
	box_in.push_back(Plane(Vector3(0, 1, 0), 10.0));
	box_in.push_back(Plane(Vector3(0, -1, 0), 10.0));
	box_in.push_back(Plane(Vector3(0, 0, 1), 10.0));
	box_in.push_back(Plane(Vector3(0, 0, -1), 10.0));
	TypedArray<Plane> box_out;
	box_out.push_back(Plane(Vector3(1, 0, 0), 120.0));
	box_out.push_back(Plane(Vector3(-1, 0, 0), -100.0));
	TypedArray<Plane> half;
	half.push_back(Plane(Vector3(1, 0, 0), 0.0));
	int in_culled = 0;
	int out_culled = 0;
	int half_culled = 0;
	for (int i = 0; i < ml.size(); i++) {
		const Dictionary m = ml[i];
		in_culled += CgameMeshlets::frustum_cull(m, box_in) ? 1 : 0;
		out_culled += CgameMeshlets::frustum_cull(m, box_out) ? 1 : 0;
		half_culled += CgameMeshlets::frustum_cull(m, half) ? 1 : 0;
	}
	CHECK(in_culled == 0);
	CHECK(out_culled == ml.size());
	CHECK(half_culled > 0);
	CHECK(half_culled < ml.size());
}

TEST_CASE("[CgameClusterLOD] Hierarchy invariants") {
	const Mesh mesh = make_sphere(36, 48, 1.0);
	const int tri_total = mesh.indices.size() / 3;
	const Dictionary h = CgameClusterLOD::build_hierarchy(mesh.vertices, mesh.indices, 4);
	const Array clusters = h["clusters"];
	CHECK_MESSAGE((int)h["levels"] >= 3, "hierarchy has several levels");

	HashMap<int, int> level_tris;
	bool mono_ok = true;
	bool sphere_ok = true;
	bool limits_ok = true;
	for (int i = 0; i < clusters.size(); i++) {
		const Dictionary c = clusters[i];
		const PackedInt32Array ci = c["indices"];
		const int lv = c["level"];
		const int ctris = ci.size() / 3;
		level_tris[lv] += ctris;
		const PackedInt32Array vids = c["vertex_ids"];
		if (ctris > 124 || vids.size() > 64) {
			limits_ok = false;
		}
		const real_t e = c["error"];
		const real_t pe = c["parent_error"];
		if (pe < e) {
			mono_ok = false;
		}
		if (!Math::is_inf(pe)) {
			const real_t d = ((Vector3)c["lod_center"]).distance_to((Vector3)c["parent_center"]);
			if (d + (real_t)c["lod_radius"] > (real_t)c["parent_radius"] + 0.0001) {
				sphere_ok = false;
			}
		}
		const PackedInt32Array kids = c["children"];
		for (int k = 0; k < kids.size(); k++) {
			const Dictionary kc = clusters[kids[k]];
			if ((real_t)kc["error"] > e || (real_t)kc["parent_error"] != e) {
				mono_ok = false;
			}
		}
	}
	CHECK_MESSAGE(mono_ok, "parent error >= child error everywhere");
	CHECK_MESSAGE(sphere_ok, "parent LOD sphere contains child LOD sphere");
	CHECK_MESSAGE(limits_ok, "re-split clusters respect meshlet limits");
	CHECK(level_tris[0] == tri_total);
	CHECK_MESSAGE(level_tris[1] < level_tris[0] * 0.7, "level 1 is much coarser than level 0");
	CHECK_MESSAGE(level_tris[2] < level_tris[1], "level 2 is coarser than level 1");
	CHECK(((PackedInt32Array)h["roots"]).size() > 0);
}

TEST_CASE("[CgameClusterLOD] Cut selection is watertight and shrinks with distance") {
	const Mesh mesh = make_sphere(36, 48, 1.0);
	const int tri_total = mesh.indices.size() / 3;
	const double area0 = surface_area(mesh.vertices, mesh.indices);
	const Dictionary h = CgameClusterLOD::build_hierarchy(mesh.vertices, mesh.indices, 4);

	const PackedInt32Array exact = CgameClusterLOD::select_cut(h, Vector3(0, 0, 1.5), FOV, SCREEN_H, 0.0001);
	CHECK(CgameClusterLOD::triangle_count(h, exact) == tri_total);
	CHECK(surface_area(mesh.vertices, cut_indices(h, exact)) == doctest::Approx(area0).epsilon(0.001));

	const int far_tris = CgameClusterLOD::triangle_count(h, CgameClusterLOD::select_cut(h, Vector3(0, 0, 400), FOV, SCREEN_H, 1.0));
	const int near_tris = CgameClusterLOD::triangle_count(h, CgameClusterLOD::select_cut(h, Vector3(0, 0, 3), FOV, SCREEN_H, 1.0));
	CHECK_MESSAGE((far_tris > 0 && far_tris * 3 < near_tris), "far camera selects far fewer triangles");

	int prev = 1 << 30;
	bool shrinking = true;
	bool cracks_ok = true;
	bool area_ok = true;
	bool unique_ok = true;
	const real_t distances[] = { 2.0, 6.0, 20.0, 60.0, 200.0, 800.0 };
	for (real_t dist : distances) {
		const PackedInt32Array cut = CgameClusterLOD::select_cut(h, Vector3(0, 0, dist), FOV, SCREEN_H, 1.0);
		const int n_tris = CgameClusterLOD::triangle_count(h, cut);
		if (n_tris > prev) {
			shrinking = false;
		}
		prev = n_tris;
		const PackedInt32Array ci = cut_indices(h, cut);
		int open = 0;
		int over = 0;
		edge_stats(ci, open, over);
		if (open != 0 || over != 0) {
			cracks_ok = false;
		}
		const double ratio = surface_area(mesh.vertices, ci) / area0;
		if (ratio > 1.001 || ratio < 0.85) {
			area_ok = false;
		}
		HashSet<int> ids;
		for (int i = 0; i < cut.size(); i++) {
			ids.insert(cut[i]);
		}
		if ((int)ids.size() != cut.size()) {
			unique_ok = false;
		}
	}
	CHECK_MESSAGE(shrinking, "triangle count never grows with distance");
	CHECK_MESSAGE(cracks_ok, "cuts are watertight");
	CHECK_MESSAGE(area_ok, "cut surface area stays close to the original");
	CHECK_MESSAGE(unique_ok, "cut has no duplicate clusters");
}

TEST_CASE("[CgameClusterLOD] Determinism and edge cases") {
	const Mesh mesh = make_sphere(36, 48, 1.0);
	const Dictionary h1 = CgameClusterLOD::build_hierarchy(mesh.vertices, mesh.indices, 4);
	const Dictionary h2 = CgameClusterLOD::build_hierarchy(mesh.vertices, mesh.indices, 4);
	const Array c1 = h1["clusters"];
	const Array c2 = h2["clusters"];
	REQUIRE(c1.size() == c2.size());
	bool same = true;
	for (int i = 0; i < c1.size(); i++) {
		const Dictionary a = c1[i];
		const Dictionary b = c2[i];
		if ((PackedInt32Array)a["indices"] != (PackedInt32Array)b["indices"] || (real_t)a["error"] != (real_t)b["error"]) {
			same = false;
		}
	}
	CHECK_MESSAGE(same, "rebuild gives identical clusters and errors");
	CHECK(CgameClusterLOD::select_cut(h1, Vector3(0, 0, 3), FOV, SCREEN_H, 1.0) == CgameClusterLOD::select_cut(h2, Vector3(0, 0, 3), FOV, SCREEN_H, 1.0));

	ERR_PRINT_OFF;
	CHECK(CgameClusterLOD::build_hierarchy(PackedVector3Array(), PackedInt32Array()).is_empty());
	ERR_PRINT_ON;

	// A single level is just the meshlets with infinite parent error.
	const Dictionary flat = CgameClusterLOD::build_hierarchy(mesh.vertices, mesh.indices, 1);
	CHECK((int)flat["levels"] == 1);
	const PackedInt32Array cut = CgameClusterLOD::select_cut(flat, Vector3(0, 0, 1000), FOV, SCREEN_H, 1.0);
	CHECK(CgameClusterLOD::triangle_count(flat, cut) == mesh.indices.size() / 3);
}


TEST_CASE("[CgameClusterLOD] Reconstructed cut keeps PBR vertex channels and validates source") {
	const Mesh source = make_sphere(10, 20, 3.0);
	const Dictionary hierarchy = CgameClusterLOD::build_hierarchy(source.vertices, source.indices, 5);
	REQUIRE(!hierarchy.is_empty());
	const PackedInt32Array cut = hierarchy["roots"];
	REQUIRE(cut.size() > 0);
	const int vertex_count = source.vertices.size();
	PackedVector3Array normals;
	PackedVector2Array uv, uv2;
	PackedColorArray colors;
	PackedFloat32Array tangents;
	normals.resize(vertex_count);
	uv.resize(vertex_count);
	uv2.resize(vertex_count);
	colors.resize(vertex_count);
	tangents.resize(vertex_count * 4);
	for (int i = 0; i < vertex_count; i++) {
		normals.set(i, source.vertices[i].normalized());
		uv.set(i, Vector2((i % 20) / 20.0, (i / 20) / 10.0));
		uv2.set(i, Vector2((i % 13) / 13.0, (i % 17) / 17.0));
		colors.set(i, Color(0.15, 0.35, 0.65, 1.0));
		tangents.set(i * 4, 1.0);
		tangents.set(i * 4 + 1, 0.0);
		tangents.set(i * 4 + 2, 0.0);
		tangents.set(i * 4 + 3, -1.0);
	}
	Array arrays;
	arrays.resize(::Mesh::ARRAY_MAX);
	arrays[::Mesh::ARRAY_VERTEX] = source.vertices;
	arrays[::Mesh::ARRAY_INDEX] = source.indices;
	arrays[::Mesh::ARRAY_NORMAL] = normals;
	arrays[::Mesh::ARRAY_TEX_UV] = uv;
	arrays[::Mesh::ARRAY_TEX_UV2] = uv2;
	arrays[::Mesh::ARRAY_COLOR] = colors;
	arrays[::Mesh::ARRAY_TANGENT] = tangents;
	const Array surface = CgameClusterLOD::build_cut_surface(hierarchy, cut, arrays);
	REQUIRE(surface.size() == ::Mesh::ARRAY_MAX);
	CHECK((PackedVector3Array)surface[::Mesh::ARRAY_VERTEX] == source.vertices);
	CHECK((PackedVector3Array)surface[::Mesh::ARRAY_NORMAL] == normals);
	CHECK((PackedVector2Array)surface[::Mesh::ARRAY_TEX_UV] == uv);
	CHECK((PackedVector2Array)surface[::Mesh::ARRAY_TEX_UV2] == uv2);
	CHECK((PackedColorArray)surface[::Mesh::ARRAY_COLOR] == colors);
	CHECK((PackedFloat32Array)surface[::Mesh::ARRAY_TANGENT] == tangents);
	const PackedInt32Array selected = surface[::Mesh::ARRAY_INDEX];
	CHECK(selected.size() == CgameClusterLOD::triangle_count(hierarchy, cut) * 3);
	CHECK(selected.size() <= source.indices.size());
	CHECK((PackedInt32Array)arrays[::Mesh::ARRAY_INDEX] == source.indices);
	for (int i = 0; i < selected.size(); i++) {
		CHECK(selected[i] >= 0);
		CHECK(selected[i] < vertex_count);
	}
	// Create an actual RenderingServer-backed surface, not merely a dictionary.
	Ref<ArrayMesh> draw_mesh;
	draw_mesh.instantiate();
	draw_mesh->add_surface_from_arrays(::Mesh::PRIMITIVE_TRIANGLES, surface);
	CHECK(draw_mesh->get_surface_count() == 1);
	CHECK(draw_mesh->surface_get_array_index_len(0) == selected.size());

	Array extended = arrays.duplicate(false);
	PackedByteArray custom_data;
	custom_data.push_back(9);
	custom_data.push_back(17);
	extended[::Mesh::ARRAY_CUSTOM0] = custom_data;
	const Array custom = CgameClusterLOD::build_cut_surface(hierarchy, cut, extended);
	CHECK((PackedByteArray)custom[::Mesh::ARRAY_CUSTOM0] == custom_data);

	ERR_PRINT_OFF;
	PackedInt32Array duplicate = cut;
	duplicate.push_back(cut[0]);
	CHECK(CgameClusterLOD::build_cut_surface(hierarchy, duplicate, arrays).is_empty());
	PackedInt32Array out_of_range;
	out_of_range.push_back(-1);
	CHECK(CgameClusterLOD::build_cut_surface(hierarchy, out_of_range, arrays).is_empty());
	out_of_range.set(0, ((Array)hierarchy["clusters"]).size());
	CHECK(CgameClusterLOD::build_cut_surface(hierarchy, out_of_range, arrays).is_empty());
	Array mismatched = arrays.duplicate(false);
	mismatched[::Mesh::ARRAY_VERTEX] = PackedVector3Array();
	CHECK(CgameClusterLOD::build_cut_surface(hierarchy, cut, mismatched).is_empty());
	CHECK(CgameClusterLOD::build_cut_surface(hierarchy, PackedInt32Array(), arrays).is_empty());
	ERR_PRINT_ON;
}

static Ref<CgameOcclusionRaster> make_wall_raster() {
	// Camera at the origin looking down -Z; wall 20x10 at z -11..-10.5.
	Projection proj = Projection::create_perspective(70.0, 2.0, 0.1, 200.0);
	Ref<CgameOcclusionRaster> r;
	r.instantiate();
	r->begin(proj, 256, 128);
	const AABB wall(Vector3(-10, -5, -11), Vector3(20, 10, 0.5));
	PackedVector3Array tris;
	const Vector3 p = wall.position;
	const Vector3 s = wall.size;
	auto corner = [&](int i) { return p + Vector3((i & 1) ? s.x : 0, (i & 2) ? s.y : 0, (i & 4) ? s.z : 0); };
	// Six faces, two triangles each (double sided rasterization, so winding is irrelevant).
	const int quads[6][4] = { { 0, 1, 3, 2 }, { 4, 5, 7, 6 }, { 0, 1, 5, 4 }, { 2, 3, 7, 6 }, { 0, 2, 6, 4 }, { 1, 3, 7, 5 } };
	for (const auto &q : quads) {
		tris.push_back(corner(q[0]));
		tris.push_back(corner(q[1]));
		tris.push_back(corner(q[2]));
		tris.push_back(corner(q[0]));
		tris.push_back(corner(q[2]));
		tris.push_back(corner(q[3]));
	}
	r->rasterize_occluder(tris);
	return r;
}

TEST_CASE("[CgameOcclusionRaster] Wall culls the box behind it") {
	Ref<CgameOcclusionRaster> r = make_wall_raster();
	CHECK(r->get_occluder_triangles() == 12);
	CHECK(r->get_pixels_written() > 1000);
	CHECK(!r->is_visible(AABB(Vector3(-1, -1, -20), Vector3(2, 2, 2))));
	CHECK(r->is_visible(AABB(Vector3(22, -1, -21), Vector3(2, 2, 2))));
	CHECK(r->is_visible(AABB(Vector3(-1, -1, -6), Vector3(2, 2, 2))));
	CHECK(r->is_visible(AABB(Vector3(12, -1, -21), Vector3(10, 2, 2))));
	CHECK(r->is_visible(AABB(Vector3(-1, -1, 5), Vector3(2, 2, 2))));
	CHECK(r->is_visible(AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))));
	CHECK(r->get_tested() == 6);
	CHECK(r->get_culled() == 1);
}

TEST_CASE("[CgameOcclusionRaster] Hi-Z pyramid is a max reduction") {
	Ref<CgameOcclusionRaster> r = make_wall_raster();
	r->build_hiz();
	bool ok = r->hiz_level_count() > 4;
	for (int lv = 1; lv < r->hiz_level_count(); lv++) {
		const Vector2i sz = r->hiz_size(lv);
		const Vector2i prev = r->hiz_size(lv - 1);
		for (int y = 0; y < sz.y; y++) {
			for (int x = 0; x < sz.x; x++) {
				const float v = r->hiz_get(lv, x, y);
				for (int dy = 0; dy < 2; dy++) {
					for (int dx = 0; dx < 2; dx++) {
						const int cx = MIN(x * 2 + dx, prev.x - 1);
						const int cy = MIN(y * 2 + dy, prev.y - 1);
						if (v < r->hiz_get(lv - 1, cx, cy)) {
							ok = false;
						}
					}
				}
			}
		}
	}
	CHECK_MESSAGE(ok, "every Hi-Z texel is >= the max of its children");
	CHECK(r->hiz_size(r->hiz_level_count() - 1) == Vector2i(1, 1));
	CHECK(Math::is_inf(r->hiz_get(r->hiz_level_count() - 1, 0, 0)));
}

TEST_CASE("[CgameOcclusionRaster] Batch test matches single tests") {
	Ref<CgameOcclusionRaster> r = make_wall_raster();
	Array boxes;
	boxes.push_back(AABB(Vector3(-1, -1, -20), Vector3(2, 2, 2)));
	boxes.push_back(AABB(Vector3(22, -1, -21), Vector3(2, 2, 2)));
	boxes.push_back(AABB(Vector3(-1, -1, -6), Vector3(2, 2, 2)));
	boxes.push_back(AABB(Vector3(-3, -2, -30), Vector3(1, 1, 1)));
	boxes.push_back(AABB(Vector3(-1, -1, 5), Vector3(2, 2, 2)));
	const PackedByteArray batch = r->test_many(boxes);
	REQUIRE(batch.size() == boxes.size());
	for (int i = 0; i < boxes.size(); i++) {
		CHECK((batch[i] == 1) == r->is_visible(boxes[i]));
	}
	CHECK(batch[0] == 0);
	CHECK(batch[1] == 1);
}

TEST_CASE("[CgameOcclusionRaster] Temporal reprojection and misuse") {
	Ref<CgameOcclusionRaster> r = make_wall_raster();
	Projection proj = Projection::create_perspective(70.0, 2.0, 0.1, 200.0);
	r->begin(proj, 256, 128);
	r->temporal_reproject(proj);
	CHECK(!r->is_visible(AABB(Vector3(-1, -1, -20), Vector3(2, 2, 2))));
	CHECK(r->is_visible(AABB(Vector3(-1, -1, -6), Vector3(2, 2, 2))));

	Ref<CgameOcclusionRaster> fresh;
	fresh.instantiate();
	ERR_PRINT_OFF;
	CHECK(fresh->is_visible(AABB(Vector3(-1, -1, -20), Vector3(2, 2, 2))));
	ERR_PRINT_ON;
}

} // namespace TestCgameVirtualGeometry
