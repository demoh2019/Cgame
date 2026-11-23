/**************************************************************************/
/*  test_pcg_spatial_filter_3d.h                                          */
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

#include "../pcg_spatial_filter_3d.h"

#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGSpatialFilter3D {

TEST_CASE("[PCGSpatialFilter3D] stable ordering, height-aware spacing and exact boundary") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	PackedVector3Array p;
	for (const Vector3 &point : { Vector3(0, 0, 0), Vector3(0.25, 0, 0),
				 Vector3(0.25, 3, 0), Vector3(2, 0, 0), Vector3(0, 0, 2),
				 Vector3(-2, 0, 0), Vector3(0.25, 3, 0), Vector3(2, 0, 2) }) {
		p.push_back(point);
	}
	const PackedVector3Array original = p;
	const PackedInt32Array out = filter->filter_indices(p, 2.0);
	REQUIRE(out.size() == 6);
	CHECK(out[0] == 0);
	CHECK(out[1] == 2);
	CHECK(out[2] == 3);
	CHECK(out[3] == 4);
	CHECK(out[4] == 5);
	CHECK(out[5] == 7);
	CHECK(p == original);
	CHECK(filter->filter_indices(p, 2.0) == out);
	CHECK(filter->filter_indices(p, 0.0).size() == p.size());
	const PackedInt32Array capped = filter->filter_indices(p, 2.0, 2);
	REQUIRE(capped.size() == 2);
	CHECK(capped[0] == 0);
	CHECK(capped[1] == 2);
}

TEST_CASE("[PCGSpatialFilter3D] negative and adjacent spatial cells") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	PackedVector3Array p;
	for (const Vector3 &point : { Vector3(0.95, 0.95, 0.95),
				 Vector3(1.05, 1.05, 1.05), Vector3(-0.1, -0.1, -0.1),
				 Vector3(-0.25, -0.2, -0.2), Vector3(3, 3, 3) }) {
		p.push_back(point);
	}
	const PackedInt32Array out = filter->filter_indices(p, 1.0);
	REQUIRE(out.size() == 3);
	CHECK(out[0] == 0);
	CHECK(out[1] == 2);
	CHECK(out[2] == 4);
}

TEST_CASE("[PCGSpatialFilter3D] atomic invalid input rejection and bounded output") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	PackedVector3Array p;
	p.push_back(Vector3(0, 0, 0));
	p.push_back(Vector3(1, 0, 0));
	CHECK(filter->filter_indices(p, -1.0).is_empty());
	CHECK(filter->filter_indices(p, 0.01).is_empty());
	CHECK(filter->filter_indices(p, Math::NaN).is_empty());
	CHECK(filter->filter_indices(p, Math::INF).is_empty());
	CHECK(filter->filter_indices(p, 10001.0).is_empty());
	CHECK(filter->filter_indices(p, 1.0, -1).is_empty());
	CHECK(filter->filter_indices(p, 1.0, 4097).is_empty());
	CHECK(filter->filter_indices(p, 1.0, 0).is_empty());
	p.push_back(Vector3(0, Math::NaN, 0));
	CHECK(filter->filter_indices(p, 1.0).is_empty());
	p.remove_at(2);
	p.push_back(Vector3(0, 0, 10000001));
	CHECK(filter->filter_indices(p, 1.0).is_empty());
	p.resize(16385);
	CHECK(filter->filter_indices(p, 1.0).is_empty());
	p.resize(0);
	for (int i = 0; i < 16384; ++i) {
		p.push_back(Vector3(i * 2.0, 0, 0));
	}
	const PackedInt32Array capped = filter->filter_indices(p, 1.0);
	REQUIRE(capped.size() == 4096);
	CHECK(capped[0] == 0);
	CHECK(capped[4095] == 4095);
}

