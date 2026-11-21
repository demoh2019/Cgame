/**************************************************************************/
/*  cgame_hair_strands.cpp                                                */
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

#include "cgame_hair_strands.h"

#include "core/object/class_db.h"
#include "scene/resources/mesh.h"

namespace {

struct RibbonBuffers {
	Vector<Vector3> verts;
	Vector<Vector3> norms;
	Vector<Vector2> uvs;
	Vector<Color> cols;
	Vector<int> idx;

	// Every strand point becomes two vertices at the same position; the vertex shader expands them
	// toward the camera. NORMAL = strand tangent, UV = (side 0/1, t root->tip),
	// COLOR = (half width, per-strand random, t, 1).
	void append_strand(int p_strand, const Vector3 *p_pts, int p_count, real_t p_width) {
		if (p_count < 2) {
			return;
		}
		const real_t rnd = real_t((uint64_t(p_strand) * 2654435761ULL) & 0xFFFF) / 65535.0;
		const int first = verts.size();
		for (int i = 0; i < p_count; i++) {
			const Vector3 a = p_pts[MAX(i - 1, 0)];
			const Vector3 b = p_pts[MIN(i + 1, p_count - 1)];
			const Vector3 tangent = (b - a).normalized();
			const real_t t = real_t(i) / real_t(p_count - 1);
			for (int side = 0; side < 2; side++) {
				verts.push_back(p_pts[i]);
				norms.push_back(tangent);
				uvs.push_back(Vector2(real_t(side), t));
				cols.push_back(Color(p_width * 0.5, rnd, t, 1.0));
			}
		}
		for (int i = 0; i < p_count - 1; i++) {
			const int v = first + i * 2;
			idx.push_back(v);
			idx.push_back(v + 1);
			idx.push_back(v + 2);
			idx.push_back(v + 1);
			idx.push_back(v + 3);
			idx.push_back(v + 2);
		}
	}

	Ref<ArrayMesh> finish() const {
		Ref<ArrayMesh> mesh;
		mesh.instantiate();
		if (verts.is_empty()) {
			return mesh;
		}
		Array arrays;
		arrays.resize(Mesh::ARRAY_MAX);
		arrays[Mesh::ARRAY_VERTEX] = verts;
		arrays[Mesh::ARRAY_NORMAL] = norms;
		arrays[Mesh::ARRAY_TEX_UV] = uvs;
		arrays[Mesh::ARRAY_COLOR] = cols;
		arrays[Mesh::ARRAY_INDEX] = idx;
		mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
		return mesh;
	}
};

} // namespace

void CgameHairStrands::grow_guides(const Vector<Vector3> &p_root_points, const Vector<Vector3> &p_root_normals, int p_segments, real_t p_length) {
	guide_count = MIN(p_root_points.size(), p_root_normals.size());
	segments = MAX(p_segments, 1);
	points_per_guide = segments + 1;
	seg_len = p_length / real_t(segments);
	rest.resize(guide_count * points_per_guide);
	pos.resize(rest.size());
	prev.resize(rest.size());
	for (int g = 0; g < guide_count; g++) {
		const Vector3 n = p_root_normals[g].normalized();
		for (int i = 0; i < points_per_guide; i++) {
			rest.write[g * points_per_guide + i] = p_root_points[g] + n * (seg_len * real_t(i));
		}
	}
	_build_neighbors();
	initialized = false;
}

void CgameHairStrands::add_capsule(const Vector3 &p_a, const Vector3 &p_b, real_t p_radius) {
	cap_a.push_back(p_a);
	cap_b.push_back(p_b);
	cap_r.push_back(p_radius);
}

void CgameHairStrands::clear_capsules() {
	cap_a.clear();
	cap_b.clear();
	cap_r.clear();
}

void CgameHairStrands::reset(const Transform3D &p_head_transform) {
	for (int i = 0; i < rest.size(); i++) {
		const Vector3 w = p_head_transform.xform(rest[i]);
		pos.write[i] = w;
		prev.write[i] = w;
	}
	initialized = true;
}

Vector<Vector3> CgameHairStrands::guide_points(int p_guide) const {
	ERR_FAIL_INDEX_V(p_guide, guide_count, Vector<Vector3>());
	return pos.slice(p_guide * points_per_guide, (p_guide + 1) * points_per_guide);
}

