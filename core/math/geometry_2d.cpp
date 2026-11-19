/**************************************************************************/
/*  geometry_2d.cpp                                                       */
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

#include "geometry_2d.h"

#include "core/math/math_funcs_binary.h"

GODOT_GCC_WARNING_PUSH_AND_IGNORE("-Walloc-zero")
#include <thirdparty/clipper2/include/clipper2/clipper.h>
GODOT_GCC_WARNING_POP
#include <thirdparty/misc/polypartition.h>
#define STB_RECT_PACK_IMPLEMENTATION
#include <thirdparty/misc/stb_rect_pack.h>

#include <utility>

const int clipper_precision = 5; // Based on CMP_EPSILON.

void Geometry2D::merge_many_polygons(const Vector<Vector<Vector2>> &p_polygons, Vector<Vector<Vector2>> &r_out_polygons, Vector<Vector<Vector2>> &r_out_holes) {
	using namespace Clipper2Lib;

	PathsD subjects;
	subjects.reserve(p_polygons.size());
	for (const Vector<Vector2> &polygon : p_polygons) {
		PathD path(polygon.size());
		const Vector2 *const source = polygon.ptr();
		for (int i = 0; i < polygon.size(); i++) {
			path[i] = PointD(source[i].x, source[i].y);
		}
		// Clipper owns the path after insertion. Moving avoids a deep copy
		// of all points in every input polygon.
		subjects.push_back(std::move(path));
	}

	PathsD solution = Union(subjects, FillRule::NonZero);
	solution = SimplifyPaths(solution, 0.01);

	r_out_polygons.clear();
	r_out_holes.clear();
	for (PathsD::size_type i = 0; i < solution.size(); ++i) {
		const PathD &path = solution[i];

		Vector<Point2> output_polygon;
		ERR_FAIL_COND(output_polygon.resize_uninitialized(path.size()) != OK);
		Point2 *const output = output_polygon.ptrw();
		for (PathsD::size_type j = 0; j < path.size(); ++j) {
			output[j] = Point2(static_cast<real_t>(path[j].x), static_cast<real_t>(path[j].y));
		}
		// Move the allocated output buffer to the owning list instead of
		// copying/referencing it and repeatedly resolving writable storage.
		if (IsPositive(path)) {
			r_out_polygons.push_back(std::move(output_polygon));
		} else {
			r_out_holes.push_back(std::move(output_polygon));
		}
	}
}

Vector<Vector<Vector2>> Geometry2D::decompose_many_polygons_in_convex(const Vector<Vector<Point2>> &p_polygons, const Vector<Vector<Point2>> &p_holes) {
	Vector<Vector<Vector2>> decomp;
	List<TPPLPoly> in_poly, out_poly;

	for (const Vector<Vector2> &polygon : p_polygons) {
		TPPLPoly inp;
		inp.Init(polygon.size());
		for (int i = 0; i < polygon.size(); i++) {
			inp.GetPoint(i) = polygon[i];
		}
		inp.SetOrientation(TPPL_ORIENTATION_CCW);
		in_poly.push_back(inp);
	}
	for (const Vector<Vector2> &polygon : p_holes) {
		TPPLPoly inp;
		inp.Init(polygon.size());
		for (int i = 0; i < polygon.size(); i++) {
			inp.GetPoint(i) = polygon[i];
		}
		inp.SetOrientation(TPPL_ORIENTATION_CW);
		inp.SetHole(true);
		in_poly.push_back(inp);
	}
	TPPLPartition tpart;
	if (tpart.ConvexPartition_HM(&in_poly, &out_poly) == 0) { // Failed.
		ERR_PRINT("Convex decomposing failed!");
		return decomp;
	}

	ERR_FAIL_COND_V(decomp.resize(out_poly.size()) != OK, Vector<Vector<Vector2>>());
	Vector<Vector2> *const output_polygons = decomp.ptrw();
	int idx = 0;
	for (TPPLPoly &tp : out_poly) {
		const int point_count = tp.GetNumPoints();
		Vector<Vector2> &polygon = output_polygons[idx];
		ERR_FAIL_COND_V(polygon.resize(point_count) != OK, Vector<Vector<Vector2>>());
		Vector2 *const points = polygon.ptrw();
		// Resolve both writable COW levels once, rather than on every
		// vertex of potentially large convex decomposition results.
		for (int i = 0; i < point_count; i++) {
			points[i] = tp.GetPoint(i);
		}
		idx++;
	}

	return decomp;
}

Vector<Vector<Vector2>> Geometry2D::decompose_polygon_in_convex(const Vector<Point2> &p_polygon) {
	return Geometry2D::decompose_many_polygons_in_convex({ p_polygon }, {});
}

