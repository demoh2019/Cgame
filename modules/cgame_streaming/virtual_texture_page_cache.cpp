/**************************************************************************/
/*  virtual_texture_page_cache.cpp                                        */
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

#include "virtual_texture_page_cache.h"

#include "core/object/class_db.h"
#include "core/templates/local_vector.h"

int VirtualTexturePageCache::pack_page(int p_mip, int p_x, int p_y) {
	return (p_mip << 24) | (p_y << 12) | p_x;
}

int VirtualTexturePageCache::page_mip(int p_key) {
	return (p_key >> 24) & 0xFF;
}

int VirtualTexturePageCache::page_x(int p_key) {
	return p_key & 0xFFF;
}

int VirtualTexturePageCache::page_y(int p_key) {
	return (p_key >> 12) & 0xFFF;
}

void VirtualTexturePageCache::set_provider(const Callable &p_provider) {
	provider = p_provider;
}

Callable VirtualTexturePageCache::get_provider() const {
	return provider;
}

int VirtualTexturePageCache::get_virtual_size() const {
	return virtual_size;
}

int VirtualTexturePageCache::get_page_size() const {
	return page_size;
}

int VirtualTexturePageCache::get_border() const {
	return border;
}

int VirtualTexturePageCache::get_physical_pages_x() const {
	return physical_pages_x;
}

int VirtualTexturePageCache::get_physical_pages_y() const {
	return physical_pages_y;
}

int VirtualTexturePageCache::get_pages_mip0() const {
	return pages_mip0;
}

int VirtualTexturePageCache::get_top_mip() const {
	return top_mip;
}

int VirtualTexturePageCache::get_stat_hits() const {
	return stat_hits;
}

int VirtualTexturePageCache::get_stat_misses() const {
	return stat_misses;
}

int VirtualTexturePageCache::get_stat_evictions() const {
	return stat_evictions;
}

void VirtualTexturePageCache::setup(int p_virtual_size, int p_page_size, int p_physical_x, int p_physical_y, int p_border) {
	ERR_FAIL_COND(p_virtual_size <= 0 || p_page_size <= 0 || p_physical_x <= 0 || p_physical_y <= 0 || p_border < 0);
	ERR_FAIL_COND_MSG(p_virtual_size / p_page_size > 4096, "Virtual texture exceeds 4096 pages per axis.");
	virtual_size = p_virtual_size;
	page_size = p_page_size;
	physical_pages_x = p_physical_x;
	physical_pages_y = p_physical_y;
	border = p_border;
	pages_mip0 = MAX(1, virtual_size / page_size);
	top_mip = 0;
	while ((pages_mip0 >> top_mip) > 1) {
		top_mip++;
	}
	int slots = physical_pages_x * physical_pages_y;
	slot_key.resize(slots);
	slot_key.fill(-1);
	slot_used.resize(slots);
	slot_used.fill(0);
	resident.clear();
	pending.clear();
	frame = 1;
	stat_hits = 0;
	stat_misses = 0;
	stat_evictions = 0;
	int slot_px = page_size + 2 * border;
	atlas = Image::create_empty(physical_pages_x * slot_px, physical_pages_y * slot_px, false, Image::FORMAT_RGBA8);
	indirection = Image::create_empty(pages_mip0, pages_mip0, false, Image::FORMAT_RGBA8);
	indirection_dirty = true;
	_ensure_top();
}

int VirtualTexturePageCache::pages_at(int p_mip) const {
	return MAX(1, pages_mip0 >> p_mip);
}

void VirtualTexturePageCache::request_from_feedback(const PackedInt32Array &p_feedback) {
	for (int key : p_feedback) {
		int mip = page_mip(key);
		if (mip > top_mip) {
			continue;
		}
		HashMap<int, int>::Iterator it = resident.find(key);
		if (it) {
			stat_hits++;
			_touch_slot(it->value);
		} else if (!pending.has(key)) {
			stat_misses++;
			pending[key] = mip;
		} else {
			stat_misses++;
		}
	}
}

namespace {
struct PendingOrder {
	bool operator()(int p_a, int p_b) const {
		int ma = VirtualTexturePageCache::page_mip(p_a);
		int mb = VirtualTexturePageCache::page_mip(p_b);
		if (ma != mb) {
			return ma > mb;
		}
		return p_a < p_b;
	}
};
} //namespace

int VirtualTexturePageCache::update(int p_max_uploads_per_frame) {
	_ensure_top();
	LocalVector<int> order;
	for (const KeyValue<int, int> &kv : pending) {
		order.push_back(kv.key);
	}
	order.sort_custom<PendingOrder>();
	int uploaded = 0;
	for (int key : order) {
		if (uploaded >= p_max_uploads_per_frame) {
			break;
		}
		int slot = _acquire_slot();
		if (slot < 0) {
			break;
		}
		_load_page(key, slot);
		pending.erase(key);
		uploaded++;
	}
	frame++;
	return uploaded;
}

