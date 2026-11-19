/**************************************************************************/
/*  terrain_3d.cpp                                                        */
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

#include "terrain_3d.h"

#include "core/math/math_funcs.h"
#include "core/math/random_number_generator.h"
#include "core/object/class_db.h"
#include "core/io/image.h"
#include "scene/resources/material.h"
#include "scene/resources/mesh.h"
#include "scene/resources/multimesh.h"

void HeightmapTerrain3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_grid_size", "size"), &HeightmapTerrain3D::set_grid_size);
	ClassDB::bind_method(D_METHOD("get_grid_size"), &HeightmapTerrain3D::get_grid_size);
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &HeightmapTerrain3D::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &HeightmapTerrain3D::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_height_data", "data"), &HeightmapTerrain3D::set_height_data);
	ClassDB::bind_method(D_METHOD("get_height_data"), &HeightmapTerrain3D::get_height_data);
	ClassDB::bind_method(D_METHOD("set_color_data", "data"), &HeightmapTerrain3D::set_color_data);
	ClassDB::bind_method(D_METHOD("get_color_data"), &HeightmapTerrain3D::get_color_data);
	ClassDB::bind_method(D_METHOD("set_height_at", "x", "z", "height"), &HeightmapTerrain3D::set_height_at);
	ClassDB::bind_method(D_METHOD("get_height_at", "x", "z"), &HeightmapTerrain3D::get_height_at);
	ClassDB::bind_method(D_METHOD("sample_height", "grid_position"), &HeightmapTerrain3D::sample_height);
	ClassDB::bind_method(D_METHOD("sculpt", "grid_position", "radius", "delta"), &HeightmapTerrain3D::sculpt);
	ClassDB::bind_method(D_METHOD("smooth", "grid_position", "radius", "strength"), &HeightmapTerrain3D::smooth);
	ClassDB::bind_method(D_METHOD("paint_color", "grid_position", "radius", "color", "opacity"), &HeightmapTerrain3D::paint_color);
	ClassDB::bind_method(D_METHOD("erode_thermal", "iterations", "talus", "strength"), &HeightmapTerrain3D::erode_thermal);
	ClassDB::bind_method(D_METHOD("import_heightmap", "image", "min_height", "max_height"), &HeightmapTerrain3D::import_heightmap);
	ClassDB::bind_method(D_METHOD("create_foliage_multimesh", "mesh", "count", "seed", "min_normal_y", "min_scale", "max_scale"), &HeightmapTerrain3D::create_foliage_multimesh, DEFVAL(0.7), DEFVAL(0.8), DEFVAL(1.2));

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "grid_size"), "set_grid_size", "get_grid_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "0.01,100,0.01,or_greater"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "height_data", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_height_data", "get_height_data");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "color_data", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_color_data", "get_color_data");
}

void HeightmapTerrain3D::_validate_property(PropertyInfo &p_property) const {
	if (p_property.name == "mesh") {
		// MeshInstance3D's mesh is only a derived cache, never source data.
		p_property.usage &= ~PROPERTY_USAGE_STORAGE;
	}
}

float HeightmapTerrain3D::_height_clamped(int p_x, int p_z) const {
	const int x = CLAMP(p_x, 0, grid_size.x - 1);
	const int z = CLAMP(p_z, 0, grid_size.y - 1);
	return height_data[_index(x, z)];
}

