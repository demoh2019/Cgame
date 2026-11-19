/**************************************************************************/
/*  test_heightmap_terrain_geometry.cpp                                   */
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

TEST_FORCE_LINK(test_heightmap_terrain_geometry)

#include "scene/3d/heightmap_terrain_geometry.h"

namespace TestHeightmapTerrainGeometry {

using namespace HeightmapTerrainGeometry;

static Vector<real_t> make_field(int p_width, int p_depth, const std::function<real_t(int, int)> &p_height) {
	Vector<real_t> data;
	data.resize(p_width * p_depth);
	for (int z = 0; z < p_depth; z++) {
		for (int x = 0; x < p_width; x++) {
			data.write[z * p_width + x] = p_height(x, z);
		}
	}
	return data;
}

static HeightField view(const Vector<real_t> &p_data, int p_width, int p_depth) {
	HeightField field;
	field.heights = p_data.ptr();
	field.width = p_width;
	field.depth = p_depth;
	return field;
}

TEST_CASE("[HeightmapTerrain] Bilinear sampling matches the mesh triangles") {
	// A tilted plane: height = 2x + 3z, so any interpolation inside a quad is exact.
	const Vector<real_t> data = make_field(5, 5, [](int x, int z) { return real_t(2 * x + 3 * z); });
	const HeightField field = view(data, 5, 5);
	CHECK(sample_height(field, 0, 0) == doctest::Approx(0.0));
	CHECK(sample_height(field, 2, 1) == doctest::Approx(7.0));
	CHECK(sample_height(field, 1.5, 2.25) == doctest::Approx(2 * 1.5 + 3 * 2.25));
	CHECK(sample_height(field, 3.75, 0.5) == doctest::Approx(2 * 3.75 + 3 * 0.5));
	// Outside the grid the border value is used, and degenerate fields return zero.
	CHECK(sample_height(field, -10, -10) == doctest::Approx(0.0));
	CHECK(sample_height(field, 100, 100) == doctest::Approx(2 * 4 + 3 * 4));
	CHECK(sample_height(HeightField(), 1, 1) == doctest::Approx(0.0));

	// On a non planar quad the value follows the diagonal from (x+1, z) to (x, z+1).
	Vector<real_t> bump;
	bump.resize(4);
	bump.write[0] = 0; // (0,0)
	bump.write[1] = 0; // (1,0)
	bump.write[2] = 0; // (0,1)
	bump.write[3] = 8; // (1,1)
	const HeightField quad = view(bump, 2, 2);
	CHECK(sample_height(quad, 0.25, 0.25) == doctest::Approx(0.0)); // Lower triangle is flat.
	CHECK(sample_height(quad, 0.75, 0.75) == doctest::Approx(4.0)); // Upper triangle: 8 * (0.5 + 0.5 - 0.5)...
	CHECK(sample_height(quad, 1.0, 1.0) == doctest::Approx(8.0));
}

TEST_CASE("[HeightmapTerrain] Normals of flat and sloped ground") {
	Params params;
	params.spacing = Vector2(2, 2);
	params.height_scale = 1.0;

	const Vector<real_t> flat = make_field(4, 4, [](int, int) { return real_t(5); });
	const HeightField flat_field = view(flat, 4, 4);
	CHECK(sample_normal(flat_field, 1, 1, params).is_equal_approx(Vector3(0, 1, 0)));
	CHECK(sample_normal(flat_field, 0, 0, params).is_equal_approx(Vector3(0, 1, 0))); // Corners too.

	// Rising by 1 m per 2 m along x: slope 0.5, the normal tilts toward -x.
	const Vector<real_t> ramp = make_field(6, 6, [](int x, int) { return real_t(x); });
	const HeightField ramp_field = view(ramp, 6, 6);
	const Vector3 expected = Vector3(-0.5, 1, 0).normalized();
	CHECK(sample_normal(ramp_field, 2, 2, params).is_equal_approx(expected));
	// The border uses a one sided difference with the same slope.
	CHECK(sample_normal(ramp_field, 0, 2, params).is_equal_approx(expected));
	CHECK(sample_normal(ramp_field, 5, 2, params).is_equal_approx(expected));
	CHECK(sample_normal_bilinear(ramp_field, 2.5, 2.5, params).is_equal_approx(expected));

	// Height scale steepens the slope.
	params.height_scale = 4.0;
	CHECK(sample_normal(ramp_field, 2, 2, params).is_equal_approx(Vector3(-2, 1, 0).normalized()));
}

TEST_CASE("[HeightmapTerrain] Chunk mesh has the right vertex and index counts") {
	const Vector<real_t> data = make_field(33, 33, [](int, int) { return real_t(0); });
	const HeightField field = view(data, 33, 33);
	Params params;
	params.skirt_depth = 2.0;

	ChunkMesh mesh;
	REQUIRE(build_chunk(field, 0, 0, 16, 1, params, mesh));
	// 17 x 17 grid plus four skirt rows of 17 vertices.
	CHECK(mesh.vertices.size() == 17 * 17 + 4 * 17);
	CHECK(mesh.normals.size() == mesh.vertices.size());
	CHECK(mesh.uvs.size() == mesh.vertices.size());
	CHECK(mesh.indices.size() == 16 * 16 * 6 + 4 * 16 * 6);
	for (int index : mesh.indices) {
		CHECK(index >= 0);
		CHECK(index < mesh.vertices.size());
	}
	// Lower detail: stride 4 is a 5 x 5 grid.
	REQUIRE(build_chunk(field, 0, 0, 16, 4, params, mesh));
	CHECK(mesh.vertices.size() == 5 * 5 + 4 * 5);
	CHECK(mesh.indices.size() == 4 * 4 * 6 + 4 * 4 * 6);

	// Invalid requests are refused.
	CHECK_FALSE(build_chunk(field, 0, 0, 16, 3, params, mesh)); // 16 is not a multiple of 3.
	CHECK_FALSE(build_chunk(field, 40, 0, 16, 1, params, mesh)); // Outside the field.
	CHECK_FALSE(build_chunk(HeightField(), 0, 0, 16, 1, params, mesh));
	CHECK_FALSE(build_chunk(field, 0, 0, 0, 1, params, mesh));
}

TEST_CASE("[HeightmapTerrain] Positions, uvs and bounds of a chunk") {
	const Vector<real_t> data = make_field(33, 33, [](int x, int z) { return real_t(x + z); });
	const HeightField field = view(data, 33, 33);
	Params params;
	params.spacing = Vector2(2, 3);
	params.height_scale = 0.5;
	params.height_offset = 10.0;
	params.origin = Vector2(-32, -48); // Centers a 32 x 32 sample terrain.
	params.skirt_depth = 1.5;

	ChunkMesh mesh;
	REQUIRE(build_chunk(field, 16, 16, 16, 2, params, mesh));
	// First vertex: sample (16, 16).
	CHECK(mesh.vertices[0].is_equal_approx(Vector3(-32 + 16 * 2, 10 + 32 * 0.5, -48 + 16 * 3)));
	CHECK(mesh.uvs[0].is_equal_approx(Vector2(16.0 / 32.0, 16.0 / 32.0)));
	// Last body vertex: sample (32, 32), the far corner of the terrain.
	const int side = 9;
	CHECK(mesh.vertices[side * side - 1].is_equal_approx(Vector3(32, 10 + 64 * 0.5, 48)));
	CHECK(mesh.uvs[side * side - 1].is_equal_approx(Vector2(1, 1)));
	// The bounds cover the vertices and the skirt below them.
	CHECK(mesh.bounds.position.x == doctest::Approx(0.0));
	CHECK(mesh.bounds.get_end().x == doctest::Approx(32.0));
	CHECK(mesh.bounds.position.y == doctest::Approx(10 + 32 * 0.5 - 1.5));
	CHECK(mesh.bounds.get_end().y == doctest::Approx(10 + 64 * 0.5));
	for (const Vector3 &vertex : mesh.vertices) {
		CHECK(mesh.bounds.grow(1e-3).has_point(vertex));
	}
}

TEST_CASE("[HeightmapTerrain] Triangles face up and skirts face outward") {
	const Vector<real_t> data = make_field(17, 17, [](int x, int z) { return real_t(0.1 * x * (z % 3)); });
	const HeightField field = view(data, 17, 17);
	Params params;
	params.skirt_depth = 1.0;
	ChunkMesh mesh;
	REQUIRE(build_chunk(field, 0, 0, 16, 1, params, mesh));

	const int body_triangles = 16 * 16 * 2;
	for (int t = 0; t < mesh.indices.size() / 3; t++) {
		const Vector3 p0 = mesh.vertices[mesh.indices[t * 3]];
		const Vector3 p1 = mesh.vertices[mesh.indices[t * 3 + 1]];
		const Vector3 p2 = mesh.vertices[mesh.indices[t * 3 + 2]];
		// Godot front faces are clockwise: the front normal is (p2 - p0) x (p1 - p0).
		const Vector3 face = (p2 - p0).cross(p1 - p0);
		if (t < body_triangles) {
			CHECK(face.y > 0.0); // The ground is visible from above.
		} else {
			// Skirt: purely vertical wall pointing away from the chunk center (8, 8).
			CHECK(Math::abs(face.y) < real_t(1e-4));
			const Vector3 middle = (p0 + p1 + p2) / 3.0;
			const Vector3 outward = Vector3(middle.x - 8.0, 0, middle.z - 8.0);
			CHECK(face.dot(outward) > 0.0);
		}
	}
}

TEST_CASE("[HeightmapTerrain] Adjacent chunks share their border vertices exactly") {
	const Vector<real_t> data = make_field(33, 33, [](int x, int z) { return Math::sin(real_t(x) * 0.5) * Math::cos(real_t(z) * 0.3) * 4; });
	const HeightField field = view(data, 33, 33);
	Params params;
	ChunkMesh left;
	ChunkMesh right;
	REQUIRE(build_chunk(field, 0, 0, 16, 1, params, left));
	REQUIRE(build_chunk(field, 16, 0, 16, 1, params, right));
	// The east edge of the left chunk is the west edge of the right chunk.
	for (int j = 0; j < 17; j++) {
		const Vector3 a = left.vertices[j * 17 + 16];
		const Vector3 b = right.vertices[j * 17];
		CHECK(a.is_equal_approx(b));
		CHECK(left.normals[j * 17 + 16].is_equal_approx(right.normals[j * 17])); // No lighting seam.
	}
}

TEST_CASE("[HeightmapTerrain] Chunks past the border collapse onto it") {
	const Vector<real_t> data = make_field(20, 20, [](int, int) { return real_t(1); });
	const HeightField field = view(data, 20, 20);
	Params params;
	ChunkMesh mesh;
	// A 16 quad chunk starting at sample 16 only has 3 real quads in each direction.
	REQUIRE(build_chunk(field, 16, 16, 16, 1, params, mesh));
	for (const Vector3 &vertex : mesh.vertices) {
		CHECK(vertex.x <= real_t(19.0) + real_t(1e-4));
		CHECK(vertex.z <= real_t(19.0) + real_t(1e-4));
		CHECK(vertex.is_finite());
	}
	CHECK(mesh.bounds.get_end().x == doctest::Approx(19.0));
}

TEST_CASE("[HeightmapTerrain] Level of detail selection with hysteresis") {
	// Base distance 100, four levels: <100, <200, <400, beyond.
	CHECK(select_lod(0, 100, 4) == 0);
	CHECK(select_lod(99, 100, 4) == 0);
	CHECK(select_lod(100, 100, 4) == 1);
	CHECK(select_lod(199, 100, 4) == 1);
	CHECK(select_lod(250, 100, 4) == 2);
	CHECK(select_lod(399, 100, 4) == 2);
	CHECK(select_lod(400, 100, 4) == 3);
	CHECK(select_lod(1e9, 100, 4) == 3); // Clamped to the last level.
	CHECK(select_lod(50, 100, 1) == 0);
	CHECK(select_lod(Math::INF, 100, 4) == 0); // Invalid input falls back to full detail.
	CHECK(select_lod(500, 0, 4) == 0);

	// Hysteresis: a chunk at level 1 stays there slightly past 200 m, but not far past.
	CHECK(select_lod(205, 100, 4, 1) == 1);
	CHECK(select_lod(230, 100, 4, 1) == 2);
	CHECK(select_lod(95, 100, 4, 1) == 1); // And slightly below 100 m.
	CHECK(select_lod(80, 100, 4, 1) == 0);
	CHECK(select_lod(205, 100, 4, -1) == 2); // Without a current level there is no stickiness.

	CHECK(lod_stride(0, 32) == 1);
	CHECK(lod_stride(2, 32) == 4);
	CHECK(lod_stride(10, 32) == 32); // Never more than the chunk itself.
	CHECK(lod_stride(3, 12) == 4); // 8 does not divide 12, so back off to 4.
}

TEST_CASE("[HeightmapTerrain] Chunk height range includes the far border samples") {
	const Vector<real_t> data = make_field(9, 9, [](int x, int z) { return real_t(x == 4 && z == 4 ? 7 : (x == 0 ? -3 : 1)); });
	const HeightField field = view(data, 9, 9);
	real_t low;
	real_t high;
	chunk_height_range(field, 0, 0, 4, low, high);
	CHECK(low == doctest::Approx(-3.0));
	CHECK(high == doctest::Approx(7.0)); // Sample (4, 4) is the far corner of this chunk.
	chunk_height_range(field, 4, 4, 4, low, high);
	CHECK(low == doctest::Approx(1.0));
	CHECK(high == doctest::Approx(7.0));
}

} // namespace TestHeightmapTerrainGeometry