Ref<Image> VirtualTexturePageCache::indirection_image() {
	if (indirection_dirty) {
		_rebuild_indirection();
	}
	return indirection;
}

Ref<Image> VirtualTexturePageCache::physical_atlas() const {
	return atlas;
}

Dictionary VirtualTexturePageCache::lookup(const Vector2 &p_uv, int p_mip) const {
	int m = CLAMP(p_mip, 0, top_mip);
	while (m <= top_mip) {
		int n = pages_at(m);
		int px = CLAMP((int)Math::floor(p_uv.x * n), 0, n - 1);
		int py = CLAMP((int)Math::floor(p_uv.y * n), 0, n - 1);
		HashMap<int, int>::ConstIterator it = resident.find(pack_page(m, px, py));
		if (it) {
			Dictionary d;
			d["slot"] = _slot_xy(it->value);
			d["resident_mip"] = m;
			d["page"] = Vector2i(px, py);
			return d;
		}
		m++;
	}
	Dictionary d;
	d["slot"] = Vector2i(-1, -1);
	d["resident_mip"] = -1;
	d["page"] = Vector2i(-1, -1);
	return d;
}

bool VirtualTexturePageCache::is_resident(int p_mip, int p_x, int p_y) const {
	return resident.has(pack_page(p_mip, p_x, p_y));
}

int VirtualTexturePageCache::resident_count() const {
	return resident.size();
}

int VirtualTexturePageCache::pending_count() const {
	return pending.size();
}

Dictionary VirtualTexturePageCache::stats() const {
	Dictionary d;
	d["hits"] = stat_hits;
	d["misses"] = stat_misses;
	d["evictions"] = stat_evictions;
	d["resident_pages"] = resident.size();
	return d;
}

Vector2i VirtualTexturePageCache::_slot_xy(int p_slot) const {
	return Vector2i(p_slot % physical_pages_x, p_slot / physical_pages_x);
}

void VirtualTexturePageCache::_touch_slot(int p_slot) {
	slot_used.write[p_slot] = frame;
}

void VirtualTexturePageCache::_ensure_top() {
	int key = pack_page(top_mip, 0, 0);
	if (resident.has(key) || !provider.is_valid()) {
		return;
	}
	int slot = _acquire_slot();
	if (slot >= 0) {
		_load_page(key, slot);
		pending.erase(key);
	}
}

int VirtualTexturePageCache::_acquire_slot() {
	int best = -1;
	int best_used = 0x7FFFFFFF;
	for (int s = 0; s < slot_key.size(); s++) {
		int k = slot_key[s];
		if (k < 0) {
			return s;
		}
		if (slot_used[s] >= frame || page_mip(k) == top_mip) {
			continue;
		}
		if (slot_used[s] < best_used) {
			best_used = slot_used[s];
			best = s;
		}
	}
	if (best >= 0) {
		resident.erase(slot_key[best]);
		slot_key.write[best] = -1;
		stat_evictions++;
		indirection_dirty = true;
	}
	return best;
}

void VirtualTexturePageCache::_load_page(int p_key, int p_slot) {
	Ref<Image> img;
	if (provider.is_valid()) {
		Variant args[3] = { page_mip(p_key), page_x(p_key), page_y(p_key) };
		const Variant *argp[3] = { &args[0], &args[1], &args[2] };
		Variant ret;
		Callable::CallError err;
		provider.callp(argp, 3, ret, err);
		if (err.error == Callable::CallError::CALL_OK) {
			img = ret;
		}
	}
	slot_key.write[p_slot] = p_key;
	slot_used.write[p_slot] = frame;
	resident[p_key] = p_slot;
	indirection_dirty = true;
	if (img.is_null() || img->is_empty()) {
		return;
	}
	if (img->get_format() != Image::FORMAT_RGBA8) {
		img->convert(Image::FORMAT_RGBA8);
	}
	if (img->get_width() != page_size || img->get_height() != page_size) {
		img->resize(page_size, page_size, Image::INTERPOLATE_BILINEAR);
	}
	int slot_px = page_size + 2 * border;
	Vector2i origin = _slot_xy(p_slot) * slot_px;
	atlas->blit_rect(img, Rect2i(0, 0, page_size, page_size), origin + Vector2i(border, border));
	if (border > 0) {
		_fill_border(img, origin);
	}
}