struct _AtlasWorkRect {
	Size2i s;
	Point2i p;
	int idx = 0;
	_FORCE_INLINE_ bool operator<(const _AtlasWorkRect &p_r) const { return s.width > p_r.s.width; }
};

void Geometry2D::make_atlas(const Vector<Size2i> &p_rects, Vector<Point2i> &r_result, Size2i &r_size) {
	// Keep the original scanline placement strategy and power-of-two
	// aspect-ratio scoring, but retain only the best candidate's positions.
	// The former implementation stored a complete Vector of rectangles for
	// every candidate width (up to 13), causing repeated COW copies.
	ERR_FAIL_COND(p_rects.is_empty());
	for (int i = 0; i < p_rects.size(); i++) {
		ERR_FAIL_COND(p_rects[i].width <= 0);
		ERR_FAIL_COND(p_rects[i].height <= 0);
	}

	Vector<_AtlasWorkRect> wrects;
	ERR_FAIL_COND(wrects.resize(p_rects.size()) != OK);
	_AtlasWorkRect *rects = wrects.ptrw();
	for (int i = 0; i < p_rects.size(); i++) {
		rects[i].s = p_rects[i];
		rects[i].idx = i;
	}
	wrects.sort();
	rects = wrects.ptrw();
	const int widest = rects[0].s.width;
	ERR_FAIL_COND_MSG(widest > (1 << 12), "No atlas candidate can contain the widest rectangle.");

	ERR_FAIL_COND(r_result.resize(p_rects.size()) != OK);
	Point2i *const best_positions = r_result.ptrw();
	real_t best_aspect = 1e20;
	Size2i best_size;

	for (int i = 0; i <= 12; i++) {
		const int w = 1 << i;
		if (w < widest) {
			continue;
		}

		// A new vector starts empty; zero-initialize its entire height map
		// once rather than repeatedly resolving a COW writable proxy.
		Vector<int> hmax;
		ERR_FAIL_COND(hmax.resize_initialized(w) != OK);
		int *const heights = hmax.ptrw();
		int max_h = 0;
		int max_w = 0;

		int ofs = 0;
		int limit_h = 0;
		for (int j = 0; j < wrects.size(); j++) {
			_AtlasWorkRect &rect = rects[j];
			if (ofs + rect.s.width > w) {
				ofs = 0;
			}

			int from_y = 0;
			for (int k = 0; k < rect.s.width; k++) {
				if (heights[ofs + k] > from_y) {
					from_y = heights[ofs + k];
				}
			}

			rect.p.x = ofs;
			rect.p.y = from_y;
			const int end_h = from_y + rect.s.height;
			const int end_w = ofs + rect.s.width;
			if (ofs == 0) {
				limit_h = end_h;
			}

			for (int k = 0; k < rect.s.width; k++) {
				heights[ofs + k] = end_h;
			}

			if (end_h > max_h) {
				max_h = end_h;
			}
			if (end_w > max_w) {
				max_w = end_w;
			}
			if (ofs == 0 || end_h > limit_h) {
				ofs += rect.s.width;
			}
		}

		const real_t h = Math::next_power_of_2((uint32_t)max_h);
		const real_t candidate_w = Math::next_power_of_2((uint32_t)max_w);
		const real_t aspect = h > candidate_w ? h / candidate_w : candidate_w / h;
		if (aspect < best_aspect) {
			best_aspect = aspect;
			best_size = Size2i(max_w, max_h);
			for (int j = 0; j < wrects.size(); j++) {
				best_positions[rects[j].idx] = rects[j].p;
			}
		}
	}

	r_size = best_size;
}