void CgameHairStrands::step(real_t p_dt, const Transform3D &p_head_transform) {
	if (guide_count == 0 || p_dt <= 0.0) {
		return;
	}
	if (!initialized) {
		reset(p_head_transform);
	}
	const real_t frames = p_dt * 60.0;
	const real_t damp = Math::pow(damping, frames);
	const Vector3 accel = gravity + wind;
	const real_t dt2 = p_dt * p_dt;
	const Transform3D inv = p_head_transform.affine_inverse();
	const int count = points_per_guide;
	const Vector3 *r = rest.ptr();
	Vector3 *p = pos.ptrw();
	Vector3 *pv = prev.ptrw();

	for (int g = 0; g < guide_count; g++) {
		const int base = g * count;
		const Vector3 root = p_head_transform.xform(r[base]);
		p[base] = root;
		pv[base] = root;
		// Verlet integration + global shape matching toward the (moving) rest pose.
		for (int i = 1; i < count; i++) {
			const int k = base + i;
			const Vector3 cur = p[k];
			Vector3 np = cur + (cur - pv[k]) * damp + accel * dt2;
			pv[k] = cur;
			const real_t t = real_t(i) / real_t(segments);
			const real_t stiff = 1.0 - Math::pow(real_t(1.0) - stiffness * (real_t(1.0) - stiffness_root_bias * t), frames);
			np += (p_head_transform.xform(r[k]) - np) * stiff;
			p[k] = np;
		}
		// DFTL: each follower is pulled back to segment length from its leader, and the induced
		// velocity is damped so the chain does not whip.
		for (int it = 0; it < iterations; it++) {
			for (int i = 1; i < count; i++) {
				const int k2 = base + i;
				const Vector3 d = p[k2] - p[k2 - 1];
				const real_t l = d.length();
				if (l > 0.000001) {
					const Vector3 corr = d * (seg_len / l) - d;
					p[k2] += corr;
					pv[k2] += corr * ftl_damping;
				}
			}
			_collide(base, p_head_transform, inv);
		}
	}
}

void CgameHairStrands::_collide(int p_base, const Transform3D &p_head, const Transform3D &p_inv) {
	if (cap_r.is_empty()) {
		return;
	}
	Vector3 *p = pos.ptrw();
	Vector3 *pv = prev.ptrw();
	for (int i = 1; i < points_per_guide; i++) {
		const int k = p_base + i;
		Vector3 local = p_inv.xform(p[k]);
		bool moved = false;
		for (int c = 0; c < cap_r.size(); c++) {
			const Vector3 a = cap_a[c];
			const Vector3 ab = cap_b[c] - a;
			const real_t denom = ab.length_squared();
			real_t t = 0.0;
			if (denom > 0.0000001) {
				t = CLAMP((local - a).dot(ab) / denom, 0.0, 1.0);
			}
			const Vector3 q = a + ab * t;
			const Vector3 d = local - q;
			const real_t dl = d.length();
			const real_t rr = cap_r[c] + collision_margin;
			if (dl < rr) {
				const Vector3 n = dl > 0.000001 ? d / dl : Vector3(0, 1, 0);
				local = q + n * rr;
				moved = true;
			}
		}
		if (moved) {
			const Vector3 w = p_head.xform(local);
			pv[k] = pv[k].lerp(w, 0.5); // Friction: kill part of the inward velocity.
			p[k] = w;
		}
	}
}

void CgameHairStrands::_build_neighbors() {
	neighbors.resize(guide_count * 2);
	for (int g = 0; g < guide_count; g++) {
		int best1 = g;
		int best2 = g;
		real_t d1 = Math::INF;
		real_t d2 = Math::INF;
		const Vector3 r = rest[g * points_per_guide];
		for (int o = 0; o < guide_count; o++) {
			if (o == g) {
				continue;
			}
			const real_t d = r.distance_squared_to(rest[o * points_per_guide]);
			if (d < d1) {
				d2 = d1;
				best2 = best1;
				d1 = d;
				best1 = o;
			} else if (d < d2) {
				d2 = d;
				best2 = o;
			}
		}
		neighbors.write[g * 2] = best1;
		neighbors.write[g * 2 + 1] = best2;
	}
}

void CgameHairStrands::_interpolate_strand(int p_guide, int p_strand_index, RandomPCG &p_rng, Vector3 *r_out) const {
	const int count = points_per_guide;
	const int g1 = neighbors[p_guide * 2];
	const int g2 = neighbors[p_guide * 2 + 1];
	real_t w1 = 0.0;
	real_t w2 = 0.0;
	Vector3 off;
	if (p_strand_index > 0) {
		w1 = p_rng.randf() * 0.35;
		w2 = p_rng.randf() * 0.35;
		const real_t ox = p_rng.random(-1.0, 1.0);
		const real_t oy = p_rng.random(-1.0, 1.0);
		const real_t oz = p_rng.random(-1.0, 1.0);
		off = Vector3(ox, oy, oz) * strand_spread;
	}
	const real_t w0 = 1.0 - w1 - w2;
	const Vector3 *p = pos.ptr();
	for (int i = 0; i < count; i++) {
		const real_t t = real_t(i) / real_t(segments);
		const Vector3 pt = p[p_guide * count + i] * w0 + p[g1 * count + i] * w1 + p[g2 * count + i] * w2;
		r_out[i] = pt + off * (0.25 + 0.75 * t) * MIN(t * 4.0, 1.0);
	}
}

