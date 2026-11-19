/**************************************************************************/
/*  chunked_terrain_3d.cpp                                             */
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

#include "chunked_terrain_3d.h"

#include "core/config/engine.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "scene/main/viewport.h"
#include "scene/3d/camera_3d.h"
#include "scene/resources/3d/world_3d.h"
#include "servers/rendering/rendering_server.h"

#ifndef PHYSICS_3D_DISABLED
#include "servers/physics_3d/physics_server_3d.h"
#endif

using namespace HeightmapTerrainGeometry;

HeightmapTerrainGeometry::Params ChunkedTerrain3D::_params() const {
	Params params;
	const int width = MAX(data_width, 2);
	const int depth = MAX(data_depth, 2);
	params.spacing = Vector2(size.x / real_t(width - 1), size.y / real_t(depth - 1));
	params.height_scale = height_scale;
	params.height_offset = height_offset;
	params.origin = centered ? -size * real_t(0.5) : Vector2();
	params.skirt_depth = skirt_depth;
	return params;
}

HeightField ChunkedTerrain3D::_field() const {
	HeightField field;
	field.heights = height_data.ptr();
	field.width = data_width;
	field.depth = data_depth;
	return field;
}

void ChunkedTerrain3D::_load_from_texture() {
	if (data_from_script) {
		return;
	}
	height_data.clear();
	data_width = 0;
	data_depth = 0;
	if (heightmap.is_null()) {
		return;
	}
	Ref<Image> image = heightmap->get_image();
	if (image.is_null() || image->is_empty()) {
		return;
	}
	if (image->is_compressed()) {
		image->decompress();
	}
	data_width = image->get_width();
	data_depth = image->get_height();
	height_data.resize(data_width * data_depth);
	real_t *out = height_data.ptrw();
	for (int z = 0; z < data_depth; z++) {
		for (int x = 0; x < data_width; x++) {
			// The red channel carries the height. Float or half float images keep full precision;
			// 8 bit images give 256 height steps.
			out[z * data_width + x] = image->get_pixel(x, z).r;
		}
	}
}

void ChunkedTerrain3D::_queue_rebuild() {
	if (!is_inside_tree()) {
		built = false;
		return;
	}
	if (!rebuild_queued) {
		rebuild_queued = true;
		callable_mp(this, &ChunkedTerrain3D::force_update).call_deferred();
	}
}

void ChunkedTerrain3D::_free_collision(Chunk &r_chunk) {
#ifndef PHYSICS_3D_DISABLED
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	if (ps) {
		if (r_chunk.body.is_valid()) {
			ps->free_rid(r_chunk.body);
		}
		if (r_chunk.shape.is_valid()) {
			ps->free_rid(r_chunk.shape);
		}
	}
	r_chunk.body = RID();
	r_chunk.shape = RID();
#endif
	r_chunk.has_collision = false;
}

void ChunkedTerrain3D::_free_chunk_mesh_and_collision(Chunk &r_chunk) {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs) {
		if (r_chunk.instance.is_valid()) {
			rs->free_rid(r_chunk.instance);
		}
		for (int i = 0; i < MAX_LOD; i++) {
			if (r_chunk.meshes[i].is_valid()) {
				rs->free_rid(r_chunk.meshes[i]);
			}
		}
	}
	r_chunk.instance = RID();
	for (int i = 0; i < MAX_LOD; i++) {
		r_chunk.meshes[i] = RID();
	}
	r_chunk.lod = -1;
	r_chunk.visible = false;
	_free_collision(r_chunk);
}

void ChunkedTerrain3D::_free_chunks() {
	for (Chunk &chunk : chunks) {
		_free_chunk_mesh_and_collision(chunk);
	}
	chunks.clear();
	chunks_x = 0;
	chunks_z = 0;
}

