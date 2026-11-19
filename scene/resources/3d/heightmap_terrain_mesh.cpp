/**************************************************************************/
/*  heightmap_terrain_mesh.cpp                                             */
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

#include "heightmap_terrain_mesh.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

int HeightmapTerrainMesh::_index(int p_x, int p_z) const {
	return p_z * grid_size.x + p_x;
}

float HeightmapTerrainMesh::_height_clamped(int p_x, int p_z) const {
	return height_data[_index(CLAMP(p_x, 0, grid_size.x - 1), CLAMP(p_z, 0, grid_size.y - 1))];
}

Vector2 HeightmapTerrainMesh::_grid_to_local(int p_x, int p_z) const {
	return Vector2((float(p_x) / (grid_size.x - 1) - 0.5f) * terrain_size.x,
			(float(p_z) / (grid_size.y - 1) - 0.5f) * terrain_size.y);
}

float HeightmapTerrainMesh::_brush_falloff(const Vector2 &p_center, float p_radius, int p_x, int p_z) const {
	const float distance = _grid_to_local(p_x, p_z).distance_to(p_center);
	return MAX(0.0f, 1.0f - distance / p_radius);
}

void HeightmapTerrainMesh::_reset_grid() {
	const int count = grid_size.x * grid_size.y;
	height_data.resize(count);
	layer_weights.resize(count);
	for (int i = 0; i < count; i++) {
		height_data.set(i, 0.0f);
		layer_weights.set(i, Color(1, 0, 0, 0));
	}
	request_update();
}

HeightmapTerrainMesh::HeightmapTerrainMesh() {
	_reset_grid();
}

void HeightmapTerrainMesh::set_grid_size(const Vector2i &p_size) {
	ERR_FAIL_COND_MSG(p_size.x < 2 || p_size.y < 2 || p_size.x > 512 || p_size.y > 512, "HeightmapTerrainMesh dimensions must be in the range 2..512.");
	if (p_size == grid_size) {
		return;
	}
	grid_size = p_size;
	_reset_grid();
}

Vector2i HeightmapTerrainMesh::get_grid_size() const {
	return grid_size;
}

void HeightmapTerrainMesh::set_terrain_size(const Vector2 &p_size) {
	ERR_FAIL_COND_MSG(!p_size.is_finite() || p_size.x <= 0 || p_size.y <= 0, "HeightmapTerrainMesh size must be finite and positive.");
	if (terrain_size == p_size) {
		return;
	}
	terrain_size = p_size;
	request_update();
}

Vector2 HeightmapTerrainMesh::get_terrain_size() const {
	return terrain_size;
}

void HeightmapTerrainMesh::set_height_data(const PackedFloat32Array &p_heights) {
	ERR_FAIL_COND_MSG(p_heights.size() != grid_size.x * grid_size.y, "Height array must contain grid_width * grid_depth samples.");
	for (int i = 0; i < p_heights.size(); i++) {
		ERR_FAIL_COND_MSG(!Math::is_finite(p_heights[i]), "Height samples must be finite.");
	}
	height_data = p_heights;
	request_update();
}

PackedFloat32Array HeightmapTerrainMesh::get_height_data() const {
	return height_data;
}

void HeightmapTerrainMesh::set_layer_weights(const PackedColorArray &p_weights) {
	ERR_FAIL_COND_MSG(p_weights.size() != grid_size.x * grid_size.y, "Layer array must contain grid_width * grid_depth colors.");
	for (int i = 0; i < p_weights.size(); i++) {
		const Color c = p_weights[i];
		float sum = 0;
		for (int channel = 0; channel < 4; channel++) {
			ERR_FAIL_COND_MSG(!Math::is_finite(c[channel]) || c[channel] < 0.0f, "Layer weights must be finite and non-negative.");
			sum += c[channel];
		}
		ERR_FAIL_COND_MSG(!Math::is_finite(sum) || sum <= 0.0f, "At least one layer must be positive for every vertex.");
	}
	PackedColorArray normalized = p_weights;
	for (int i = 0; i < normalized.size(); i++) {
		Color c = normalized[i];
		const float sum = c.r + c.g + c.b + c.a;
		normalized.set(i, c / sum);
	}
	layer_weights = normalized;
	request_update();
}

PackedColorArray HeightmapTerrainMesh::get_layer_weights() const {
	return layer_weights;
}

void HeightmapTerrainMesh::set_grid_height(int p_x, int p_z, float p_height) {
	ERR_FAIL_INDEX(p_x, grid_size.x);
	ERR_FAIL_INDEX(p_z, grid_size.y);
	ERR_FAIL_COND_MSG(!Math::is_finite(p_height), "Height must be finite.");
	height_data.set(_index(p_x, p_z), p_height);
	request_update();
}

float HeightmapTerrainMesh::get_grid_height(int p_x, int p_z) const {
	ERR_FAIL_INDEX_V(p_x, grid_size.x, 0.0f);
	ERR_FAIL_INDEX_V(p_z, grid_size.y, 0.0f);
	return height_data[_index(p_x, p_z)];
}

