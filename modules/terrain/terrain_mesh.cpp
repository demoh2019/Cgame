/**************************************************************************/
/*  terrain_mesh.cpp                                                      */
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

#include "terrain_mesh.h"

#include "core/math/math_funcs.h"
#include "core/math/face3.h"
#include "core/object/class_db.h"

TerrainMesh::TerrainMesh() {
	heights.resize_initialized(grid_size.x * grid_size.y);
}

void TerrainMesh::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_grid_size", "grid_size"), &TerrainMesh::set_grid_size);
	ClassDB::bind_method(D_METHOD("get_grid_size"), &TerrainMesh::get_grid_size);
	ClassDB::bind_method(D_METHOD("set_cell_size", "cell_size"), &TerrainMesh::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &TerrainMesh::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_height_scale", "height_scale"), &TerrainMesh::set_height_scale);
	ClassDB::bind_method(D_METHOD("get_height_scale"), &TerrainMesh::get_height_scale);
	ClassDB::bind_method(D_METHOD("set_heights", "heights"), &TerrainMesh::set_heights);
	ClassDB::bind_method(D_METHOD("get_heights"), &TerrainMesh::get_heights);
	ClassDB::bind_method(D_METHOD("set_height", "x", "z", "height"), &TerrainMesh::set_height);
	ClassDB::bind_method(D_METHOD("get_height", "x", "z"), &TerrainMesh::get_height);
	ClassDB::bind_method(D_METHOD("sample_height", "grid_position"), &TerrainMesh::sample_height);
	ClassDB::bind_method(D_METHOD("sculpt", "grid_position", "radius", "amount"), &TerrainMesh::sculpt);
	ClassDB::bind_method(D_METHOD("smooth", "grid_position", "radius", "strength"), &TerrainMesh::smooth);
	ClassDB::bind_method(D_METHOD("erode", "iterations", "talus", "strength"), &TerrainMesh::erode, DEFVAL(0.0f), DEFVAL(0.5f));

	// Grid size must be restored before heights when loading a saved resource.
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "grid_size"), "set_grid_size", "get_grid_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "0.01,100,0.01,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "height_scale", PROPERTY_HINT_RANGE, "0.01,100,0.01,or_greater"), "set_height_scale", "get_height_scale");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "heights"), "set_heights", "get_heights");
}

void TerrainMesh::set_grid_size(const Vector2i &p_grid_size) {
	ERR_FAIL_COND_MSG(p_grid_size.x < 2 || p_grid_size.y < 2 || p_grid_size.x > 1024 || p_grid_size.y > 1024, "Terrain grid dimensions must be in [2, 1024].");
	if (grid_size == p_grid_size) {
		return;
	}

	PackedFloat32Array resized;
	resized.resize_initialized(p_grid_size.x * p_grid_size.y);
	float *dst = resized.ptrw();
	const float *src = heights.ptr();
	for (int z = 0; z < MIN(grid_size.y, p_grid_size.y); z++) {
		for (int x = 0; x < MIN(grid_size.x, p_grid_size.x); x++) {
			dst[z * p_grid_size.x + x] = src[_index(x, z)];
		}
	}
	grid_size = p_grid_size;
	heights = resized;
	request_update();
}

void TerrainMesh::set_cell_size(float p_cell_size) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_cell_size) || p_cell_size <= 0.0f, "Terrain cell size must be finite and positive.");
	if (cell_size == p_cell_size) {
		return;
	}
	cell_size = p_cell_size;
	request_update();
}

void TerrainMesh::set_height_scale(float p_height_scale) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_height_scale) || p_height_scale <= 0.0f, "Terrain height scale must be finite and positive.");
	if (height_scale == p_height_scale) {
		return;
	}
	height_scale = p_height_scale;
	request_update();
}

void TerrainMesh::set_heights(const PackedFloat32Array &p_heights) {
	ERR_FAIL_COND_MSG(p_heights.size() != grid_size.x * grid_size.y, "Height count must equal grid_size.x * grid_size.y.");
	for (int i = 0; i < p_heights.size(); i++) {
		ERR_FAIL_COND_MSG(!Math::is_finite(p_heights[i]), "Terrain heights must be finite.");
	}
	if (heights == p_heights) {
		return;
	}
	heights = p_heights;
	request_update();
}

