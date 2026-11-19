/**************************************************************************/
/*  heightmap_terrain_3d.h                                             */
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
class HeightmapTerrain3D : public Node3D {
	GDCLASS(HeightmapTerrain3D, Node3D);

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
		bool visible = false;
#ifndef PHYSICS_3D_DISABLED
		RID body;
		RID shape;
#endif
		bool has_collision = false;
	};

	Ref<Texture2D> heightmap;
	Vector<real_t> height_data; // Active samples, from set_height_data() or the heightmap.
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
	real_t view_distance = 0.0;
	real_t skirt_depth = 4.0;
	Ref<Material> material;
	bool cast_shadows = true;
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
	void _update_transforms();
	void _update_chunks();
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
	real_t get_lod_distance() const { return lod_distance; }
	void set_view_distance(real_t p_distance);
	real_t get_view_distance() const { return view_distance; }
	void set_skirt_depth(real_t p_depth);
	real_t get_skirt_depth() const { return skirt_depth; }
	void set_material(const Ref<Material> &p_material);
	Ref<Material> get_material() const { return material; }
	void set_cast_shadows(bool p_enabled);
	bool get_cast_shadows() const { return cast_shadows; }
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

	int get_chunk_count() const { return int(chunks.size()); }
	Vector2i get_chunk_grid_size() const { return Vector2i(chunks_x, chunks_z); }
	int get_visible_chunk_count() const;
	int get_collision_chunk_count() const;
	int get_chunk_lod(const Vector2i &p_chunk) const;
	// Applies pending changes and the distance based detail selection now, instead of at the next update.
	void force_update();

	HeightmapTerrain3D();
	~HeightmapTerrain3D();
};
