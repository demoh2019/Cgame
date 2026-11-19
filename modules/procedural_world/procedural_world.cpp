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

#include "procedural_world.h"

#include "core/math/math_funcs.h"
#include "core/math/random_number_generator.h"
#include "core/object/class_db.h"

uint32_t ProceduralWorld::_hash(int32_t p_x, int32_t p_y, uint32_t p_seed) {
	uint32_t h = uint32_t(p_x) * 0x9e3779b9U ^ uint32_t(p_y) * 0x85ebca6bU ^ p_seed;
	h ^= h >> 16;
	h *= 0x7feb352dU;
	h ^= h >> 15;
	h *= 0x846ca68bU;
	h ^= h >> 16;
	return h;
}

float ProceduralWorld::_noise(float p_x, float p_y, uint32_t p_seed) {
	const int32_t x = int32_t(Math::floor(p_x));
	const int32_t y = int32_t(Math::floor(p_y));
	float tx = p_x - float(x);
	float ty = p_y - float(y);
	tx = tx * tx * (3.0f - 2.0f * tx);
	ty = ty * ty * (3.0f - 2.0f * ty);

	constexpr float HASH_SCALE = 1.0f / 4294967295.0f;
	const float a = float(_hash(x, y, p_seed)) * HASH_SCALE;
	const float b = float(_hash(x + 1, y, p_seed)) * HASH_SCALE;
	const float c = float(_hash(x, y + 1, p_seed)) * HASH_SCALE;
	const float d = float(_hash(x + 1, y + 1, p_seed)) * HASH_SCALE;
	const float upper = a + (b - a) * tx;
	const float lower = c + (d - c) * tx;
	return (upper + (lower - upper) * ty) * 2.0f - 1.0f;
}

