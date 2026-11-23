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
#include "terrain_geomorph_policy.h"
#include "terrain_streaming_budget_policy.h"
#include "terrain_streaming_priority_policy.h"

#include "core/config/engine.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/os/time.h"
#include "scene/main/viewport.h"
#include "scene/3d/camera_3d.h"
#include "scene/resources/3d/world_3d.h"
#include "servers/rendering/rendering_server.h"

#ifndef PHYSICS_3D_DISABLED
#include "servers/physics_3d/physics_server_3d.h"
#endif

using namespace HeightmapTerrainGeometry;

// The ledger is shared by every ChunkedTerrain3D in the running SceneTree.
// It is touched only on the main thread by native terrain process callbacks.
uint64_t ChunkedTerrain3D::shared_mesh_budget_frame = uint64_t(-1);
uint64_t ChunkedTerrain3D::shared_mesh_budget_start_usec = 0;
uint32_t ChunkedTerrain3D::shared_mesh_builds_this_frame = 0;
uint32_t ChunkedTerrain3D::shared_mesh_budget_usec = 0;

HeightmapTerrainGeometry::Params ChunkedTerrain3D::_params() const {
	Params params;
	const int width = MAX(data_width, 2);
	const int depth = MAX(data_depth, 2);
	params.spacing = Vector2(size.x / real_t(width - 1), size.y / real_t(depth - 1));
	params.height_scale = height_scale;
	params.height_offset = height_offset;
	params.normal_override = normal_data.size() == width * depth ? normal_data.ptr() : nullptr;
	params.color_override = color_data.size() == width * depth ? color_data.ptr() : nullptr;
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
	// Texture-backed height maps retain their original generated normals.
	normal_data.clear();
	color_data.clear();
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
	r_chunk.lod_use_clock = 0;
	for (int i = 0; i < MAX_LOD; i++) {
		r_chunk.lod_last_used[i] = 0;
	}
	r_chunk.morph = -1.0f;
	r_chunk.visible = false;
	_free_collision(r_chunk);
}

void ChunkedTerrain3D::_free_chunks() {
	pending_mesh_build_count = 0;
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
			// An error bound is measured only when the source field is rebuilt.
			// It is shared by all LOD mesh variants and never sampled on GPU.
			chunk.lod_errors[0] = 0.0;
			int previous_stride = 1;
			for (int level = 1; level < MAX_LOD; level++) {
				const int stride = lod_stride(level, chunk_quads);
				if (stride == previous_stride) {
					chunk.lod_errors[level] = chunk.lod_errors[level - 1];
				} else {
					const real_t error = chunk_lod_max_error(field, chunk.x0, chunk.z0,
							chunk_quads, stride) * Math::abs(height_scale);
					// Monotonic errors make LOD choice stable even for
					// terrain where independent simplification levels cross.
					chunk.lod_errors[level] = MAX(error, chunk.lod_errors[level - 1]);
				}
				previous_stride = stride;
			}
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
	Params params = _params();
	if (lod_geomorph_enabled && p_lod < lod_count - 1) {
		params.geomorph_coarse_stride = lod_stride(p_lod + 1, chunk_quads);
	}
	if (!build_chunk(_field(), r_chunk.x0, r_chunk.z0, chunk_quads, lod_stride(p_lod, chunk_quads), params, mesh)) {
		return;
	}
	Array arrays;
	arrays.resize(RSE::ARRAY_MAX);
	arrays[RSE::ARRAY_VERTEX] = mesh.vertices;
	arrays[RSE::ARRAY_NORMAL] = mesh.normals;
	if (!mesh.colors.is_empty()) {
		arrays[RSE::ARRAY_COLOR] = mesh.colors;
	}
	arrays[RSE::ARRAY_TEX_UV] = mesh.uvs;
	if (!mesh.morph_uv2.is_empty()) {
		arrays[RSE::ARRAY_TEX_UV2] = mesh.morph_uv2;
	}
	// The normal target is streamed only on geomorph-enabled high-quality
	// meshes. Custom0 RGB_FLOAT avoids quantizing steep-cliff normals.
	BitField<RSE::ArrayFormat> custom_format = static_cast<RSE::ArrayFormat>(0);
	if (!mesh.morph_normal_xyz.is_empty()) {
		arrays[RSE::ARRAY_CUSTOM0] = mesh.morph_normal_xyz;
		custom_format = static_cast<RSE::ArrayFormat>(
				uint64_t(RSE::ARRAY_CUSTOM_RGB_FLOAT) << RSE::ARRAY_FORMAT_CUSTOM0_SHIFT);
	}
	arrays[RSE::ARRAY_INDEX] = mesh.indices;
	const RID mesh_rid = rs->mesh_create();
	rs->mesh_add_surface_from_arrays(mesh_rid, RSE::PRIMITIVE_TRIANGLES,
			arrays, Array(), Dictionary(), custom_format);
	if (material.is_valid()) {
		rs->mesh_surface_set_material(mesh_rid, 0, material->get_rid());
	}
	r_chunk.meshes[p_lod] = mesh_rid;
}

// Only trim AFTER swapping the instance to the newly selected base RID.
// Removing an in-use mesh invalidates the render instance on some drivers.
void ChunkedTerrain3D::_trim_cached_lods(Chunk &r_chunk) {
	if (max_cached_lods == 0 || r_chunk.lod < 0 || !r_chunk.instance.is_valid()) {
		return;
	}
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return;
	}
	int resident = 0;
	for (int i = 0; i < MAX_LOD; i++) {
		resident += r_chunk.meshes[i].is_valid() ? 1 : 0;
	}
	while (resident > max_cached_lods) {
		int victim = -1;
		for (int i = 0; i < MAX_LOD; i++) {
			if (i == r_chunk.lod || !r_chunk.meshes[i].is_valid()) {
				continue;
			}
			if (victim < 0 || r_chunk.lod_last_used[i] < r_chunk.lod_last_used[victim]) {
				victim = i;
			}
		}
		if (victim < 0) {
			break; // The active GPU mesh is never eligible for eviction.
		}
		rs->free_rid(r_chunk.meshes[victim]);
		r_chunk.meshes[victim] = RID();
		r_chunk.lod_last_used[victim] = 0;
		--resident;
	}
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

