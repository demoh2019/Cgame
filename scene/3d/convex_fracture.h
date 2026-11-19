/**************************************************************************/
/*  convex_fracture.h                                             */
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

#include "core/math/aabb.h"
#include "core/math/plane.h"
#include "core/math/random_pcg.h"
#include "core/math/vector3.h"
#include "core/templates/local_vector.h"

// Breaks a convex body into convex pieces with a Voronoi diagram: every seed point owns the part of
// the body that is closer to it than to any other seed. The pieces tile the body exactly, so volume
// (and, with uniform density, mass) is conserved. Pure geometry; used by DestructibleBody3D.
namespace ConvexFracture {

struct Face {
	Plane plane; // Faces outward: points of the body satisfy normal . x <= d.
	LocalVector<Vector3> vertices; // The polygon, in no particular winding order.
	bool cut = false; // Created by the fracture rather than part of the original surface.
};

struct Piece {
	LocalVector<Face> faces;
	LocalVector<Vector3> points; // Unique vertices.
	real_t volume = 0.0;
	Vector3 centroid;
};

// Planes of a convex body, facing outward (inside: normal . x <= d), from its vertices.
bool planes_from_points(const Vector<Vector3> &p_points, Vector<Plane> &r_planes);

// Bounding box of the body described by the planes. Empty (zero size) if the planes do not enclose
// a volume.
AABB bounds_of_planes(const Vector<Plane> &p_planes);

bool is_inside(const Vector<Plane> &p_planes, const Vector3 &p_point, real_t p_epsilon = 1e-4);

// Random points inside the body. With `p_concentration` > 0 they cluster toward `p_focus`
// (the nearest of 1 + 3 * concentration candidates is kept), as an impact shatters mostly the area
// it hits. Deterministic for a given generator state.
void generate_seeds(const Vector<Plane> &p_planes, int p_count, const Vector3 &p_focus, real_t p_concentration, RandomPCG &r_random, LocalVector<Vector3> &r_seeds);

// Voronoi pieces of the body for the given seeds. Seeds closer than `p_min_seed_distance` to an
// earlier one are skipped, and pieces smaller than `p_min_volume_fraction` of the whole body are
// dropped (they would only add collision cost). Returns false if the body is invalid or no
// piece remains.
bool fracture(const Vector<Plane> &p_planes, const LocalVector<Vector3> &p_seeds, LocalVector<Piece> &r_pieces, real_t p_min_volume_fraction = 1e-3, real_t p_min_seed_distance = 1e-4);

} // namespace ConvexFracture
