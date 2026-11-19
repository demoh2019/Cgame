/**************************************************************************/
/*  convex_fracture.cpp                                             */
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

#include "convex_fracture.h"

#include "core/math/geometry_3d.h"
#include "core/math/quick_hull.h"

namespace ConvexFracture {

bool planes_from_points(const Vector<Vector3> &p_points, Vector<Plane> &r_planes) {
	r_planes.clear();
	if (p_points.size() < 4) {
		return false;
	}
	Geometry3D::MeshData hull;
	if (QuickHull::build(p_points, hull) != OK || hull.faces.size() < 4) {
		return false;
	}
	// One plane per distinct orientation: the hull may report coplanar faces separately.
	for (const Geometry3D::MeshData::Face &face : hull.faces) {
		bool duplicate = false;
		for (const Plane &existing : r_planes) {
			if (existing.normal.dot(face.plane.normal) > real_t(0.99999) && Math::abs(existing.d - face.plane.d) < real_t(1e-4)) {
				duplicate = true;
				break;
			}
		}
		if (!duplicate) {
			r_planes.push_back(face.plane);
		}
	}
	return r_planes.size() >= 4;
}

bool is_inside(const Vector<Plane> &p_planes, const Vector3 &p_point, real_t p_epsilon) {
	for (const Plane &plane : p_planes) {
		if (plane.normal.dot(p_point) - plane.d > p_epsilon) {
			return false;
		}
	}
	return true;
}

namespace {

// A convex polyhedron stored as polygons. Clipping it with half spaces is all the fracture needs.
struct Polyhedron {
	LocalVector<Face> faces;

	static Polyhedron from_bounds(const AABB &p_bounds) {
		Polyhedron result;
		const Vector3 low = p_bounds.position;
		const Vector3 high = p_bounds.get_end();
		const Vector3 c[8] = {
			Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z), Vector3(low.x, high.y, low.z), Vector3(high.x, high.y, low.z),
			Vector3(low.x, low.y, high.z), Vector3(high.x, low.y, high.z), Vector3(low.x, high.y, high.z), Vector3(high.x, high.y, high.z)
		};
		auto add = [&](const Vector3 &p_normal, real_t p_d, int a, int b, int d, int e) {
			Face face;
			face.plane = Plane(p_normal, p_d);
			face.vertices.push_back(c[a]);
			face.vertices.push_back(c[b]);
			face.vertices.push_back(c[d]);
			face.vertices.push_back(c[e]);
			result.faces.push_back(face);
		};
		add(Vector3(1, 0, 0), high.x, 1, 3, 7, 5);
		add(Vector3(-1, 0, 0), -low.x, 0, 4, 6, 2);
		add(Vector3(0, 1, 0), high.y, 2, 6, 7, 3);
		add(Vector3(0, -1, 0), -low.y, 0, 1, 5, 4);
		add(Vector3(0, 0, 1), high.z, 4, 5, 7, 6);
		add(Vector3(0, 0, -1), -low.z, 0, 2, 3, 1);
		return result;
	}