void ChunkedTerrain3D::_update_chunks(bool p_ignore_mesh_budget) {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (!rs || !built || chunks.is_empty() || !is_inside_tree()) {
		return;
	}
	pending_mesh_build_count = 0;
	const bool time_sliced = mesh_build_budget_usec > 0 && !p_ignore_mesh_budget;
	if (time_sliced) {
		const uint64_t frame = Engine::get_singleton()->get_process_frames();
		if (shared_mesh_budget_frame != frame) {
			shared_mesh_budget_frame = frame;
			shared_mesh_budget_start_usec = Time::get_singleton()->get_ticks_usec();
			shared_mesh_builds_this_frame = 0;
			shared_mesh_budget_usec = mesh_build_budget_usec;
		} else {
			// The tightest of active terrain budgets wins when different
			// terrain nodes coexist; the game normally assigns one preset.
			shared_mesh_budget_usec = MIN(shared_mesh_budget_usec, mesh_build_budget_usec);
		}
	}
	Vector3 viewer_global;
	const bool has_viewer = _get_viewer_position(viewer_global);
	const Transform3D global = get_global_transform();
	const Vector3 viewer = has_viewer ? global.affine_inverse().xform(viewer_global) : Vector3();
	const Vector3 scale = global.basis.get_scale();
	const real_t unit_scale = (scale.x + scale.z) * real_t(0.5);
	const RID scenario = get_world_3d()->get_scenario();

	// Perspective screen-space LOD: compute the scale once per LOD pass.
	// Orthographic/no-camera views keep the original distance-only behavior.
	real_t effective_lod_distance = lod_distance;
	if (screen_space_lod_enabled && has_viewer) {
		Viewport *viewport = get_viewport();
		Camera3D *camera = viewport ? viewport->get_camera_3d() : nullptr;
		if (camera && camera->get_projection() == Camera3D::PROJECTION_PERSPECTIVE) {
			const Size2 viewport_size = viewport->get_visible_rect().size;
			// Match actual rendered 3D resolution, not just the window size.
			// Dynamic resolution / FSR must not keep excessive terrain geometry.
			const real_t real_3d_height = viewport_size.y * viewport->get_scaling_3d_scale();
			real_t vertical_fov = camera->get_fov();
			if (camera->get_keep_aspect_mode() == Camera3D::KEEP_WIDTH && viewport_size.x > 0.0) {
				vertical_fov = Projection::get_fovy(vertical_fov, viewport_size.y / viewport_size.x);
			}
			effective_lod_distance *= screen_lod_multiplier(real_3d_height, vertical_fov, lod_reference_fov);
		}
	}

	// One camera-dependent projection factor per streaming update. Pixel-error
	// selection uses the *rendered 3D* resolution, including FSR scaling.
	real_t projection_scale = 0.0;
	if (lod_pixel_error > 0.0 && has_viewer) {
		Viewport *viewport = get_viewport();
		if (viewport != nullptr) {
			Camera3D *camera = viewport->get_camera_3d();
			const Size2 viewport_size = viewport->get_visible_rect().size;
			const real_t pixel_height = viewport_size.y * viewport->get_scaling_3d_scale();
			if (camera != nullptr && pixel_height > 0.0) {
				if (camera->get_projection() == Camera3D::PROJECTION_ORTHOGONAL) {
					// The size property represents horizontal span for
					// KEEP_WIDTH and vertical span for KEEP_HEIGHT.
					// Preserve pixel error on widescreen, portrait and FSR.
					projection_scale = orthographic_lod_pixel_scale(
							viewport_size.x, viewport_size.y,
							viewport->get_scaling_3d_scale(), camera->get_size(),
							camera->get_keep_aspect_mode() == Camera3D::KEEP_WIDTH);
				} else if (camera->get_projection() == Camera3D::PROJECTION_PERSPECTIVE) {
					real_t vertical_fov = camera->get_fov();
					if (camera->get_keep_aspect_mode() == Camera3D::KEEP_WIDTH && viewport_size.x > 0.0) {
						vertical_fov = Projection::get_fovy(vertical_fov, viewport_size.y / viewport_size.x);
					}
					const real_t half_fov = Math::deg_to_rad(vertical_fov * real_t(0.5));
					projection_scale = pixel_height / MAX(real_t(2.0) * Math::tan(half_fov), real_t(0.001));
				}
			}
		}
	}

	// Sort only when terrain streaming is time-sliced and an actual viewer
	// exists. The legacy, unbudgeted renderer retains its original array scan.
	// This is per-node ordering: the shared CPU ledger is still global across
	// all ChunkedTerrain3D instances in the scene.
	LocalVector<TerrainStreamingPriorityPolicy::Candidate> stream_order;
	if (time_sliced && mesh_streaming_priority > 0 && has_viewer && chunks.size() > 1) {
		stream_order.resize(chunks.size());
		Vector3 camera_forward;
		if (mesh_streaming_priority >= 2) {
			Viewport *viewport = get_viewport();
			Camera3D *camera = viewport != nullptr ? viewport->get_camera_3d() : nullptr;
			if (camera != nullptr) {
				camera_forward = -camera->get_global_transform().basis.get_column(2).normalized();
			}
		}
		for (uint32_t i = 0; i < chunks.size(); i++) {
			const Chunk &chunk = chunks[i];
			const Vector3 closest = viewer.clamp(chunk.bounds.position, chunk.bounds.get_end());
			const float distance = float((viewer - closest).length() * unit_scale);
			float alignment = 0.0f;
			if (camera_forward.length_squared() > real_t(0.0001)) {
				const Vector3 toward = global.xform(chunk.bounds.get_center()) - viewer_global;
				if (toward.length_squared() > real_t(0.0001)) {
					alignment = float(toward.normalized().dot(camera_forward));
				}
			}
			TerrainStreamingPriorityPolicy::Candidate &priority = stream_order[i];
			priority.index = i;
			priority.score = TerrainStreamingPriorityPolicy::score(distance,
					alignment, mesh_streaming_priority);
			// Never favor an out-of-range cell ahead of a visible one.
			const bool in_range = view_distance <= 0.0 || distance <= view_distance;
			priority.missing_visible_mesh = in_range && !chunk.instance.is_valid();
		}
		stream_order.sort_custom<TerrainStreamingPriorityPolicy::Less>();
	}

	for (uint32_t stream_index = 0; stream_index < chunks.size(); stream_index++) {
		Chunk &chunk = chunks[stream_order.is_empty() ?
				stream_index : stream_order[stream_index].index];
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
			// Geometric error is computed only when the renderer first needs this
			// chunk and only with the opt-in setting. Flat terrain downshifts
			// early; cliffs/ridges retain geometry, following pixel-error LOD.
			real_t chunk_lod_distance = effective_lod_distance;
			real_t error_factor = 1.0;
			if (lod_geometric_error_strength > real_t(0.001) && has_viewer && lod_count > 1) {
				real_t error_meters = 0.0;
				if (lod_pixel_error > 0.0 && projection_scale > 0.0) {
					// Pixel-error LOD already caches geometry deviations per
					// level when building the heightfield: reuse that result.
					// The game never performs a duplicate heightfield scan.
					error_meters = chunk.lod_errors[MIN(lod_count - 1, 2)] * scale.y;
				} else {
					// Legacy distance-only LOD measures its coarse deviation
					// lazily, only once on the first visible update.
					if (chunk.geometric_error < 0.0f) {
						const int coarse_stride = lod_stride(MIN(lod_count - 1, 2), chunk_quads);
						chunk.geometric_error = float(chunk_lod_deviation(_field(),
								chunk.x0, chunk.z0, chunk_quads, coarse_stride));
					}
					error_meters = real_t(chunk.geometric_error) *
							Math::abs(height_scale * scale.y);
				}
				error_factor = geometric_error_lod_bias(error_meters,
						lod_geometric_error_strength);
				chunk_lod_distance *= error_factor;
			}
			// Without a viewer (editor) use a moderate level instead of the most expensive one.
			int lod = has_viewer ? select_lod(distance, chunk_lod_distance, lod_count, chunk.lod) : MIN(1, lod_count - 1);
			if (has_viewer && lod_pixel_error > 0.0 && projection_scale > 0.0) {
				real_t errors[MAX_LOD] = {};
				for (int level = 0; level < lod_count; level++) {
					errors[level] = chunk.lod_errors[level] * scale.y;
				}
				// Error-derived weight tightens pixel tolerance for peaks and
				// relaxes it on flat surfaces; LOD and morph use the same bound.
				const real_t pixel_error_tolerance = lod_pixel_error / error_factor;
				lod = select_lod_by_pixel_error(errors, lod_count, distance,
						projection_scale, pixel_error_tolerance, chunk.lod);
			}
			bool mesh_deferred = false;
			if (lod != chunk.lod || !chunk.instance.is_valid()) {
				const bool needs_mesh = !chunk.meshes[lod].is_valid();
				bool may_build = true;
				if (needs_mesh && time_sliced) {
					const uint64_t elapsed = Time::get_singleton()->get_ticks_usec() -
							shared_mesh_budget_start_usec;
					may_build = TerrainStreamingBudgetPolicy::may_build(
							elapsed, shared_mesh_budget_usec, shared_mesh_builds_this_frame);
				}
				if (!may_build) {
					// Keep the existing visible LOD and shader morph weight
					// until the replacement can be generated next frame.
					pending_mesh_build_count++;
					mesh_deferred = true;
				} else {
					_ensure_mesh(chunk, lod);
					if (needs_mesh && time_sliced && chunk.meshes[lod].is_valid()) {
						shared_mesh_builds_this_frame++;
					}
					if (chunk.meshes[lod].is_valid()) {
						if (!chunk.instance.is_valid()) {
							chunk.instance = rs->instance_create2(chunk.meshes[lod], scenario);
							// Raw RenderingServer terrains need explicit static GI flags.
							rs->instance_geometry_set_flag(chunk.instance, RSE::INSTANCE_FLAG_USE_BAKED_LIGHT, contribute_to_gi);
							rs->instance_set_transform(chunk.instance, global);
							rs->instance_geometry_set_cast_shadows_setting(chunk.instance, cast_shadows ? RSE::SHADOW_CASTING_SETTING_ON : RSE::SHADOW_CASTING_SETTING_OFF);
							rs->instance_set_layer_mask(chunk.instance, render_layers);
						} else {
							rs->instance_set_base(chunk.instance, chunk.meshes[lod]);
						}
						chunk.lod = lod;
						chunk.lod_last_used[lod] = ++chunk.lod_use_clock;
						_trim_cached_lods(chunk);
						chunk.morph = -1.0f; // Mesh topology changed; update its own morph uniform.
					}
				}
			}
			if (chunk.instance.is_valid() && !mesh_deferred) {
				float target = 0.0f;
				if (lod_geomorph_enabled && has_viewer && chunk.lod >= 0 && chunk.lod < lod_count - 1) {
					// Pixel-based LOD morphs toward the next geometry level
					// near its measured screen-error threshold.
					real_t threshold = chunk_lod_distance * real_t(1 << chunk.lod);
					if (lod_pixel_error > 0.0 && projection_scale > 0.0) {
						threshold = MAX(chunk.lod_errors[chunk.lod + 1] * scale.y *
								projection_scale / (lod_pixel_error / error_factor), real_t(1.0));
					}
					target = TerrainGeomorphPolicy::factor(float(distance), float(threshold));
				}
				if (chunk.morph < 0.0f || Math::abs(chunk.morph - target) > 0.015f) {
					rs->instance_geometry_set_shader_parameter(chunk.instance, "aa_lod_morph", target);
					chunk.morph = target;
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
	// Explicit updates (editor, tests and manual teleports) preserve the old
	// synchronous behavior. Normal scene streaming respects the time slice.
	_update_chunks(true);
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
			if (pending_mesh_build_count > 0 || time_since_update >= update_interval) {
				if (time_since_update >= update_interval) {
					time_since_update = 0.0;
				}
				if (!built) {
					_rebuild();
				}
				// Continue any deferred mesh builds on the next process frame,
				// without waiting for the regular 0.16-0.5 s LOD refresh.
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
	// Any new height samples invalidate externally supplied slopes and colors.
	normal_data.clear();
	color_data.clear();
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

void ChunkedTerrain3D::set_normal_data(const PackedVector3Array &p_normals) {
	ERR_FAIL_COND_MSG(!p_normals.is_empty() && (data_width < 2 || data_depth < 2 ||
			p_normals.size() != data_width * data_depth),
			"ChunkedTerrain3D custom normals must match the active height-data dimensions.");
	// Validate before assignment so a bad external array never damages the
	// previous normal field. Normalize once on upload, not per-vertex or frame.
	for (const Vector3 &normal : p_normals) {
		ERR_FAIL_COND_MSG(!normal.is_finite() || normal.length_squared() < real_t(1e-12),
				"ChunkedTerrain3D normals must be finite and nonzero.");
	}
	normal_data.resize(p_normals.size());
	Vector3 *out = normal_data.ptrw();
	for (int i = 0; i < p_normals.size(); i++) {
		out[i] = p_normals[i].normalized();
	}
	built = false;
	_queue_rebuild();
}


PackedFloat32Array ChunkedTerrain3D::bake_horizon_visibility(const PackedFloat32Array &p_heights,
		const Vector2i &p_dimensions, real_t p_spacing, int p_radius_steps) {
	PackedFloat32Array result;
	ERR_FAIL_COND_V_MSG(p_dimensions.x < 2 || p_dimensions.y < 2 ||
			p_dimensions.x > 4096 || p_dimensions.y > 4096 ||
			p_heights.size() != p_dimensions.x * p_dimensions.y ||
			!Math::is_finite(p_spacing) || p_spacing <= 0.0 ||
			p_radius_steps < 2 || p_radius_steps > 12,
			result, "Invalid terrain horizon bake dimensions, spacing or radius.");
	// Convert the script-facing PackedFloat32Array only once. This also
	// supports real_t builds configured for double precision.
	Vector<real_t> native_heights;
	native_heights.resize(p_heights.size());
	real_t *native = native_heights.ptrw();
	for (int i = 0; i < p_heights.size(); i++) {
		native[i] = p_heights[i];
	}
	const HeightField field{ native_heights.ptr(), p_dimensions.x, p_dimensions.y };
	const Vector<real_t> visibility =
			HeightmapTerrainGeometry::bake_horizon_visibility(field, p_spacing, p_radius_steps);
	result.resize(visibility.size());
	float *out = result.ptrw();
	for (int i = 0; i < visibility.size(); i++) {
		out[i] = float(visibility[i]);
	}
	return result;
}

bool ChunkedTerrain3D::apply_color_patch(const Rect2i &p_region, const PackedColorArray &p_colors) {
	ERR_FAIL_COND_V_MSG(data_width < 2 || data_depth < 2 ||
			color_data.size() != data_width * data_depth ||
			p_region.position.x < 0 || p_region.position.y < 0 ||
			p_region.position.x >= data_width || p_region.position.y >= data_depth ||
			p_region.size.x <= 0 || p_region.size.y <= 0 ||
			p_region.size.x > data_width - p_region.position.x ||
			p_region.size.y > data_depth - p_region.position.y,
			false, "Color patches require initialized vertex colors and an in-bounds nonempty region.");
	const int count = p_region.size.x * p_region.size.y;
	ERR_FAIL_COND_V_MSG(p_colors.size() != count, false, "Color patch values must match the region dimensions.");
	for (const Color &color : p_colors) {
		ERR_FAIL_COND_V_MSG(!Math::is_finite(color.r) || !Math::is_finite(color.g) ||
				!Math::is_finite(color.b) || !Math::is_finite(color.a),
				false, "Color patch samples must be finite.");
	}
	bool changed = false;
	for (int z = 0; z < p_region.size.y && !changed; z++) {
		for (int x = 0; x < p_region.size.x; x++) {
			const int source = z * p_region.size.x + x;
			const int destination = (p_region.position.y + z) * data_width + p_region.position.x + x;
			if (color_data[destination] != p_colors[source]) {
				changed = true;
				break;
			}
		}
	}
	if (!changed) {
		last_region_invalidated_chunks = 0;
		return true;
	}
	Color *colors = color_data.ptrw();
	for (int z = 0; z < p_region.size.y; z++) {
		for (int x = 0; x < p_region.size.x; x++) {
			colors[(p_region.position.y + z) * data_width + p_region.position.x + x] =
					p_colors[z * p_region.size.x + x];
		}
	}
	if (built) {
		_invalidate_region(p_region, false);
	} else {
		_queue_rebuild();
	}
	return true;
}

void ChunkedTerrain3D::set_color_data(const PackedColorArray &p_colors) {
	ERR_FAIL_COND_MSG(!p_colors.is_empty() && (data_width < 2 || data_depth < 2 ||
			p_colors.size() != data_width * data_depth),
			"ChunkedTerrain3D vertex colors must match the active height-data dimensions.");
	for (const Color &color : p_colors) {
		ERR_FAIL_COND_MSG(!Math::is_finite(color.r) || !Math::is_finite(color.g) ||
				!Math::is_finite(color.b) || !Math::is_finite(color.a),
				"ChunkedTerrain3D vertex colors must be finite.");
	}
	// COW packed array: a single copy of the authored colors, shared by cached
	// LOD mesh builds. Empty colors keep legacy memory and vertex formats.
	color_data = p_colors;
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
	normal_data.clear();
	color_data.clear();
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
		chunk.geometric_error = -1.0f; // A new LOD count may change sample stride.
	}
}

void ChunkedTerrain3D::set_lod_distance(real_t p_distance) {
	lod_distance = MAX(p_distance, real_t(1.0));
}

void ChunkedTerrain3D::set_lod_pixel_error(real_t p_pixels) {
	const real_t error = Math::is_finite(p_pixels) ? MAX(p_pixels, real_t(0.0)) : real_t(0.0);
	if (lod_pixel_error == error) {
		return;
	}
	lod_pixel_error = error;
	// A graphics-quality change will reselect one of the already cached
	// LOD mesh variants; height data, world collision and materials survive.
	for (Chunk &chunk : chunks) {
		chunk.lod = -1;
	}
}

void ChunkedTerrain3D::set_mesh_build_budget_usec(int p_usec) {
	// Engine property is deliberately opt-in and never rebuilds a heightfield.
	// 20 ms is an upper bound for accidental extreme editor values.
	mesh_build_budget_usec = uint32_t(CLAMP(p_usec, 0, 20000));
}

void ChunkedTerrain3D::set_mesh_streaming_priority(int p_mode) {
	// Reordering candidates never invalidates cached meshes or collision.
	mesh_streaming_priority = CLAMP(p_mode, 0, 2);
}

void ChunkedTerrain3D::set_max_cached_lods(int p_limit) {
	const int limit = CLAMP(p_limit, 0, MAX_LOD);
	if (max_cached_lods == limit) {
		return;
	}
	max_cached_lods = limit;
	// Changing quality in a live world releases unused GPU meshes now, not
	// after the next camera movement. A chunk with lod == -1 may still have
	// an attached old RID, so wait for the next LOD binding in that case.
	for (Chunk &chunk : chunks) {
		_trim_cached_lods(chunk);
	}
}

int ChunkedTerrain3D::get_cached_mesh_count() const {
	int result = 0;
	for (const Chunk &chunk : chunks) {
		for (int lod = 0; lod < MAX_LOD; lod++) {
			result += chunk.meshes[lod].is_valid() ? 1 : 0;
		}
	}
	return result;
}

int ChunkedTerrain3D::get_chunk_cached_lod_count(const Vector2i &p_chunk) const {
	ERR_FAIL_COND_V(p_chunk.x < 0 || p_chunk.y < 0 || p_chunk.x >= chunks_x || p_chunk.y >= chunks_z, 0);
	const Chunk &chunk = chunks[p_chunk.y * chunks_x + p_chunk.x];
	int result = 0;
	for (int lod = 0; lod < MAX_LOD; lod++) {
		result += chunk.meshes[lod].is_valid() ? 1 : 0;
	}
	return result;
}

void ChunkedTerrain3D::set_lod_geomorph_enabled(bool p_enabled) {
	if (lod_geomorph_enabled == p_enabled) {
		return;
	}
	lod_geomorph_enabled = p_enabled;
	// Rebuild cached surfaces only on explicit quality changes, never while
	// the camera moves; the shader handles all subsequent vertex morphing.
	built = false;
	_queue_rebuild();
}

void ChunkedTerrain3D::set_lod_reference_fov(real_t p_degrees) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_degrees), "Terrain reference FOV must be finite.");
	lod_reference_fov = CLAMP(p_degrees, real_t(1.01), real_t(178.99));
}

void ChunkedTerrain3D::set_lod_geometric_error_strength(real_t p_strength) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_strength), "Terrain LOD error strength must be finite.");
	lod_geometric_error_strength = CLAMP(p_strength, real_t(0.0), real_t(1.0));
	// Cached errors remain valid when adjusting the budget; no mesh rebuild.
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

