/**************************************************************************/
/*  cgame_meshlet_pages.cpp                                               */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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
/* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS */
/* IN THE SOFTWARE.                                                        */
/**************************************************************************/

#include "cgame_meshlet_pages.h"

#include "cgame_meshlets.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/local_vector.h"

#include <cstdint>
#include <cstring>

namespace {

constexpr uint32_t PAGE_MAGIC = 0x504d4743u; // "CGMP", little-endian.
constexpr uint32_t PAGE_VERSION = 1;

static void put_u32(uint8_t *p_dst, uint32_t p_offset, uint32_t p_value) {
	for (int j = 0; j < 4; ++j) {
		p_dst[p_offset + j] = uint8_t(p_value >> (8 * j));
	}
}

static uint32_t get_u32(const uint8_t *p_src, uint32_t p_offset) {
	return uint32_t(p_src[p_offset]) |
			(uint32_t(p_src[p_offset + 1]) << 8) |
			(uint32_t(p_src[p_offset + 2]) << 16) |
			(uint32_t(p_src[p_offset + 3]) << 24);
}

static void put_f32(uint8_t *p_dst, uint32_t p_offset, float p_value) {
	uint32_t bits;
	static_assert(sizeof(bits) == sizeof(p_value), "GPU page floats must be IEEE-754 binary32");
	std::memcpy(&bits, &p_value, sizeof(bits));
	put_u32(p_dst, p_offset, bits);
}

static float get_f32(const uint8_t *p_src, uint32_t p_offset) {
	const uint32_t bits = get_u32(p_src, p_offset);
	float value;
	std::memcpy(&value, &bits, sizeof(value));
	return value;
}

} // namespace