TEST_CASE("[PCGSpatialFilter3D] scaled footprints respect vertical terraces and original-order indices") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array points = { Vector3(0, 0, 0), Vector3(0.9, 0, 0),
		Vector3(3, 0, 0), Vector3(3.8, 0, 0), Vector3(-2.6, 0, 0),
		Vector3(0.9, 3, 0) };
	const PackedFloat32Array scales = { 0.5f, 2.0f, 1.0f, 0.5f, 1.2f, 2.0f };
	const PackedInt32Array large_first = filter->filter_indices_scaled(points, scales, 1.0);
	REQUIRE(large_first.size() == 5);
	CHECK(large_first[0] == 1); // Larger bush wins over the smaller neighbor.
	CHECK(large_first[1] == 2);
	CHECK(large_first[2] == 3); // Exactly enough room after a smaller footprint.
	CHECK(large_first[3] == 4);
	CHECK(large_first[4] == 5); // Same horizontal position, but higher terrace.
	const PackedInt32Array original_first = filter->filter_indices_scaled(points, scales, 1.0, 4096, false);
	REQUIRE(original_first.size() == 5);
	CHECK(original_first[0] == 0);
	CHECK(original_first[1] == 2);
	CHECK(original_first[4] == 5);
	const PackedInt32Array zero = filter->filter_indices_scaled(points, scales, 0.0, 2);
	REQUIRE(zero.size() == 2);
	CHECK(zero[0] == 0);
	CHECK(zero[1] == 1);

	PackedFloat32Array ones;
	ones.resize(points.size());
	for (int i = 0; i < points.size(); ++i) {
		ones.set(i, 1.0f);
	}
	CHECK(filter->filter_indices_scaled(points, ones, 1.0) == filter->filter_indices(points, 1.0));
	CHECK(filter->filter_indices_scaled(points, scales, 1.0) == large_first);
	CHECK(points[0] == Vector3(0, 0, 0));
	CHECK(scales[0] == 0.5f);
}

TEST_CASE("[PCGSpatialFilter3D] scaled 5x5x5 bucket boundaries and all-or-nothing validation") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array crossing = {
		Vector3(0.99, -1.0, 0.99), Vector3(2.01, -1.0, 0.99), Vector3(0.99, 1.2, 0.99)
	};
	const PackedFloat32Array big = { 2.0f, 2.0f, 2.0f };
	const PackedInt32Array picked = filter->filter_indices_scaled(crossing, big, 1.0, 4096, false);
	REQUIRE(picked.size() == 2);
	CHECK(picked[0] == 0);
	CHECK(picked[1] == 2); // Height difference > 2*spacing is allowed.
	const PackedVector3Array edge = { Vector3(0, 0, 0), Vector3(1.25, 0, 0) };
	CHECK(filter->filter_indices_scaled(edge, { 0.5f, 2.0f }, 1.0).size() == 2);
	ERR_PRINT_OFF
	CHECK(filter->filter_indices_scaled(crossing, { 1.0f }, 1.0).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, -1.0).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, 0.01).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, Math::INF).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, 1.0, -1).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, 1.0, 4097).is_empty());
	PackedFloat32Array invalid_scales = big;
	invalid_scales.set(1, Math::NaN);
	CHECK(filter->filter_indices_scaled(crossing, invalid_scales, 1.0).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, { 2.0f, 0.49f, 1.0f }, 1.0).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, { 2.0f, 2.01f, 1.0f }, 1.0).is_empty());
	const PackedVector3Array invalid = { Vector3(0, 0, 0), Vector3(0, Math::NaN, 0) };
	CHECK(filter->filter_indices_scaled(invalid, { 1.0f, 1.0f }, 1.0).is_empty());
	ERR_PRINT_ON
}

