/**************************************************************************/
/*  chunked_terrain_3d.h                                             */
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

#pragma once

#include "scene/3d/heightmap_terrain_geometry.h"
#include "scene/3d/node_3d.h"
#include "scene/resources/material.h"
#include "scene/resources/texture.h"

// Large landscape rendered from a height field. The terrain is cut into square chunks; each chunk
// has several levels of detail and the level is chosen by the distance to the viewer, so the
// triangle count stays roughly constant however large the terrain is. Chunks near the focus get a
// heightmap collision shape, far ones have none.
class ChunkedTerrain3D : public Node3D {
	GDCLASS(ChunkedTerrain3D, Node3D);

public:
	static constexpr int MAX_LOD = 8;

private:
	struct Chunk {
		int x0 = 0;
		int z0 = 0;
		// Local space bounds without skirt (used for distance and visibility decisions).
		AABB bounds;
		RID instance;
		RID meshes[MAX_LOD];
		int lod = -1;
		real_t lod_errors[MAX_LOD] = {}; // Cached height deviation per LOD.
		float morph = -1.0f; // Cache the last instance uniform; avoid redundant RD writes.
		float geometric_error = -1.0f; // Lazily cached normalized height deviation.
		bool visible = false;
#ifndef PHYSICS_3D_DISABLED
		RID body;
		RID shape;
#endif
		bool has_collision = false;
	};

	Ref<Texture2D> heightmap;
	Vector<real_t> height_data; // Active samples, from set_height_data() or the heightmap.
	PackedVector3Array normal_data; // Optional externally sampled, seam-continuous vertex normals.
	PackedColorArray color_data; // Optional source-grid terrain cavity/ridge colors.
	bool data_from_script = false;
	int data_width = 0;
	int data_depth = 0;

	Vector2 size = Vector2(1024, 1024);
	real_t height_scale = 100.0;
	real_t height_offset = 0.0;
	bool centered = true;
	int chunk_quads = 32;
	int lod_count = 4;
	real_t lod_distance = 128.0;
	real_t lod_pixel_error = 0.0; // Zero keeps the existing distance-based selector.
	// Soft *shared per-process frame* CPU time slice for lazy LOD mesh builds.
	// Zero retains eager mesh generation for old scenes and tools.
	uint32_t mesh_build_budget_usec = 0;
	// 0 = original row-major order, 1 = nearest first,
	// 2 = nearest with a bounded camera-facing priority bonus.
	int mesh_streaming_priority = 0;
	int pending_mesh_build_count = 0;
	static uint64_t shared_mesh_budget_frame;
	static uint64_t shared_mesh_budget_start_usec;
	static uint32_t shared_mesh_builds_this_frame;
	static uint32_t shared_mesh_budget_usec;
	bool lod_geomorph_enabled = false;
	bool screen_space_lod_enabled = false;
	real_t lod_reference_fov = 60.0;
	real_t lod_geometric_error_strength = 0.0; // 0: legacy selection, 1: ruggedness bias.
	real_t view_distance = 0.0;
	real_t skirt_depth = 4.0;
	Ref<Material> material;
	bool cast_shadows = true;
	uint32_t render_layers = 1; // Visual layers of the chunk instances (Camera3D.cull_mask), e.g. for top-down bake cameras.
	// The RID-backed heightfield is static and can contribute to SDFGI without
	// becoming a shadow caster. Off by default for non-GI projects.
	bool contribute_to_gi = false;
	bool collision_enabled = true;
	real_t collision_distance = 128.0;
	uint32_t collision_layer = 1;
	uint32_t collision_mask = 1;
	NodePath focus;
	double update_interval = 0.1;

	LocalVector<Chunk> chunks;
	int chunks_x = 0;
	int chunks_z = 0;
	double time_since_update = 1e9;
	bool built = false;
	bool rebuild_queued = false;
	int last_region_invalidated_chunks = 0; // Number of render chunks affected by the last edit.

	HeightmapTerrainGeometry::Params _params() const;
	HeightmapTerrainGeometry::HeightField _field() const;
	void _load_from_texture();
	void _queue_rebuild();
	void _rebuild();
	void _free_chunks();
	void _free_chunk_mesh_and_collision(Chunk &r_chunk);
	void _free_collision(Chunk &r_chunk);
	void _ensure_mesh(Chunk &r_chunk, int p_lod);
	void _ensure_collision(Chunk &r_chunk);
	void _invalidate_region(const Rect2i &p_region, bool p_geometry_changed);
	void _update_transforms();
	void _update_chunks(bool p_ignore_mesh_budget = false);
	bool _get_viewer_position(Vector3 &r_position) const;

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_heightmap(const Ref<Texture2D> &p_texture);
	Ref<Texture2D> get_heightmap() const { return heightmap; }
	// Supplies the heights directly (row-major, width * depth samples, normally 0..1), for example
	// from noise. Replaces the heightmap texture until clear_height_data() is called.
	void set_height_data(const PackedFloat32Array &p_heights, const Vector2i &p_dimensions);
	PackedFloat32Array get_height_data() const;
	// Optional row-major unit normals for the active height grid, including borders.
	void set_normal_data(const PackedVector3Array &p_normals);
	PackedVector3Array get_normal_data() const { return normal_data; }
	// Native CPU horizon bake; callers can pass a padded height grid to
	// keep independently streamed terrain chunks visually seamless.
	static PackedFloat32Array bake_horizon_visibility(const PackedFloat32Array &p_heights,
			const Vector2i &p_dimensions, real_t p_spacing, int p_radius_steps = 6);
	void set_color_data(const PackedColorArray &p_colors);
	PackedColorArray get_color_data() const { return color_data; }
	// Changes existing vertex colors without touching collision or heightfield LOD error.
	bool apply_color_patch(const Rect2i &p_region, const PackedColorArray &p_colors);
	Vector2i get_height_dimensions() const { return Vector2i(data_width, data_depth); }
	void clear_height_data();

