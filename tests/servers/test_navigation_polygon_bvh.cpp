/**************************************************************************/
/*  test_navigation_polygon_bvh.cpp                                       */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_navigation_polygon_bvh)

#include "modules/modules_enabled.gen.h"

#include <cfloat>

#ifdef MODULE_NAVIGATION_2D_ENABLED
#include "modules/navigation_2d/2d/nav_polygon_bvh_2d.h"

TEST_CASE("[NavigationBVH2D] Nearest polygon matches the exhaustive scan") {
	for (int count : { 0, 1, 8, 9, 400 }) {
		LocalVector<Nav2D::Polygon> polygons;
		polygons.resize(count);
		for (int i = 0; i < count; i++) {
			const real_t x = (i % 20) * 4.0;
			const real_t y = (i / 20) * 4.0;
			polygons[i].vertices.push_back(Vector2(x, y));
			polygons[i].vertices.push_back(Vector2(x + 3.0, y));
			polygons[i].vertices.push_back(Vector2(x, y + 3.0));
		}

		NavPolygonBVH2D bvh;
		bvh.build(polygons);
		CHECK(bvh.is_empty() == (count <= 8));
		CHECK((bvh.get_size_bytes() > 0) == (count > 8));

		for (int probe = 0; probe < 80; probe++) {
			const Vector2 query((probe * 17 % 110) - 14.5, (probe * 23 % 100) - 17.25);

			real_t expected_distance = FLT_MAX;
			const Nav2D::Polygon *expected_polygon = nullptr;
			Vector2 expected_point;
			for (const Nav2D::Polygon &polygon : polygons) {
				const Triangle2 triangle(polygon.vertices[0], polygon.vertices[1], polygon.vertices[2]);
				const Vector2 closest = triangle.get_closest_point_to(query);
				const real_t distance = closest.distance_to(query);
				if (distance < expected_distance) {
					expected_distance = distance;
					expected_polygon = &polygon;
					expected_point = closest;
				}
			}

			real_t distance = FLT_MAX;
			const Nav2D::Polygon *found_polygon = nullptr;
			Vector2 found_point;
			bvh.find_closest_point(polygons, query, distance, found_polygon, found_point);
			CHECK(found_polygon == expected_polygon);
			CHECK(distance == doctest::Approx(expected_distance));
			if (found_polygon != nullptr) {
				CHECK(found_point.is_equal_approx(expected_point));
			}
		}

		// Rebuilding must release the old tree and maintain exact query results.
		bvh.build(polygons);
		CHECK(bvh.is_empty() == (count <= 8));
	}
}
#endif // MODULE_NAVIGATION_2D_ENABLED

#ifdef MODULE_NAVIGATION_3D_ENABLED
#include "modules/navigation_3d/3d/nav_polygon_bvh_3d.h"

TEST_CASE("[NavigationBVH3D] Nearest polygon matches the exhaustive scan") {
	for (int count : { 0, 1, 8, 9, 400 }) {
		LocalVector<Nav3D::Polygon> polygons;
		polygons.resize(count);
		for (int i = 0; i < count; i++) {
			const real_t x = (i % 20) * 4.0;
			const real_t z = (i / 20) * 4.0;
			polygons[i].vertices.push_back(Vector3(x, 0.0, z));
			polygons[i].vertices.push_back(Vector3(x + 3.0, 0.0, z));
			polygons[i].vertices.push_back(Vector3(x, 0.0, z + 3.0));
		}

		NavPolygonBVH3D bvh;
		bvh.build(polygons);
		CHECK(bvh.is_empty() == (count <= 8));
		CHECK((bvh.get_size_bytes() > 0) == (count > 8));

		for (int probe = 0; probe < 80; probe++) {
			const Vector3 query((probe * 17 % 110) - 14.5, (probe % 9) - 4.25, (probe * 23 % 100) - 17.25);

			real_t expected_distance = FLT_MAX;
			const Nav3D::Polygon *expected_polygon = nullptr;
			Vector3 expected_point;
			for (const Nav3D::Polygon &polygon : polygons) {
				const Face3 face(polygon.vertices[0], polygon.vertices[1], polygon.vertices[2]);
				const Vector3 closest = face.get_closest_point_to(query);
				const real_t distance = closest.distance_to(query);
				if (distance < expected_distance) {
					expected_distance = distance;
					expected_polygon = &polygon;
					expected_point = closest;
				}
			}

			real_t distance = FLT_MAX;
			const Nav3D::Polygon *found_polygon = nullptr;
			Vector3 found_point;
			bvh.find_closest_point(polygons, query, distance, found_polygon, found_point);
			CHECK(found_polygon == expected_polygon);
			CHECK(distance == doctest::Approx(expected_distance));
			if (found_polygon != nullptr) {
				CHECK(found_point.is_equal_approx(expected_point));
			}
		}

		bvh.build(polygons);
		CHECK(bvh.is_empty() == (count <= 8));
	}
}
#endif // MODULE_NAVIGATION_3D_ENABLED
