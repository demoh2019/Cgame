/**************************************************************************/
/*  virtual_shadow_pages.cpp                                              */
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

#include "virtual_shadow_pages.h"

#include "core/object/class_db.h"

int VirtualShadowPages::get_levels() const {
	return levels;
}

real_t VirtualShadowPages::get_level0_size() const {
	return level0_size;
}

int VirtualShadowPages::get_page_size() const {
	return page_size;
}

int VirtualShadowPages::get_virtual_resolution() const {
	return virtual_resolution;
}

int VirtualShadowPages::get_pages_per_axis() const {
	return pages_per_axis;
}

int VirtualShadowPages::get_physical_capacity() const {
	return physical_capacity;
}

int64_t VirtualShadowPages::_key(int p_level, int p_gx, int p_gy) {
	return ((int64_t)(p_level & 0xFF) << 48) | ((int64_t)((p_gx + 0x800000) & 0xFFFFFF) << 24) | (int64_t)((p_gy + 0x800000) & 0xFFFFFF);
}

bool VirtualShadowPages::_in_current_window(int p_level, int p_gx, int p_gy) const {
	if (p_level < 0 || p_level >= int(center.size()) || pages_per_axis < 1) {
		return false;
	}
	// An N-by-N clipmap has exactly N slots along each axis, even for
	// odd N (or N == 1). Use signed 64-bit deltas to avoid overflow near
	// large world coordinates. The half-open range is [-N/2, N-N/2).
	const int64_t dx = int64_t(p_gx) - center[p_level].x;
	const int64_t dy = int64_t(p_gy) - center[p_level].y;
	const int half = pages_per_axis / 2;
	return dx >= -half && dx < pages_per_axis - half &&
			dy >= -half && dy < pages_per_axis - half;
}

void VirtualShadowPages::_append_render_job(const Entry &p_entry) {
	render_jobs.push_back(p_entry.level);
	render_jobs.push_back(p_entry.gx);
	render_jobs.push_back(p_entry.gy);
	render_jobs.push_back(p_entry.slot);
}

void VirtualShadowPages::setup(int p_clipmap_levels, real_t p_level0_world_size, int p_page_size_texels, int p_virtual_res, int p_physical_pages) {
	levels = CLAMP(p_clipmap_levels, 1, 32);
	level0_size = MAX(p_level0_world_size, (real_t)0.001);
	page_size = MAX(p_page_size_texels, 1);
	virtual_resolution = MAX(p_virtual_res, page_size);
	pages_per_axis = MAX(virtual_resolution / page_size, 1);
	physical_capacity = MAX(p_physical_pages, 1);
	cache.clear();
	requested.clear();
	render_jobs.clear();
	free_slots.clear();
	for (int i = physical_capacity - 1; i >= 0; i--) {
		free_slots.push_back(i);
	}
	center.clear();
	for (int l = 0; l < levels; l++) {
		center.push_back(Vector2i());
	}
	frame = 0;
}

real_t VirtualShadowPages::level_world_size(int p_level) const {
	return level0_size * (real_t)(1 << p_level);
}

real_t VirtualShadowPages::page_world_size(int p_level) const {
	return level_world_size(p_level) / (real_t)pages_per_axis;
}

real_t VirtualShadowPages::texel_world_size(int p_level) const {
	return level_world_size(p_level) / (real_t)virtual_resolution;
}

void VirtualShadowPages::begin_frame(const Vector3 &p_light_dir, const Vector3 &p_camera_pos) {
	ERR_FAIL_COND_MSG(levels == 0, "VirtualShadowPages.setup() must be called first.");
	frame++;
	requested.clear();
	render_jobs.clear();
	evicted = 0;
	dropped = 0;
	Vector3 d = p_light_dir.normalized();
	if (d.length_squared() < 0.5f) {
		d = Vector3(0, -1, 0);
	}
	if (Math::abs(d.dot(Vector3(0, 1, 0))) > 0.99f) {
		right = Vector3(1, 0, 0);
	} else {
		right = d.cross(Vector3(0, 1, 0)).normalized();
	}
	up = right.cross(d).normalized();
	if (!d.is_equal_approx(light_dir) && !cache.is_empty()) {
		// Light moved: every cached page is stale.
		for (KeyValue<int64_t, Entry> &kv : cache) {
			kv.value.dirty = true;
		}
	}
	light_dir = d;
	real_t cx = p_camera_pos.dot(right);
	real_t cy = p_camera_pos.dot(up);
	for (int l = 0; l < levels; l++) {
		real_t pw = page_world_size(l);
		center[l] = Vector2i((int)Math::floor(cx / pw), (int)Math::floor(cy / pw));
	}
}