void VirtualTexturePageCache::_fill_border(const Ref<Image> &p_img, const Vector2i &p_origin) {
	int last = page_size - 1;
	for (int y = -border; y < page_size + border; y++) {
		for (int x = -border; x < page_size + border; x++) {
			if (x >= 0 && x < page_size && y >= 0 && y < page_size) {
				continue;
			}
			Color c = p_img->get_pixel(CLAMP(x, 0, last), CLAMP(y, 0, last));
			atlas->set_pixel(p_origin.x + border + x, p_origin.y + border + y, c);
		}
	}
}

void VirtualTexturePageCache::_rebuild_indirection() {
	for (int y = 0; y < pages_mip0; y++) {
		for (int x = 0; x < pages_mip0; x++) {
			int m = 0;
			bool found = false;
			while (m <= top_mip) {
				HashMap<int, int>::ConstIterator it = resident.find(pack_page(m, x >> m, y >> m));
				if (it) {
					Vector2i xy = _slot_xy(it->value);
					indirection->set_pixel(x, y, Color::from_rgba8(xy.x, xy.y, m, 255));
					found = true;
					break;
				}
				m++;
			}
			if (!found) {
				indirection->set_pixel(x, y, Color::from_rgba8(0, 0, 255, 0));
			}
		}
	}
	indirection_dirty = false;
}

void VirtualTexturePageCache::_bind_methods() {
	ClassDB::bind_static_method("VirtualTexturePageCache", D_METHOD("pack_page", "mip", "x", "y"), &VirtualTexturePageCache::pack_page);
	ClassDB::bind_static_method("VirtualTexturePageCache", D_METHOD("page_mip", "key"), &VirtualTexturePageCache::page_mip);
	ClassDB::bind_static_method("VirtualTexturePageCache", D_METHOD("page_x", "key"), &VirtualTexturePageCache::page_x);
	ClassDB::bind_static_method("VirtualTexturePageCache", D_METHOD("page_y", "key"), &VirtualTexturePageCache::page_y);

	ClassDB::bind_method(D_METHOD("set_provider", "provider"), &VirtualTexturePageCache::set_provider);
	ClassDB::bind_method(D_METHOD("get_provider"), &VirtualTexturePageCache::get_provider);
	ClassDB::bind_method(D_METHOD("get_virtual_size"), &VirtualTexturePageCache::get_virtual_size);
	ClassDB::bind_method(D_METHOD("get_page_size"), &VirtualTexturePageCache::get_page_size);
	ClassDB::bind_method(D_METHOD("get_border"), &VirtualTexturePageCache::get_border);
	ClassDB::bind_method(D_METHOD("get_physical_pages_x"), &VirtualTexturePageCache::get_physical_pages_x);
	ClassDB::bind_method(D_METHOD("get_physical_pages_y"), &VirtualTexturePageCache::get_physical_pages_y);
	ClassDB::bind_method(D_METHOD("get_pages_mip0"), &VirtualTexturePageCache::get_pages_mip0);
	ClassDB::bind_method(D_METHOD("get_top_mip"), &VirtualTexturePageCache::get_top_mip);
	ClassDB::bind_method(D_METHOD("get_stat_hits"), &VirtualTexturePageCache::get_stat_hits);
	ClassDB::bind_method(D_METHOD("get_stat_misses"), &VirtualTexturePageCache::get_stat_misses);
	ClassDB::bind_method(D_METHOD("get_stat_evictions"), &VirtualTexturePageCache::get_stat_evictions);

	ClassDB::bind_method(D_METHOD("setup", "virtual_size", "page_size", "physical_x", "physical_y", "border"), &VirtualTexturePageCache::setup, DEFVAL(4));
	ClassDB::bind_method(D_METHOD("pages_at", "mip"), &VirtualTexturePageCache::pages_at);
	ClassDB::bind_method(D_METHOD("request_from_feedback", "feedback"), &VirtualTexturePageCache::request_from_feedback);
	ClassDB::bind_method(D_METHOD("update", "max_uploads_per_frame"), &VirtualTexturePageCache::update);
	ClassDB::bind_method(D_METHOD("indirection_image"), &VirtualTexturePageCache::indirection_image);
	ClassDB::bind_method(D_METHOD("physical_atlas"), &VirtualTexturePageCache::physical_atlas);
	ClassDB::bind_method(D_METHOD("lookup", "uv", "mip"), &VirtualTexturePageCache::lookup);
	ClassDB::bind_method(D_METHOD("is_resident", "mip", "x", "y"), &VirtualTexturePageCache::is_resident);
	ClassDB::bind_method(D_METHOD("resident_count"), &VirtualTexturePageCache::resident_count);
	ClassDB::bind_method(D_METHOD("pending_count"), &VirtualTexturePageCache::pending_count);
	ClassDB::bind_method(D_METHOD("stats"), &VirtualTexturePageCache::stats);

	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "provider"), "set_provider", "get_provider");
}