void HeightmapTerrain3D::_rebuild_mesh() {
	if (height_data.size() != grid_size.x * grid_size.y || color_data.size() != height_data.size()) {
		return;
	}

	const int width = grid_size.x;
	const int depth = grid_size.y;
	const int vertex_count = width * depth;
	PackedVector3Array vertices;
	PackedVector3Array normals;
	PackedVector2Array uvs;
	PackedInt32Array indices;
	vertices.resize(vertex_count);
	normals.resize(vertex_count);
	uvs.resize(vertex_count);
	indices.resize((width - 1) * (depth - 1) * 6);

	for (int z = 0; z < depth; z++) {
		for (int x = 0; x < width; x++) {
			int i = _index(x, z);
			vertices.set(i, Vector3(x * cell_size, height_data[i], z * cell_size));
			const real_t dx = (_height_clamped(x - 1, z) - _height_clamped(x + 1, z)) / cell_size;
			const real_t dz = (_height_clamped(x, z - 1) - _height_clamped(x, z + 1)) / cell_size;
			normals.set(i, Vector3(dx, 2.0, dz).normalized());
			uvs.set(i, Vector2(real_t(x) / (width - 1), real_t(z) / (depth - 1)));
		}
	}

	int next = 0;
	for (int z = 0; z < depth - 1; z++) {
		for (int x = 0; x < width - 1; x++) {
			const int a = _index(x, z);
			const int b = _index(x + 1, z);
			const int c = _index(x, z + 1);
			const int d = _index(x + 1, z + 1);
			// Winding produces an upward normal for a flat heightfield.
			indices.set(next++, a);
			indices.set(next++, c);
			indices.set(next++, b);
			indices.set(next++, b);
			indices.set(next++, c);
			indices.set(next++, d);
		}
	}

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = vertices;
	arrays[Mesh::ARRAY_NORMAL] = normals;
	arrays[Mesh::ARRAY_TEX_UV] = uvs;
	arrays[Mesh::ARRAY_COLOR] = color_data;
	arrays[Mesh::ARRAY_INDEX] = indices;

	Ref<ArrayMesh> new_mesh;
	new_mesh.instantiate();
	new_mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	new_mesh->surface_set_material(0, default_material);
	set_mesh(new_mesh);
}

void HeightmapTerrain3D::set_grid_size(const Vector2i &p_size) {
	ERR_FAIL_COND_MSG(p_size.x < 2 || p_size.y < 2 || p_size.x > 257 || p_size.y > 257, "Terrain grid dimensions must be between 2 and 257.");
	if (grid_size == p_size) {
		return;
	}
	grid_size = p_size;
	height_data.resize(grid_size.x * grid_size.y);
	height_data.fill(0.0f);
	color_data.resize(height_data.size());
	color_data.fill(Color(1, 1, 1));
	_rebuild_mesh();
}

void HeightmapTerrain3D::set_cell_size(real_t p_size) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_size) || p_size <= 0.0, "Terrain cell size must be finite and greater than zero.");
	if (Math::is_equal_approx(cell_size, p_size)) {
		return;
	}
	cell_size = p_size;
	_rebuild_mesh();
}

void HeightmapTerrain3D::set_height_data(const PackedFloat32Array &p_data) {
	ERR_FAIL_COND_MSG(p_data.size() != grid_size.x * grid_size.y, "Terrain height data size does not match grid_size.");
	for (int i = 0; i < p_data.size(); i++) {
		ERR_FAIL_COND_MSG(!Math::is_finite(p_data[i]), "Terrain heights must be finite.");
	}
	height_data = p_data;
	_rebuild_mesh();
}

void HeightmapTerrain3D::set_color_data(const PackedColorArray &p_data) {
	ERR_FAIL_COND_MSG(p_data.size() != grid_size.x * grid_size.y, "Terrain color data size does not match grid_size.");
	color_data = p_data;
	_rebuild_mesh();
}

void HeightmapTerrain3D::set_height_at(int p_x, int p_z, float p_height) {
	ERR_FAIL_INDEX(p_x, grid_size.x);
	ERR_FAIL_INDEX(p_z, grid_size.y);
	ERR_FAIL_COND_MSG(!Math::is_finite(p_height), "Terrain height must be finite.");
	height_data.set(_index(p_x, p_z), p_height);
	_rebuild_mesh();
}

float HeightmapTerrain3D::get_height_at(int p_x, int p_z) const {
	ERR_FAIL_INDEX_V(p_x, grid_size.x, 0.0f);
	ERR_FAIL_INDEX_V(p_z, grid_size.y, 0.0f);
	return height_data[_index(p_x, p_z)];
}

real_t HeightmapTerrain3D::sample_height(const Vector2 &p_grid_position) const {
	ERR_FAIL_COND_V(!Math::is_finite(p_grid_position.x) || !Math::is_finite(p_grid_position.y), 0.0);
	ERR_FAIL_COND_V(p_grid_position.x < 0 || p_grid_position.y < 0 || p_grid_position.x > grid_size.x - 1 || p_grid_position.y > grid_size.y - 1, 0.0);
	const int x0 = (int)Math::floor(p_grid_position.x);
	const int z0 = (int)Math::floor(p_grid_position.y);
	const int x1 = MIN(x0 + 1, grid_size.x - 1);
	const int z1 = MIN(z0 + 1, grid_size.y - 1);
	const real_t fx = p_grid_position.x - x0;
	const real_t fz = p_grid_position.y - z0;
	const real_t h0 = Math::lerp((real_t)height_data[_index(x0, z0)], (real_t)height_data[_index(x1, z0)], fx);
	const real_t h1 = Math::lerp((real_t)height_data[_index(x0, z1)], (real_t)height_data[_index(x1, z1)], fx);
	return Math::lerp(h0, h1, fz);
}

