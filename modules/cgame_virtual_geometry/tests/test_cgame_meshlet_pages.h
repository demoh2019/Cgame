/**************************************************************************/
/*  test_cgame_meshlet_pages.h                                            */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
#pragma once

#include "../cgame_meshlet_pages.h"
#include "core/math/math_funcs.h"
#include "core/templates/hash_map.h"
#include "tests/test_macros.h"

#include <algorithm>
#include <cstdint>

namespace TestCgameMeshletPages {

static uint64_t tri_key(int p_a, int p_b, int p_c) {
	int v[3] = { p_a, p_b, p_c };
	std::sort(v, v + 3);
	return (uint64_t(v[0]) << 40) | (uint64_t(v[1]) << 20) | uint64_t(v[2]);
}

static void make_grid(PackedVector3Array &r_vertices, PackedInt32Array &r_indices, int p_side = 50) {
	for (int z = 0; z < p_side; ++z) {
		for (int x = 0; x < p_side; ++x) {
			r_vertices.push_back(Vector3(x, Math::sin(real_t(x) * 0.1), z));
		}
	}
	for (int z = 0; z < p_side - 1; ++z) {
		for (int x = 0; x < p_side - 1; ++x) {
			const int a = z * p_side + x;
			r_indices.push_back(a);
			r_indices.push_back(a + p_side);
			r_indices.push_back(a + 1);
			r_indices.push_back(a + 1);
			r_indices.push_back(a + p_side);
			r_indices.push_back(a + p_side + 1);
		}
	}
}

TEST_CASE("[CgameMeshletPages] bounded binary pages retain every original triangle reference") {
	PackedVector3Array positions;
	PackedInt32Array input;
	make_grid(positions, input);
	const Array pages = CgameMeshletPages::build_pages(positions, input, 1024);
	REQUIRE(pages.size() > 2);
	const Array again = CgameMeshletPages::build_pages(positions, input, 1024);
	REQUIRE(again.size() == pages.size());
	HashMap<uint64_t, int> original;
	HashMap<uint64_t, int> reconstructed;
	for (int i = 0; i < input.size(); i += 3) {
		original[tri_key(input[i], input[i + 1], input[i + 2])] += 1;
	}
	uint32_t first = 0;
	int total_triangles = 0;
	for (int i = 0; i < pages.size(); ++i) {
		const PackedByteArray page = pages[i];
		const PackedByteArray same_page = again[i];
		CHECK(page == same_page); // Stable byte-for-byte for same source.
		CHECK(page.size() <= 1024);
		CHECK(page.size() > CgameMeshletPages::HEADER_BYTES);
		const Dictionary info = CgameMeshletPages::inspect_page(page);
		REQUIRE_FALSE(info.is_empty());
		CHECK(int(info["bytes"]) == page.size());
		CHECK(uint32_t(int(info["first_meshlet"])) == first);
		const int meshlet_count = info["meshlet_count"];
		const Array clusters = info["meshlets"];
		CHECK(clusters.size() == meshlet_count);
		first += meshlet_count;
		int per_page_tris = 0;
		for (int j = 0; j < clusters.size(); ++j) {
			const Dictionary m = clusters[j];
			const PackedInt32Array vertex_ids = m["vertex_ids"];
			const PackedByteArray local_indices = m["local_indices"];
			CHECK(vertex_ids.size() >= 3);
			CHECK(vertex_ids.size() <= 64);
			CHECK(local_indices.size() % 3 == 0);
			CHECK(local_indices.size() <= 124 * 3);
			CHECK(Vector3(m["bounds_center"]).is_finite());
			CHECK(float(m["bounds_radius"]) >= 0.0f);
			for (int tri = 0; tri < local_indices.size(); tri += 3) {
				const int ia = local_indices[tri];
				const int ib = local_indices[tri + 1];
				const int ic = local_indices[tri + 2];
				REQUIRE(ia < vertex_ids.size());
				REQUIRE(ib < vertex_ids.size());
				REQUIRE(ic < vertex_ids.size());
				const int a = vertex_ids[ia];
				const int b = vertex_ids[ib];
				const int c = vertex_ids[ic];
				CHECK(a >= 0);
				CHECK(b >= 0);
				CHECK(c >= 0);
				CHECK(a < positions.size());
				CHECK(b < positions.size());
				CHECK(c < positions.size());
				reconstructed[tri_key(a, b, c)] += 1;
				per_page_tris++;
			}
		}
		CHECK(per_page_tris == int(info["triangle_count"]));
		total_triangles += per_page_tris;
	}
	CHECK(total_triangles == input.size() / 3);
	CHECK(reconstructed.size() == original.size());
	for (const KeyValue<uint64_t, int> &entry : original) {
		CHECK(reconstructed.has(entry.key));
		if (reconstructed.has(entry.key)) {
			CHECK(reconstructed[entry.key] == entry.value);
		}
	}
}

TEST_CASE("[CgameMeshletPages] corrupted page byte counts offsets references and cones fail closed") {
	PackedVector3Array vertices;
	PackedInt32Array indices;
	make_grid(vertices, indices, 8);
	const Array pages = CgameMeshletPages::build_pages(vertices, indices, 1024);
	REQUIRE(pages.size() > 0);
	const PackedByteArray valid = pages[0];
	CHECK_FALSE(CgameMeshletPages::inspect_page(valid).is_empty());
	PackedByteArray corrupt = valid.duplicate();
	corrupt.set(0, 0); // Invalid magic.
	CHECK(CgameMeshletPages::inspect_page(corrupt).is_empty());
	corrupt = valid.duplicate();
	corrupt.set(4, 255); // Unsupported layout version.
	CHECK(CgameMeshletPages::inspect_page(corrupt).is_empty());
	corrupt = valid.duplicate();
	corrupt.set(28, 0); // Header size mismatch.
	CHECK(CgameMeshletPages::inspect_page(corrupt).is_empty());
	corrupt = valid.duplicate();
	corrupt.set(24, 255); // Impossible triangles stream offset.
	CHECK(CgameMeshletPages::inspect_page(corrupt).is_empty());
	corrupt = valid.duplicate();
	corrupt.set(32 + 8, 0); // First descriptor has no vertex references.
	CHECK(CgameMeshletPages::inspect_page(corrupt).is_empty());
	corrupt = valid.duplicate();
	corrupt.set(32 + 12, 255); // First descriptor has too many triangles.
	CHECK(CgameMeshletPages::inspect_page(corrupt).is_empty());
	corrupt = valid.duplicate();
	corrupt.push_back(0); // Trailing smuggled bytes.
	CHECK(CgameMeshletPages::inspect_page(corrupt).is_empty());
	CHECK(CgameMeshletPages::inspect_page(PackedByteArray()).is_empty());
}

TEST_CASE("[CgameMeshletPages] malformed source geometry is never partially serialized") {
	PackedVector3Array vertices;
	PackedInt32Array indices;
	make_grid(vertices, indices, 8);
	CHECK(CgameMeshletPages::build_pages(vertices, indices, 1023).is_empty());
	CHECK(CgameMeshletPages::build_pages(vertices, indices, 65537).is_empty());
	CHECK(CgameMeshletPages::build_pages(vertices, indices, 4096).size() > 0);
	PackedInt32Array bad_indices = indices;
	bad_indices.set(bad_indices.size() - 1, vertices.size());
	CHECK(CgameMeshletPages::build_pages(vertices, bad_indices, 4096).is_empty());
	bad_indices = indices;
	bad_indices.set(0, -1);
	CHECK(CgameMeshletPages::build_pages(vertices, bad_indices, 4096).is_empty());
	bad_indices = indices;
	bad_indices.resize(indices.size() - 1);
	CHECK(CgameMeshletPages::build_pages(vertices, bad_indices, 4096).is_empty());
	PackedVector3Array bad_vertices = vertices;
	bad_vertices.set(bad_vertices.size() - 1, Vector3(Math::NaN, 0, 0));
	CHECK(CgameMeshletPages::build_pages(bad_vertices, indices, 4096).is_empty());
	CHECK(CgameMeshletPages::build_pages(vertices, indices, 4096).size() > 0);
}

} // namespace TestCgameMeshletPages
