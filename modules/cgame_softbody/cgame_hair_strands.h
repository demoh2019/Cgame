/**************************************************************************/
/*  cgame_hair_strands.h                                                  */
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

#include "core/math/plane.h"
#include "core/math/random_pcg.h"
#include "core/math/transform_3d.h"
#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

class ArrayMesh;

// Strand-based hair: guide-strand physics, interpolated render strands, capsule collision, LOD,
// culling and camera-facing ribbon mesh building.
//
// Techniques (re-implemented from the papers and descriptions, no code copied):
// - Dynamic Follow-The-Leader (DFTL): Matthias Mueller, Tae-Yong Kim, Nuttapong Chentanez,
//   "Fast Simulation of Inextensible Hair and Fur", VRIPHYS 2012. Paper only; only the
//   published idea is used.
// - Global shape matching, local length constraints, guide -> render strand interpolation and
//   capsule collision follow the concepts of AMD TressFX
//   (https://github.com/GPUOpen-Effects/TressFX, Copyright (c) AMD, MIT license).
// - The XPBD family and Ten Minute Physics (MIT, Matthias Muller) inspire the small-step
//   structure used by the sibling cloth and rope classes.
//
// Layout: guide g owns points [g * points_per_guide, (g + 1) * points_per_guide); point 0 is the
// pinned root. `rest` is in head space, `pos`/`prev` in world space (Verlet).
class CgameHairStrands : public RefCounted {
	GDCLASS(CgameHairStrands, RefCounted);

	int segments = 0;
	int guide_count = 0;
	int points_per_guide = 0;
	real_t seg_len = 0.0;

	Vector<Vector3> rest;
	Vector<Vector3> pos;
	Vector<Vector3> prev;
	Vector<int> neighbors;

	Vector3 gravity = Vector3(0, -9.8, 0);
	Vector3 wind;
	real_t damping = 0.98;
	real_t stiffness = 0.08;
	real_t stiffness_root_bias = 0.5;
	real_t ftl_damping = 0.9;
	int iterations = 2;
	real_t collision_margin = 0.002;
	real_t strand_spread = 0.012;
	int max_per_guide = 8;
	real_t max_distance = 60.0;

	Vector<Vector3> cap_a;
	Vector<Vector3> cap_b;
	Vector<float> cap_r;
	bool initialized = false;

	void _collide(int p_base, const Transform3D &p_head, const Transform3D &p_inv);
	void _build_neighbors();
	void _interpolate_strand(int p_guide, int p_strand_index, RandomPCG &p_rng, Vector3 *r_out) const;

protected:
	static void _bind_methods();

public:
	int get_segments() const { return segments; }
	int get_guide_count() const { return guide_count; }
	int get_points_per_guide() const { return points_per_guide; }
	real_t get_seg_len() const { return seg_len; }
	Vector<Vector3> get_rest() const { return rest; }
	Vector<Vector3> get_pos() const { return pos; }
	Vector<Vector3> get_prev() const { return prev; }
	Vector<int> get_neighbors() const { return neighbors; }

	void set_gravity(const Vector3 &p_gravity) { gravity = p_gravity; }
	Vector3 get_gravity() const { return gravity; }
	void set_wind(const Vector3 &p_wind) { wind = p_wind; }
	Vector3 get_wind() const { return wind; }
	void set_damping(real_t p_value) { damping = p_value; }
	real_t get_damping() const { return damping; }
	void set_stiffness(real_t p_value) { stiffness = p_value; }
	real_t get_stiffness() const { return stiffness; }
	void set_stiffness_root_bias(real_t p_value) { stiffness_root_bias = p_value; }
	real_t get_stiffness_root_bias() const { return stiffness_root_bias; }
	void set_ftl_damping(real_t p_value) { ftl_damping = p_value; }
	real_t get_ftl_damping() const { return ftl_damping; }
	void set_iterations(int p_value) { iterations = MAX(p_value, 1); }
	int get_iterations() const { return iterations; }
	void set_collision_margin(real_t p_value) { collision_margin = p_value; }
	real_t get_collision_margin() const { return collision_margin; }
	void set_strand_spread(real_t p_value) { strand_spread = p_value; }
	real_t get_strand_spread() const { return strand_spread; }
	void set_max_per_guide(int p_value) { max_per_guide = MAX(p_value, 1); }
	int get_max_per_guide() const { return max_per_guide; }
	void set_max_distance(real_t p_value) { max_distance = p_value; }
	real_t get_max_distance() const { return max_distance; }

	void grow_guides(const Vector<Vector3> &p_root_points, const Vector<Vector3> &p_root_normals, int p_segments, real_t p_length);
	void add_capsule(const Vector3 &p_a, const Vector3 &p_b, real_t p_radius);
	void clear_capsules();
	void reset(const Transform3D &p_head_transform);
	Vector<Vector3> guide_points(int p_guide) const;
	void step(real_t p_dt, const Transform3D &p_head_transform);

	TypedArray<PackedVector3Array> render_strands(int p_per_guide, int p_seed) const;
	int lod_strand_count(real_t p_screen_coverage) const;
	Vector<int> cull(const TypedArray<Plane> &p_view_frustum_planes, const Vector3 &p_view_pos) const;
	Ref<ArrayMesh> build_mesh(const TypedArray<PackedVector3Array> &p_strands, real_t p_width) const;
	// Native ribbon generation straight from the guides, skipping the intermediate strand arrays.
	Ref<ArrayMesh> build_ribbon_mesh(int p_per_guide, int p_seed, real_t p_width) const;

	CgameHairStrands() {}
};