void HeightmapTerrain3D::sculpt(const Vector2 &p_grid_position, real_t p_radius, real_t p_delta) {
	ERR_FAIL_COND(!Math::is_finite(p_grid_position.x) || !Math::is_finite(p_grid_position.y) || !Math::is_finite(p_radius) || !Math::is_finite(p_delta) || p_radius <= 0.0);
	const int min_x = MAX(0, (int)Math::floor(p_grid_position.x - p_radius));
	const int max_x = MIN(grid_size.x - 1, (int)Math::ceil(p_grid_position.x + p_radius));
	const int min_z = MAX(0, (int)Math::floor(p_grid_position.y - p_radius));
	const int max_z = MIN(grid_size.y - 1, (int)Math::ceil(p_grid_position.y + p_radius));
	for (int z = min_z; z <= max_z; z++) {
		for (int x = min_x; x <= max_x; x++) {
			real_t distance = Vector2(x, z).distance_to(p_grid_position);
			if (distance >= p_radius) {
				continue;
			}
			const real_t weight = 1.0 - distance / p_radius;
			height_data.set(_index(x, z), height_data[_index(x, z)] + p_delta * weight * weight);
		}
	}
	_rebuild_mesh();
}

void HeightmapTerrain3D::smooth(const Vector2 &p_grid_position, real_t p_radius, real_t p_strength) {
	ERR_FAIL_COND(!Math::is_finite(p_grid_position.x) || !Math::is_finite(p_grid_position.y) || !Math::is_finite(p_radius) || !Math::is_finite(p_strength) || p_radius <= 0.0);
	const real_t strength = CLAMP(p_strength, 0.0, 1.0);
	if (strength == 0.0) {
		return;
	}
	// Snapshot avoids scan-order bias.
	const PackedFloat32Array previous = height_data;
	for (int z = 0; z < grid_size.y; z++) {
		for (int x = 0; x < grid_size.x; x++) {
			const real_t distance = Vector2(x, z).distance_to(p_grid_position);
			if (distance >= p_radius) {
				continue;
			}
			real_t sum = 0.0;
			int count = 0;
			for (int oz = -1; oz <= 1; oz++) {
				for (int ox = -1; ox <= 1; ox++) {
					int nx = CLAMP(x + ox, 0, grid_size.x - 1);
					int nz = CLAMP(z + oz, 0, grid_size.y - 1);
					sum += previous[_index(nx, nz)];
					count++;
				}
			}
			const real_t weight = strength * (1.0 - distance / p_radius);
			height_data.set(_index(x, z), Math::lerp((real_t)previous[_index(x, z)], sum / count, weight));
		}
	}
	_rebuild_mesh();
}

void HeightmapTerrain3D::paint_color(const Vector2 &p_grid_position, real_t p_radius, const Color &p_color, real_t p_opacity) {
	ERR_FAIL_COND(!Math::is_finite(p_grid_position.x) || !Math::is_finite(p_grid_position.y) || !Math::is_finite(p_radius) || !Math::is_finite(p_opacity) || p_radius <= 0.0);
	const real_t opacity = CLAMP(p_opacity, 0.0, 1.0);
	for (int z = 0; z < grid_size.y; z++) {
		for (int x = 0; x < grid_size.x; x++) {
			real_t distance = Vector2(x, z).distance_to(p_grid_position);
			if (distance >= p_radius) {
				continue;
			}
			real_t weight = opacity * (1.0 - distance / p_radius);
			int i = _index(x, z);
			color_data.set(i, color_data[i].lerp(p_color, weight));
		}
	}
	_rebuild_mesh();
}