TEST_CASE("[PCGSpatialFilter3D] exclusion spheres apply before spacing and preserve source IDs") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array candidates = {
		Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0),
		Vector3(6, 0, 0), Vector3(0, 3, 0), Vector3(1, 0, 0),
		Vector3(8, 0, 0)
	};
	const PackedVector3Array centers = { Vector3(0, 0, 0), Vector3(5, 0, 0) };
	const PackedFloat64Array radii = { 1.0, 1.0 };
	const PackedInt32Array expected = { 1, 4, 6 };
	CHECK(filter->filter_indices_excluding(candidates, centers, radii, 3.0) == expected);
	CHECK(filter->filter_indices_excluding(candidates, centers, radii, 3.0) == expected);
	CHECK(filter->filter_indices_excluding(candidates, {}, {}, 3.0) ==
			filter->filter_indices(candidates, 3.0));
	CHECK(filter->filter_indices_excluding(candidates, centers, radii, 3.0, 2).size() == 2);
	CHECK(filter->filter_indices_excluding(candidates, centers, radii, 0.0) == expected);
	CHECK(candidates[0] == Vector3(0, 0, 0));
	CHECK(centers[1] == Vector3(5, 0, 0));
	// Excluded points must never occupy spatial hash cells.
	const PackedInt32Array unblocked = { 1, 2 };
	CHECK(filter->filter_indices_excluding(
				  { Vector3(0, 0, 0), Vector3(0.75, 0, 0), Vector3(2.75, 0, 0) },
				  { Vector3(0, 0, 0) }, { 0.5 }, 2.0) == unblocked);
	// Full 3D radius: an elevated point is outside an exclusion beneath it.
	const PackedInt32Array elevated = { 1 };
	CHECK(filter->filter_indices_excluding(
				  { Vector3(0, 0, 0), Vector3(0, 3, 0) },
				  { Vector3(0, 0, 0) }, { 2.0 }, 2.0) == elevated);
}

TEST_CASE("[PCGSpatialFilter3D] exclusions validate complete batch atomically") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array candidates = { Vector3(0, 0, 0), Vector3(3, 0, 0) };
	const PackedVector3Array centers = { Vector3(0, 0, 0) };
	const PackedFloat64Array radii = { 1.0 };
	CHECK(filter->filter_indices_excluding(candidates, centers, radii, 1.0).size() == 1);
	CHECK(filter->filter_indices_excluding(candidates, centers, {}, 1.0).is_empty());
	CHECK(filter->filter_indices_excluding(candidates, centers, { -1.0 }, 1.0).is_empty());
	CHECK(filter->filter_indices_excluding(candidates, centers, { Math::NaN }, 1.0).is_empty());
	CHECK(filter->filter_indices_excluding(candidates, centers, { Math::INF }, 1.0).is_empty());
	CHECK(filter->filter_indices_excluding(candidates, centers, { 10001.0 }, 1.0).is_empty());
	CHECK(filter->filter_indices_excluding(candidates,
						{ Vector3(Math::INF, 0, 0) }, radii, 1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding(candidates,
						{ Vector3(10000001, 0, 0) }, radii, 1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding(
						{ Vector3(0, 0, 0), Vector3(Math::NaN, 0, 0) },
						centers, radii, 1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding(candidates, centers, radii, -1.0).is_empty());
	CHECK(filter->filter_indices_excluding(candidates, centers, radii, 0.01).is_empty());
	CHECK(filter->filter_indices_excluding(candidates, centers, radii, 1.0, -1).is_empty());
	CHECK(filter->filter_indices_excluding(candidates, centers, radii, 1.0, 4097).is_empty());
	PackedVector3Array many_centers;
	PackedFloat64Array many_radii;
	for (int i = 0; i < 129; ++i) {
		many_centers.push_back(Vector3(i, 0, 0));
		many_radii.push_back(1.0);
	}
	CHECK(filter->filter_indices_excluding(
						candidates, many_centers, many_radii, 1.0)
					.is_empty());
	many_centers.resize(128);
	many_radii.resize(128);
	CHECK(filter->filter_indices_excluding(
						candidates, many_centers, many_radii, 1.0)
					.is_empty()); // Both candidates excluded.
	CHECK(filter->filter_indices_excluding(candidates, {}, {}, 1.0, 0).is_empty());
}

TEST_CASE("[PCGSpatialFilter3D] mixed sphere and box exclusion preserves original candidate IDs") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array points = {
		Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0),
		Vector3(5, 0, 0), Vector3(6, 0, 0), Vector3(8, 0, 0),
		Vector3(2, 3, 0), Vector3(-4, 0, 0)
	};
	const PackedVector3Array centers = { Vector3(0, 0, 0) };
	const PackedFloat64Array radii = { 1.0 };
	const PackedVector3Array box_mins = { Vector3(1.5, -1, -1), Vector3(8, 0, 0) };
	const PackedVector3Array box_maxs = { Vector3(3, 1, 1), Vector3(8, 0, 0) };
	const PackedInt32Array expected = { 3, 6, 7 };
	CHECK(filter->filter_indices_excluding_volumes(points, centers, radii,
				  box_mins, box_maxs, 2.0) == expected);
	CHECK(filter->filter_indices_excluding_volumes(points, centers, radii,
				  box_mins, box_maxs, 2.0) == expected);
	const PackedInt32Array zero_spacing = { 3, 4, 6, 7 };
	CHECK(filter->filter_indices_excluding_volumes(points, centers, radii,
				  box_mins, box_maxs, 0.0) == zero_spacing);
	const PackedInt32Array capped = { 3, 6 };
	CHECK(filter->filter_indices_excluding_volumes(points, centers, radii,
				  box_mins, box_maxs, 2.0, 2) == capped);
	// Empty boxes preserve the existing sphere-only API bit-for-bit.
	CHECK(filter->filter_indices_excluding_volumes(points, centers, radii,
				  {}, {}, 2.0) == filter->filter_indices_excluding(points, centers, radii, 2.0));
	// Empty sphere and box inputs preserve the original spatial filter.
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {}, {}, {}, 2.0) ==
			filter->filter_indices(points, 2.0));
	// An excluded candidate never occupies a spatial-hash cell.
	const PackedInt32Array surviving = { 1, 2 };
	CHECK(filter->filter_indices_excluding_volumes(
				  { Vector3(0, 0, 0), Vector3(0.9, 0, 0), Vector3(3, 0, 0) },
				  {}, {}, { Vector3(0, -1, -1) }, { Vector3(0, 1, 1) },
				  2.0) == surviving);
	CHECK(points[0] == Vector3(0, 0, 0)); // No mutation.
}

