/**************************************************************************/
/*  test_nav_polygon_bvh.cpp                                              */
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

#include "tests/test_macros.h"
#include "core/os/os.h"
#include "core/string/print_string.h"

TEST_FORCE_LINK(test_nav_polygon_bvh)

#include "modules/modules_enabled.gen.h"

#ifdef MODULE_NAVIGATION_2D_ENABLED

#include "modules/navigation_2d/2d/nav_polygon_bvh_2d.h"

namespace TestNavPolygonBVH2D {

static void create_grid(LocalVector<Nav2D::Polygon> &r_polygons, int p_columns, int p_rows) {
	r_polygons.resize(p_columns * p_rows);
	for (int y = 0; y < p_rows; y++) {
		for (int x = 0; x < p_columns; x++) {
			Nav2D::Polygon &polygon = r_polygons[y * p_columns + x];
			const Vector2 origin(x * 4.0, y * 4.0);
			polygon.vertices.push_back(origin);
			polygon.vertices.push_back(origin + Vector2(2, 0));
			polygon.vertices.push_back(origin + Vector2(2, 2));
			polygon.vertices.push_back(origin + Vector2(0, 2));
		}
	}
}

static const Nav2D::Polygon *linear_find(const LocalVector<Nav2D::Polygon> &p_polygons, const Vector2 &p_point, real_t &r_distance, Vector2 &r_position) {
	const Nav2D::Polygon *best = nullptr;
	for (const Nav2D::Polygon &polygon : p_polygons) {
		if (polygon.vertices.size() < 3) {
			continue;
		}
		for (uint32_t i = 2; i < polygon.vertices.size(); i++) {
			Triangle2 triangle(polygon.vertices[0], polygon.vertices[i - 1], polygon.vertices[i]);
			Vector2 closest = triangle.get_closest_point_to(p_point);
			real_t distance = closest.distance_to(p_point);
			if (distance < r_distance) {
				r_distance = distance;
				r_position = closest;
				best = &polygon;
			}
		}
	}
	return best;
}

TEST_CASE("[NavigationBVH2D] Empty input does not allocate") {
	LocalVector<Nav2D::Polygon> polygons;
	NavPolygonBVH2D bvh;
	bvh.build(polygons);
	CHECK(bvh.is_empty());
	CHECK(bvh.get_size_bytes() == 0);
}

TEST_CASE("[NavigationBVH2D] Eight polygons keep zero-cost linear fallback") {
	LocalVector<Nav2D::Polygon> polygons;
	create_grid(polygons, 4, 2);
	NavPolygonBVH2D bvh;
	bvh.build(polygons);
	CHECK(bvh.is_empty());
	CHECK(bvh.get_size_bytes() == 0);
	const Nav2D::Polygon *found = nullptr;
	real_t distance = 1e20;
	Vector2 closest;
	bvh.find_closest_point(polygons, Vector2(13, 5), distance, found, closest);
	CHECK(found == &polygons[7]);
	CHECK(distance == 0);
}

TEST_CASE("[NavigationBVH2D] Nine polygons switch to bounded BVH") {
	LocalVector<Nav2D::Polygon> polygons;
	create_grid(polygons, 3, 3);
	NavPolygonBVH2D bvh;
	bvh.build(polygons);
	CHECK_FALSE(bvh.is_empty());
	CHECK(bvh.get_size_bytes() > 0);
	CHECK(bvh.get_size_bytes() < uint64_t(polygons.size()) * 256);
}

TEST_CASE("[NavigationBVH2D] Large grid matches original polygon scan") {
	LocalVector<Nav2D::Polygon> polygons;
	create_grid(polygons, 32, 32);
	NavPolygonBVH2D bvh;
	bvh.build(polygons);
	REQUIRE_FALSE(bvh.is_empty());
	for (int i = 0; i < 100; i++) {
		const Vector2 point(real_t((i * 37) % 145) + real_t(0.27), real_t((i * 29) % 139) + real_t(0.41));
		const Nav2D::Polygon *actual = nullptr;
		const Nav2D::Polygon *expected = nullptr;
		Vector2 actual_point;
		Vector2 expected_point;
		real_t actual_distance = 1e20;
		real_t expected_distance = 1e20;
		bvh.find_closest_point(polygons, point, actual_distance, actual, actual_point);
		expected = linear_find(polygons, point, expected_distance, expected_point);
		CHECK(actual == expected);
		CHECK(Math::is_equal_approx(actual_distance, expected_distance));
		CHECK(actual_point.is_equal_approx(expected_point));
	}
}

TEST_CASE("[NavigationBVH2D] Equal-distance ties retain original polygon order") {
	LocalVector<Nav2D::Polygon> polygons;
	create_grid(polygons, 3, 3);
	for (uint32_t i = 1; i < polygons.size(); i++) {
		polygons[i].vertices = polygons[0].vertices;
	}
	NavPolygonBVH2D bvh;
	bvh.build(polygons);
	const Nav2D::Polygon *found = nullptr;
	real_t distance = 1e20;
	Vector2 point;
	bvh.find_closest_point(polygons, Vector2(1, 1), distance, found, point);
	CHECK(found == &polygons[0]);
}

TEST_CASE("[NavigationBVH2D] Rebuilding smaller input releases BVH memory") {
	LocalVector<Nav2D::Polygon> polygons;
	create_grid(polygons, 5, 5);
	NavPolygonBVH2D bvh;
	bvh.build(polygons);
	REQUIRE_FALSE(bvh.is_empty());
	polygons.resize(0);
	bvh.build(polygons);
	CHECK(bvh.is_empty());
	CHECK(bvh.get_size_bytes() == 0);
}

TEST_CASE("[NavigationBVH2D] Existing better match is not overwritten") {
	LocalVector<Nav2D::Polygon> polygons;
	create_grid(polygons, 4, 4);
	NavPolygonBVH2D bvh;
	bvh.build(polygons);
	const Nav2D::Polygon *best = &polygons[3];
	real_t distance = 0;
	Vector2 point(0, 0);
	bvh.find_closest_point(polygons, Vector2(999, 999), distance, best, point);
	CHECK(best == &polygons[3]);
	CHECK(distance == 0);
}


TEST_CASE("[NavigationBVH2D] Benchmark actual BVH lookup versus exhaustive scan") {
	LocalVector<Nav2D::Polygon> polygons;
	create_grid(polygons, 32, 32);
	NavPolygonBVH2D bvh;
	bvh.build(polygons);
	const uint64_t bvh_start = OS::get_singleton()->get_ticks_usec();
	real_t bvh_sum = 0;
	for (int i = 0; i < 512; i++) {
		const Vector2 query(real_t((i * 37) % 145) + 0.27, real_t((i * 29) % 139) + 0.41);
		const Nav2D::Polygon *found = nullptr;
		Vector2 point;
		real_t distance = 1e20;
		bvh.find_closest_point(polygons, query, distance, found, point);
		bvh_sum += distance;
	}
	const uint64_t bvh_us = OS::get_singleton()->get_ticks_usec() - bvh_start;
	const uint64_t linear_start = OS::get_singleton()->get_ticks_usec();
	real_t linear_sum = 0;
	for (int i = 0; i < 512; i++) {
		const Vector2 query(real_t((i * 37) % 145) + 0.27, real_t((i * 29) % 139) + 0.41);
		Vector2 point;
		real_t distance = 1e20;
		linear_find(polygons, query, distance, point);
		linear_sum += distance;
	}
	const uint64_t linear_us = OS::get_singleton()->get_ticks_usec() - linear_start;
	CHECK(Math::is_equal_approx(bvh_sum, linear_sum));
	print_line(vformat("Navigation 2D BVH endpoint benchmark, 1024 polygons x 512 queries: BVH %d us; exhaustive %d us; BVH allocated %d bytes.",
			int64_t(bvh_us), int64_t(linear_us), int64_t(bvh.get_size_bytes())));
}

} // namespace TestNavPolygonBVH2D
#endif // MODULE_NAVIGATION_2D_ENABLED