void HeightmapTerrain3D::erode_thermal(int p_iterations, real_t p_talus, real_t p_strength) {
	ERR_FAIL_COND_MSG(p_iterations < 0 || p_iterations > 128, "Thermal erosion requires 0 to 128 iterations.");
	ERR_FAIL_COND_MSG(!Math::is_finite(p_talus) || p_talus < 0.0, "Talus must be finite and nonnegative.");
	ERR_FAIL_COND_MSG(!Math::is_finite(p_strength) || p_strength < 0.0 || p_strength > 1.0, "Strength must be between 0 and 1.");
	if (p_iterations == 0 || p_strength == 0.0) {
		return;
	}

	const int dx[4] = { 1, -1, 0, 0 };
	const int dz[4] = { 0, 0, 1, -1 };
	for (int iteration = 0; iteration < p_iterations; iteration++) {
		PackedFloat32Array changes;
		changes.resize(height_data.size());
		changes.fill(0);
		for (int z = 0; z < grid_size.y; z++) {
			for (int x = 0; x < grid_size.x; x++) {
				const int source = _index(x, z);
				real_t drops[4] = {};
				real_t max_drop = 0.0;
				real_t total_drop = 0.0;
				for (int side = 0; side < 4; side++) {
					const int nx = x + dx[side];
					const int nz = z + dz[side];
					if (nx < 0 || nz < 0 || nx >= grid_size.x || nz >= grid_size.y) {
						continue;
					}
					const real_t drop = real_t(height_data[source]) - real_t(height_data[_index(nx, nz)]) - p_talus;
					if (drop > 0.0) {
						drops[side] = drop;
						total_drop += drop;
						max_drop = MAX(max_drop, drop);
					}
				}
				if (total_drop <= 0.0) {
					continue;
				}
				// Every downhill contribution is balanced by an equal source removal.
				const real_t transfer = max_drop * p_strength * 0.25;
				changes.set(source, changes[source] - transfer);
				for (int side = 0; side < 4; side++) {
					if (drops[side] <= 0.0) {
						continue;
					}
					int target = _index(x + dx[side], z + dz[side]);
					changes.set(target, changes[target] + transfer * drops[side] / total_drop);
				}
			}
		}
		for (int i = 0; i < height_data.size(); i++) {
			height_data.set(i, height_data[i] + changes[i]);
		}
	}
	_rebuild_mesh();
}

void HeightmapTerrain3D::import_heightmap(const Ref<Image> &p_image, real_t p_min_height, real_t p_max_height) {
	ERR_FAIL_COND(p_image.is_null() || p_image->is_empty() || p_image->is_compressed());
	ERR_FAIL_COND(!Math::is_finite(p_min_height) || !Math::is_finite(p_max_height) || p_max_height < p_min_height);
	const Vector2i size(p_image->get_width(), p_image->get_height());
	ERR_FAIL_COND(size.x < 2 || size.y < 2 || size.x > 257 || size.y > 257);
	// Validate first, then mutate atomically.
	PackedFloat32Array imported;
	imported.resize(size.x * size.y);
	for (int z = 0; z < size.y; z++) {
		for (int x = 0; x < size.x; x++) {
			float grayscale = p_image->get_pixel(x, z).get_luminance();
			imported.set(z * size.x + x, Math::lerp(p_min_height, p_max_height, (real_t)CLAMP(grayscale, 0.0f, 1.0f)));
		}
	}
	if (size != grid_size) {
		grid_size = size;
		color_data.resize(imported.size());
		color_data.fill(Color(1, 1, 1));
		notify_property_list_changed();
	}
	height_data = imported;
	_rebuild_mesh();
}

HeightmapTerrain3D::HeightmapTerrain3D() {
	height_data.resize(grid_size.x * grid_size.y);
	height_data.fill(0.0);
	color_data.resize(height_data.size());
	color_data.fill(Color(1, 1, 1));
	default_material.instantiate();
	default_material->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
	_rebuild_mesh();
}