TEST_CASE("[PCGSpatialFilter3D] mixed volumes reject invalid boxes and points atomically") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array points = { Vector3(0, 0, 0), Vector3(4, 0, 0) };
	const PackedVector3Array box_mins = { Vector3(-1, -1, -1) };
	const PackedVector3Array box_maxs = { Vector3(1, 1, 1) };
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {},
						box_mins, box_maxs, 1.0)
					.size() == 1);
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {},
						box_mins, {}, 1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {},
						box_maxs, box_mins, 1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {},
						{ Vector3(Math::NaN, 0, 0) }, box_maxs, 1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {},
						box_mins, { Vector3(Math::INF, 1, 1) }, 1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {},
						{ Vector3(10000001, 0, 0) }, box_maxs, 1.0)
					.is_empty());
	// Reject invalid candidates even when they fall inside an exclusion box.
	CHECK(filter->filter_indices_excluding_volumes(
						{ Vector3(0, 0, 0), Vector3(Math::NaN, 0, 0) }, {}, {},
						box_mins, box_maxs, 1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_volumes(points, { Vector3(0, 0, 0) },
						{}, box_mins, box_maxs, 1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {},
						box_mins, box_maxs, Math::INF)
					.is_empty());
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {},
						box_mins, box_maxs, 1.0, 4097)
					.is_empty());
	PackedVector3Array many_mins;
	PackedVector3Array many_maxs;
	for (int i = 0; i < 129; ++i) {
		many_mins.push_back(Vector3(i, -1, -1));
		many_maxs.push_back(Vector3(i + 0.2, 1, 1));
	}
	CHECK(filter->filter_indices_excluding_volumes(points, {}, {},
						many_mins, many_maxs, 1.0)
					.is_empty());
}