void ChunkedTerrain3D::_rebuild() {
	_free_chunks();
	built = false;
	if (!is_inside_tree() || !get_world_3d().is_valid()) {
		return;
	}
	_load_from_texture();
	const HeightField field = _field();
	if (!field.is_valid() || !(size.x > 0.0) || !(size.y > 0.0)) {
		return;
	}
	chunks_x = (data_width - 1 + chunk_quads - 1) / chunk_quads;
	chunks_z = (data_depth - 1 + chunk_quads - 1) / chunk_quads;
	chunks.resize(uint32_t(chunks_x) * uint32_t(chunks_z));
	const Params params = _params();
	for (int cz = 0; cz < chunks_z; cz++) {
		for (int cx = 0; cx < chunks_x; cx++) {
			Chunk &chunk = chunks[cz * chunks_x + cx];
			chunk.x0 = cx * chunk_quads;
			chunk.z0 = cz * chunk_quads;
			real_t low;
			real_t high;
			chunk_height_range(field, chunk.x0, chunk.z0, chunk_quads, low, high);
			const int x1 = MIN(chunk.x0 + chunk_quads, data_width - 1);
			const int z1 = MIN(chunk.z0 + chunk_quads, data_depth - 1);
			const Vector3 a(params.origin.x + real_t(chunk.x0) * params.spacing.x, low * height_scale + height_offset, params.origin.y + real_t(chunk.z0) * params.spacing.y);
			const Vector3 b(params.origin.x + real_t(x1) * params.spacing.x, high * height_scale + height_offset, params.origin.y + real_t(z1) * params.spacing.y);
			chunk.bounds = AABB(a, b - a).abs();
		}
	}
	built = true;
	time_since_update = 1e9;
}

void ChunkedTerrain3D::_ensure_mesh(Chunk &r_chunk, int p_lod) {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (!rs || r_chunk.meshes[p_lod].is_valid()) {
		return;
	}
	ChunkMesh mesh;
	if (!build_chunk(_field(), r_chunk.x0, r_chunk.z0, chunk_quads, lod_stride(p_lod, chunk_quads), _params(), mesh)) {
		return;
	}
	Array arrays;
	arrays.resize(RSE::ARRAY_MAX);
	arrays[RSE::ARRAY_VERTEX] = mesh.vertices;
	arrays[RSE::ARRAY_NORMAL] = mesh.normals;
	arrays[RSE::ARRAY_TEX_UV] = mesh.uvs;
	arrays[RSE::ARRAY_INDEX] = mesh.indices;
	const RID mesh_rid = rs->mesh_create();
	rs->mesh_add_surface_from_arrays(mesh_rid, RSE::PRIMITIVE_TRIANGLES, arrays);
	if (material.is_valid()) {
		rs->mesh_surface_set_material(mesh_rid, 0, material->get_rid());
	}
	r_chunk.meshes[p_lod] = mesh_rid;
}

void ChunkedTerrain3D::_ensure_collision(Chunk &r_chunk) {
#ifndef PHYSICS_3D_DISABLED
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	if (!ps || r_chunk.has_collision || !get_world_3d().is_valid()) {
		return;
	}
	const int width = MIN(chunk_quads + 1, data_width - r_chunk.x0);
	const int depth = MIN(chunk_quads + 1, data_depth - r_chunk.z0);
	if (width < 2 || depth < 2) {
		return;
	}
	PackedFloat32Array heights;
	heights.resize(width * depth);
	float *out = heights.ptrw();
	real_t low = Math::INF;
	real_t high = -Math::INF;
	for (int z = 0; z < depth; z++) {
		for (int x = 0; x < width; x++) {
			const real_t h = height_data[(r_chunk.z0 + z) * data_width + r_chunk.x0 + x] * height_scale + height_offset;
			out[z * width + x] = h;
			low = MIN(low, h);
			high = MAX(high, h);
		}
	}
	Dictionary data;
	data["width"] = width;
	data["depth"] = depth;
	data["heights"] = heights;
	data["min_height"] = low;
	data["max_height"] = high;

	r_chunk.shape = ps->heightmap_shape_create();
	ps->shape_set_data(r_chunk.shape, data);
	r_chunk.body = ps->body_create();
	ps->body_set_mode(r_chunk.body, PS3DE::BODY_MODE_STATIC);
	ps->body_set_space(r_chunk.body, get_world_3d()->get_space());
	ps->body_set_collision_layer(r_chunk.body, collision_layer);
	ps->body_set_collision_mask(r_chunk.body, collision_mask);

	// The heightmap shape is centered on its own origin with one unit between samples.
	const Params params = _params();
	const Vector3 scale = get_global_transform().basis.get_scale();
	const Vector3 center = Vector3(params.origin.x + (real_t(r_chunk.x0) + real_t(width - 1) * real_t(0.5)) * params.spacing.x, 0.0, params.origin.y + (real_t(r_chunk.z0) + real_t(depth - 1) * real_t(0.5)) * params.spacing.y);
	Transform3D shape_transform;
	shape_transform.basis = Basis::from_scale(Vector3(params.spacing.x * scale.x, scale.y, params.spacing.y * scale.z));
	shape_transform.origin = center * scale;
	ps->body_add_shape(r_chunk.body, r_chunk.shape, shape_transform);
	Transform3D body_transform = get_global_transform();
	body_transform.basis = body_transform.basis.orthonormalized();
	ps->body_set_state(r_chunk.body, PS3DE::BODY_STATE_TRANSFORM, body_transform);
	r_chunk.has_collision = true;
#endif
}