TypedArray<PackedVector3Array> CgameHairStrands::render_strands(int p_per_guide, int p_seed) const {
	TypedArray<PackedVector3Array> out;
	if (guide_count == 0 || p_per_guide <= 0) {
		return out;
	}
	RandomPCG rng;
	rng.seed(p_seed);
	Vector<Vector3> tmp;
	tmp.resize(points_per_guide);
	for (int g = 0; g < guide_count; g++) {
		for (int s = 0; s < p_per_guide; s++) {
			_interpolate_strand(g, s, rng, tmp.ptrw());
			out.push_back(tmp);
		}
	}
	return out;
}

int CgameHairStrands::lod_strand_count(real_t p_screen_coverage) const {
	if (p_screen_coverage <= 0.002) {
		return 0;
	}
	const real_t c = CLAMP(p_screen_coverage, 0.0, 1.0);
	return CLAMP(1 + (int)Math::round(real_t(max_per_guide - 1) * Math::sqrt(c)), 1, max_per_guide);
}

Vector<int> CgameHairStrands::cull(const TypedArray<Plane> &p_view_frustum_planes, const Vector3 &p_view_pos) const {
	Vector<int> visible;
	const int count = points_per_guide;
	for (int g = 0; g < guide_count; g++) {
		Vector3 center;
		for (int i = 0; i < count; i++) {
			center += pos[g * count + i];
		}
		center /= real_t(count);
		real_t radius = 0.0;
		for (int i = 0; i < count; i++) {
			radius = MAX(radius, center.distance_to(pos[g * count + i]));
		}
		if (center.distance_to(p_view_pos) - radius > max_distance) {
			continue;
		}
		bool inside = true;
		for (int pi = 0; pi < p_view_frustum_planes.size(); pi++) {
			const Plane plane = p_view_frustum_planes[pi];
			if (plane.distance_to(center) > radius) {
				inside = false;
				break;
			}
		}
		if (inside) {
			visible.push_back(g);
		}
	}
	return visible;
}

Ref<ArrayMesh> CgameHairStrands::build_mesh(const TypedArray<PackedVector3Array> &p_strands, real_t p_width) const {
	RibbonBuffers buf;
	for (int s = 0; s < p_strands.size(); s++) {
		const Vector<Vector3> pts = p_strands[s];
		buf.append_strand(s, pts.ptr(), pts.size(), p_width);
	}
	return buf.finish();
}

Ref<ArrayMesh> CgameHairStrands::build_ribbon_mesh(int p_per_guide, int p_seed, real_t p_width) const {
	RibbonBuffers buf;
	if (guide_count == 0 || p_per_guide <= 0) {
		return buf.finish();
	}
	RandomPCG rng;
	rng.seed(p_seed);
	Vector<Vector3> tmp;
	tmp.resize(points_per_guide);
	int strand = 0;
	for (int g = 0; g < guide_count; g++) {
		for (int s = 0; s < p_per_guide; s++) {
			_interpolate_strand(g, s, rng, tmp.ptrw());
			buf.append_strand(strand++, tmp.ptr(), points_per_guide, p_width);
		}
	}
	return buf.finish();
}