TEST_CASE("[PCGSpatialFilter3D] seeded density is stable by ID across reorder and positions") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	PackedVector3Array candidates;
	for (int i = 0; i < 9; ++i) {
		candidates.push_back(Vector3(i * 2, 0, 0));
	}
	const PackedFloat32Array densities = { 1.0f, 0.0f, 0.5f, 0.25f, 0.9f, 1.0f, 0.1f, 0.2f, 0.75f };
	const PackedInt32Array ids = { 100, 101, 102, 103, 104, 105, 106, 107, 108 };
	const PackedInt32Array expected = { 0, 2, 4, 5, 8 };
	CHECK(filter->filter_indices_density(candidates, densities, ids, 7) == expected);
	CHECK(filter->filter_indices_density(candidates, densities, ids, 7) == expected);
	CHECK(filter->filter_indices_density(candidates, densities, ids, 8) ==
			PackedInt32Array({ 0, 4, 5, 8 }));
	CHECK(filter->filter_indices_density(candidates, densities, ids, 7, 3) ==
			PackedInt32Array({ 0, 2, 4 }));
	PackedVector3Array reversed_positions;
	PackedFloat32Array reversed_densities;
	PackedInt32Array reversed_ids;
	for (int i = 8; i >= 0; --i) {
		reversed_positions.push_back(candidates[i] + Vector3(0, 20, 0));
		reversed_densities.push_back(densities[i]);
		reversed_ids.push_back(ids[i]);
	}
	CHECK(filter->filter_indices_density(reversed_positions, reversed_densities,
				  reversed_ids, 7) == PackedInt32Array({ 0, 3, 4, 6, 8 }));
	const PackedFloat32Array binary = { 1.0f, 0.0f, 1.0f };
	const PackedInt32Array binary_ids = { 3, 4, 5 };
	CHECK(filter->filter_indices_density(
				  { Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0) },
				  binary, binary_ids, 99) == PackedInt32Array({ 0, 2 }));
	CHECK(candidates[0] == Vector3(0, 0, 0));
	CHECK(ids[0] == 100);
}

TEST_CASE("[PCGSpatialFilter3D] density rejects invalid input atomically and caps outputs") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array points = { Vector3(0, 0, 0), Vector3(2, 0, 0) };
	const PackedFloat32Array valid_densities = { 1.0f, 1.0f };
	const PackedInt32Array valid_ids = { 1, 2 };
	CHECK(filter->filter_indices_density(points, valid_densities, valid_ids, 7, 0).is_empty());
	CHECK(filter->filter_indices_density(points, { 1.0f }, valid_ids, 7).is_empty());
	CHECK(filter->filter_indices_density(points, valid_densities, { 1 }, 7).is_empty());
	CHECK(filter->filter_indices_density(points, valid_densities, { 1, 1 }, 7).is_empty());
	CHECK(filter->filter_indices_density(points, valid_densities, { -1, 2 }, 7).is_empty());
	CHECK(filter->filter_indices_density(points, valid_densities, { 2147483647, 2 }, 7).is_empty());
	CHECK(filter->filter_indices_density(points, { Math::NaN, 1.0f }, valid_ids, 7).is_empty());
	CHECK(filter->filter_indices_density(points, { 1.0f, float(Math::INF) }, valid_ids, 7).is_empty());
	CHECK(filter->filter_indices_density(points, { -0.01f, 1.0f }, valid_ids, 7).is_empty());
	CHECK(filter->filter_indices_density(points, { 1.01f, 1.0f }, valid_ids, 7).is_empty());
	CHECK(filter->filter_indices_density(points, valid_densities, valid_ids, -1).is_empty());
	CHECK(filter->filter_indices_density(points, valid_densities, valid_ids, 2147483647LL).is_empty());
	CHECK(filter->filter_indices_density(points, valid_densities, valid_ids, 7, -1).is_empty());
	CHECK(filter->filter_indices_density(points, valid_densities, valid_ids, 7, 4097).is_empty());
	CHECK(filter->filter_indices_density(
						{ Vector3(0, 0, 0), Vector3(Math::NaN, 0, 0) },
						valid_densities, valid_ids, 7)
					.is_empty());
	CHECK(filter->filter_indices_density(
						{ Vector3(0, 0, 0), Vector3(10000001, 0, 0) },
						valid_densities, valid_ids, 7)
					.is_empty());
	PackedVector3Array lots_of_points;
	PackedFloat32Array lots_of_densities;
	PackedInt32Array lots_of_ids;
	for (int i = 0; i < 16385; ++i) {
		lots_of_points.push_back(Vector3(i, 0, 0));
		lots_of_densities.push_back(1.0f);
		lots_of_ids.push_back(i);
	}
	CHECK(filter->filter_indices_density(
						lots_of_points, lots_of_densities, lots_of_ids, 7)
					.is_empty());
	lots_of_points.resize(16384);
	lots_of_densities.resize(16384);
	lots_of_ids.resize(16384);
	const PackedInt32Array capped = filter->filter_indices_density(
			lots_of_points, lots_of_densities, lots_of_ids, 7);
	REQUIRE(capped.size() == 4096);
	CHECK(capped[0] == 0);
	CHECK(capped[4095] == 4095);
}