void ChunkedTerrain3D::_update_transforms() {
	RenderingServer *rs = RenderingServer::get_singleton();
	const Transform3D global = get_global_transform();
	for (Chunk &chunk : chunks) {
		if (rs && chunk.instance.is_valid()) {
			rs->instance_set_transform(chunk.instance, global);
		}
#ifndef PHYSICS_3D_DISABLED
		if (chunk.has_collision && PhysicsServer3D::get_singleton()) {
			Transform3D body_transform = global;
			body_transform.basis = body_transform.basis.orthonormalized();
			PhysicsServer3D::get_singleton()->body_set_state(chunk.body, PS3DE::BODY_STATE_TRANSFORM, body_transform);
		}
#endif
	}
}

bool ChunkedTerrain3D::_get_viewer_position(Vector3 &r_position) const {
	if (!focus.is_empty()) {
		if (Node3D *node = Object::cast_to<Node3D>(get_node_or_null(focus))) {
			if (node->is_inside_tree()) {
				r_position = node->get_global_position();
				return true;
			}
		}
	}
	Viewport *viewport = get_viewport();
	if (viewport) {
		if (Camera3D *camera = viewport->get_camera_3d()) {
			r_position = camera->get_global_position();
			return true;
		}
	}
	return false;
}

void ChunkedTerrain3D::_update_chunks() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (!rs || !built || chunks.is_empty() || !is_inside_tree()) {
		return;
	}
	Vector3 viewer_global;
	const bool has_viewer = _get_viewer_position(viewer_global);
	const Transform3D global = get_global_transform();
	const Vector3 viewer = has_viewer ? global.affine_inverse().xform(viewer_global) : Vector3();
	const Vector3 scale = global.basis.get_scale();
	const real_t unit_scale = (scale.x + scale.z) * real_t(0.5);
	const RID scenario = get_world_3d()->get_scenario();

	for (Chunk &chunk : chunks) {
		// Distance from the viewer to the closest point of the chunk's box, in world units.
		real_t distance = 0.0;
		if (has_viewer) {
			const Vector3 low = chunk.bounds.position;
			const Vector3 high = chunk.bounds.get_end();
			const Vector3 closest = viewer.clamp(low, high);
			distance = (viewer - closest).length() * unit_scale;
		}

		const bool in_range = !has_viewer || view_distance <= 0.0 || distance <= view_distance;
		if (!in_range) {
			if (chunk.visible && chunk.instance.is_valid()) {
				rs->instance_set_visible(chunk.instance, false);
				chunk.visible = false;
			}
		} else {
			// Without a viewer (editor) use a moderate level instead of the most expensive one.
			const int lod = has_viewer ? select_lod(distance, lod_distance, lod_count, chunk.lod) : MIN(1, lod_count - 1);
			if (lod != chunk.lod || !chunk.instance.is_valid()) {
				_ensure_mesh(chunk, lod);
				if (chunk.meshes[lod].is_valid()) {
					if (!chunk.instance.is_valid()) {
						chunk.instance = rs->instance_create2(chunk.meshes[lod], scenario);
						rs->instance_set_transform(chunk.instance, global);
						rs->instance_geometry_set_cast_shadows_setting(chunk.instance, cast_shadows ? RSE::SHADOW_CASTING_SETTING_ON : RSE::SHADOW_CASTING_SETTING_OFF);
					} else {
						rs->instance_set_base(chunk.instance, chunk.meshes[lod]);
					}
					chunk.lod = lod;
				}
			}
			if (chunk.instance.is_valid() && !chunk.visible) {
				rs->instance_set_visible(chunk.instance, true);
				chunk.visible = true;
			}
		}

		if (collision_enabled && has_viewer) {
			if (distance <= collision_distance) {
				if (!chunk.has_collision) {
					_ensure_collision(chunk);
				}
			} else if (chunk.has_collision && distance > collision_distance * real_t(1.25)) {
				_free_collision(chunk);
			}
		} else if (chunk.has_collision) {
			_free_collision(chunk);
		}
	}
}