Vector2i VirtualShadowPages::clipmap_center(int p_level) const {
	ERR_FAIL_INDEX_V(p_level, (int)center.size(), Vector2i());
	return center[p_level];
}

int VirtualShadowPages::level_for_footprint(real_t p_footprint) const {
	real_t f = MAX(p_footprint, (real_t)0.000001);
	for (int l = 0; l < levels; l++) {
		if (texel_world_size(l) >= f) {
			return l;
		}
	}
	return levels - 1;
}

void VirtualShadowPages::request_for_receivers(const PackedVector3Array &p_points, const PackedFloat32Array &p_pixel_footprints) {
	ERR_FAIL_COND_MSG(levels == 0, "VirtualShadowPages.setup() must be called first.");
	for (int i = 0; i < p_points.size(); i++) {
		real_t fp = i < p_pixel_footprints.size() ? p_pixel_footprints[i] : texel_world_size(0);
		int l = level_for_footprint(fp);
		Vector3 p = p_points[i];
		real_t pw = page_world_size(l);
		int gx = (int)Math::floor(p.dot(right) / pw);
		int gy = (int)Math::floor(p.dot(up) / pw);
		if (!_in_current_window(l, gx, gy)) {
			continue;
		}
		requested.insert(_key(l, gx, gy));
	}
}

void VirtualShadowPages::invalidate_casters(const Array &p_aabbs_moved) {
	ERR_FAIL_COND_MSG(levels == 0, "VirtualShadowPages.setup() must be called first.");
	for (int ai = 0; ai < p_aabbs_moved.size(); ai++) {
		AABB box = p_aabbs_moved[ai];
		Vector2 lo(Math::INF, Math::INF);
		Vector2 hi(-Math::INF, -Math::INF);
		for (int c = 0; c < 8; c++) {
			Vector3 corner = box.get_endpoint(c);
			Vector2 q(corner.dot(right), corner.dot(up));
			lo = lo.min(q);
			hi = hi.max(q);
		}
		for (int l = 0; l < levels; l++) {
			real_t pw = page_world_size(l);
			int x0 = (int)Math::floor(lo.x / pw);
			int x1 = (int)Math::floor(hi.x / pw);
			int y0 = (int)Math::floor(lo.y / pw);
			int y1 = (int)Math::floor(hi.y / pw);
			if ((int64_t)(x1 - x0 + 1) * (int64_t)(y1 - y0 + 1) > (int64_t)cache.size()) {
				// Wide box: scan the cache instead of enumerating the rect.
				for (KeyValue<int64_t, Entry> &kv : cache) {
					Entry &e = kv.value;
					if (e.level == l && e.gx >= x0 && e.gx <= x1 && e.gy >= y0 && e.gy <= y1) {
						e.dirty = true;
					}
				}
			} else {
				for (int gx = x0; gx <= x1; gx++) {
					for (int gy = y0; gy <= y1; gy++) {
						HashMap<int64_t, Entry>::Iterator it = cache.find(_key(l, gx, gy));
						if (it) {
							it->value.dirty = true;
						}
					}
				}
			}
		}
	}
}

int VirtualShadowPages::_take_slot() {
	if (!free_slots.is_empty()) {
		int s = free_slots[free_slots.size() - 1];
		free_slots.remove_at(free_slots.size() - 1);
		return s;
	}
	bool found = false;
	int64_t victim = 0;
	int64_t oldest = (int64_t)1 << 60;
	for (const KeyValue<int64_t, Entry> &kv : cache) {
		if (requested.has(kv.key)) {
			continue;
		}
		if (kv.value.used < oldest) {
			oldest = kv.value.used;
			victim = kv.key;
			found = true;
		}
	}
	if (!found) {
		return -1;
	}
	int slot = cache[victim].slot;
	cache.erase(victim);
	evicted++;
	return slot;
}