TEST_CASE("[PCGSpatialFilter3D] yaw-oriented boxes combine with spheres and AABBs") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	// With 45-degree yaw, local positive X points toward world negative Z.
	const PackedVector3Array points = {
		Vector3(0, 0, 0), // Inside oriented exclusion.
		Vector3(1.4142135, 0, -1.4142135), // Along the long local X axis; excluded.
		Vector3(1.4142135, 0, 1.4142135), // Short local Z axis; outside.
		Vector3(0, 2, 0), // Above oriented exclusion; AABB below.
		Vector3(4, 0, 0), // Outside oriented volume; in sphere.
		Vector3(-4, 0, -4), // Outside every shape.
	};
	const PackedVector3Array obb_centers = { Vector3(0, 0, 0) };
	const PackedVector3Array obb_extents = { Vector3(3, 1, 0.5) };
	const PackedFloat64Array obb_yaws = { Math::deg_to_rad(45.0) };
	const PackedVector3Array spheres = { Vector3(4, 0, 0) };
	const PackedFloat64Array radii = { 0.1 };
	const PackedVector3Array box_mins = { Vector3(-0.5, 1.5, -0.5) };
	const PackedVector3Array box_maxs = { Vector3(0.5, 2.5, 0.5) };
	const PackedInt32Array expected = { 2, 5 };
	CHECK(filter->filter_indices_excluding_oriented_volumes(
				  points, spheres, radii, box_mins, box_maxs,
				  obb_centers, obb_extents, obb_yaws, 0.0) == expected);
	CHECK(filter->filter_indices_excluding_oriented_volumes(
				  points, spheres, radii, box_mins, box_maxs,
				  obb_centers, obb_extents, obb_yaws, 2.1) == expected);
	const PackedInt32Array first_only = { 2 };
	CHECK(filter->filter_indices_excluding_oriented_volumes(
				  points, spheres, radii, box_mins, box_maxs,
				  obb_centers, obb_extents, obb_yaws, 0.0, 1) == first_only);
	// Empty oriented-volume input is exactly the existing mixed selector.
	CHECK(filter->filter_indices_excluding_oriented_volumes(
				  points, spheres, radii, box_mins, box_maxs, {}, {}, {}, 0.0) ==
			filter->filter_indices_excluding_volumes(
					points, spheres, radii, box_mins, box_maxs, 0.0));
	CHECK(filter->filter_indices_excluding_oriented_volumes(
				  points, {}, {}, {}, {}, {}, {}, {}, 0.0) ==
			filter->filter_indices(points, 0.0));
}