float TerrainMesh::get_height(int p_x, int p_z) const {
	ERR_FAIL_INDEX_V(p_x, grid_size.x, 0.0f);
	ERR_FAIL_INDEX_V(p_z, grid_size.y, 0.0f);
	return heights[_index(p_x, p_z)];
}

float TerrainMesh::_height_clamped(int p_x, int p_z) const {
	return heights[_index(CLAMP(p_x, 0, grid_size.x - 1), CLAMP(p_z, 0, grid_size.y - 1))];
}

void TerrainMesh::set_height(int p_x, int p_z, float p_height) {
	ERR_FAIL_INDEX(p_x, grid_size.x);
	ERR_FAIL_INDEX(p_z, grid_size.y);
	ERR_FAIL_COND_MSG(!Math::is_finite(p_height), "Terrain heights must be finite.");
	const int index = _index(p_x, p_z);
	if (heights[index] == p_height) {
		return;
	}
	heights.ptrw()[index] = p_height;
	request_update();
}

float TerrainMesh::sample_height(const Vector2 &p_grid_position) const {
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_grid_position.x) || !Math::is_finite(p_grid_position.y), 0.0f, "Sample coordinates must be finite.");
	const float x = CLAMP(p_grid_position.x, 0.0f, float(grid_size.x - 1));
	const float z = CLAMP(p_grid_position.y, 0.0f, float(grid_size.y - 1));
	const int x0 = int(Math::floor(x));
	const int z0 = int(Math::floor(z));
	const int x1 = MIN(x0 + 1, grid_size.x - 1);
	const int z1 = MIN(z0 + 1, grid_size.y - 1);
	const float tx = x - x0;
	const float tz = z - z0;
	const float top = Math::lerp(get_height(x0, z0), get_height(x1, z0), tx);
	const float bottom = Math::lerp(get_height(x0, z1), get_height(x1, z1), tx);
	return Math::lerp(top, bottom, tz);
}

bool TerrainMesh::intersect_segment(const Vector3 &p_from, const Vector3 &p_to, Vector3 &r_hit) const {
	// Local-space segment against actual triangles, not an approximation of the grid surface.
	// The X/Z sweep bounds exclude unrelated cells for short and vertical brush rays.
	if (!p_from.is_finite() || !p_to.is_finite() || p_from == p_to) {
		return false;
	}
	const float x_min = MIN(p_from.x, p_to.x) / cell_size;
	const float x_max = MAX(p_from.x, p_to.x) / cell_size;
	const float z_min = MIN(p_from.z, p_to.z) / cell_size;
	const float z_max = MAX(p_from.z, p_to.z) / cell_size;
	if (x_max < 0.0f || z_max < 0.0f || x_min > grid_size.x - 1 || z_min > grid_size.y - 1) {
		return false;
	}
	const int min_x = MAX(0, int(Math::floor(x_min)) - 1);
	const int max_x = MIN(grid_size.x - 2, int(Math::ceil(x_max)));
	const int min_z = MAX(0, int(Math::floor(z_min)) - 1);
	const int max_z = MIN(grid_size.y - 2, int(Math::ceil(z_max)));
	const Vector3 a = p_from;
	real_t best_distance_sq = p_from.distance_squared_to(p_to);
	bool hit = false;
	for (int z = min_z; z <= max_z; z++) {
		for (int x = min_x; x <= max_x; x++) {
			const Vector3 p00(x * cell_size, get_height(x, z) * height_scale, z * cell_size);
			const Vector3 p10((x + 1) * cell_size, get_height(x + 1, z) * height_scale, z * cell_size);
			const Vector3 p01(x * cell_size, get_height(x, z + 1) * height_scale, (z + 1) * cell_size);
			const Vector3 p11((x + 1) * cell_size, get_height(x + 1, z + 1) * height_scale, (z + 1) * cell_size);
			const Face3 faces[2] = { Face3(p00, p01, p10), Face3(p10, p01, p11) };
			for (const Face3 &face : faces) {
				Vector3 candidate;
				if (!face.intersects_segment(p_from, p_to, &candidate)) {
					continue;
				}
				const real_t distance_sq = a.distance_squared_to(candidate);
				if (distance_sq <= best_distance_sq) {
					best_distance_sq = distance_sq;
					r_hit = candidate;
					hit = true;
				}
			}
		}
	}
	return hit;
}