void ChunkedTerrain3D::set_render_layers(uint32_t p_layers) {
	if (render_layers == p_layers) {
		return;
	}
	render_layers = p_layers;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (!rs) {
		return;
	}
	for (Chunk &chunk : chunks) {
		if (chunk.instance.is_valid()) {
			rs->instance_set_layer_mask(chunk.instance, render_layers);
		}
	}
}

void ChunkedTerrain3D::set_contribute_to_gi(bool p_enabled) {
	if (contribute_to_gi == p_enabled) {
		return;
	}
	contribute_to_gi = p_enabled;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (!rs) {
		return;
	}
	// Reuse existing instances. Switching GI participation never
	// regenerates terrain meshes, collision or streamed LODs.
	for (Chunk &chunk : chunks) {
		if (chunk.instance.is_valid()) {
			rs->instance_geometry_set_flag(chunk.instance, RSE::INSTANCE_FLAG_USE_BAKED_LIGHT, contribute_to_gi);
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

bool ChunkedTerrain3D::apply_height_patch(const Rect2i &p_region, const PackedFloat32Array &p_heights) {
	// Atomic admission: never overwrite earlier samples when a late value is
	// NaN/Inf, the region spills beyond the height grid or the request is too
	// large to process as a single terrain-edit transaction.
	if (!data_from_script || data_width < 2 || data_depth < 2 ||
			p_region.position.x < 0 || p_region.position.y < 0 ||
			p_region.size.x < 1 || p_region.size.y < 1 ||
			p_region.size.x > data_width || p_region.size.y > data_depth ||
			p_region.position.x > data_width - p_region.size.x ||
			p_region.position.y > data_depth - p_region.size.y ||
			int64_t(p_region.size.x) * int64_t(p_region.size.y) > 4096 ||
			p_heights.size() != p_region.size.x * p_region.size.y) {
		return false;
	}
	for (int i = 0; i < p_heights.size(); ++i) {
		if (!Math::is_finite(p_heights[i])) {
			return false;
		}
	}
	bool changed = false;
	for (int z = 0; z < p_region.size.y && !changed; ++z) {
		for (int x = 0; x < p_region.size.x; ++x) {
			if (height_data[(p_region.position.y + z) * data_width + p_region.position.x + x] !=
					real_t(p_heights[z * p_region.size.x + x])) {
				changed = true;
				break;
			}
		}
	}
	if (!changed) {
		last_region_invalidated_chunks = 0;
		return true; // No GPU/physics invalidation for identical patches.
	}
	real_t *samples = height_data.ptrw();
	for (int z = 0; z < p_region.size.y; ++z) {
		for (int x = 0; x < p_region.size.x; ++x) {
			samples[(p_region.position.y + z) * data_width + p_region.position.x + x] =
					p_heights[z * p_region.size.x + x];
		}
	}

	// Repair only the affected externally cached normals (and one-ring
	// derivatives). This leaves authored normals elsewhere untouched.
	if (normal_data.size() == data_width * data_depth) {
		const Rect2i dirty_normals = p_region.grow(1).intersection(
				Rect2i(0, 0, data_width, data_depth));
		const real_t step_x = size.x / real_t(data_width - 1);
		const real_t step_z = size.y / real_t(data_depth - 1);
		Vector3 *normals = normal_data.ptrw();
		for (int z = dirty_normals.position.y; z < dirty_normals.get_end().y; ++z) {
			for (int x = dirty_normals.position.x; x < dirty_normals.get_end().x; ++x) {
				const int west = MAX(x - 1, 0);
				const int east = MIN(x + 1, data_width - 1);
				const int north = MAX(z - 1, 0);
				const int south = MIN(z + 1, data_depth - 1);
				const real_t dx = (samples[z * data_width + west] -
						samples[z * data_width + east]) * height_scale /
						(real_t(east - west) * step_x);
				const real_t dz = (samples[north * data_width + x] -
						samples[south * data_width + x]) * height_scale /
						(real_t(south - north) * step_z);
				normals[z * data_width + x] = Vector3(dx, 1.0, dz).normalized();
			}
		}
	}
	update_region(p_region);
	return true;
}

void ChunkedTerrain3D::update_region(const Rect2i &p_region) {
	_invalidate_region(p_region, true);
}

void ChunkedTerrain3D::_invalidate_region(const Rect2i &p_region, bool p_geometry_changed) {
	last_region_invalidated_chunks = 0;
	if (!built || chunks.is_empty() || p_region.position.x < 0 || p_region.position.y < 0 ||
			p_region.size.x < 1 || p_region.size.y < 1 ||
			p_region.size.x > data_width || p_region.size.y > data_depth ||
			p_region.position.x > data_width - p_region.size.x ||
			p_region.position.y > data_depth - p_region.size.y) {
		return;
	}
	// Visit only chunks touching the edited samples and one neighboring sample.
	// Sparse brush costs are proportional to dirty chunks, not total world size.
	const Rect2i grown = p_region.grow(1).intersection(Rect2i(0, 0, data_width, data_depth));
	const int min_cx = CLAMP((grown.position.x - 1) / chunk_quads, 0, chunks_x - 1);
	const int min_cz = CLAMP((grown.position.y - 1) / chunk_quads, 0, chunks_z - 1);
	const int max_cx = CLAMP((grown.position.x + grown.size.x - 1) / chunk_quads, 0, chunks_x - 1);
	const int max_cz = CLAMP((grown.position.y + grown.size.y - 1) / chunk_quads, 0, chunks_z - 1);
	RenderingServer *rs = RenderingServer::get_singleton();
	const Params params = _params();
	for (int cz = min_cz; cz <= max_cz; cz++) {
		for (int cx = min_cx; cx <= max_cx; cx++) {
			Chunk &chunk = chunks[cz * chunks_x + cx];
			last_region_invalidated_chunks++;
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
			chunk.lod_use_clock = 0;
			for (int level = 0; level < MAX_LOD; level++) {
				chunk.lod_last_used[level] = 0;
			}
			chunk.morph = -1.0f;
			chunk.visible = false;
			if (!p_geometry_changed) {
				// Repaint only: retain terrain collision, bounds and cached LOD errors.
				continue;
			}
			chunk.geometric_error = -1.0f; // Only height changes invalidate ruggedness.
			_free_collision(chunk);

			real_t low;
			real_t high;
			chunk_height_range(_field(), chunk.x0, chunk.z0, chunk_quads, low, high);
			const int x1 = MIN(chunk.x0 + chunk_quads, data_width - 1);
			const int z1 = MIN(chunk.z0 + chunk_quads, data_depth - 1);
			const Vector3 a(params.origin.x + real_t(chunk.x0) * params.spacing.x, low * height_scale + height_offset, params.origin.y + real_t(chunk.z0) * params.spacing.y);
			const Vector3 b(params.origin.x + real_t(x1) * params.spacing.x, high * height_scale + height_offset, params.origin.y + real_t(z1) * params.spacing.y);
			chunk.bounds = AABB(a, b - a).abs();
			// Edits also invalidate each coarser level's maximum height error.
			// Without this recalculation steep newly sculpted hills could still
			// select the same cheap LOD that was appropriate for a flat chunk.
			chunk.lod_errors[0] = 0.0;
			int previous_stride = 1;
			for (int level = 1; level < MAX_LOD; ++level) {
				const int stride = lod_stride(level, chunk_quads);
				if (stride == previous_stride) {
					chunk.lod_errors[level] = chunk.lod_errors[level - 1];
				} else {
					const real_t error = chunk_lod_max_error(_field(), chunk.x0, chunk.z0,
							chunk_quads, stride) * Math::abs(height_scale);
					chunk.lod_errors[level] = MAX(error, chunk.lod_errors[level - 1]);
				}
				previous_stride = stride;
			}
		}
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

real_t ChunkedTerrain3D::get_chunk_lod_error(const Vector2i &p_chunk, int p_lod) const {
	if (p_chunk.x < 0 || p_chunk.y < 0 || p_chunk.x >= chunks_x ||
			p_chunk.y >= chunks_z || p_lod < 0 || p_lod >= MAX_LOD) {
		return -1.0;
	}
	return chunks[p_chunk.y * chunks_x + p_chunk.x].lod_errors[p_lod];
}

void ChunkedTerrain3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_heightmap", "texture"), &ChunkedTerrain3D::set_heightmap);
	ClassDB::bind_method(D_METHOD("get_heightmap"), &ChunkedTerrain3D::get_heightmap);
	ClassDB::bind_method(D_METHOD("set_height_data", "heights", "dimensions"), &ChunkedTerrain3D::set_height_data);
	ClassDB::bind_method(D_METHOD("get_height_data"), &ChunkedTerrain3D::get_height_data);
	ClassDB::bind_method(D_METHOD("set_normal_data", "normals"), &ChunkedTerrain3D::set_normal_data);
	ClassDB::bind_method(D_METHOD("get_normal_data"), &ChunkedTerrain3D::get_normal_data);
	ClassDB::bind_static_method("ChunkedTerrain3D",
			D_METHOD("bake_horizon_visibility", "heights", "dimensions", "spacing", "radius_steps"),
			&ChunkedTerrain3D::bake_horizon_visibility, DEFVAL(6));
	ClassDB::bind_method(D_METHOD("set_color_data", "colors"), &ChunkedTerrain3D::set_color_data);
	ClassDB::bind_method(D_METHOD("get_color_data"), &ChunkedTerrain3D::get_color_data);
	ClassDB::bind_method(D_METHOD("apply_color_patch", "region", "colors"), &ChunkedTerrain3D::apply_color_patch);
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
	ClassDB::bind_method(D_METHOD("set_lod_geomorph_enabled", "enabled"), &ChunkedTerrain3D::set_lod_geomorph_enabled);
	ClassDB::bind_method(D_METHOD("is_lod_geomorph_enabled"), &ChunkedTerrain3D::is_lod_geomorph_enabled);
	ClassDB::bind_method(D_METHOD("get_lod_distance"), &ChunkedTerrain3D::get_lod_distance);
	ClassDB::bind_method(D_METHOD("set_lod_pixel_error", "pixels"), &ChunkedTerrain3D::set_lod_pixel_error);
	ClassDB::bind_method(D_METHOD("get_lod_pixel_error"), &ChunkedTerrain3D::get_lod_pixel_error);
	ClassDB::bind_method(D_METHOD("set_mesh_build_budget_usec", "microseconds"), &ChunkedTerrain3D::set_mesh_build_budget_usec);
	ClassDB::bind_method(D_METHOD("get_mesh_build_budget_usec"), &ChunkedTerrain3D::get_mesh_build_budget_usec);
	ClassDB::bind_method(D_METHOD("set_mesh_streaming_priority", "mode"), &ChunkedTerrain3D::set_mesh_streaming_priority);
	ClassDB::bind_method(D_METHOD("get_mesh_streaming_priority"), &ChunkedTerrain3D::get_mesh_streaming_priority);
	ClassDB::bind_method(D_METHOD("set_max_cached_lods", "limit"), &ChunkedTerrain3D::set_max_cached_lods);
	ClassDB::bind_method(D_METHOD("get_max_cached_lods"), &ChunkedTerrain3D::get_max_cached_lods);
	ClassDB::bind_method(D_METHOD("get_cached_mesh_count"), &ChunkedTerrain3D::get_cached_mesh_count);
	ClassDB::bind_method(D_METHOD("get_chunk_cached_lod_count", "chunk"), &ChunkedTerrain3D::get_chunk_cached_lod_count);
	ClassDB::bind_method(D_METHOD("get_pending_mesh_build_count"), &ChunkedTerrain3D::get_pending_mesh_build_count);
	ClassDB::bind_method(D_METHOD("set_screen_space_lod_enabled", "enabled"), &ChunkedTerrain3D::set_screen_space_lod_enabled);
	ClassDB::bind_method(D_METHOD("is_screen_space_lod_enabled"), &ChunkedTerrain3D::is_screen_space_lod_enabled);
	ClassDB::bind_method(D_METHOD("set_lod_reference_fov", "degrees"), &ChunkedTerrain3D::set_lod_reference_fov);
	ClassDB::bind_method(D_METHOD("get_lod_reference_fov"), &ChunkedTerrain3D::get_lod_reference_fov);
	ClassDB::bind_method(D_METHOD("set_lod_geometric_error_strength", "strength"), &ChunkedTerrain3D::set_lod_geometric_error_strength);
	ClassDB::bind_method(D_METHOD("get_lod_geometric_error_strength"), &ChunkedTerrain3D::get_lod_geometric_error_strength);
	ClassDB::bind_method(D_METHOD("set_view_distance", "distance"), &ChunkedTerrain3D::set_view_distance);
	ClassDB::bind_method(D_METHOD("get_view_distance"), &ChunkedTerrain3D::get_view_distance);
	ClassDB::bind_method(D_METHOD("set_skirt_depth", "depth"), &ChunkedTerrain3D::set_skirt_depth);
	ClassDB::bind_method(D_METHOD("get_skirt_depth"), &ChunkedTerrain3D::get_skirt_depth);
	ClassDB::bind_method(D_METHOD("set_material", "material"), &ChunkedTerrain3D::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &ChunkedTerrain3D::get_material);
	ClassDB::bind_method(D_METHOD("set_cast_shadows", "enabled"), &ChunkedTerrain3D::set_cast_shadows);
	ClassDB::bind_method(D_METHOD("set_render_layers", "layers"), &ChunkedTerrain3D::set_render_layers);
	ClassDB::bind_method(D_METHOD("get_render_layers"), &ChunkedTerrain3D::get_render_layers);
	ClassDB::bind_method(D_METHOD("get_cast_shadows"), &ChunkedTerrain3D::get_cast_shadows);
	ClassDB::bind_method(D_METHOD("set_contribute_to_gi", "enabled"), &ChunkedTerrain3D::set_contribute_to_gi);
	ClassDB::bind_method(D_METHOD("is_contributing_to_gi"), &ChunkedTerrain3D::is_contributing_to_gi);
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
	ClassDB::bind_method(D_METHOD("get_last_region_invalidated_chunks"), &ChunkedTerrain3D::get_last_region_invalidated_chunks);
	ClassDB::bind_method(D_METHOD("apply_height_patch", "region", "heights"), &ChunkedTerrain3D::apply_height_patch);
	ClassDB::bind_method(D_METHOD("get_chunk_count"), &ChunkedTerrain3D::get_chunk_count);
	ClassDB::bind_method(D_METHOD("get_chunk_grid_size"), &ChunkedTerrain3D::get_chunk_grid_size);
	ClassDB::bind_method(D_METHOD("get_visible_chunk_count"), &ChunkedTerrain3D::get_visible_chunk_count);
	ClassDB::bind_method(D_METHOD("get_collision_chunk_count"), &ChunkedTerrain3D::get_collision_chunk_count);
	ClassDB::bind_method(D_METHOD("get_chunk_lod", "chunk"), &ChunkedTerrain3D::get_chunk_lod);
	ClassDB::bind_method(D_METHOD("get_chunk_lod_error", "chunk", "lod"), &ChunkedTerrain3D::get_chunk_lod_error);
	ClassDB::bind_method(D_METHOD("force_update"), &ChunkedTerrain3D::force_update);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "heightmap", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_heightmap", "get_heightmap");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "size", PROPERTY_HINT_NONE, "suffix:m"), "set_size", "get_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "height_scale", PROPERTY_HINT_RANGE, "0.001,10000,0.001,or_greater,suffix:m"), "set_height_scale", "get_height_scale");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "height_offset", PROPERTY_HINT_RANGE, "-10000,10000,0.01,or_less,or_greater,suffix:m"), "set_height_offset", "get_height_offset");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "centered"), "set_centered", "is_centered");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "material", PROPERTY_HINT_RESOURCE_TYPE, "BaseMaterial3D,ShaderMaterial"), "set_material", "get_material");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "cast_shadows"), "set_cast_shadows", "get_cast_shadows");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "render_layers", PROPERTY_HINT_LAYERS_3D_RENDER), "set_render_layers", "get_render_layers");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "contribute_to_gi"), "set_contribute_to_gi", "is_contributing_to_gi");
	ADD_GROUP("Detail", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "chunk_quads", PROPERTY_HINT_RANGE, "2,256,1"), "set_chunk_quads", "get_chunk_quads");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "lod_count", PROPERTY_HINT_RANGE, "1,8,1"), "set_lod_count", "get_lod_count");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lod_distance", PROPERTY_HINT_RANGE, "1,100000,1,or_greater,suffix:m"), "set_lod_distance", "get_lod_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lod_pixel_error", PROPERTY_HINT_RANGE, "0,20,0.1,or_greater,suffix:px"), "set_lod_pixel_error", "get_lod_pixel_error");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "mesh_build_budget_usec", PROPERTY_HINT_RANGE, "0,20000,100,suffix:us"), "set_mesh_build_budget_usec", "get_mesh_build_budget_usec");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "mesh_streaming_priority", PROPERTY_HINT_ENUM, "Original order,Nearest first,Camera facing"), "set_mesh_streaming_priority", "get_mesh_streaming_priority");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_cached_lods", PROPERTY_HINT_RANGE, "0,8,1"), "set_max_cached_lods", "get_max_cached_lods");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "screen_space_lod_enabled"), "set_screen_space_lod_enabled", "is_screen_space_lod_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lod_reference_fov", PROPERTY_HINT_RANGE, "1.01,178.99,0.1,degrees"), "set_lod_reference_fov", "get_lod_reference_fov");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lod_geometric_error_strength", PROPERTY_HINT_RANGE, "0,1,0.05"), "set_lod_geometric_error_strength", "get_lod_geometric_error_strength");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "lod_geomorph_enabled"), "set_lod_geomorph_enabled", "is_lod_geomorph_enabled");
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