void ChunkedTerrain3D::force_update() {
	rebuild_queued = false;
	if (!built) {
		_rebuild();
	}
	_update_chunks();
	time_since_update = 0.0;
}

void ChunkedTerrain3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_WORLD: {
			set_process_internal(true);
			_rebuild();
			_update_chunks();
		} break;

		case NOTIFICATION_EXIT_WORLD: {
			set_process_internal(false);
			_free_chunks();
			built = false;
		} break;

		case NOTIFICATION_TRANSFORM_CHANGED: {
			_update_transforms();
		} break;

		case NOTIFICATION_VISIBILITY_CHANGED: {
			RenderingServer *rs = RenderingServer::get_singleton();
			if (rs) {
				const bool visible = is_visible_in_tree();
				for (Chunk &chunk : chunks) {
					if (chunk.instance.is_valid()) {
						rs->instance_set_visible(chunk.instance, visible && chunk.visible);
					}
				}
			}
		} break;

		case NOTIFICATION_INTERNAL_PROCESS: {
			time_since_update += get_process_delta_time();
			if (time_since_update >= update_interval) {
				time_since_update = 0.0;
				if (!built) {
					_rebuild();
				}
				_update_chunks();
			}
		} break;
	}
}

void ChunkedTerrain3D::set_heightmap(const Ref<Texture2D> &p_texture) {
	if (heightmap == p_texture) {
		return;
	}
	heightmap = p_texture;
	if (!data_from_script) {
		built = false;
		_queue_rebuild();
	}
}

void ChunkedTerrain3D::set_height_data(const PackedFloat32Array &p_heights, const Vector2i &p_dimensions) {
	ERR_FAIL_COND_MSG(p_dimensions.x < 2 || p_dimensions.y < 2, "ChunkedTerrain3D needs at least 2 x 2 height samples.");
	ERR_FAIL_COND_MSG(p_heights.size() != p_dimensions.x * p_dimensions.y, "ChunkedTerrain3D height data size does not match the dimensions.");
	data_from_script = true;
	data_width = p_dimensions.x;
	data_depth = p_dimensions.y;
	height_data.resize(p_heights.size());
	real_t *out = height_data.ptrw();
	const float *in = p_heights.ptr();
	for (int i = 0; i < p_heights.size(); i++) {
		out[i] = in[i];
	}
	built = false;
	_queue_rebuild();
}

PackedFloat32Array ChunkedTerrain3D::get_height_data() const {
	PackedFloat32Array result;
	result.resize(height_data.size());
	float *out = result.ptrw();
	for (int i = 0; i < height_data.size(); i++) {
		out[i] = float(height_data[i]);
	}
	return result;
}

void ChunkedTerrain3D::clear_height_data() {
	data_from_script = false;
	built = false;
	_queue_rebuild();
}

#define TERRAIN_REBUILD_SETTER(m_setter, m_type, m_member, m_expression) \
	void ChunkedTerrain3D::m_setter(m_type p_value) {                   \
		const m_type value = m_expression;                                  \
		if (m_member == value) {                                            \
			return;                                                         \
		}                                                                   \
		m_member = value;                                                   \
		built = false;                                                      \
		_queue_rebuild();                                                   \
	}