float HeightmapTerrainMesh::get_local_height(const Vector2 &p_local_xz) const {
	if (!p_local_xz.is_finite()) {
		return 0.0f;
	}
	float u = CLAMP((p_local_xz.x / terrain_size.x + 0.5f) * (grid_size.x - 1), 0.0f, float(grid_size.x - 1));
	float v = CLAMP((p_local_xz.y / terrain_size.y + 0.5f) * (grid_size.y - 1), 0.0f, float(grid_size.y - 1));
	int x = int(Math::floor(u));
	int z = int(Math::floor(v));
	float tx = u - x;
	float tz = v - z;
	float h0 = Math::lerp(_height_clamped(x, z), _height_clamped(x + 1, z), tx);
	float h1 = Math::lerp(_height_clamped(x, z + 1), _height_clamped(x + 1, z + 1), tx);
	return Math::lerp(h0, h1, tz);
}

void HeightmapTerrainMesh::raise_brush(const Vector2 &p_local_xz, float p_radius, float p_delta) {
	ERR_FAIL_COND_MSG(!p_local_xz.is_finite() || !Math::is_finite(p_radius) || !Math::is_finite(p_delta) || p_radius <= 0.0f, "Height brush requires finite position, positive radius, and finite delta.");
	for (int z = 0; z < grid_size.y; z++) {
		for (int x = 0; x < grid_size.x; x++) {
			float weight = _brush_falloff(p_local_xz, p_radius, x, z);
			if (weight > 0) {
				int idx = _index(x, z);
				float new_height = height_data[idx] + p_delta * weight;
				if (Math::is_finite(new_height)) {
					height_data.set(idx, new_height);
				}
			}
		}
	}
	request_update();
}

void HeightmapTerrainMesh::flatten_brush(const Vector2 &p_local_xz, float p_radius, float p_height, float p_strength) {
	ERR_FAIL_COND_MSG(!p_local_xz.is_finite() || !Math::is_finite(p_radius) || p_radius <= 0 || !Math::is_finite(p_height) || !Math::is_finite(p_strength) || p_strength < 0 || p_strength > 1, "Flatten brush requires finite inputs and strength in 0..1.");
	for (int z = 0; z < grid_size.y; z++) {
		for (int x = 0; x < grid_size.x; x++) {
			float weight = p_strength * _brush_falloff(p_local_xz, p_radius, x, z);
			if (weight > 0) {
				int idx = _index(x, z);
				float new_height = Math::lerp(height_data[idx], p_height, weight);
				if (Math::is_finite(new_height)) {
					height_data.set(idx, new_height);
				}
			}
		}
	}
	request_update();
}

void HeightmapTerrainMesh::smooth_brush(const Vector2 &p_local_xz, float p_radius, float p_strength) {
	ERR_FAIL_COND_MSG(!p_local_xz.is_finite() || !Math::is_finite(p_radius) || p_radius <= 0 || !Math::is_finite(p_strength) || p_strength < 0 || p_strength > 1, "Smooth brush requires finite inputs and strength in 0..1.");
	PackedFloat32Array source = height_data.duplicate();
	for (int z = 0; z < grid_size.y; z++) {
		for (int x = 0; x < grid_size.x; x++) {
			float weight = p_strength * _brush_falloff(p_local_xz, p_radius, x, z);
			if (weight <= 0) {
				continue;
			}
			float total = source[_index(x, z)];
			int count = 1;
			for (const Vector2i &offset : { Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1) }) {
				int nx = x + offset.x;
				int nz = z + offset.y;
				if (nx >= 0 && nx < grid_size.x && nz >= 0 && nz < grid_size.y) {
					total += source[_index(nx, nz)];
					count++;
				}
			}
			float new_height = Math::lerp(source[_index(x, z)], total / count, weight);
			if (Math::is_finite(new_height)) {
				height_data.set(_index(x, z), new_height);
			}
		}
	}
	request_update();
}

void HeightmapTerrainMesh::paint_layer(const Vector2 &p_local_xz, float p_radius, int p_layer, float p_strength) {
	ERR_FAIL_INDEX(p_layer, 4);
	ERR_FAIL_COND_MSG(!p_local_xz.is_finite() || !Math::is_finite(p_radius) || p_radius <= 0 || !Math::is_finite(p_strength) || p_strength < 0 || p_strength > 1, "Layer brush requires finite inputs and strength in 0..1.");
	Color target(0, 0, 0, 0);
	target[p_layer] = 1.0f;
	for (int z = 0; z < grid_size.y; z++) {
		for (int x = 0; x < grid_size.x; x++) {
			float weight = p_strength * _brush_falloff(p_local_xz, p_radius, x, z);
			if (weight > 0) {
				int idx = _index(x, z);
				layer_weights.set(idx, layer_weights[idx].lerp(target, weight));
			}
		}
	}
	request_update();
}

