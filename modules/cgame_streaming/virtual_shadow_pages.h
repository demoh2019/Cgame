/**************************************************************************/
/*  virtual_shadow_pages.h                                                */
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

#include "core/math/aabb.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"

// CPU-side virtual shadow map page manager: clipmap levels, fixed-size pages, page requests
// from visible receivers, caster invalidation and an LRU physical page pool with cross-frame
// cache reuse.
class VirtualShadowPages : public RefCounted {
	GDCLASS(VirtualShadowPages, RefCounted);

	struct Entry {
		int slot = 0;
		bool dirty = false;
		int64_t used = 0;
		int level = 0;
		int gx = 0;
		int gy = 0;
	};

	int levels = 0;
	real_t level0_size = 0.0;
	int page_size = 128;
	int virtual_resolution = 0;
	int pages_per_axis = 0;
	int physical_capacity = 0;

	Vector3 light_dir = Vector3(0, -1, 0);
	Vector3 right = Vector3(1, 0, 0);
	Vector3 up = Vector3(0, 0, -1);
	LocalVector<Vector2i> center;
	HashMap<int64_t, Entry> cache;
	LocalVector<int> free_slots;
	HashSet<int64_t> requested;
	PackedInt32Array render_jobs; // (clipmap level, global page X, page Y, physical slot)
	int64_t frame = 0;
	int evicted = 0;
	int dropped = 0;

	static int64_t _key(int p_level, int p_gx, int p_gy);
	bool _in_current_window(int p_level, int p_gx, int p_gy) const;
	void _append_render_job(const Entry &p_entry);
	int _take_slot();

protected:
	static void _bind_methods();

public:
	int get_levels() const;
	real_t get_level0_size() const;
	int get_page_size() const;
	int get_virtual_resolution() const;
	int get_pages_per_axis() const;
	int get_physical_capacity() const;

	void setup(int p_clipmap_levels, real_t p_level0_world_size, int p_page_size_texels, int p_virtual_res, int p_physical_pages);
	real_t level_world_size(int p_level) const;
	real_t page_world_size(int p_level) const;
	real_t texel_world_size(int p_level) const;
	void begin_frame(const Vector3 &p_light_dir, const Vector3 &p_camera_pos);
	Vector2i clipmap_center(int p_level) const;
	int level_for_footprint(real_t p_footprint) const;
	void request_for_receivers(const PackedVector3Array &p_points, const PackedFloat32Array &p_pixel_footprints);
	void invalidate_casters(const Array &p_aabbs_moved);
	Dictionary end_frame();
	int resident_count() const;
	bool is_resident(int p_level, int p_gx, int p_gy) const;
	PackedInt32Array page_table() const;
	PackedInt32Array get_render_jobs() const { return render_jobs; }
};