void CgameHairStrands::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_segments"), &CgameHairStrands::get_segments);
	ClassDB::bind_method(D_METHOD("get_guide_count"), &CgameHairStrands::get_guide_count);
	ClassDB::bind_method(D_METHOD("get_points_per_guide"), &CgameHairStrands::get_points_per_guide);
	ClassDB::bind_method(D_METHOD("get_seg_len"), &CgameHairStrands::get_seg_len);
	ClassDB::bind_method(D_METHOD("get_rest"), &CgameHairStrands::get_rest);
	ClassDB::bind_method(D_METHOD("get_pos"), &CgameHairStrands::get_pos);
	ClassDB::bind_method(D_METHOD("get_prev"), &CgameHairStrands::get_prev);
	ClassDB::bind_method(D_METHOD("get_neighbors"), &CgameHairStrands::get_neighbors);

	ClassDB::bind_method(D_METHOD("set_gravity", "gravity"), &CgameHairStrands::set_gravity);
	ClassDB::bind_method(D_METHOD("get_gravity"), &CgameHairStrands::get_gravity);
	ClassDB::bind_method(D_METHOD("set_wind", "wind"), &CgameHairStrands::set_wind);
	ClassDB::bind_method(D_METHOD("get_wind"), &CgameHairStrands::get_wind);
	ClassDB::bind_method(D_METHOD("set_damping", "damping"), &CgameHairStrands::set_damping);
	ClassDB::bind_method(D_METHOD("get_damping"), &CgameHairStrands::get_damping);
	ClassDB::bind_method(D_METHOD("set_stiffness", "stiffness"), &CgameHairStrands::set_stiffness);
	ClassDB::bind_method(D_METHOD("get_stiffness"), &CgameHairStrands::get_stiffness);
	ClassDB::bind_method(D_METHOD("set_stiffness_root_bias", "bias"), &CgameHairStrands::set_stiffness_root_bias);
	ClassDB::bind_method(D_METHOD("get_stiffness_root_bias"), &CgameHairStrands::get_stiffness_root_bias);
	ClassDB::bind_method(D_METHOD("set_ftl_damping", "damping"), &CgameHairStrands::set_ftl_damping);
	ClassDB::bind_method(D_METHOD("get_ftl_damping"), &CgameHairStrands::get_ftl_damping);
	ClassDB::bind_method(D_METHOD("set_iterations", "iterations"), &CgameHairStrands::set_iterations);
	ClassDB::bind_method(D_METHOD("get_iterations"), &CgameHairStrands::get_iterations);
	ClassDB::bind_method(D_METHOD("set_collision_margin", "margin"), &CgameHairStrands::set_collision_margin);
	ClassDB::bind_method(D_METHOD("get_collision_margin"), &CgameHairStrands::get_collision_margin);
	ClassDB::bind_method(D_METHOD("set_strand_spread", "spread"), &CgameHairStrands::set_strand_spread);
	ClassDB::bind_method(D_METHOD("get_strand_spread"), &CgameHairStrands::get_strand_spread);
	ClassDB::bind_method(D_METHOD("set_max_per_guide", "count"), &CgameHairStrands::set_max_per_guide);
	ClassDB::bind_method(D_METHOD("get_max_per_guide"), &CgameHairStrands::get_max_per_guide);
	ClassDB::bind_method(D_METHOD("set_max_distance", "distance"), &CgameHairStrands::set_max_distance);
	ClassDB::bind_method(D_METHOD("get_max_distance"), &CgameHairStrands::get_max_distance);

	ClassDB::bind_method(D_METHOD("grow_guides", "root_points", "root_normals", "segments", "length"), &CgameHairStrands::grow_guides);
	ClassDB::bind_method(D_METHOD("add_capsule", "a", "b", "radius"), &CgameHairStrands::add_capsule);
	ClassDB::bind_method(D_METHOD("clear_capsules"), &CgameHairStrands::clear_capsules);
	ClassDB::bind_method(D_METHOD("reset", "head_transform"), &CgameHairStrands::reset);
	ClassDB::bind_method(D_METHOD("guide_points", "guide"), &CgameHairStrands::guide_points);
	ClassDB::bind_method(D_METHOD("step", "dt", "head_transform"), &CgameHairStrands::step);

	ClassDB::bind_method(D_METHOD("render_strands", "per_guide", "seed"), &CgameHairStrands::render_strands);
	ClassDB::bind_method(D_METHOD("lod_strand_count", "screen_coverage"), &CgameHairStrands::lod_strand_count);
	ClassDB::bind_method(D_METHOD("cull", "view_frustum_planes", "view_pos"), &CgameHairStrands::cull);
	ClassDB::bind_method(D_METHOD("build_mesh", "strands", "width"), &CgameHairStrands::build_mesh);
	ClassDB::bind_method(D_METHOD("build_ribbon_mesh", "per_guide", "seed", "width"), &CgameHairStrands::build_ribbon_mesh);

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "gravity", PROPERTY_HINT_NONE, "suffix:m/s²"), "set_gravity", "get_gravity");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "wind", PROPERTY_HINT_NONE, "suffix:m/s²"), "set_wind", "get_wind");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "damping", PROPERTY_HINT_RANGE, "0,1,0.001"), "set_damping", "get_damping");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "stiffness", PROPERTY_HINT_RANGE, "0,1,0.001"), "set_stiffness", "get_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "stiffness_root_bias", PROPERTY_HINT_RANGE, "0,1,0.001"), "set_stiffness_root_bias", "get_stiffness_root_bias");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ftl_damping", PROPERTY_HINT_RANGE, "0,1,0.001"), "set_ftl_damping", "get_ftl_damping");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations", PROPERTY_HINT_RANGE, "1,16,1,or_greater"), "set_iterations", "get_iterations");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "collision_margin", PROPERTY_HINT_RANGE, "0,0.1,0.0001,or_greater,suffix:m"), "set_collision_margin", "get_collision_margin");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "strand_spread", PROPERTY_HINT_RANGE, "0,0.2,0.0001,or_greater,suffix:m"), "set_strand_spread", "get_strand_spread");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_per_guide", PROPERTY_HINT_RANGE, "1,64,1,or_greater"), "set_max_per_guide", "get_max_per_guide");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_distance", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:m"), "set_max_distance", "get_max_distance");
}