Array CgameMeshletPages::build_pages(const PackedVector3Array &p_vertices,
		const PackedInt32Array &p_indices, int p_page_bytes) {
	Array pages;
	const int vertex_count = p_vertices.size();
	const int index_count = p_indices.size();
	if (p_page_bytes < 1024 || p_page_bytes > MAX_PAGE_BYTES ||
			vertex_count < 3 || vertex_count > 1000000 ||
			index_count < 3 || index_count > 3000000 ||
			index_count % 3 != 0) {
		return pages;
	}

	LocalVector<float> positions;
	positions.resize(size_t(vertex_count) * 3);
	for (int i = 0; i < vertex_count; ++i) {
		const Vector3 vertex = p_vertices[i];
		if (!vertex.is_finite()) {
			return pages;
		}
		const float x = float(vertex.x);
		const float y = float(vertex.y);
		const float z = float(vertex.z);
		if (!Math::is_finite(x) || !Math::is_finite(y) || !Math::is_finite(z)) {
			return pages;
		}
		positions[i * 3] = x;
		positions[i * 3 + 1] = y;
		positions[i * 3 + 2] = z;
	}
	LocalVector<uint32_t> indices;
	indices.resize(index_count);
	for (int i = 0; i < index_count; ++i) {
		if (p_indices[i] < 0 || p_indices[i] >= vertex_count) {
			return pages;
		}
		indices[i] = uint32_t(p_indices[i]);
	}
	LocalVector<CgameMeshlets::Meshlet> meshlets;
	if (!CgameMeshlets::build_native(positions.ptr(), uint32_t(vertex_count),
				indices.ptr(), size_t(index_count), 64, 124, meshlets) ||
			meshlets.is_empty()) {
		return pages;
	}

	// Greedy contiguous packing. A complete meshlet is never split across
	// pages. Byte size is bounded before allocating, independent of geometry.
	for (uint32_t first = 0; first < meshlets.size();) {
		uint32_t count = 0;
		uint32_t vertices = 0;
		uint32_t triangle_bytes = 0;
		while (first + count < meshlets.size()) {
			const CgameMeshlets::Meshlet &candidate = meshlets[first + count];
			if (candidate.vertex_ids.is_empty() || candidate.indices.is_empty() ||
					candidate.vertex_ids.size() > 64 || candidate.indices.size() > 124 * 3 ||
					candidate.indices.size() % 3 != 0) {
				return Array();
			}
			const uint64_t wanted = uint64_t(HEADER_BYTES) +
					uint64_t(count + 1) * DESCRIPTOR_BYTES +
					uint64_t(vertices + candidate.vertex_ids.size()) * 4 +
					uint64_t(triangle_bytes + candidate.indices.size());
			if (wanted > uint64_t(p_page_bytes)) {
				break;
			}
			vertices += candidate.vertex_ids.size();
			triangle_bytes += candidate.indices.size();
			count++;
		}
		if (count == 0) {
			return Array();
		}
		const uint32_t desc_offset = HEADER_BYTES;
		const uint32_t vertex_offset = desc_offset + count * DESCRIPTOR_BYTES;
		const uint32_t triangle_offset = vertex_offset + vertices * 4;
		const uint32_t total_bytes = triangle_offset + triangle_bytes;
		PackedByteArray page;
		page.resize(total_bytes);
		uint8_t *dst = page.ptrw();
		put_u32(dst, 0, PAGE_MAGIC);
		put_u32(dst, 4, PAGE_VERSION);
		put_u32(dst, 8, first);
		put_u32(dst, 12, count);
		put_u32(dst, 16, desc_offset);
		put_u32(dst, 20, vertex_offset);
		put_u32(dst, 24, triangle_offset);
		put_u32(dst, 28, total_bytes);

		uint32_t current_vertex = vertex_offset;
		uint32_t current_triangle = triangle_offset;
		for (uint32_t i = 0; i < count; ++i) {
			const CgameMeshlets::Meshlet &meshlet = meshlets[first + i];
			const uint32_t off = desc_offset + i * DESCRIPTOR_BYTES;
			put_u32(dst, off, current_vertex);
			put_u32(dst, off + 4, current_triangle);
			put_u32(dst, off + 8, meshlet.vertex_ids.size());
			put_u32(dst, off + 12, meshlet.indices.size() / 3);
			put_f32(dst, off + 16, float(meshlet.bounds_center.x));
			put_f32(dst, off + 20, float(meshlet.bounds_center.y));
			put_f32(dst, off + 24, float(meshlet.bounds_center.z));
			put_f32(dst, off + 28, meshlet.bounds_radius);
			put_f32(dst, off + 32, float(meshlet.cone_axis.x));
			put_f32(dst, off + 36, float(meshlet.cone_axis.y));
			put_f32(dst, off + 40, float(meshlet.cone_axis.z));
			put_f32(dst, off + 44, meshlet.cone_cutoff);
			for (uint32_t j = 0; j < meshlet.vertex_ids.size(); ++j) {
				put_u32(dst, current_vertex, uint32_t(meshlet.vertex_ids[j]));
				current_vertex += 4;
			}
			for (uint32_t j = 0; j < meshlet.indices.size(); ++j) {
				const int local = meshlet.indices[j];
				if (local < 0 || local >= int(meshlet.vertex_ids.size())) {
					return Array();
				}
				dst[current_triangle++] = uint8_t(local);
			}
		}
		pages.push_back(page);
		first += count;
	}
	return pages;
}

