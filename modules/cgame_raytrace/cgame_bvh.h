/**************************************************************************/
/*  cgame_bvh.h                                                           */
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

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "core/variant/dictionary.h"

// CPU bounding volume hierarchy over a triangle soup: binned SAH build, flat node array,
// Moller-Trumbore ray/triangle test. Queries are const and thread-safe once built.
class CgameBVH : public RefCounted {
	GDCLASS(CgameBVH, RefCounted);

public:
	static constexpr int BINS = 16;
	static constexpr int MAX_LEAF = 2; // SAH may stop at or below this many triangles.
	static constexpr int FORCE_SPLIT = 8; // Leaves are not larger than this unless the depth cap is hit.
	static constexpr int MAX_DEPTH = 96; // Hard cap; keeps the traversal stack fixed-size.
	static constexpr float T_MIN = 0.00001f;
	static constexpr float MISS = 1.0e30f;

	struct Hit {
		bool hit = false;
		float t = 0.0f;
		int tri = -1; // Index into the triangle array given to build().
		float u = 0.0f;
		float v = 0.0f;
		Vector3 normal;
	};

private:
	struct Node {
		Vector3 bmin;
		Vector3 bmax;
		int32_t first = 0; // Leaf: first triangle slot. Interior: left child (right = left + 1).
		int32_t cnt = 0; // > 0 for leaves.
	};

	struct Tri {
		Vector3 v0;
		Vector3 e1;
		Vector3 e2;
	};

	struct BuildJob {
		int node;
		int start;
		int cnt;
		int depth;
	};

	struct SplitResult {
		int axis = -1;
		int bin = 0;
		bool beats_leaf = false;
	};

	LocalVector<Node> nodes;
	LocalVector<Tri> tris;
	LocalVector<int32_t> tri_index;
	int tri_count = 0;
	int leaf_count = 0;
	int max_depth = 0;
	double build_ms = 0.0;

	// Build-time scratch, released at the end of build().
	LocalVector<Vector3> b_lo;
	LocalVector<Vector3> b_hi;
	LocalVector<Vector3> b_cen;

	static float _area(const Vector3 &p_extent);
	static Vector3 _safe_inv(const Vector3 &p_dir);
	SplitResult _find_split(int p_start, int p_cnt, const Vector3 &p_lo, const Vector3 &p_hi, const Vector3 &p_clo, const Vector3 &p_chi) const;
	_FORCE_INLINE_ float _box_t(const Node &p_node, const Vector3 &p_o, const Vector3 &p_inv, float p_t_max) const;
	_FORCE_INLINE_ bool _tri_hit(const Tri &p_tri, const Vector3 &p_o, const Vector3 &p_d, float &r_t, float &r_u, float &r_v) const;

protected:
	static void _bind_methods();

public:
	void build(const Vector<Vector3> &p_triangles);
	void clear();
	bool is_built() const { return !nodes.is_empty(); }

	// Native queries (thread-safe, no allocations).
	bool intersect_native(const Vector3 &p_origin, const Vector3 &p_dir, float p_t_max, Hit &r_hit) const;
	bool occluded_native(const Vector3 &p_origin, const Vector3 &p_dir, float p_t_max) const;

	// Script API.
	Dictionary intersect(const Vector3 &p_origin, const Vector3 &p_dir, float p_t_max = 1.0e20f) const;
	bool occluded(const Vector3 &p_origin, const Vector3 &p_dir, float p_t_max = 1.0e20f) const;
	Dictionary get_stats() const;
	int get_triangle_count() const { return tri_count; }
};