TEST_CASE("[PCGSpatialFilter3D] rotated boxes exclude inclusive faces before spacing") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array points = {
		Vector3(2, 0, 0), // Exactly on local X face, blocked.
		Vector3(2.01, 0, 0), // Outside, should be selected even if near blocked point.
		Vector3(5.0, 0, 0), // Outside and spaced.
		Vector3(0, 1, 0), // Exactly on local Y face, blocked.
		Vector3(0, 1.01, 0), // Above box, outside.
	};
	const PackedVector3Array centers = { Vector3(0, 0, 0) };
	const PackedVector3Array extents = { Vector3(2, 1, 0.5) };
	const PackedFloat64Array yaws = { 0.0 };
	const PackedInt32Array selected = filter->filter_indices_excluding_oriented_volumes(
			points, {}, {}, {}, {}, centers, extents, yaws, 2.5);
	REQUIRE(selected.size() == 2);
	CHECK(selected[0] == 1);
	CHECK(selected[1] == 2);
	// Vertical face and exact zero extents count as an inclusive surface.
	const PackedInt32Array above_plane = { 1 };
	CHECK(filter->filter_indices_excluding_oriented_volumes(
				  { Vector3(0, 0, 0), Vector3(0, 0.01, 0) },
				  {}, {}, {}, {}, centers,
				  { Vector3(0, 0, 0) }, yaws, 0.0) == above_plane);
}

TEST_CASE("[PCGSpatialFilter3D] negative yaw rotates footprint opposite direction") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array candidates = {
		Vector3(1.4142135, 0, 1.4142135), // Inside -45-degree long axis.
		Vector3(1.4142135, 0, -1.4142135), // Outside short axis.
	};
	const PackedInt32Array expected = { 1 };
	CHECK(filter->filter_indices_excluding_oriented_volumes(
				  candidates, {}, {}, {}, {},
				  { Vector3() }, { Vector3(3, 1, 0.5) },
				  { Math::deg_to_rad(-45.0) }, 0.0) == expected);
}

TEST_CASE("[PCGSpatialFilter3D] invalid rotated volumes fail closed atomically") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array points = { Vector3(1, 0, 0), Vector3(3, 0, 0) };
	const PackedVector3Array centers = { Vector3(0, 0, 0) };
	const PackedVector3Array extents = { Vector3(1, 2, 3) };
	const PackedFloat64Array yaws = { 0.4 };
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, {}, yaws, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, extents, {}, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, { Vector3(-1, 1, 1) }, yaws, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, { Vector3(10001, 1, 1) }, yaws, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, extents, { Math::NaN }, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, extents, { Math::INF }, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, extents, { 7.0 }, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, { Vector3(Math::NaN, 0, 0) },
						extents, yaws, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, extents, yaws, -1.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, extents, yaws, 0.01)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, centers, extents, yaws, 0.0, 4097)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						{ Vector3(0, 0, 0), Vector3(Math::NaN, 0, 0) },
						{}, {}, {}, {}, centers, extents, yaws, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, { Vector3(1, 1, 1) },
						{ Vector3(-1, -1, -1) }, centers, extents, yaws, 0.0)
					.is_empty());
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, { Vector3(0, 0, 0) }, { -1.0 }, {}, {},
						centers, extents, yaws, 0.0)
					.is_empty());
	PackedVector3Array excess_centers;
	PackedVector3Array excess_extents;
	PackedFloat64Array excess_yaws;
	for (int i = 0; i < 129; ++i) {
		excess_centers.push_back(Vector3(i, 0, 0));
		excess_extents.push_back(Vector3(1, 1, 1));
		excess_yaws.push_back(0.0);
	}
	CHECK(filter->filter_indices_excluding_oriented_volumes(
						points, {}, {}, {}, {}, excess_centers, excess_extents,
						excess_yaws, 0.0)
					.is_empty());
}

} // namespace TestPCGSpatialFilter3D