TERRAIN_REBUILD_SETTER(set_height_scale, real_t, height_scale, p_value)
TERRAIN_REBUILD_SETTER(set_height_offset, real_t, height_offset, p_value)
TERRAIN_REBUILD_SETTER(set_centered, bool, centered, p_value)
TERRAIN_REBUILD_SETTER(set_skirt_depth, real_t, skirt_depth, MAX(p_value, real_t(0.0)))
TERRAIN_REBUILD_SETTER(set_chunk_quads, int, chunk_quads, CLAMP(p_value, 2, 256))

void ChunkedTerrain3D::set_size(const Vector2 &p_size) {
	ERR_FAIL_COND_MSG(!(p_size.x > 0.0) || !(p_size.y > 0.0) || !p_size.is_finite(), "ChunkedTerrain3D size must be positive and finite.");
	if (size == p_size) {
		return;
	}
	size = p_size;
	built = false;
	_queue_rebuild();
}

void ChunkedTerrain3D::set_lod_count(int p_count) {
	lod_count = CLAMP(p_count, 1, MAX_LOD);
	for (Chunk &chunk : chunks) {
		chunk.lod = -1; // Re-evaluate; the existing meshes stay cached.
	}
}

void ChunkedTerrain3D::set_lod_distance(real_t p_distance) {
	lod_distance = MAX(p_distance, real_t(1.0));
}

void ChunkedTerrain3D::set_view_distance(real_t p_distance) {
	view_distance = MAX(p_distance, real_t(0.0));
}

void ChunkedTerrain3D::set_material(const Ref<Material> &p_material) {
	material = p_material;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (!rs) {
		return;
	}
	for (Chunk &chunk : chunks) {
		for (int i = 0; i < MAX_LOD; i++) {
			if (chunk.meshes[i].is_valid()) {
				rs->mesh_surface_set_material(chunk.meshes[i], 0, material.is_valid() ? material->get_rid() : RID());
			}
		}
	}
}

void ChunkedTerrain3D::set_cast_shadows(bool p_enabled) {
	cast_shadows = p_enabled;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (!rs) {
		return;
	}
	for (Chunk &chunk : chunks) {
		if (chunk.instance.is_valid()) {
			rs->instance_geometry_set_cast_shadows_setting(chunk.instance, cast_shadows ? RSE::SHADOW_CASTING_SETTING_ON : RSE::SHADOW_CASTING_SETTING_OFF);
		}
	}
}

void ChunkedTerrain3D::set_collision_enabled(bool p_enabled) {
	collision_enabled = p_enabled;
	if (!collision_enabled) {
		for (Chunk &chunk : chunks) {
			if (chunk.has_collision) {
				_free_collision(chunk);
			}
		}
	}
}

void ChunkedTerrain3D::set_collision_distance(real_t p_distance) {
	collision_distance = MAX(p_distance, real_t(0.0));
}

void ChunkedTerrain3D::set_collision_layer(uint32_t p_layer) {
	collision_layer = p_layer;
#ifndef PHYSICS_3D_DISABLED
	for (Chunk &chunk : chunks) {
		if (chunk.has_collision) {
			PhysicsServer3D::get_singleton()->body_set_collision_layer(chunk.body, collision_layer);
		}
	}
#endif
}

void ChunkedTerrain3D::set_collision_mask(uint32_t p_mask) {
	collision_mask = p_mask;
#ifndef PHYSICS_3D_DISABLED
	for (Chunk &chunk : chunks) {
		if (chunk.has_collision) {
			PhysicsServer3D::get_singleton()->body_set_collision_mask(chunk.body, collision_mask);
		}
	}
#endif
}

real_t ChunkedTerrain3D::get_height_at(const Vector3 &p_world_position) const {
	const HeightField field = _field();
	if (!field.is_valid()) {
		return get_global_position().y;
	}
	const Transform3D global = get_global_transform();
	const Vector3 local = global.affine_inverse().xform(p_world_position);
	const Params params = _params();
	const real_t sx = (local.x - params.origin.x) / params.spacing.x;
	const real_t sz = (local.z - params.origin.y) / params.spacing.y;
	const real_t height = sample_height(field, sx, sz) * height_scale + height_offset;
	return global.xform(Vector3(local.x, height, local.z)).y;
}