	// Keeps the part with normal . x <= d. Returns false if nothing is left.
	bool clip(const Plane &p_plane, real_t p_epsilon) {
		LocalVector<Face> kept;
		LocalVector<Vector3> on_plane;
		for (const Face &face : faces) {
			Face clipped;
			clipped.plane = face.plane;
			clipped.cut = face.cut;
			const uint32_t count = face.vertices.size();
			for (uint32_t i = 0; i < count; i++) {
				const Vector3 &a = face.vertices[i];
				const Vector3 &b = face.vertices[(i + 1) % count];
				const real_t da = p_plane.normal.dot(a) - p_plane.d;
				const real_t db = p_plane.normal.dot(b) - p_plane.d;
				if (da <= p_epsilon) {
					clipped.vertices.push_back(a);
					if (Math::abs(da) <= p_epsilon) {
						on_plane.push_back(a);
					}
				}
				if ((da < -p_epsilon && db > p_epsilon) || (da > p_epsilon && db < -p_epsilon)) {
					const Vector3 hit = a + (b - a) * (da / (da - db));
					clipped.vertices.push_back(hit);
					on_plane.push_back(hit);
				}
			}
			if (clipped.vertices.size() >= 3) {
				kept.push_back(clipped);
			}
		}
		if (kept.size() < 3) {
			faces.clear();
			return false;
		}
		// Close the cut with a cap polygon made of the points that lie on the plane.
		LocalVector<Vector3> cap_points;
		for (const Vector3 &point : on_plane) {
			bool duplicate = false;
			for (const Vector3 &existing : cap_points) {
				if (existing.distance_squared_to(point) < p_epsilon * p_epsilon * real_t(4.0)) {
					duplicate = true;
					break;
				}
			}
			if (!duplicate) {
				cap_points.push_back(point);
			}
		}
		faces = kept;
		if (cap_points.size() >= 3) {
			Vector3 center;
			for (const Vector3 &point : cap_points) {
				center += point;
			}
			center /= real_t(cap_points.size());
			// Order the points around the center, in the plane.
			const Vector3 u = (cap_points[0] - center).normalized();
			const Vector3 v = p_plane.normal.cross(u);
			struct Angled {
				real_t angle;
				Vector3 point;
				bool operator<(const Angled &p_other) const { return angle < p_other.angle; }
			};
			LocalVector<Angled> ordered;
			for (const Vector3 &point : cap_points) {
				const Vector3 offset = point - center;
				ordered.push_back({ Math::atan2(offset.dot(v), offset.dot(u)), point });
			}
			ordered.sort();
			Face cap;
			cap.plane = p_plane;
			cap.cut = true;
			for (const Angled &entry : ordered) {
				cap.vertices.push_back(entry.point);
			}
			faces.push_back(cap);
		}
		return true;
	}

	real_t volume(Vector3 *r_centroid) const {
		// Tetrahedra from an interior point to the triangles of every face.
		Vector3 reference;
		uint32_t vertex_count = 0;
		for (const Face &face : faces) {
			for (const Vector3 &vertex : face.vertices) {
				reference += vertex;
				vertex_count++;
			}
		}
		if (vertex_count == 0) {
			return 0.0;
		}
		reference /= real_t(vertex_count);
		real_t total = 0.0;
		Vector3 weighted;
		for (const Face &face : faces) {
			// Fan around the polygon's own center so unordered concave-looking input stays sane.
			Vector3 center;
			for (const Vector3 &vertex : face.vertices) {
				center += vertex;
			}
			center /= real_t(face.vertices.size());
			// Sort the polygon by angle around its normal for a consistent fan.
			const Vector3 u = (face.vertices[0] - center).normalized();
			const Vector3 v = face.plane.normal.cross(u);
			LocalVector<Pair<real_t, Vector3>> ordered;
			for (const Vector3 &vertex : face.vertices) {
				const Vector3 offset = vertex - center;
				ordered.push_back(Pair<real_t, Vector3>(Math::atan2(offset.dot(v), offset.dot(u)), vertex));
			}
			for (uint32_t i = 1; i < ordered.size(); i++) { // Insertion sort; polygons are small.
				Pair<real_t, Vector3> item = ordered[i];
				int32_t j = int32_t(i) - 1;
				while (j >= 0 && ordered[j].first > item.first) {
					ordered[j + 1] = ordered[j];
					j--;
				}
				ordered[j + 1] = item;
			}
			for (uint32_t i = 0; i < ordered.size(); i++) {
				const Vector3 &a = ordered[i].second;
				const Vector3 &b = ordered[(i + 1) % ordered.size()].second;
				const real_t tetra = Math::abs((center - reference).dot((a - reference).cross(b - reference))) / real_t(6.0);
				// Centroid of the tetrahedron (reference, center, a, b).
				weighted += (reference + center + a + b) * real_t(0.25) * tetra;
				total += tetra;
			}
		}
		if (r_centroid) {
			*r_centroid = total > 0.0 ? weighted / total : reference;
		}
		return total;
	}
};

} // namespace

AABB bounds_of_planes(const Vector<Plane> &p_planes) {
	if (p_planes.size() < 4) {
		return AABB();
	}
	const Vector<Vector3> corners = Geometry3D::compute_convex_mesh_points(p_planes.ptr(), p_planes.size());
	if (corners.size() < 4) {
		return AABB();
	}
	AABB bounds(corners[0], Vector3());
	for (const Vector3 &corner : corners) {
		bounds.expand_to(corner);
	}
	return bounds;
}