Dictionary CgameMeshletPages::inspect_page(const PackedByteArray &p_page) {
	Dictionary invalid;
	const int size = p_page.size();
	if (size < HEADER_BYTES + DESCRIPTOR_BYTES + 4 * 3 + 3 ||
			size > MAX_PAGE_BYTES) {
		return invalid;
	}
	const uint8_t *src = p_page.ptr();
	if (get_u32(src, 0) != PAGE_MAGIC || get_u32(src, 4) != PAGE_VERSION ||
			get_u32(src, 28) != uint32_t(size)) {
		return invalid;
	}
	const uint32_t first = get_u32(src, 8);
	const uint32_t count = get_u32(src, 12);
	const uint32_t desc = get_u32(src, 16);
	const uint32_t vertices = get_u32(src, 20);
	const uint32_t triangles = get_u32(src, 24);
	if (count < 1 || count > 128 || desc != HEADER_BYTES ||
			vertices != desc + count * DESCRIPTOR_BYTES ||
			vertices >= triangles || triangles >= uint32_t(size)) {
		return invalid;
	}
	uint32_t cursor_vertex = vertices;
	uint32_t cursor_triangle = triangles;
	int triangle_count = 0;
	Array meshlet_list;
	for (uint32_t i = 0; i < count; ++i) {
		const uint32_t off = desc + i * DESCRIPTOR_BYTES;
		const uint32_t ref_offset = get_u32(src, off);
		const uint32_t tri_offset = get_u32(src, off + 4);
		const uint32_t ref_count = get_u32(src, off + 8);
		const uint32_t tris = get_u32(src, off + 12);
		if (ref_count < 3 || ref_count > 64 || tris < 1 || tris > 124 ||
				ref_offset != cursor_vertex || tri_offset != cursor_triangle ||
				uint64_t(cursor_vertex) + uint64_t(ref_count) * 4 > triangles ||
				uint64_t(cursor_triangle) + uint64_t(tris) * 3 > uint32_t(size)) {
			return invalid;
		}
		const Vector3 center(get_f32(src, off + 16), get_f32(src, off + 20),
				get_f32(src, off + 24));
		const float radius = get_f32(src, off + 28);
		const Vector3 cone(get_f32(src, off + 32), get_f32(src, off + 36),
				get_f32(src, off + 40));
		const float cutoff = get_f32(src, off + 44);
		if (!center.is_finite() || !Math::is_finite(radius) || radius < 0.0f ||
				!cone.is_finite() || !Math::is_finite(cutoff)) {
			return invalid;
		}
		PackedInt32Array ids;
		ids.resize(ref_count);
		int32_t *id_write = ids.ptrw();
		for (uint32_t j = 0; j < ref_count; ++j) {
			const uint32_t id = get_u32(src, cursor_vertex);
			if (id >= 1000000) {
				return invalid;
			}
			id_write[j] = int32_t(id);
			cursor_vertex += 4;
		}
		PackedByteArray local_indices;
		local_indices.resize(tris * 3);
		uint8_t *tri_write = local_indices.ptrw();
		for (uint32_t j = 0; j < tris * 3; ++j) {
			const uint8_t local = src[cursor_triangle++];
			if (local >= ref_count) {
				return invalid;
			}
			tri_write[j] = local;
		}
		Dictionary m;
		m["vertex_ids"] = ids;
		m["local_indices"] = local_indices;
		m["bounds_center"] = center;
		m["bounds_radius"] = radius;
		m["cone_axis"] = cone;
		m["cone_cutoff"] = cutoff;
		meshlet_list.push_back(m);
		triangle_count += tris;
	}
	// No holes, overlapping byte ranges, hidden references or trailing data
	// allowed. This is necessary when pages come from files or network.
	if (cursor_vertex != triangles || cursor_triangle != uint32_t(size)) {
		return invalid;
	}
	Dictionary result;
	result["first_meshlet"] = first;
	result["meshlet_count"] = count;
	result["triangle_count"] = triangle_count;
	result["bytes"] = size;
	result["meshlets"] = meshlet_list;
	return result;
}

void CgameMeshletPages::_bind_methods() {
	ClassDB::bind_static_method("CgameMeshletPages",
			D_METHOD("build_pages", "vertices", "indices", "page_bytes"),
			&CgameMeshletPages::build_pages, DEFVAL(DEFAULT_PAGE_BYTES));
	ClassDB::bind_static_method("CgameMeshletPages",
			D_METHOD("inspect_page", "page"), &CgameMeshletPages::inspect_page);
}