void TerrainMesh::sculpt(const Vector2 &p_grid_position, float p_radius, float p_amount) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_radius) || p_radius <= 0.0f || !Math::is_finite(p_amount) ||
			!Math::is_finite(p_grid_position.x) || !Math::is_finite(p_grid_position.y), "Invalid sculpt brush parameters.");
	if (p_amount == 0.0f) {
		return;
	}
	const int min_x = MAX(0, int(Math::floor(p_grid_position.x - p_radius)));
	const int max_x = MIN(grid_size.x - 1, int(Math::ceil(p_grid_position.x + p_radius)));
	const int min_z = MAX(0, int(Math::floor(p_grid_position.y - p_radius)));
	const int max_z = MIN(grid_size.y - 1, int(Math::ceil(p_grid_position.y + p_radius)));
	if (min_x > max_x || min_z > max_z) {
		return;
	}
	float *data = heights.ptrw();
	bool changed = false;
	for (int z = min_z; z <= max_z; z++) {
		for (int x = min_x; x <= max_x; x++) {
			const float distance = Vector2(x, z).distance_to(p_grid_position);
			if (distance >= p_radius) {
				continue;
			}
			const float amount = p_amount * (1.0f - distance / p_radius);
			const int index = _index(x, z);
			const float result = data[index] + amount;
			if (Math::is_finite(result) && result != data[index]) {
				data[index] = result;
				changed = true;
			}
		}
	}
	if (changed) {
		request_update();
	}
}

void TerrainMesh::smooth(const Vector2 &p_grid_position, float p_radius, float p_strength) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_radius) || p_radius <= 0.0f ||
			!Math::is_finite(p_strength) || p_strength < 0.0f || p_strength > 1.0f ||
			!Math::is_finite(p_grid_position.x) || !Math::is_finite(p_grid_position.y), "Invalid smooth brush parameters.");
	if (p_strength == 0.0f) {
		return;
	}
	const int min_x = MAX(0, int(Math::floor(p_grid_position.x - p_radius)));
	const int max_x = MIN(grid_size.x - 1, int(Math::ceil(p_grid_position.x + p_radius)));
	const int min_z = MAX(0, int(Math::floor(p_grid_position.y - p_radius)));
	const int max_z = MIN(grid_size.y - 1, int(Math::ceil(p_grid_position.y + p_radius)));
	if (min_x > max_x || min_z > max_z) {
		return;
	}
	// Read all neighboring heights from the original snapshot, not from partially smoothed cells.
	const PackedFloat32Array original = heights;
	float *data = heights.ptrw();
	bool changed = false;
	for (int z = min_z; z <= max_z; z++) {
		for (int x = min_x; x <= max_x; x++) {
			const float distance = Vector2(x, z).distance_to(p_grid_position);
			if (distance >= p_radius) {
				continue;
			}
			float sum = 0.0f;
			int count = 0;
			for (int nz = MAX(0, z - 1); nz <= MIN(grid_size.y - 1, z + 1); nz++) {
				for (int nx = MAX(0, x - 1); nx <= MIN(grid_size.x - 1, x + 1); nx++) {
					sum += original[_index(nx, nz)];
					count++;
				}
			}
			const int index = _index(x, z);
			const float weight = p_strength * (1.0f - distance / p_radius);
			const float result = original[index] + (sum / count - original[index]) * weight;
			if (Math::is_finite(result) && result != data[index]) {
				data[index] = result;
				changed = true;
			}
		}
	}
	if (changed) {
		request_update();
	}
}

