/**************************************************************************/
/*  virtual_texture_page_cache.h                                          */
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

#include "core/io/image.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/variant/callable.h"

// Sparse virtual texture: page table, feedback-driven requests, LRU physical page cache,
// mip fallback and an indirection image for shaders. The lowest (1-page) mip is pinned.
// Atlas layout: physical slot (sx, sy) covers (page_size + 2 * border) pixels square.
class VirtualTexturePageCache : public RefCounted {
	GDCLASS(VirtualTexturePageCache, RefCounted);

	int virtual_size = 0;
	int page_size = 0;
	int border = 4;
	int physical_pages_x = 0;
	int physical_pages_y = 0;
	Callable provider;
	int pages_mip0 = 0;
	int top_mip = 0;
	int stat_hits = 0;
	int stat_misses = 0;
	int stat_evictions = 0;

	Vector<int> slot_key; // -1 = free
	Vector<int> slot_used; // frame stamp of last touch
	HashMap<int, int> resident; // key -> slot
	HashMap<int, int> pending; // key -> mip
	int frame = 1;
	Ref<Image> atlas;
	Ref<Image> indirection;
	bool indirection_dirty = true;

	Vector2i _slot_xy(int p_slot) const;
	void _touch_slot(int p_slot);
	void _ensure_top();
	int _acquire_slot();
	void _load_page(int p_key, int p_slot);
	void _fill_border(const Ref<Image> &p_img, const Vector2i &p_origin);
	void _rebuild_indirection();

protected:
	static void _bind_methods();

public:
	static int pack_page(int p_mip, int p_x, int p_y);
	static int page_mip(int p_key);
	static int page_x(int p_key);
	static int page_y(int p_key);

	void set_provider(const Callable &p_provider);
	Callable get_provider() const;
	int get_virtual_size() const;
	int get_page_size() const;
	int get_border() const;
	int get_physical_pages_x() const;
	int get_physical_pages_y() const;
	int get_pages_mip0() const;
	int get_top_mip() const;
	int get_stat_hits() const;
	int get_stat_misses() const;
	int get_stat_evictions() const;

	void setup(int p_virtual_size, int p_page_size, int p_physical_x, int p_physical_y, int p_border = 4);
	int pages_at(int p_mip) const;
	void request_from_feedback(const PackedInt32Array &p_feedback);
	int update(int p_max_uploads_per_frame);
	Ref<Image> indirection_image();
	Ref<Image> physical_atlas() const;
	Dictionary lookup(const Vector2 &p_uv, int p_mip) const;
	bool is_resident(int p_mip, int p_x, int p_y) const;
	int resident_count() const;
	int pending_count() const;
	Dictionary stats() const;
};