#ifdef MODULE_NAVIGATION_3D_ENABLED

#include "modules/navigation_3d/3d/nav_polygon_bvh_3d.h"

namespace TestNavPolygonBVH3D {

static void create_grid(LocalVector<Nav3D::Polygon> &r_polygons, int p_columns, int p_rows) {
	r_polygons.resize(p_columns * p_rows);
	for (int z = 0; z < p_rows; z++) {
		for (int x = 0; x < p_columns; x++) {
			Nav3D::Polygon &polygon = r_polygons[z * p_columns + x];
			const Vector3 origin(x * 4.0, 0, z * 4.0);
			polygon.vertices.push_back(origin);
			polygon.vertices.push_back(origin + Vector3(2, 0, 0));
			polygon.vertices.push_back(origin + Vector3(2, 0, 2));
			polygon.vertices.push_back(origin + Vector3(0, 0, 2));
		}
	}
}

static const Nav3D::Polygon *linear_find(const LocalVector<Nav3D::Polygon> &p_polygons, const Vector3 &p_point, real_t &r_distance, Vector3 &r_position) {
	const Nav3D::Polygon *best = nullptr;
	for (const Nav3D::Polygon &polygon : p_polygons) {
		if (polygon.vertices.size() < 3) {
			continue;
		}
		for (uint32_t i = 2; i < polygon.vertices.size(); i++) {
			Face3 triangle(polygon.vertices[0], polygon.vertices[i - 1], polygon.vertices[i]);
			Vector3 closest = triangle.get_closest_point_to(p_point);
			real_t distance = closest.distance_to(p_point);
			if (distance < r_distance) {
				r_distance = distance;
				r_position = closest;
				best = &polygon;
			}
		}
	}
	return best;
}

TEST_CASE("[NavigationBVH3D] Empty input does not allocate") {
	LocalVector<Nav3D::Polygon> polygons;
	NavPolygonBVH3D bvh;
	bvh.build(polygons);
	CHECK(bvh.is_empty());
	CHECK(bvh.get_size_bytes() == 0);
}

TEST_CASE("[NavigationBVH3D] Eight polygons keep zero-cost linear fallback") {
	LocalVector<Nav3D::Polygon> polygons;
	create_grid(polygons, 4, 2);
	NavPolygonBVH3D bvh;
	bvh.build(polygons);
	CHECK(bvh.is_empty());
	CHECK(bvh.get_size_bytes() == 0);
	const Nav3D::Polygon *found = nullptr;
	real_t distance = 1e20;
	Vector3 closest;
	bvh.find_closest_point(polygons, Vector3(13, 1, 5), distance, found, closest);
	CHECK(found == &polygons[7]);
	CHECK(Math::is_equal_approx(distance, real_t(1.0)));
}

TEST_CASE("[NavigationBVH3D] Nine polygons switch to bounded BVH") {
	LocalVector<Nav3D::Polygon> polygons;
	create_grid(polygons, 3, 3);
	NavPolygonBVH3D bvh;
	bvh.build(polygons);
	CHECK_FALSE(bvh.is_empty());
	CHECK(bvh.get_size_bytes() > 0);
	CHECK(bvh.get_size_bytes() < uint64_t(polygons.size()) * 256);
}

TEST_CASE("[NavigationBVH3D] Large grid matches original polygon scan") {
	LocalVector<Nav3D::Polygon> polygons;
	create_grid(polygons, 32, 32);
	NavPolygonBVH3D bvh;
	bvh.build(polygons);
	REQUIRE_FALSE(bvh.is_empty());
	for (int i = 0; i < 100; i++) {
		const Vector3 point(real_t((i * 37) % 145) + real_t(0.27), real_t((i % 5) * 0.3), real_t((i * 29) % 139) + real_t(0.41));
		const Nav3D::Polygon *actual = nullptr;
		const Nav3D::Polygon *expected = nullptr;
		Vector3 actual_point;
		Vector3 expected_point;
		real_t actual_distance = 1e20;
		real_t expected_distance = 1e20;
		bvh.find_closest_point(polygons, point, actual_distance, actual, actual_point);
		expected = linear_find(polygons, point, expected_distance, expected_point);
		CHECK(actual == expected);
		CHECK(Math::is_equal_approx(actual_distance, expected_distance));
		CHECK(actual_point.is_equal_approx(expected_point));
	}
}

TEST_CASE("[NavigationBVH3D] Equal-distance ties retain original polygon order") {
	LocalVector<Nav3D::Polygon> polygons;
	create_grid(polygons, 3, 3);
	for (uint32_t i = 1; i < polygons.size(); i++) {
		polygons[i].vertices = polygons[0].vertices;
	}
	NavPolygonBVH3D bvh;
	bvh.build(polygons);
	const Nav3D::Polygon *found = nullptr;
	real_t distance = 1e20;
	Vector3 point;
	bvh.find_closest_point(polygons, Vector3(1, 0, 1), distance, found, point);
	CHECK(found == &polygons[0]);
}

TEST_CASE("[NavigationBVH3D] Rebuilding smaller input releases BVH memory") {
	LocalVector<Nav3D::Polygon> polygons;
	create_grid(polygons, 5, 5);
	NavPolygonBVH3D bvh;
	bvh.build(polygons);
	REQUIRE_FALSE(bvh.is_empty());
	polygons.resize(0);
	bvh.build(polygons);
	CHECK(bvh.is_empty());
	CHECK(bvh.get_size_bytes() == 0);
}

TEST_CASE("[NavigationBVH3D] Existing better match is not overwritten") {
	LocalVector<Nav3D::Polygon> polygons;
	create_grid(polygons, 4, 4);
	NavPolygonBVH3D bvh;
	bvh.build(polygons);
	const Nav3D::Polygon *best = &polygons[3];
	real_t distance = 0;
	Vector3 point;
	bvh.find_closest_point(polygons, Vector3(999, 999, 999), distance, best, point);
	CHECK(best == &polygons[3]);
	CHECK(distance == 0);
}


TEST_CASE("[NavigationBVH3D] Benchmark actual BVH lookup versus exhaustive scan") {
	LocalVector<Nav3D::Polygon> polygons;
	create_grid(polygons, 32, 32);
	NavPolygonBVH3D bvh;
	bvh.build(polygons);
	const uint64_t bvh_start = OS::get_singleton()->get_ticks_usec();
	real_t bvh_sum = 0;
	for (int i = 0; i < 512; i++) {
		const Vector3 query(real_t((i * 37) % 145) + 0.27, real_t((i % 5) * 0.3), real_t((i * 29) % 139) + 0.41);
		const Nav3D::Polygon *found = nullptr;
		Vector3 point;
		real_t distance = 1e20;
		bvh.find_closest_point(polygons, query, distance, found, point);
		bvh_sum += distance;
	}
	const uint64_t bvh_us = OS::get_singleton()->get_ticks_usec() - bvh_start;
	const uint64_t linear_start = OS::get_singleton()->get_ticks_usec();
	real_t linear_sum = 0;
	for (int i = 0; i < 512; i++) {
		const Vector3 query(real_t((i * 37) % 145) + 0.27, real_t((i % 5) * 0.3), real_t((i * 29) % 139) + 0.41);
		Vector3 point;
		real_t distance = 1e20;
		linear_find(polygons, query, distance, point);
		linear_sum += distance;
	}
	const uint64_t linear_us = OS::get_singleton()->get_ticks_usec() - linear_start;
	CHECK(Math::is_equal_approx(bvh_sum, linear_sum));
	print_line(vformat("Navigation 3D BVH endpoint benchmark, 1024 polygons x 512 queries: BVH %d us; exhaustive %d us; BVH allocated %d bytes.",
			int64_t(bvh_us), int64_t(linear_us), int64_t(bvh.get_size_bytes())));
}

} // namespace TestNavPolygonBVH3D
#endif // MODULE_NAVIGATION_3D_ENABLED