PackedFloat32Array ProceduralWorld::generate_heightmap(int p_width, int p_height, int p_seed, float p_scale, float p_amplitude, int p_octaves, const Vector2i &p_origin) const {
	ERR_FAIL_COND_V_MSG(p_width <= 0 || p_height <= 0 || p_width > 2048 || p_height > 2048 || int64_t(p_width) * p_height > 4194304, PackedFloat32Array(), "Heightmap dimensions must be positive and contain at most 4194304 samples.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_scale) || p_scale < 0.001f || !Math::is_finite(p_amplitude) || p_amplitude < 0.0f, PackedFloat32Array(), "Scale must be finite and >= 0.001, and amplitude must be finite and nonnegative.");
	ERR_FAIL_COND_V_MSG(p_octaves < 1 || p_octaves > 8, PackedFloat32Array(), "Octaves must be in range 1..8.");
	ERR_FAIL_COND_V_MSG(Math::abs(int64_t(p_origin.x)) > 1000000 || Math::abs(int64_t(p_origin.y)) > 1000000, PackedFloat32Array(), "Heightmap world origin must lie within +/-1000000.");

	PackedFloat32Array heights;
	heights.resize(p_width * p_height);
	float *data = heights.ptrw();
	for (int y = 0; y < p_height; y++) {
		for (int x = 0; x < p_width; x++) {
			float value = 0.0f;
			float weight = 0.0f;
			float octave_amplitude = 1.0f;
			float frequency = 1.0f / p_scale;
			for (int octave = 0; octave < p_octaves; octave++) {
				value += _noise(float(p_origin.x + x) * frequency, float(p_origin.y + y) * frequency, uint32_t(p_seed) + uint32_t(octave) * 0x9e3779b9U) * octave_amplitude;
				weight += octave_amplitude;
				octave_amplitude *= 0.5f;
				frequency *= 2.0f;
			}
			data[y * p_width + x] = (value / weight) * p_amplitude;
		}
	}
	return heights;
}

PackedFloat32Array ProceduralWorld::erode_heightmap(const PackedFloat32Array &p_heights, int p_width, int p_height, int p_iterations, float p_talus, float p_strength) const {
	ERR_FAIL_COND_V_MSG(p_width <= 0 || p_height <= 0 || p_width > 2048 || p_height > 2048 || int64_t(p_width) * p_height != p_heights.size(), PackedFloat32Array(), "The heightmap must have exactly width * height samples.");
	ERR_FAIL_COND_V_MSG(p_iterations < 0 || p_iterations > 256 || !Math::is_finite(p_talus) || p_talus < 0 || !Math::is_finite(p_strength) || p_strength < 0 || p_strength > 1, PackedFloat32Array(), "Invalid erosion parameters.");

	for (float value : p_heights) {
		ERR_FAIL_COND_V_MSG(!Math::is_finite(value), PackedFloat32Array(), "Heightmap samples must be finite.");
	}

	PackedFloat32Array current = p_heights;
	const int dx[] = { 0, 0, -1, 1 };
	const int dy[] = { -1, 1, 0, 0 };
	for (int iteration = 0; iteration < p_iterations; iteration++) {
		PackedFloat32Array next = current;
		float *dst = next.ptrw();
		const float *src = current.ptr();
		for (int y = 0; y < p_height; y++) {
			for (int x = 0; x < p_width; x++) {
				const int here = y * p_width + x;
				for (int direction = 0; direction < 4; direction++) {
					const int nx = x + dx[direction];
					const int ny = y + dy[direction];
					if (nx < 0 || nx >= p_width || ny < 0 || ny >= p_height) {
						continue;
					}
					const int there = ny * p_width + nx;
					const float excess = src[here] - src[there] - p_talus;
					if (excess > 0.0f) {
						// Conservative, simultaneous transfers: each edge subtracts and adds
						// the same amount, and the 1/8 factor limits steep-cell outflows.
						const float transfer = excess * p_strength * 0.125f;
						dst[here] -= transfer;
						dst[there] += transfer;
					}
				}
			}
		}
		current = next;
	}
	return current;
}

PackedVector2Array ProceduralWorld::scatter_points(const Rect2 &p_area, float p_min_distance, int p_seed, int p_max_points, int p_attempts_per_point) const {
	PackedVector2Array points;
	ERR_FAIL_COND_V_MSG(!p_area.position.is_finite() || !p_area.size.is_finite() || !p_area.get_end().is_finite() || p_area.size.x <= 0 || p_area.size.y <= 0, points, "Area must be finite with positive size.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_min_distance) || p_min_distance <= 0 || p_max_points < 0 || p_max_points > 4096 || p_attempts_per_point < 1 || p_attempts_per_point > 100, points, "Invalid scatter parameters.");
	if (p_max_points == 0) {
		return points;
	}

	const float cell_size = p_min_distance / Math::SQRT2;
	const double col_count = Math::ceil(double(p_area.size.x) / double(cell_size));
	const double row_count = Math::ceil(double(p_area.size.y) / double(cell_size));
	ERR_FAIL_COND_V_MSG(!Math::is_finite(col_count) || !Math::is_finite(row_count) || col_count > 2048.0 || row_count > 2048.0, points, "Scatter grid dimensions exceed limits.");
	const int64_t columns = int64_t(col_count);
	const int64_t rows = int64_t(row_count);
	ERR_FAIL_COND_V_MSG(columns <= 0 || rows <= 0 || columns * rows > 4194304, points, "Scatter grid would exceed 4194304 cells.");

	Vector<int> grid;
	grid.resize(int(columns * rows));
	int *cell_data = grid.ptrw();
	for (int i = 0; i < grid.size(); i++) {
		cell_data[i] = -1;
	}

	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed(uint64_t(uint32_t(p_seed)));
	const float min_distance_squared = p_min_distance * p_min_distance;
	for (int attempt = 0; attempt < p_max_points * p_attempts_per_point && points.size() < p_max_points; attempt++) {
		const Vector2 candidate = p_area.position + Vector2(rng->randf() * p_area.size.x, rng->randf() * p_area.size.y);
		const int cx = MIN(int((candidate.x - p_area.position.x) / cell_size), int(columns) - 1);
		const int cy = MIN(int((candidate.y - p_area.position.y) / cell_size), int(rows) - 1);
		bool valid = true;
		for (int y = MAX(0, cy - 2); y <= MIN(int(rows) - 1, cy + 2) && valid; y++) {
			for (int x = MAX(0, cx - 2); x <= MIN(int(columns) - 1, cx + 2); x++) {
				const int index = cell_data[y * int(columns) + x];
				if (index != -1 && candidate.distance_squared_to(points[index]) < min_distance_squared) {
					valid = false;
					break;
				}
			}
		}
		if (valid) {
			cell_data[cy * int(columns) + cx] = points.size();
			points.push_back(candidate);
		}
	}
	return points;
}

Array ProceduralWorld::get_chunk_coordinates(const Rect2 &p_world_area, int p_chunk_size) const {
	Array result;
	ERR_FAIL_COND_V_MSG(!p_world_area.position.is_finite() || !p_world_area.size.is_finite() || !p_world_area.get_end().is_finite() || p_world_area.size.x < 0 || p_world_area.size.y < 0 || p_chunk_size <= 0, result, "Invalid chunk area or size.");
	if (p_world_area.size.x == 0 || p_world_area.size.y == 0) {
		return result;
	}

	ERR_FAIL_COND_V_MSG(Math::abs(p_world_area.position.x) > 1000000000.0f || Math::abs(p_world_area.position.y) > 1000000000.0f || Math::abs(p_world_area.get_end().x) > 1000000000.0f || Math::abs(p_world_area.get_end().y) > 1000000000.0f, result, "World coordinates exceed supported range.");

	const int64_t x0 = int64_t(Math::floor(p_world_area.position.x / p_chunk_size));
	const int64_t y0 = int64_t(Math::floor(p_world_area.position.y / p_chunk_size));
	const int64_t x1 = int64_t(Math::ceil((p_world_area.position.x + p_world_area.size.x) / p_chunk_size));
	const int64_t y1 = int64_t(Math::ceil((p_world_area.position.y + p_world_area.size.y) / p_chunk_size));
	ERR_FAIL_COND_V_MSG(x1 <= x0 || y1 <= y0 || x1 - x0 > 1024 || y1 - y0 > 1024 || (x1 - x0) * (y1 - y0) > 65536, result, "Chunk range is too large.");
	for (int64_t y = y0; y < y1; y++) {
		for (int64_t x = x0; x < x1; x++) {
			result.push_back(Vector2i(int(x), int(y)));
		}
	}
	return result;
}

void ProceduralWorld::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate_heightmap", "width", "height", "seed", "scale", "amplitude", "octaves", "origin"), &ProceduralWorld::generate_heightmap, DEFVAL(64.0f), DEFVAL(32.0f), DEFVAL(4), DEFVAL(Vector2i()));
	ClassDB::bind_method(D_METHOD("erode_heightmap", "heights", "width", "height", "iterations", "talus", "strength"), &ProceduralWorld::erode_heightmap, DEFVAL(8), DEFVAL(1.0f), DEFVAL(0.5f));
	ClassDB::bind_method(D_METHOD("scatter_points", "area", "min_distance", "seed", "max_points", "attempts_per_point"), &ProceduralWorld::scatter_points, DEFVAL(1024), DEFVAL(30));
	ClassDB::bind_method(D_METHOD("get_chunk_coordinates", "world_area", "chunk_size"), &ProceduralWorld::get_chunk_coordinates, DEFVAL(64));
}