	void set_size(const Vector2 &p_size);
	Vector2 get_size() const { return size; }
	void set_height_scale(real_t p_scale);
	real_t get_height_scale() const { return height_scale; }
	void set_height_offset(real_t p_offset);
	real_t get_height_offset() const { return height_offset; }
	void set_centered(bool p_centered);
	bool is_centered() const { return centered; }
	void set_chunk_quads(int p_quads);
	int get_chunk_quads() const { return chunk_quads; }
	void set_lod_count(int p_count);
	int get_lod_count() const { return lod_count; }
	void set_lod_distance(real_t p_distance);
	void set_lod_pixel_error(real_t p_pixels);
	void set_mesh_build_budget_usec(int p_usec);
	void set_mesh_streaming_priority(int p_mode);
	int get_mesh_streaming_priority() const { return mesh_streaming_priority; }
	int get_mesh_build_budget_usec() const { return int(mesh_build_budget_usec); }
	int get_pending_mesh_build_count() const { return pending_mesh_build_count; }
	real_t get_lod_pixel_error() const { return lod_pixel_error; }
	void set_lod_geomorph_enabled(bool p_enabled);
	bool is_lod_geomorph_enabled() const { return lod_geomorph_enabled; }
	real_t get_lod_distance() const { return lod_distance; }
	void set_screen_space_lod_enabled(bool p_enabled) { screen_space_lod_enabled = p_enabled; }
	bool is_screen_space_lod_enabled() const { return screen_space_lod_enabled; }
	void set_lod_reference_fov(real_t p_degrees);
	real_t get_lod_reference_fov() const { return lod_reference_fov; }
	void set_lod_geometric_error_strength(real_t p_strength);
	real_t get_lod_geometric_error_strength() const { return lod_geometric_error_strength; }
	void set_view_distance(real_t p_distance);
	real_t get_view_distance() const { return view_distance; }
	void set_skirt_depth(real_t p_depth);
	real_t get_skirt_depth() const { return skirt_depth; }
	void set_material(const Ref<Material> &p_material);
	Ref<Material> get_material() const { return material; }
	void set_cast_shadows(bool p_enabled);
	bool get_cast_shadows() const { return cast_shadows; }
	void set_render_layers(uint32_t p_layers);
	uint32_t get_render_layers() const { return render_layers; }
	void set_contribute_to_gi(bool p_enabled);
	bool is_contributing_to_gi() const { return contribute_to_gi; }
	void set_collision_enabled(bool p_enabled);
	bool is_collision_enabled() const { return collision_enabled; }
	void set_collision_distance(real_t p_distance);
	real_t get_collision_distance() const { return collision_distance; }
	void set_collision_layer(uint32_t p_layer);
	uint32_t get_collision_layer() const { return collision_layer; }
	void set_collision_mask(uint32_t p_mask);
	uint32_t get_collision_mask() const { return collision_mask; }
	void set_focus(const NodePath &p_focus) { focus = p_focus; }
	NodePath get_focus() const { return focus; }
	void set_update_interval(double p_seconds) { update_interval = MAX(p_seconds, 0.0); }
	double get_update_interval() const { return update_interval; }

	// World height of the ground at the x/z of `p_world_position`; the y of the argument is ignored.
	real_t get_height_at(const Vector3 &p_world_position) const;
	Vector3 get_normal_at(const Vector3 &p_world_position) const;
	// Whether the x/z of the world position lies over the terrain.
	bool is_over_terrain(const Vector3 &p_world_position) const;
	// Recomputes meshes and collision after the samples inside `p_region` (sample coordinates) changed.
	void update_region(const Rect2i &p_region);
	int get_last_region_invalidated_chunks() const { return last_region_invalidated_chunks; }
	// Atomically replace at most 4096 height samples in a rectangular source
	// region; only touched render/collision chunks are invalidated. Use
	// force_update() to synchronously rebuild immediately if required.
	bool apply_height_patch(const Rect2i &p_region, const PackedFloat32Array &p_heights);

	int get_chunk_count() const { return int(chunks.size()); }
	Vector2i get_chunk_grid_size() const { return Vector2i(chunks_x, chunks_z); }
	int get_visible_chunk_count() const;
	int get_collision_chunk_count() const;
	int get_chunk_lod(const Vector2i &p_chunk) const;
	// Height deviation at a particular simplification level, in world
	// vertical units; refreshed when nearby height samples are edited.
	real_t get_chunk_lod_error(const Vector2i &p_chunk, int p_lod) const;
	// Applies pending changes and the distance based detail selection now, instead of at the next update.
	void force_update();

	ChunkedTerrain3D();
	~ChunkedTerrain3D();
};