void HeightmapTerrainMesh::_create_mesh_array(Array &r_arrays) const {
	const int count = grid_size.x * grid_size.y;
	PackedVector3Array positions;
	PackedVector3Array normals;
	PackedVector2Array uvs;
	PackedColorArray colors;
	PackedInt32Array indices;
	positions.resize(count);
	normals.resize(count);
	uvs.resize(count);
	colors.resize(count);
	indices.resize((grid_size.x - 1) * (grid_size.y - 1) * 6);

	const float step_x = terrain_size.x / (grid_size.x - 1);
	const float step_z = terrain_size.y / (grid_size.y - 1);
	for (int z = 0; z < grid_size.y; z++) {
		for (int x = 0; x < grid_size.x; x++) {
			const int idx = _index(x, z);
			const Vector2 local = _grid_to_local(x, z);
			positions.set(idx, Vector3(local.x, height_data[idx], local.y));
			const float tangent_x = (_height_clamped(x + 1, z) - _height_clamped(x - 1, z)) / (step_x * (x > 0 && x < grid_size.x - 1 ? 2.0f : 1.0f));
			const float tangent_z = (_height_clamped(x, z + 1) - _height_clamped(x, z - 1)) / (step_z * (z > 0 && z < grid_size.y - 1 ? 2.0f : 1.0f));
			normals.set(idx, Vector3(-tangent_x, 1, -tangent_z).normalized());
			uvs.set(idx, Vector2(float(x) / (grid_size.x - 1), float(z) / (grid_size.y - 1)));
			colors.set(idx, layer_weights[idx]);
		}
	}
	int write = 0;
	for (int z = 0; z < grid_size.y - 1; z++) {
		for (int x = 0; x < grid_size.x - 1; x++) {
			int a = _index(x, z);
			int b = _index(x + 1, z);
			int c = _index(x, z + 1);
			int d = _index(x + 1, z + 1);
			indices.set(write++, a);
			indices.set(write++, c);
			indices.set(write++, b);
			indices.set(write++, b);
			indices.set(write++, c);
			indices.set(write++, d);
		}
	}
	r_arrays[Mesh::ARRAY_VERTEX] = positions;
	r_arrays[Mesh::ARRAY_NORMAL] = normals;
	r_arrays[Mesh::ARRAY_TEX_UV] = uvs;
	r_arrays[Mesh::ARRAY_COLOR] = colors;
	r_arrays[Mesh::ARRAY_INDEX] = indices;
}

void HeightmapTerrainMesh::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_grid_size", "grid_size"), &HeightmapTerrainMesh::set_grid_size);
	ClassDB::bind_method(D_METHOD("get_grid_size"), &HeightmapTerrainMesh::get_grid_size);
	ClassDB::bind_method(D_METHOD("set_terrain_size", "terrain_size"), &HeightmapTerrainMesh::set_terrain_size);
	ClassDB::bind_method(D_METHOD("get_terrain_size"), &HeightmapTerrainMesh::get_terrain_size);
	ClassDB::bind_method(D_METHOD("set_height_data", "height_data"), &HeightmapTerrainMesh::set_height_data);
	ClassDB::bind_method(D_METHOD("get_height_data"), &HeightmapTerrainMesh::get_height_data);
	ClassDB::bind_method(D_METHOD("set_layer_weights", "layer_weights"), &HeightmapTerrainMesh::set_layer_weights);
	ClassDB::bind_method(D_METHOD("get_layer_weights"), &HeightmapTerrainMesh::get_layer_weights);
	ClassDB::bind_method(D_METHOD("set_grid_height", "x", "z", "height"), &HeightmapTerrainMesh::set_grid_height);
	ClassDB::bind_method(D_METHOD("get_grid_height", "x", "z"), &HeightmapTerrainMesh::get_grid_height);
	ClassDB::bind_method(D_METHOD("get_local_height", "local_xz"), &HeightmapTerrainMesh::get_local_height);
	ClassDB::bind_method(D_METHOD("raise_brush", "local_xz", "radius", "delta"), &HeightmapTerrainMesh::raise_brush);
	ClassDB::bind_method(D_METHOD("flatten_brush", "local_xz", "radius", "height", "strength"), &HeightmapTerrainMesh::flatten_brush);
	ClassDB::bind_method(D_METHOD("smooth_brush", "local_xz", "radius", "strength"), &HeightmapTerrainMesh::smooth_brush);
	ClassDB::bind_method(D_METHOD("paint_layer", "local_xz", "radius", "layer", "strength"), &HeightmapTerrainMesh::paint_layer);

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "grid_size"), "set_grid_size", "get_grid_size");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "terrain_size", PROPERTY_HINT_NONE, "suffix:m"), "set_terrain_size", "get_terrain_size");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "height_data", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_height_data", "get_height_data");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "layer_weights", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_layer_weights", "get_layer_weights");
}