Vector3 ChunkedTerrain3D::get_normal_at(const Vector3 &p_world_position) const {
	const HeightField field = _field();
	if (!field.is_valid()) {
		return Vector3(0, 1, 0);
	}
	const Transform3D global = get_global_transform();
	const Vector3 local = global.affine_inverse().xform(p_world_position);
	const Params params = _params();
	const Vector3 normal = sample_normal_bilinear(field, (local.x - params.origin.x) / params.spacing.x, (local.z - params.origin.y) / params.spacing.y, params);
	return global.basis.get_rotation_quaternion().xform(normal).normalized();
}

bool ChunkedTerrain3D::is_over_terrain(const Vector3 &p_world_position) const {
	if (!_field().is_valid()) {
		return false;
	}
	const Vector3 local = get_global_transform().affine_inverse().xform(p_world_position);
	const Params params = _params();
	return local.x >= params.origin.x && local.x <= params.origin.x + size.x && local.z >= params.origin.y && local.z <= params.origin.y + size.y;
}

void ChunkedTerrain3D::update_region(const Rect2i &p_region) {
	if (!built || chunks.is_empty()) {
		return;
	}
	// Normals read one sample beyond a chunk, so include the neighbours of every touched chunk.
	const Rect2i grown = p_region.grow(1);
	RenderingServer *rs = RenderingServer::get_singleton();
	const Params params = _params();
	for (Chunk &chunk : chunks) {
		const Rect2i chunk_samples(chunk.x0, chunk.z0, chunk_quads + 1, chunk_quads + 1);
		if (!chunk_samples.intersects(grown)) {
			continue;
		}
		for (int i = 0; i < MAX_LOD; i++) {
			if (chunk.meshes[i].is_valid() && rs) {
				if (chunk.lod == i && chunk.instance.is_valid()) {
					// Detach before freeing; it is re-attached at the next update.
					rs->instance_set_visible(chunk.instance, false);
				}
				rs->free_rid(chunk.meshes[i]);
				chunk.meshes[i] = RID();
			}
		}
		if (chunk.instance.is_valid() && rs) {
			rs->free_rid(chunk.instance);
			chunk.instance = RID();
		}
		chunk.lod = -1;
		chunk.visible = false;
		_free_collision(chunk);

		real_t low;
		real_t high;
		chunk_height_range(_field(), chunk.x0, chunk.z0, chunk_quads, low, high);
		const int x1 = MIN(chunk.x0 + chunk_quads, data_width - 1);
		const int z1 = MIN(chunk.z0 + chunk_quads, data_depth - 1);
		const Vector3 a(params.origin.x + real_t(chunk.x0) * params.spacing.x, low * height_scale + height_offset, params.origin.y + real_t(chunk.z0) * params.spacing.y);
		const Vector3 b(params.origin.x + real_t(x1) * params.spacing.x, high * height_scale + height_offset, params.origin.y + real_t(z1) * params.spacing.y);
		chunk.bounds = AABB(a, b - a).abs();
	}
	time_since_update = 1e9;
}

int ChunkedTerrain3D::get_visible_chunk_count() const {
	int count = 0;
	for (const Chunk &chunk : chunks) {
		if (chunk.visible) {
			count++;
		}
	}
	return count;
}

int ChunkedTerrain3D::get_collision_chunk_count() const {
	int count = 0;
	for (const Chunk &chunk : chunks) {
		if (chunk.has_collision) {
			count++;
		}
	}
	return count;
}

int ChunkedTerrain3D::get_chunk_lod(const Vector2i &p_chunk) const {
	ERR_FAIL_COND_V(p_chunk.x < 0 || p_chunk.y < 0 || p_chunk.x >= chunks_x || p_chunk.y >= chunks_z, -1);
	return chunks[p_chunk.y * chunks_x + p_chunk.x].lod;
}