void generate_seeds(const Vector<Plane> &p_planes, int p_count, const Vector3 &p_focus, real_t p_concentration, RandomPCG &r_random, LocalVector<Vector3> &r_seeds) {
	r_seeds.clear();
	if (p_count < 1) {
		return;
	}
	const AABB bounds = bounds_of_planes(p_planes);
	if (bounds.size == Vector3()) {
		return;
	}
	const int candidates = 1 + int(MAX(p_concentration, real_t(0.0)) * real_t(3.0));
	for (int i = 0; i < p_count; i++) {
		Vector3 best;
		real_t best_distance = Math::INF;
		bool found = false;
		for (int c = 0; c < candidates; c++) {
			// Rejection sampling inside the body; the bounds are never empty, so this ends quickly.
			Vector3 point;
			bool ok = false;
			for (int attempt = 0; attempt < 200 && !ok; attempt++) {
				point = bounds.position + Vector3(r_random.randf(), r_random.randf(), r_random.randf()) * bounds.size;
				ok = is_inside(p_planes, point, real_t(0.0));
			}
			if (!ok) {
				continue;
			}
			const real_t distance = point.distance_squared_to(p_focus);
			if (distance < best_distance) {
				best_distance = distance;
				best = point;
				found = true;
			}
		}
		if (found) {
			r_seeds.push_back(best);
		}
	}
}

bool fracture(const Vector<Plane> &p_planes, const LocalVector<Vector3> &p_seeds, LocalVector<Piece> &r_pieces, real_t p_min_volume_fraction, real_t p_min_seed_distance) {
	r_pieces.clear();
	const AABB bounds = bounds_of_planes(p_planes);
	if (bounds.size == Vector3() || !bounds.size.is_finite()) {
		return false;
	}
	// Tolerance scales with the body so tiny and huge bodies behave alike.
	const real_t epsilon = MAX(bounds.size.length(), real_t(1e-3)) * real_t(1e-5);

	// The body itself: the bounds, clipped by every plane.
	Polyhedron body = Polyhedron::from_bounds(bounds.grow(bounds.size.length() * real_t(0.1)));
	for (const Plane &plane : p_planes) {
		if (!body.clip(plane, epsilon)) {
			return false;
		}
	}
	// Faces that already existed are the original surface; everything created from here on is a cut.
	for (Face &face : body.faces) {
		face.cut = false;
	}
	const real_t total_volume = body.volume(nullptr);
	if (!(total_volume > 0.0) || !Math::is_finite(total_volume)) {
		return false;
	}

	// Drop seeds that nearly coincide with an earlier one.
	LocalVector<Vector3> seeds;
	for (const Vector3 &seed : p_seeds) {
		bool duplicate = !seed.is_finite();
		for (const Vector3 &other : seeds) {
			if (other.distance_to(seed) < p_min_seed_distance) {
				duplicate = true;
				break;
			}
		}
		if (!duplicate) {
			seeds.push_back(seed);
		}
	}
	if (seeds.is_empty()) {
		return false;
	}

	for (uint32_t i = 0; i < seeds.size(); i++) {
		Polyhedron cell = body;
		bool alive = true;
		for (uint32_t j = 0; j < seeds.size() && alive; j++) {
			if (i == j) {
				continue;
			}
			// Keep the half space that is closer to seed i than to seed j.
			const Vector3 normal = (seeds[j] - seeds[i]).normalized();
			alive = cell.clip(Plane(normal, normal.dot((seeds[i] + seeds[j]) * real_t(0.5))), epsilon);
		}
		if (!alive) {
			continue;
		}
		Piece piece;
		piece.volume = cell.volume(&piece.centroid);
		if (!(piece.volume > total_volume * p_min_volume_fraction) || piece.volume <= 0.0) {
			continue;
		}
		for (const Face &face : cell.faces) {
			for (const Vector3 &vertex : face.vertices) {
				bool duplicate = false;
				for (const Vector3 &existing : piece.points) {
					if (existing.distance_squared_to(vertex) < epsilon * epsilon * real_t(4.0)) {
						duplicate = true;
						break;
					}
				}
				if (!duplicate) {
					piece.points.push_back(vertex);
				}
			}
		}
		piece.faces = cell.faces;
		r_pieces.push_back(piece);
	}
	return !r_pieces.is_empty();
}

} // namespace ConvexFracture