Dictionary VirtualShadowPages::end_frame() {
	int allocated = 0;
	int reused = 0;
	int rendered = 0;
	LocalVector<int64_t> keys;
	for (int64_t k : requested) {
		keys.push_back(k);
	}
	keys.sort();
	// Touch cache hits first so they are never chosen as eviction victims.
	for (int64_t k : keys) {
		HashMap<int64_t, Entry>::Iterator it = cache.find(k);
		if (it) {
			it->value.used = frame;
		}
	}
	for (int64_t k : keys) {
		HashMap<int64_t, Entry>::Iterator it = cache.find(k);
		if (it) {
			if (it->value.dirty) {
				_append_render_job(it->value);
				it->value.dirty = false;
				rendered++;
			} else {
				reused++;
			}
			continue;
		}
		int slot = _take_slot();
		if (slot < 0) {
			dropped++;
			continue;
		}
		Entry e;
		e.slot = slot;
		e.dirty = false;
		e.used = frame;
		e.level = (int)((k >> 48) & 0xFF);
		e.gx = (int)(((k >> 24) & 0xFFFFFF) - 0x800000);
		e.gy = (int)((k & 0xFFFFFF) - 0x800000);
		cache[k] = e;
		_append_render_job(e);
		allocated++;
		rendered++;
	}
	Dictionary d;
	d["allocated"] = allocated;
	d["reused"] = reused;
	d["rendered"] = rendered;
	d["evicted"] = evicted;
	d["dropped"] = dropped;
	d["requested"] = (int)keys.size();
	d["resident"] = (int)cache.size();
	return d;
}

int VirtualShadowPages::resident_count() const {
	return cache.size();
}

bool VirtualShadowPages::is_resident(int p_level, int p_gx, int p_gy) const {
	return cache.has(_key(p_level, p_gx, p_gy));
}

PackedInt32Array VirtualShadowPages::page_table() const {
	int n = pages_per_axis;
	PackedInt32Array table;
	table.resize(levels * n * n);
	table.fill(-1);
	for (const KeyValue<int64_t, Entry> &kv : cache) {
		const Entry &e = kv.value;
		// Cache entries from an earlier camera position are still valid for
		// possible reuse, but MUST NOT overwrite toroidal mappings of the
		// currently visible clipmap (same page index modulo N).
		if (!_in_current_window(e.level, e.gx, e.gy)) {
			continue;
		}
		table.write[e.level * n * n + Math::posmod(e.gy, n) * n + Math::posmod(e.gx, n)] = e.slot;
	}
	return table;
}

void VirtualShadowPages::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_levels"), &VirtualShadowPages::get_levels);
	ClassDB::bind_method(D_METHOD("get_level0_size"), &VirtualShadowPages::get_level0_size);
	ClassDB::bind_method(D_METHOD("get_page_size"), &VirtualShadowPages::get_page_size);
	ClassDB::bind_method(D_METHOD("get_virtual_resolution"), &VirtualShadowPages::get_virtual_resolution);
	ClassDB::bind_method(D_METHOD("get_pages_per_axis"), &VirtualShadowPages::get_pages_per_axis);
	ClassDB::bind_method(D_METHOD("get_physical_capacity"), &VirtualShadowPages::get_physical_capacity);

	ClassDB::bind_method(D_METHOD("setup", "clipmap_levels", "level0_world_size", "page_size_texels", "virtual_res", "physical_pages"), &VirtualShadowPages::setup);
	ClassDB::bind_method(D_METHOD("level_world_size", "level"), &VirtualShadowPages::level_world_size);
	ClassDB::bind_method(D_METHOD("page_world_size", "level"), &VirtualShadowPages::page_world_size);
	ClassDB::bind_method(D_METHOD("texel_world_size", "level"), &VirtualShadowPages::texel_world_size);
	ClassDB::bind_method(D_METHOD("begin_frame", "light_dir", "camera_pos"), &VirtualShadowPages::begin_frame);
	ClassDB::bind_method(D_METHOD("clipmap_center", "level"), &VirtualShadowPages::clipmap_center);
	ClassDB::bind_method(D_METHOD("level_for_footprint", "footprint"), &VirtualShadowPages::level_for_footprint);
	ClassDB::bind_method(D_METHOD("request_for_receivers", "points", "pixel_footprints"), &VirtualShadowPages::request_for_receivers);
	ClassDB::bind_method(D_METHOD("invalidate_casters", "aabbs_moved"), &VirtualShadowPages::invalidate_casters);
	ClassDB::bind_method(D_METHOD("end_frame"), &VirtualShadowPages::end_frame);
	ClassDB::bind_method(D_METHOD("resident_count"), &VirtualShadowPages::resident_count);
	ClassDB::bind_method(D_METHOD("is_resident", "level", "gx", "gy"), &VirtualShadowPages::is_resident);
	ClassDB::bind_method(D_METHOD("page_table"), &VirtualShadowPages::page_table);
	ClassDB::bind_method(D_METHOD("get_render_jobs"), &VirtualShadowPages::get_render_jobs);
}