void ChunkedTerrain3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_heightmap", "texture"), &ChunkedTerrain3D::set_heightmap);
	ClassDB::bind_method(D_METHOD("get_heightmap"), &ChunkedTerrain3D::get_heightmap);
	ClassDB::bind_method(D_METHOD("set_height_data", "heights", "dimensions"), &ChunkedTerrain3D::set_height_data);
	ClassDB::bind_method(D_METHOD("get_height_data"), &ChunkedTerrain3D::get_height_data);
	ClassDB::bind_method(D_METHOD("get_height_dimensions"), &ChunkedTerrain3D::get_height_dimensions);
	ClassDB::bind_method(D_METHOD("clear_height_data"), &ChunkedTerrain3D::clear_height_data);
	ClassDB::bind_method(D_METHOD("set_size", "size"), &ChunkedTerrain3D::set_size);
	ClassDB::bind_method(D_METHOD("get_size"), &ChunkedTerrain3D::get_size);
	ClassDB::bind_method(D_METHOD("set_height_scale", "scale"), &ChunkedTerrain3D::set_height_scale);
	ClassDB::bind_method(D_METHOD("get_height_scale"), &ChunkedTerrain3D::get_height_scale);
	ClassDB::bind_method(D_METHOD("set_height_offset", "offset"), &ChunkedTerrain3D::set_height_offset);
	ClassDB::bind_method(D_METHOD("get_height_offset"), &ChunkedTerrain3D::get_height_offset);
	ClassDB::bind_method(D_METHOD("set_centered", "centered"), &ChunkedTerrain3D::set_centered);
	ClassDB::bind_method(D_METHOD("is_centered"), &ChunkedTerrain3D::is_centered);
	ClassDB::bind_method(D_METHOD("set_chunk_quads", "quads"), &ChunkedTerrain3D::set_chunk_quads);
	ClassDB::bind_method(D_METHOD("get_chunk_quads"), &ChunkedTerrain3D::get_chunk_quads);
	ClassDB::bind_method(D_METHOD("set_lod_count", "count"), &ChunkedTerrain3D::set_lod_count);
	ClassDB::bind_method(D_METHOD("get_lod_count"), &ChunkedTerrain3D::get_lod_count);
	ClassDB::bind_method(D_METHOD("set_lod_distance", "distance"), &ChunkedTerrain3D::set_lod_distance);
	ClassDB::bind_method(D_METHOD("get_lod_distance"), &ChunkedTerrain3D::get_lod_distance);
	ClassDB::bind_method(D_METHOD("set_view_distance", "distance"), &ChunkedTerrain3D::set_view_distance);
	ClassDB::bind_method(D_METHOD("get_view_distance"), &ChunkedTerrain3D::get_view_distance);
	ClassDB::bind_method(D_METHOD("set_skirt_depth", "depth"), &ChunkedTerrain3D::set_skirt_depth);
	ClassDB::bind_method(D_METHOD("get_skirt_depth"), &ChunkedTerrain3D::get_skirt_depth);
	ClassDB::bind_method(D_METHOD("set_material", "material"), &ChunkedTerrain3D::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &ChunkedTerrain3D::get_material);
	ClassDB::bind_method(D_METHOD("set_cast_shadows", "enabled"), &ChunkedTerrain3D::set_cast_shadows);
	ClassDB::bind_method(D_METHOD("get_cast_shadows"), &ChunkedTerrain3D::get_cast_shadows);
	ClassDB::bind_method(D_METHOD("set_collision_enabled", "enabled"), &ChunkedTerrain3D::set_collision_enabled);
	ClassDB::bind_method(D_METHOD("is_collision_enabled"), &ChunkedTerrain3D::is_collision_enabled);
	ClassDB::bind_method(D_METHOD("set_collision_distance", "distance"), &ChunkedTerrain3D::set_collision_distance);
	ClassDB::bind_method(D_METHOD("get_collision_distance"), &ChunkedTerrain3D::get_collision_distance);
	ClassDB::bind_method(D_METHOD("set_collision_layer", "layer"), &ChunkedTerrain3D::set_collision_layer);
	ClassDB::bind_method(D_METHOD("get_collision_layer"), &ChunkedTerrain3D::get_collision_layer);
	ClassDB::bind_method(D_METHOD("set_collision_mask", "mask"), &ChunkedTerrain3D::set_collision_mask);
	ClassDB::bind_method(D_METHOD("get_collision_mask"), &ChunkedTerrain3D::get_collision_mask);
	ClassDB::bind_method(D_METHOD("set_focus", "focus"), &ChunkedTerrain3D::set_focus);
	ClassDB::bind_method(D_METHOD("get_focus"), &ChunkedTerrain3D::get_focus);
	ClassDB::bind_method(D_METHOD("set_update_interval", "seconds"), &ChunkedTerrain3D::set_update_interval);
	ClassDB::bind_method(D_METHOD("get_update_interval"), &ChunkedTerrain3D::get_update_interval);

	ClassDB::bind_method(D_METHOD("get_height_at", "world_position"), &ChunkedTerrain3D::get_height_at);
	ClassDB::bind_method(D_METHOD("get_normal_at", "world_position"), &ChunkedTerrain3D::get_normal_at);
	ClassDB::bind_method(D_METHOD("is_over_terrain", "world_position"), &ChunkedTerrain3D::is_over_terrain);
	ClassDB::bind_method(D_METHOD("update_region", "region"), &ChunkedTerrain3D::update_region);
	ClassDB::bind_method(D_METHOD("get_chunk_count"), &ChunkedTerrain3D::get_chunk_count);
	ClassDB::bind_method(D_METHOD("get_chunk_grid_size"), &ChunkedTerrain3D::get_chunk_grid_size);
	ClassDB::bind_method(D_METHOD("get_visible_chunk_count"), &ChunkedTerrain3D::get_visible_chunk_count);
	ClassDB::bind_method(D_METHOD("get_collision_chunk_count"), &ChunkedTerrain3D::get_collision_chunk_count);
	ClassDB::bind_method(D_METHOD("get_chunk_lod", "chunk"), &ChunkedTerrain3D::get_chunk_lod);
	ClassDB::bind_method(D_METHOD("force_update"), &ChunkedTerrain3D::force_update);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "heightmap", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_heightmap", "get_heightmap");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "size", PROPERTY_HINT_NONE, "suffix:m"), "set_size", "get_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "height_scale", PROPERTY_HINT_RANGE, "0.001,10000,0.001,or_greater,suffix:m"), "set_height_scale", "get_height_scale");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "height_offset", PROPERTY_HINT_RANGE, "-10000,10000,0.01,or_less,or_greater,suffix:m"), "set_height_offset", "get_height_offset");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "centered"), "set_centered", "is_centered");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "material", PROPERTY_HINT_RESOURCE_TYPE, "BaseMaterial3D,ShaderMaterial"), "set_material", "get_material");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "cast_shadows"), "set_cast_shadows", "get_cast_shadows");
	ADD_GROUP("Detail", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "chunk_quads", PROPERTY_HINT_RANGE, "2,256,1"), "set_chunk_quads", "get_chunk_quads");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "lod_count", PROPERTY_HINT_RANGE, "1,8,1"), "set_lod_count", "get_lod_count");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lod_distance", PROPERTY_HINT_RANGE, "1,100000,1,or_greater,suffix:m"), "set_lod_distance", "get_lod_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "view_distance", PROPERTY_HINT_RANGE, "0,100000,1,or_greater,suffix:m"), "set_view_distance", "get_view_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "skirt_depth", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:m"), "set_skirt_depth", "get_skirt_depth");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "focus", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D"), "set_focus", "get_focus");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "update_interval", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater,suffix:s"), "set_update_interval", "get_update_interval");
	ADD_GROUP("Collision", "collision_");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "collision_enabled"), "set_collision_enabled", "is_collision_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "collision_distance", PROPERTY_HINT_RANGE, "0,10000,1,or_greater,suffix:m"), "set_collision_distance", "get_collision_distance");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_layer", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_collision_layer", "get_collision_layer");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_mask", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_collision_mask", "get_collision_mask");
}

ChunkedTerrain3D::ChunkedTerrain3D() {
	set_notify_transform(true);
}

ChunkedTerrain3D::~ChunkedTerrain3D() {
	_free_chunks();
}