void TerrainMesh::erode(int p_iterations, float p_talus, float p_strength) {
	ERR_FAIL_COND_MSG(p_iterations < 0 || p_iterations > 1024 || !Math::is_finite(p_talus) || p_talus < 0.0f ||
			!Math::is_finite(p_strength) || p_strength < 0.0f || p_strength > 1.0f, "Invalid thermal erosion parameters.");
	if (p_iterations == 0 || p_strength == 0.0f) {
		return;
	}
	const int width = grid_size.x;
	const int depth = grid_size.y;
	Vector<float> delta;
	delta.resize(width * depth);
	bool changed = false;
	for (int iter = 0; iter < p_iterations; iter++) {
		float *moves = delta.ptrw();
		for (int i = 0; i < delta.size(); i++) {
			moves[i] = 0.0f;
		}
		const float *src = heights.ptr();
		for (int z = 0; z < depth; z++) {
			for (int x = 0; x < width; x++) {
				const int index = _index(x, z);
				const int nx[4] = { x - 1, x + 1, x, x };
				const int nz[4] = { z, z, z - 1, z + 1 };
				int targets[4];
				float drops[4];
				int count = 0;
				float total_drop = 0.0f;
				float max_drop = 0.0f;
				for (int side = 0; side < 4; side++) {
					if (nx[side] < 0 || nx[side] >= width || nz[side] < 0 || nz[side] >= depth) {
						continue;
					}
					const int neighbor = _index(nx[side], nz[side]);
					const float drop = src[index] - src[neighbor] - p_talus;
					if (drop <= 0.0f) {
						continue;
					}
					targets[count] = neighbor;
					drops[count] = drop;
					count++;
					total_drop += drop;
					max_drop = MAX(max_drop, drop);
				}
				if (count == 0) {
					continue;
				}
				// Limit each source's total outflow, conserving volume and avoiding large single-step overshoots.
				const float outflow = 0.25f * p_strength * max_drop;
				moves[index] -= outflow;
				for (int i = 0; i < count; i++) {
					moves[targets[i]] += outflow * (drops[i] / total_drop);
				}
				changed = true;
			}
		}
		float *dst = heights.ptrw();
		for (int i = 0; i < heights.size(); i++) {
			dst[i] += moves[i];
		}
	}
	if (changed) {
		request_update();
	}
}

void TerrainMesh::_create_mesh_array(Array &p_arr) const {
	const int width = grid_size.x;
	const int depth = grid_size.y;
	PackedVector3Array vertices;
	PackedVector3Array normals;
	PackedVector2Array uvs;
	PackedInt32Array indices;
	vertices.resize(width * depth);
	normals.resize(width * depth);
	uvs.resize(width * depth);
	indices.resize((width - 1) * (depth - 1) * 6);

	Vector3 *v = vertices.ptrw();
	Vector3 *n = normals.ptrw();
	Vector2 *uv = uvs.ptrw();
	int32_t *idx = indices.ptrw();

	for (int z = 0; z < depth; z++) {
		for (int x = 0; x < width; x++) {
			const int index = _index(x, z);
			v[index] = Vector3(x * cell_size, heights[index] * height_scale, z * cell_size);
			uv[index] = Vector2(float(x) / (width - 1), float(z) / (depth - 1));
			const int left = MAX(0, x - 1);
			const int right = MIN(width - 1, x + 1);
			const int top = MAX(0, z - 1);
			const int bottom = MIN(depth - 1, z + 1);
			const float dx = (_height_clamped(right, z) - _height_clamped(left, z)) * height_scale / ((right - left) * cell_size);
			const float dz = (_height_clamped(x, bottom) - _height_clamped(x, top)) * height_scale / ((bottom - top) * cell_size);
			n[index] = Vector3(-dx, 1.0f, -dz).normalized();
		}
	}
	int cursor = 0;
	for (int z = 0; z < depth - 1; z++) {
		for (int x = 0; x < width - 1; x++) {
			const int top_left = _index(x, z);
			const int top_right = top_left + 1;
			const int bottom_left = top_left + width;
			const int bottom_right = bottom_left + 1;
			idx[cursor++] = top_left;
			idx[cursor++] = bottom_left;
			idx[cursor++] = top_right;
			idx[cursor++] = top_right;
			idx[cursor++] = bottom_left;
			idx[cursor++] = bottom_right;
		}
	}
	p_arr[Mesh::ARRAY_VERTEX] = vertices;
	p_arr[Mesh::ARRAY_NORMAL] = normals;
	p_arr[Mesh::ARRAY_TEX_UV] = uvs;
	p_arr[Mesh::ARRAY_INDEX] = indices;
}