Vector<Vector<Point2>> Geometry2D::_polypaths_do_operation(PolyBooleanOperation p_op, const Vector<Point2> &p_polypath_a, const Vector<Point2> &p_polypath_b, bool p_is_a_open) {
	using namespace Clipper2Lib;

	ClipType op = ClipType::Union;

	switch (p_op) {
		case OPERATION_UNION:
			op = ClipType::Union;
			break;
		case OPERATION_DIFFERENCE:
			op = ClipType::Difference;
			break;
		case OPERATION_INTERSECTION:
			op = ClipType::Intersection;
			break;
		case OPERATION_XOR:
			op = ClipType::Xor;
			break;
	}

	PathD path_a(p_polypath_a.size());
	for (int i = 0; i != p_polypath_a.size(); ++i) {
		path_a[i] = PointD(p_polypath_a[i].x, p_polypath_a[i].y);
	}
	PathD path_b(p_polypath_b.size());
	for (int i = 0; i != p_polypath_b.size(); ++i) {
		path_b[i] = PointD(p_polypath_b[i].x, p_polypath_b[i].y);
	}

	ClipperD clp(clipper_precision); // Scale points up internally to attain the desired precision.
	clp.PreserveCollinear(false); // Remove redundant vertices.
	if (p_is_a_open) {
		clp.AddOpenSubject({ path_a });
	} else {
		clp.AddSubject({ path_a });
	}
	clp.AddClip({ path_b });

	PathsD paths;

	if (p_is_a_open) {
		PolyTreeD tree; // Needed to populate polylines.
		clp.Execute(op, FillRule::EvenOdd, tree, paths);
	} else {
		clp.Execute(op, FillRule::EvenOdd, paths); // Works on closed polygons only.
	}

	Vector<Vector<Point2>> polypaths;
	ERR_FAIL_COND_V(polypaths.resize(paths.size()) != OK, Vector<Vector<Point2>>());
	Vector<Point2> *result_paths = polypaths.ptrw();

	for (PathsD::size_type i = 0; i < paths.size(); ++i) {
		const PathD &path = paths[i];
		Vector<Point2> &destination = result_paths[i];
		ERR_FAIL_COND_V(destination.resize(path.size()) != OK, Vector<Vector<Point2>>());
		Point2 *destination_points = destination.ptrw();
		for (PathsD::size_type j = 0; j < path.size(); ++j) {
			destination_points[j] = Point2(static_cast<real_t>(path[j].x), static_cast<real_t>(path[j].y));
		}
	}
	return polypaths;
}

Vector<Vector<Point2>> Geometry2D::_polypath_offset(const Vector<Point2> &p_polypath, real_t p_delta, PolyJoinType p_join_type, PolyEndType p_end_type) {
	using namespace Clipper2Lib;

	JoinType jt = JoinType::Square;

	switch (p_join_type) {
		case JOIN_SQUARE:
			jt = JoinType::Square;
			break;
		case JOIN_ROUND:
			jt = JoinType::Round;
			break;
		case JOIN_MITER:
			jt = JoinType::Miter;
			break;
	}

	EndType et = EndType::Polygon;

	switch (p_end_type) {
		case END_POLYGON:
			et = EndType::Polygon;
			break;
		case END_JOINED:
			et = EndType::Joined;
			break;
		case END_BUTT:
			et = EndType::Butt;
			break;
		case END_SQUARE:
			et = EndType::Square;
			break;
		case END_ROUND:
			et = EndType::Round;
			break;
	}

	PathD polypath(p_polypath.size());
	for (int i = 0; i != p_polypath.size(); ++i) {
		polypath[i] = PointD(p_polypath[i].x, p_polypath[i].y);
	}

	// Inflate/deflate.
	PathsD paths = InflatePaths({ polypath }, p_delta, jt, et, 2.0, clipper_precision, 0.25);

	Vector<Vector<Point2>> polypaths;
	ERR_FAIL_COND_V(polypaths.resize(paths.size()) != OK, Vector<Vector<Point2>>());
	Vector<Point2> *result_paths = polypaths.ptrw();

	for (PathsD::size_type i = 0; i < paths.size(); ++i) {
		const PathD &path = paths[i];
		Vector<Point2> &destination = result_paths[i];
		ERR_FAIL_COND_V(destination.resize(path.size()) != OK, Vector<Vector<Point2>>());
		Point2 *destination_points = destination.ptrw();
		for (PathsD::size_type j = 0; j < path.size(); ++j) {
			destination_points[j] = Point2(static_cast<real_t>(path[j].x), static_cast<real_t>(path[j].y));
		}
	}
	return polypaths;
}

Vector<Vector3i> Geometry2D::partial_pack_rects(const Vector<Vector2i> &p_sizes, const Size2i &p_atlas_size) {
	Vector<stbrp_node> nodes;
	nodes.resize(p_atlas_size.width);
	memset(nodes.ptrw(), 0, sizeof(stbrp_node) * nodes.size());

	stbrp_context context;
	stbrp_init_target(&context, p_atlas_size.width, p_atlas_size.height, nodes.ptrw(), p_atlas_size.width);

	Vector<stbrp_rect> rects;
	rects.resize(p_sizes.size());

	for (int i = 0; i < p_sizes.size(); i++) {
		rects.write[i].id = i;
		rects.write[i].w = p_sizes[i].width;
		rects.write[i].h = p_sizes[i].height;
		rects.write[i].x = 0;
		rects.write[i].y = 0;
		rects.write[i].was_packed = 0;
	}

	stbrp_pack_rects(&context, rects.ptrw(), rects.size());

	Vector<Vector3i> ret;
	ret.resize(p_sizes.size());

	for (int i = 0; i < p_sizes.size(); i++) {
		ret.write[rects[i].id] = Vector3i(rects[i].x, rects[i].y, rects[i].was_packed != 0 ? 1 : 0);
	}

	return ret;
}