Ref<MultiMesh> HeightmapTerrain3D::create_foliage_multimesh(const Ref<Mesh> &p_mesh, int p_count, int p_seed, real_t p_min_normal_y, real_t p_min_scale, real_t p_max_scale) const {
	ERR_FAIL_COND_V_MSG(p_mesh.is_null(), Ref<MultiMesh>(), "A foliage mesh is required.");
	ERR_FAIL_COND_V_MSG(p_count < 0 || p_count > 100000, Ref<MultiMesh>(), "Foliage instance count must be between 0 and 100000.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_min_normal_y) || p_min_normal_y < 0.0 || p_min_normal_y > 1.0, Ref<MultiMesh>(), "Minimum surface normal Y must be between 0 and 1.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_min_scale) || !Math::is_finite(p_max_scale) || p_min_scale <= 0.0 || p_max_scale < p_min_scale || p_max_scale > 1000.0, Ref<MultiMesh>(), "Foliage scales must be positive, finite and ordered, with maximum at most 1000.");
	ERR_FAIL_COND_V_MSG(grid_size.x < 2 || grid_size.y < 2 || height_data.size() != grid_size.x * grid_size.y, Ref<MultiMesh>(), "Terrain grid data is invalid.");

	Ref<MultiMesh> result;
	result.instantiate();
	result->set_transform_format(MultiMesh::TRANSFORM_3D);
	result->set_mesh(p_mesh);
	if (p_count == 0) {
		return result;
	}

	RandomNumberGenerator random;
	random.set_seed(uint64_t(int64_t(p_seed)));
	Vector<Transform3D> instances;
	instances.reserve(p_count);

	const real_t grid_max_x = real_t(grid_size.x - 1);
	const real_t grid_max_z = real_t(grid_size.y - 1);
	// Rejection sampling is deliberately bounded: a steep surface may yield
	// fewer than p_count instances instead of stalling the editor.
	const int max_attempts = p_count * 8;
	for (int attempt = 0; attempt < max_attempts && instances.size() < p_count; attempt++) {
		const real_t gx = CLAMP(random.randf_range(0.0, grid_max_x), 0.0, grid_max_x);
		const real_t gz = CLAMP(random.randf_range(0.0, grid_max_z), 0.0, grid_max_z);
		const real_t x_minus = MAX(real_t(0.0), gx - 0.25);
		const real_t x_plus = MIN(grid_max_x, gx + 0.25);
		const real_t z_minus = MAX(real_t(0.0), gz - 0.25);
		const real_t z_plus = MIN(grid_max_z, gz + 0.25);
		const real_t slope_x = (sample_height(Vector2(x_plus, gz)) - sample_height(Vector2(x_minus, gz))) / ((x_plus - x_minus) * cell_size);
		const real_t slope_z = (sample_height(Vector2(gx, z_plus)) - sample_height(Vector2(gx, z_minus))) / ((z_plus - z_minus) * cell_size);
		const Vector3 normal(-slope_x, 1.0, -slope_z);
		if (normal.normalized().y < p_min_normal_y) {
			continue;
		}

		const real_t angle = random.randf_range(0.0, Math::TAU);
		const real_t scale = random.randf_range(p_min_scale, p_max_scale);
		const Basis basis = Basis(Vector3(0, 1, 0), angle).scaled(Vector3(scale, scale, scale));
		const Vector3 origin(gx * cell_size, sample_height(Vector2(gx, gz)), gz * cell_size);
		instances.push_back(Transform3D(basis, origin));
	}

	result->set_instance_count(instances.size());
	for (int i = 0; i < instances.size(); i++) {
		result->set_instance_transform(i, instances[i]);
	}

	// MultiMesh draws as one object. Provide a conservative local AABB so
	// shifted/rotated mesh origins are not culled while terrain streaming.
	const AABB mesh_bounds = p_mesh->get_aabb();
	const Vector3 mesh_min = mesh_bounds.position;
	const Vector3 mesh_max = mesh_bounds.get_end();
	const real_t max_x = MAX(Math::abs(mesh_min.x), Math::abs(mesh_max.x));
	const real_t max_y = MAX(Math::abs(mesh_min.y), Math::abs(mesh_max.y));
	const real_t max_z = MAX(Math::abs(mesh_min.z), Math::abs(mesh_max.z));
	const real_t radius = Math::sqrt(max_x * max_x + max_y * max_y + max_z * max_z) * p_max_scale;
	float min_height = height_data[0];
	float max_height = height_data[0];
	for (float h : height_data) {
		min_height = MIN(min_height, h);
		max_height = MAX(max_height, h);
	}
	const Vector3 aabb_position(-radius, real_t(min_height) - radius, -radius);
	const Vector3 aabb_size(grid_max_x * cell_size + radius * 2.0, real_t(max_height - min_height) + radius * 2.0, grid_max_z * cell_size + radius * 2.0);
	result->set_custom_aabb(AABB(aabb_position, aabb_size));
	return result;
}
