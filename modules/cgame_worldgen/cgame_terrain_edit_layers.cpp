/**************************************************************************/
/*  cgame_terrain_edit_layers.cpp                                         */
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

#include "cgame_terrain_edit_layers.h"

#include "core/object/class_db.h"

#include "cgame_worldgen_util.h"

#include "core/math/math_funcs.h"

// ---------------------------------------------------------------- setup

void CgameTerrainEditLayers::setup(int p_width, int p_height, int p_chunk_size, const PackedFloat32Array &p_base_heights) {
	width = MAX(2, p_width);
	height = MAX(2, p_height);
	chunk_size = MAX(1, p_chunk_size);
	chunks_x = MAX(1, (int)Math::ceil((double)(width - 1) / (double)chunk_size));
	chunks_z = MAX(1, (int)Math::ceil((double)(height - 1) / (double)chunk_size));
	base.clear();
	base.resize((int64_t)width * height);
	base.fill(0.0f);
	if ((int64_t)p_base_heights.size() == (int64_t)width * height) {
		base = p_base_heights.duplicate();
	}
	layers.clear();
	next_layer_id = 1;
	splat_count_value = 0;
	splat.clear();
	undo_stack.clear();
	redo_stack.clear();
	dirty.clear();
	collision_pending.clear();
	collision_queue.clear();
	_mark_rect_dirty(Rect2i(0, 0, width, height));
}

void CgameTerrainEditLayers::set_max_undo_bytes(int64_t p_bytes) {
	max_undo_bytes = MAX((int64_t)0, p_bytes);
	_trim_history();
}

// ---------------------------------------------------------------- layers

int CgameTerrainEditLayers::_layer_index(int p_id) const {
	for (int i = 0; i < layers.size(); i++) {
		if (layers[i].id == p_id) {
			return i;
		}
	}
	return -1;
}

void CgameTerrainEditLayers::_mark_layer_dirty(const EditLayer &p_layer) {
	if (p_layer.has_bounds) {
		_mark_rect_dirty(p_layer.bounds);
	}
}

void CgameTerrainEditLayers::_mark_all_layers_dirty() {
	for (int i = 0; i < layers.size(); i++) {
		_mark_layer_dirty(layers[i]);
	}
}

void CgameTerrainEditLayers::_grow_bounds(EditLayer &r_layer, const Rect2i &p_rect) {
	if (r_layer.has_bounds) {
		r_layer.bounds = r_layer.bounds.merge(p_rect);
	} else {
		r_layer.bounds = p_rect;
		r_layer.has_bounds = true;
	}
}

int CgameTerrainEditLayers::add_layer(const String &p_name, Blend p_blend, double p_opacity) {
	ERR_FAIL_COND_V_MSG(width <= 0, -1, "CgameTerrainEditLayers: call setup() before add_layer().");
	EditLayer l;
	l.id = next_layer_id++;
	l.name = p_name;
	l.blend = p_blend;
	l.opacity = p_opacity;
	l.delta.resize((int64_t)width * height);
	l.delta.fill(0.0f);
	l.alpha.resize((int64_t)width * height);
	l.alpha.fill(0.0f);
	layers.push_back(l);
	return l.id;
}

int CgameTerrainEditLayers::add_layer_from_region(const String &p_name, const Rect2i &p_rect, const PackedFloat32Array &p_delta, const PackedFloat32Array &p_alpha, Blend p_blend, double p_opacity) {
	const int id = add_layer(p_name, p_blend, p_opacity);
	if (id < 0) {
		return id;
	}
	write_layer_region(id, p_rect, p_delta, p_alpha);
	return id;
}

bool CgameTerrainEditLayers::remove_layer(int p_id) {
	const int i = _layer_index(p_id);
	if (i < 0) {
		return false;
	}
	_mark_layer_dirty(layers[i]);
	layers.remove_at(i);
	return true;
}

// Moves a layer to p_to_index in the stack (0 = bottom, composited first).
bool CgameTerrainEditLayers::move_layer(int p_id, int p_to_index) {
	const int i = _layer_index(p_id);
	if (i < 0) {
		return false;
	}
	const EditLayer l = layers[i];
	layers.remove_at(i);
	layers.insert(CLAMP(p_to_index, 0, (int)layers.size()), l);
	_mark_all_layers_dirty();
	return true;
}

void CgameTerrainEditLayers::set_layer_visible(int p_id, bool p_visible) {
	const int i = _layer_index(p_id);
	if (i >= 0 && layers[i].visible != p_visible) {
		layers.write[i].visible = p_visible;
		_mark_layer_dirty(layers[i]);
	}
}

bool CgameTerrainEditLayers::is_layer_visible(int p_id) const {
	const int i = _layer_index(p_id);
	return i >= 0 && layers[i].visible;
}

void CgameTerrainEditLayers::set_layer_opacity(int p_id, double p_opacity) {
	const int i = _layer_index(p_id);
	if (i >= 0) {
		layers.write[i].opacity = CLAMP(p_opacity, 0.0, 1.0);
		_mark_layer_dirty(layers[i]);
	}
}

double CgameTerrainEditLayers::get_layer_opacity(int p_id) const {
	const int i = _layer_index(p_id);
	return i >= 0 ? layers[i].opacity : 0.0;
}

void CgameTerrainEditLayers::set_layer_blend(int p_id, Blend p_blend) {
	const int i = _layer_index(p_id);
	if (i >= 0) {
		layers.write[i].blend = p_blend;
		_mark_layer_dirty(layers[i]);
	}
}

CgameTerrainEditLayers::Blend CgameTerrainEditLayers::get_layer_blend(int p_id) const {
	const int i = _layer_index(p_id);
	return i >= 0 ? (Blend)layers[i].blend : BLEND_ADD;
}

void CgameTerrainEditLayers::set_layer_name(int p_id, const String &p_name) {
	const int i = _layer_index(p_id);
	if (i >= 0) {
		layers.write[i].name = p_name;
	}
}

String CgameTerrainEditLayers::get_layer_name(int p_id) const {
	const int i = _layer_index(p_id);
	return i >= 0 ? layers[i].name : String();
}

// Layer ids from bottom to top.
PackedInt32Array CgameTerrainEditLayers::layer_ids() const {
	PackedInt32Array out;
	for (int i = 0; i < layers.size(); i++) {
		out.push_back(layers[i].id);
	}
	return out;
}

Rect2i CgameTerrainEditLayers::get_layer_bounds(int p_id) const {
	const int i = _layer_index(p_id);
	return (i >= 0 && layers[i].has_bounds) ? layers[i].bounds : Rect2i();
}

// ---------------------------------------------------------------- per-texel access

double CgameTerrainEditLayers::layer_delta_at(int p_id, int p_x, int p_y) const {
	const int li = _layer_index(p_id);
	if (li < 0 || p_x < 0 || p_y < 0 || p_x >= width || p_y >= height) {
		return 0.0;
	}
	return layers[li].delta[p_y * width + p_x];
}

double CgameTerrainEditLayers::layer_alpha_at(int p_id, int p_x, int p_y) const {
	const int li = _layer_index(p_id);
	if (li < 0 || p_x < 0 || p_y < 0 || p_x >= width || p_y >= height) {
		return 0.0;
	}
	return layers[li].alpha[p_y * width + p_x];
}

// Writes one texel of a layer directly. Not on the undo stack; grows the layer bounds and marks
// the affected chunks dirty, so editor tools can drive their own history.
bool CgameTerrainEditLayers::set_layer_texel(int p_id, int p_x, int p_y, double p_delta, double p_alpha) {
	const int li = _layer_index(p_id);
	if (li < 0 || p_x < 0 || p_y < 0 || p_x >= width || p_y >= height) {
		return false;
	}
	EditLayer &l = layers.write[li];
	l.delta.set(p_y * width + p_x, (float)p_delta);
	l.alpha.set(p_y * width + p_x, (float)p_alpha);
	const Rect2i r(p_x, p_y, 1, 1);
	_grow_bounds(l, r);
	_mark_rect_dirty(r);
	return true;
}

PackedFloat32Array CgameTerrainEditLayers::get_layer_region_deltas(int p_id, const Rect2i &p_rect) const {
	const int li = _layer_index(p_id);
	const Rect2i r = p_rect.intersection(_map_rect());
	if (li < 0 || r.size.x <= 0 || r.size.y <= 0) {
		return PackedFloat32Array();
	}
	return _read_rect(layers[li].delta, r, 1);
}

PackedFloat32Array CgameTerrainEditLayers::get_layer_region_alphas(int p_id, const Rect2i &p_rect) const {
	const int li = _layer_index(p_id);
	const Rect2i r = p_rect.intersection(_map_rect());
	if (li < 0 || r.size.x <= 0 || r.size.y <= 0) {
		return PackedFloat32Array();
	}
	return _read_rect(layers[li].alpha, r, 1);
}

// Bulk write of delta/alpha for a rect (row-major, p_rect.size.x per row). The rect must lie inside
// the map and the arrays must hold exactly size.x * size.y values. Not on the undo stack.
bool CgameTerrainEditLayers::write_layer_region(int p_id, const Rect2i &p_rect, const PackedFloat32Array &p_delta, const PackedFloat32Array &p_alpha) {
	const int li = _layer_index(p_id);
	if (li < 0 || p_rect.size.x <= 0 || p_rect.size.y <= 0 || !_map_rect().encloses(p_rect)) {
		return false;
	}
	const int64_t count = (int64_t)p_rect.size.x * p_rect.size.y;
	if ((int64_t)p_delta.size() != count || (int64_t)p_alpha.size() != count) {
		return false;
	}
	EditLayer &l = layers.write[li];
	_write_rect(l.delta, p_rect, 1, p_delta);
	_write_rect(l.alpha, p_rect, 1, p_alpha);
	_grow_bounds(l, p_rect);
	_mark_rect_dirty(p_rect);
	return true;
}

// Writes delta/alpha into the whole rect of a layer (undoable).
void CgameTerrainEditLayers::fill_layer_rect(int p_id, const Rect2i &p_rect, double p_delta, double p_alpha) {
	const int li = _layer_index(p_id);
	const Rect2i r = p_rect.intersection(_map_rect());
	if (li < 0 || r.size.x <= 0 || r.size.y <= 0) {
		return;
	}
	_push_undo(_snapshot_height(layers[li], r));
	EditLayer &l = layers.write[li];
	float *d = l.delta.ptrw();
	float *a = l.alpha.ptrw();
	for (int y = r.position.y; y < r.position.y + r.size.y; y++) {
		for (int x = r.position.x; x < r.position.x + r.size.x; x++) {
			d[y * width + x] = (float)p_delta;
			a[y * width + x] = (float)p_alpha;
		}
	}
	_grow_bounds(l, r);
	_mark_rect_dirty(r);
}

// ---------------------------------------------------------------- compositing

double CgameTerrainEditLayers::_blend_texel(double p_h, double p_b, const EditLayer &p_layer, int p_i) const {
	const double d = p_layer.delta[p_i];
	switch (p_layer.blend) {
		case BLEND_ADD:
			return p_h + d * p_layer.opacity;
		case BLEND_MAX:
			return Math::lerp(p_h, MAX(p_h, p_b + d), p_layer.opacity);
		default:
			return Math::lerp(p_h, p_b + d, (double)p_layer.alpha[p_i] * p_layer.opacity);
	}
}

double CgameTerrainEditLayers::composite_height(int p_x, int p_y) const {
	if (width <= 0) {
		return 0.0;
	}
	const int cx = CLAMP(p_x, 0, width - 1);
	const int cy = CLAMP(p_y, 0, height - 1);
	const int i = cy * width + cx;
	const double b = base[i];
	double h = b;
	for (int k = 0; k < layers.size(); k++) {
		const EditLayer &l = layers[k];
		if (l.visible && l.opacity > 0.0) {
			h = _blend_texel(h, b, l, i);
		}
	}
	return h;
}

// Composite heights for p_rect (clipped to the map), row-major, rect.size.x per row.
PackedFloat32Array CgameTerrainEditLayers::composite_region(const Rect2i &p_rect) const {
	const Rect2i r = p_rect.intersection(_map_rect());
	PackedFloat32Array out;
	if (r.size.x <= 0 || r.size.y <= 0) {
		return out;
	}
	out.resize((int64_t)r.size.x * r.size.y);
	float *dst = out.ptrw();
	const float *src = base.ptr();
	const bool threaded = (int64_t)r.size.x * r.size.y * MAX(1, (int)layers.size()) >= CgameWorldgen::PARALLEL_CELL_THRESHOLD;
	CgameWorldgen::parallel_for(r.size.y, threaded, [&](int row) {
		const int y = r.position.y + row;
		for (int col = 0; col < r.size.x; col++) {
			const int i = y * width + r.position.x + col;
			const double b = src[i];
			double h = b;
			for (int k = 0; k < layers.size(); k++) {
				const EditLayer &l = layers[k];
				if (l.visible && l.opacity > 0.0) {
					h = _blend_texel(h, b, l, i);
				}
			}
			dst[row * r.size.x + col] = (float)h;
		}
	});
	return out;
}

// ---------------------------------------------------------------- brushes

double CgameTerrainEditLayers::_falloff(double p_t, int p_kind, const Ref<Curve> &p_curve) {
	const double u = CLAMP(p_t, 0.0, 1.0);
	if (p_curve.is_valid()) {
		return CLAMP((double)p_curve->sample((real_t)u), 0.0, 1.0);
	}
	switch (p_kind) {
		case FALLOFF_LINEAR:
			return u;
		case FALLOFF_SPHERE:
			return Math::sqrt(MAX(0.0, 1.0 - (1.0 - u) * (1.0 - u)));
		case FALLOFF_CONSTANT:
			return 1.0;
		default:
			return u * u * (3.0 - 2.0 * u);
	}
}

Rect2i CgameTerrainEditLayers::_brush_rect(const Vector2 &p_center, double p_radius) const {
	const int x0 = MAX(0, (int)Math::floor((double)p_center.x - p_radius));
	const int y0 = MAX(0, (int)Math::floor((double)p_center.y - p_radius));
	const int x1 = MIN(width - 1, (int)Math::ceil((double)p_center.x + p_radius));
	const int y1 = MIN(height - 1, (int)Math::ceil((double)p_center.y + p_radius));
	if (x1 < x0 || y1 < y0) {
		return Rect2i();
	}
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
}

double CgameTerrainEditLayers::_hash_noise(int p_x, int p_y, int64_t p_seed) {
	// 64-bit wrapping arithmetic with arithmetic shifts, matching the reference script.
	uint64_t n = (uint64_t)(int64_t)p_x * 374761393ULL + (uint64_t)(int64_t)p_y * 668265263ULL + (uint64_t)p_seed * 1442695041ULL;
	int64_t s = (int64_t)n;
	n = (uint64_t)(s ^ (s >> 13)) * 1274126177ULL;
	s = (int64_t)n;
	s = s ^ (s >> 16);
	return (double)(s & 0xffff) / 32767.5 - 1.0;
}

// Applies a height brush to one edit layer. Returns the changed rect (empty if none).
// p_target_height is used by BRUSH_FLATTEN; p_seed_value by BRUSH_NOISE.
Rect2i CgameTerrainEditLayers::apply_brush(int p_layer_id, Brush p_brush, const Vector2 &p_center, double p_radius, double p_strength, Falloff p_falloff, double p_target_height, int64_t p_seed_value, const Ref<Curve> &p_curve) {
	const int li = _layer_index(p_layer_id);
	if (li < 0 || p_radius <= 0.0) {
		return Rect2i();
	}
	const Rect2i rect = _brush_rect(p_center, p_radius);
	if (rect.size.x <= 0) {
		return Rect2i();
	}
	const Rect2i region = rect.grow(1).intersection(_map_rect());
	const PackedFloat32Array src_arr = composite_region(region);
	const float *src = src_arr.ptr();
	const int rw = region.size.x;
	const int rx0 = region.position.x;
	const int ry0 = region.position.y;
	const int rx1 = region.position.x + region.size.x - 1;
	const int ry1 = region.position.y + region.size.y - 1;
	const UndoEntry entry = _snapshot_height(layers[li], rect);
	EditLayer &l = layers.write[li];
	const double inv_opacity = l.blend == BLEND_ADD ? 1.0 / MAX(l.opacity, 0.01) : 1.0;
	bool changed = false;
	float *delta = l.delta.ptrw();
	float *alpha = l.alpha.ptrw();
	for (int y = rect.position.y; y < rect.position.y + rect.size.y; y++) {
		for (int x = rect.position.x; x < rect.position.x + rect.size.x; x++) {
			const double dist = Vector2((real_t)x, (real_t)y).distance_to(p_center);
			if (dist > p_radius) {
				continue;
			}
			const double w = _falloff(1.0 - dist / p_radius, p_falloff, p_curve);
			if (w <= 0.0) {
				continue;
			}
			const double h = src[(y - ry0) * rw + (x - rx0)];
			double goal = h;
			switch (p_brush) {
				case BRUSH_RAISE: {
					goal = h + p_strength * w;
				} break;
				case BRUSH_LOWER: {
					goal = h - p_strength * w;
				} break;
				case BRUSH_SMOOTH: {
					double sum = 0.0;
					for (int oy = -1; oy <= 1; oy++) {
						for (int ox = -1; ox <= 1; ox++) {
							const int sx = CLAMP(x + ox, rx0, rx1);
							const int sy = CLAMP(y + oy, ry0, ry1);
							sum += src[(sy - ry0) * rw + (sx - rx0)];
						}
					}
					goal = Math::lerp(h, sum / 9.0, CLAMP(p_strength * w, 0.0, 1.0));
				} break;
				case BRUSH_FLATTEN: {
					goal = Math::lerp(h, p_target_height, CLAMP(p_strength * w, 0.0, 1.0));
				} break;
				case BRUSH_NOISE: {
					goal = h + _hash_noise(x, y, p_seed_value) * p_strength * w;
				} break;
				case BRUSH_ERODE: {
					double lowest = h;
					for (int oy = -1; oy <= 1; oy++) {
						for (int ox = -1; ox <= 1; ox++) {
							const int sx = CLAMP(x + ox, rx0, rx1);
							const int sy = CLAMP(y + oy, ry0, ry1);
							lowest = MIN(lowest, (double)src[(sy - ry0) * rw + (sx - rx0)]);
						}
					}
					goal = h - MIN((h - lowest) * 0.5, p_strength * w);
				} break;
			}
			const double dh = goal - h;
			if (Math::is_zero_approx(dh)) {
				continue;
			}
			const int i = y * width + x;
			delta[i] += dh * inv_opacity;
			alpha[i] = MAX((double)alpha[i], CLAMP(w, 0.0, 1.0));
			changed = true;
		}
	}
	if (!changed) {
		return Rect2i();
	}
	_push_undo(entry);
	_grow_bounds(l, rect);
	_mark_rect_dirty(rect);
	return rect;
}

// ---------------------------------------------------------------- splat (material weights)

// Creates p_count material layers per texel; layer 0 starts at weight 1.
void CgameTerrainEditLayers::setup_splat(int p_count) {
	ERR_FAIL_COND_MSG(width <= 0, "CgameTerrainEditLayers: call setup() before setup_splat().");
	splat_count_value = MAX(1, p_count);
	splat.clear();
	splat.resize((int64_t)width * height * splat_count_value);
	splat.fill(0.0f);
	float *s = splat.ptrw();
	for (int64_t i = 0; i < (int64_t)width * height; i++) {
		s[i * splat_count_value] = 1.0f;
	}
	_mark_rect_dirty(Rect2i(0, 0, width, height));
}

PackedFloat32Array CgameTerrainEditLayers::splat_weights(int p_x, int p_y) const {
	PackedFloat32Array out;
	if (splat_count_value == 0) {
		return out;
	}
	const int64_t i = ((int64_t)CLAMP(p_y, 0, height - 1) * width + CLAMP(p_x, 0, width - 1)) * splat_count_value;
	out.resize(splat_count_value);
	for (int k = 0; k < splat_count_value; k++) {
		out.set(k, splat[i + k]);
	}
	return out;
}

// Paints material p_material with the brush; other weights shrink so the sum stays 1.
Rect2i CgameTerrainEditLayers::paint_splat(int p_material, const Vector2 &p_center, double p_radius, double p_strength, Falloff p_falloff, const Ref<Curve> &p_curve) {
	if (splat_count_value == 0 || p_material < 0 || p_material >= splat_count_value || p_radius <= 0.0) {
		return Rect2i();
	}
	const Rect2i rect = _brush_rect(p_center, p_radius);
	if (rect.size.x <= 0) {
		return Rect2i();
	}
	UndoEntry entry;
	entry.kind = UNDO_SPLAT;
	entry.rect = rect;
	entry.data = _read_rect(splat, rect, splat_count_value);
	bool changed = false;
	float *s = splat.ptrw();
	for (int y = rect.position.y; y < rect.position.y + rect.size.y; y++) {
		for (int x = rect.position.x; x < rect.position.x + rect.size.x; x++) {
			const double dist = Vector2((real_t)x, (real_t)y).distance_to(p_center);
			if (dist > p_radius) {
				continue;
			}
			const double a = CLAMP(_falloff(1.0 - dist / p_radius, p_falloff, p_curve) * p_strength, 0.0, 1.0);
			if (a <= 0.0) {
				continue;
			}
			const int64_t b = ((int64_t)y * width + x) * splat_count_value;
			const double old_t = s[b + p_material];
			const double new_t = MIN(1.0, old_t + a);
			const double others = 1.0 - old_t;
			double scale = 0.0;
			if (others > 0.00001) {
				scale = (1.0 - new_t) / others;
			}
			for (int k = 0; k < splat_count_value; k++) {
				if (k == p_material) {
					s[b + k] = others > 0.00001 ? new_t : 1.0;
				} else {
					s[b + k] = (double)s[b + k] * scale;
				}
			}
			changed = true;
		}
	}
	if (!changed) {
		return Rect2i();
	}
	_push_undo(entry);
	_mark_rect_dirty(rect);
	return rect;
}

// ---------------------------------------------------------------- undo / redo

PackedFloat32Array CgameTerrainEditLayers::_read_rect(const PackedFloat32Array &p_arr, const Rect2i &p_rect, int p_stride) const {
	PackedFloat32Array out;
	const int row = p_rect.size.x * p_stride;
	out.resize((int64_t)row * p_rect.size.y);
	float *dst = out.ptrw();
	const float *src = p_arr.ptr();
	int64_t k = 0;
	for (int y = p_rect.position.y; y < p_rect.position.y + p_rect.size.y; y++) {
		const int64_t s = ((int64_t)y * width + p_rect.position.x) * p_stride;
		for (int j = 0; j < row; j++) {
			dst[k++] = src[s + j];
		}
	}
	return out;
}

void CgameTerrainEditLayers::_write_rect(PackedFloat32Array &r_arr, const Rect2i &p_rect, int p_stride, const PackedFloat32Array &p_data) const {
	const int row = p_rect.size.x * p_stride;
	float *dst = r_arr.ptrw();
	const float *src = p_data.ptr();
	int64_t k = 0;
	for (int y = p_rect.position.y; y < p_rect.position.y + p_rect.size.y; y++) {
		const int64_t s = ((int64_t)y * width + p_rect.position.x) * p_stride;
		for (int j = 0; j < row; j++) {
			dst[s + j] = src[k++];
		}
	}
}

CgameTerrainEditLayers::UndoEntry CgameTerrainEditLayers::_snapshot_height(const EditLayer &p_layer, const Rect2i &p_rect) const {
	UndoEntry e;
	e.kind = UNDO_HEIGHT;
	e.layer_id = p_layer.id;
	e.rect = p_rect;
	e.data = _read_rect(p_layer.delta, p_rect, 1);
	e.data2 = _read_rect(p_layer.alpha, p_rect, 1);
	return e;
}

void CgameTerrainEditLayers::_push_undo(const UndoEntry &p_entry) {
	undo_stack.push_back(p_entry);
	redo_stack.clear();
	_trim_history();
}

int64_t CgameTerrainEditLayers::undo_bytes() const {
	int64_t total = 0;
	for (int i = 0; i < undo_stack.size(); i++) {
		total += undo_stack[i].bytes();
	}
	for (int i = 0; i < redo_stack.size(); i++) {
		total += redo_stack[i].bytes();
	}
	return total;
}

void CgameTerrainEditLayers::_trim_history() {
	while (undo_bytes() > max_undo_bytes && (undo_stack.size() + redo_stack.size()) > 1) {
		if (!redo_stack.is_empty()) {
			redo_stack.remove_at(0);
		} else {
			undo_stack.remove_at(0);
		}
	}
}

// Swaps the entry's stored data with the live data, so the same routine serves undo and redo.
bool CgameTerrainEditLayers::_swap_entry(UndoEntry &r_entry) {
	if (r_entry.kind == UNDO_HEIGHT) {
		const int li = _layer_index(r_entry.layer_id);
		if (li < 0) {
			return false;
		}
		EditLayer &l = layers.write[li];
		const PackedFloat32Array cur_d = _read_rect(l.delta, r_entry.rect, 1);
		const PackedFloat32Array cur_a = _read_rect(l.alpha, r_entry.rect, 1);
		_write_rect(l.delta, r_entry.rect, 1, r_entry.data);
		_write_rect(l.alpha, r_entry.rect, 1, r_entry.data2);
		r_entry.data = cur_d;
		r_entry.data2 = cur_a;
	} else {
		const PackedFloat32Array cur = _read_rect(splat, r_entry.rect, splat_count_value);
		_write_rect(splat, r_entry.rect, splat_count_value, r_entry.data);
		r_entry.data = cur;
	}
	_mark_rect_dirty(r_entry.rect);
	return true;
}

bool CgameTerrainEditLayers::undo() {
	while (!undo_stack.is_empty()) {
		UndoEntry e = undo_stack[undo_stack.size() - 1];
		undo_stack.resize(undo_stack.size() - 1);
		if (_swap_entry(e)) {
			redo_stack.push_back(e);
			return true;
		}
	}
	return false;
}

bool CgameTerrainEditLayers::redo() {
	while (!redo_stack.is_empty()) {
		UndoEntry e = redo_stack[redo_stack.size() - 1];
		redo_stack.resize(redo_stack.size() - 1);
		if (_swap_entry(e)) {
			undo_stack.push_back(e);
			return true;
		}
	}
	return false;
}

// ---------------------------------------------------------------- dirty tracking / collision queue

// Marks every chunk whose export (including its 1-texel border) sees a texel in p_rect.
void CgameTerrainEditLayers::_mark_rect_dirty(const Rect2i &p_rect) {
	if (p_rect.size.x <= 0 || p_rect.size.y <= 0) {
		return;
	}
	const double cs = chunk_size;
	const int c0x = MAX(0, (int)Math::ceil((double)(p_rect.position.x - 1) / cs) - 1);
	const int c0z = MAX(0, (int)Math::ceil((double)(p_rect.position.y - 1) / cs) - 1);
	const int c1x = MIN(chunks_x - 1, (int)Math::floor((double)(p_rect.position.x + p_rect.size.x) / cs));
	const int c1z = MIN(chunks_z - 1, (int)Math::floor((double)(p_rect.position.y + p_rect.size.y) / cs));
	for (int cz = c0z; cz <= c1z; cz++) {
		for (int cx = c0x; cx <= c1x; cx++) {
			const Vector2i c(cx, cz);
			dirty.insert(c);
			if (!collision_pending.has(c)) {
				collision_pending.insert(c);
				collision_queue.push_back(c);
			}
		}
	}
}

// Chunks touched since the previous call (sorted by z then x); clears the set.
TypedArray<Vector2i> CgameTerrainEditLayers::take_dirty_chunks() {
	Vector<Vector2i> list;
	for (const Vector2i &c : dirty) {
		list.push_back(c);
	}
	list.sort_custom<Vector2iLess>();
	dirty.clear();
	TypedArray<Vector2i> out;
	for (const Vector2i &c : list) {
		out.push_back(c);
	}
	return out;
}

// Pops up to p_max_per_frame distinct chunks needing a collision rebuild (oldest first).
TypedArray<Vector2i> CgameTerrainEditLayers::collision_jobs(int p_max_per_frame) {
	TypedArray<Vector2i> out;
	const int n = MIN(MAX(0, p_max_per_frame), (int)collision_queue.size());
	for (int i = 0; i < n; i++) {
		const Vector2i c = collision_queue[i];
		collision_pending.erase(c);
		out.push_back(c);
	}
	Vector<Vector2i> rest;
	for (int i = n; i < collision_queue.size(); i++) {
		rest.push_back(collision_queue[i]);
	}
	collision_queue = rest;
	return out;
}

// ---------------------------------------------------------------- chunk export / mesh

bool CgameTerrainEditLayers::_valid_chunk(const Vector2i &p_chunk) const {
	return p_chunk.x >= 0 && p_chunk.y >= 0 && p_chunk.x < chunks_x && p_chunk.y < chunks_z;
}

// Heights for a chunk with a 1-texel border: (chunk_size + 3)^2 values, row-major.
// Index (i, j) is texel (cx*cs - 1 + i, cz*cs - 1 + j); out-of-map texels clamp to the edge.
PackedFloat32Array CgameTerrainEditLayers::export_chunk_heights(const Vector2i &p_chunk) const {
	PackedFloat32Array out;
	if (!_valid_chunk(p_chunk)) {
		return out;
	}
	const int side = chunk_size + 3;
	const int ox = p_chunk.x * chunk_size - 1;
	const int oz = p_chunk.y * chunk_size - 1;
	const Rect2i region = Rect2i(ox, oz, side, side).intersection(_map_rect());
	const PackedFloat32Array src = composite_region(region);
	out.resize((int64_t)side * side);
	float *dst = out.ptrw();
	for (int j = 0; j < side; j++) {
		const int sy = CLAMP(oz + j, region.position.y, region.position.y + region.size.y - 1) - region.position.y;
		for (int i = 0; i < side; i++) {
			const int sx = CLAMP(ox + i, region.position.x, region.position.x + region.size.x - 1) - region.position.x;
			dst[j * side + i] = src[sy * region.size.x + sx];
		}
	}
	return out;
}

// Builds the chunk's mesh in chunk-local space (origin at the chunk's min corner).
// Normals use the exported border so lighting is continuous across seams.
// ARRAY_COLOR carries the first four splat weights (when splat is set up).
Ref<ArrayMesh> CgameTerrainEditLayers::build_chunk_mesh(const Vector2i &p_chunk, double p_cell_size) const {
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	if (!_valid_chunk(p_chunk)) {
		return mesh;
	}
	const PackedFloat32Array hs = export_chunk_heights(p_chunk);
	const int side = chunk_size + 3;
	const int nx = MIN(chunk_size, width - 1 - p_chunk.x * chunk_size);
	const int nz = MIN(chunk_size, height - 1 - p_chunk.y * chunk_size);
	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedVector2Array uvs;
	PackedColorArray colors;
	for (int j = 0; j < nz + 1; j++) {
		for (int i = 0; i < nx + 1; i++) {
			const int hx = i + 1;
			const int hz = j + 1;
			const double h = hs[hz * side + hx];
			const double hl = hs[hz * side + hx - 1];
			const double hr = hs[hz * side + hx + 1];
			const double hd = hs[(hz - 1) * side + hx];
			const double hu = hs[(hz + 1) * side + hx];
			verts.push_back(Vector3((real_t)(i * p_cell_size), (real_t)h, (real_t)(j * p_cell_size)));
			normals.push_back(Vector3((real_t)(hl - hr), (real_t)(2.0 * p_cell_size), (real_t)(hd - hu)).normalized());
			const int tx = p_chunk.x * chunk_size + i;
			const int tz = p_chunk.y * chunk_size + j;
			uvs.push_back(Vector2((real_t)tx / (real_t)(width - 1), (real_t)tz / (real_t)(height - 1)));
			if (splat_count_value > 0) {
				const PackedFloat32Array w = splat_weights(tx, tz);
				colors.push_back(Color(w[0], splat_count_value > 1 ? w[1] : 0.0f, splat_count_value > 2 ? w[2] : 0.0f, splat_count_value > 3 ? w[3] : 0.0f));
			}
		}
	}
	PackedInt32Array indices;
	for (int j = 0; j < nz; j++) {
		for (int i = 0; i < nx; i++) {
			const int a = j * (nx + 1) + i;
			const int b = a + 1;
			const int c = a + nx + 1;
			const int d = c + 1;
			const int tri[6] = { a, b, c, b, d, c };
			for (int k = 0; k < 6; k++) {
				indices.push_back(tri[k]);
			}
		}
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = verts;
	arrays[Mesh::ARRAY_NORMAL] = normals;
	arrays[Mesh::ARRAY_TEX_UV] = uvs;
	if (!colors.is_empty()) {
		arrays[Mesh::ARRAY_COLOR] = colors;
	}
	arrays[Mesh::ARRAY_INDEX] = indices;
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
}

// ---------------------------------------------------------------- bindings

void CgameTerrainEditLayers::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "width", "height", "chunk_size", "base_heights"), &CgameTerrainEditLayers::setup);
	ClassDB::bind_method(D_METHOD("get_width"), &CgameTerrainEditLayers::get_width);
	ClassDB::bind_method(D_METHOD("get_height"), &CgameTerrainEditLayers::get_height);
	ClassDB::bind_method(D_METHOD("get_chunk_size"), &CgameTerrainEditLayers::get_chunk_size);
	ClassDB::bind_method(D_METHOD("get_chunks_x"), &CgameTerrainEditLayers::get_chunks_x);
	ClassDB::bind_method(D_METHOD("get_chunks_z"), &CgameTerrainEditLayers::get_chunks_z);
	ClassDB::bind_method(D_METHOD("chunk_count"), &CgameTerrainEditLayers::chunk_count);
	ClassDB::bind_method(D_METHOD("set_max_undo_bytes", "bytes"), &CgameTerrainEditLayers::set_max_undo_bytes);
	ClassDB::bind_method(D_METHOD("get_max_undo_bytes"), &CgameTerrainEditLayers::get_max_undo_bytes);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_undo_bytes", PROPERTY_HINT_RANGE, "0,1073741824,1,or_greater"), "set_max_undo_bytes", "get_max_undo_bytes");

	ClassDB::bind_method(D_METHOD("add_layer", "name", "blend", "opacity"), &CgameTerrainEditLayers::add_layer, DEFVAL(BLEND_ADD), DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("add_layer_from_region", "name", "rect", "delta", "alpha", "blend", "opacity"), &CgameTerrainEditLayers::add_layer_from_region, DEFVAL(BLEND_ADD), DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("remove_layer", "id"), &CgameTerrainEditLayers::remove_layer);
	ClassDB::bind_method(D_METHOD("move_layer", "id", "to_index"), &CgameTerrainEditLayers::move_layer);
	ClassDB::bind_method(D_METHOD("set_layer_visible", "id", "visible"), &CgameTerrainEditLayers::set_layer_visible);
	ClassDB::bind_method(D_METHOD("is_layer_visible", "id"), &CgameTerrainEditLayers::is_layer_visible);
	ClassDB::bind_method(D_METHOD("set_layer_opacity", "id", "opacity"), &CgameTerrainEditLayers::set_layer_opacity);
	ClassDB::bind_method(D_METHOD("get_layer_opacity", "id"), &CgameTerrainEditLayers::get_layer_opacity);
	ClassDB::bind_method(D_METHOD("set_layer_blend", "id", "blend"), &CgameTerrainEditLayers::set_layer_blend);
	ClassDB::bind_method(D_METHOD("get_layer_blend", "id"), &CgameTerrainEditLayers::get_layer_blend);
	ClassDB::bind_method(D_METHOD("set_layer_name", "id", "name"), &CgameTerrainEditLayers::set_layer_name);
	ClassDB::bind_method(D_METHOD("get_layer_name", "id"), &CgameTerrainEditLayers::get_layer_name);
	ClassDB::bind_method(D_METHOD("layer_count"), &CgameTerrainEditLayers::layer_count);
	ClassDB::bind_method(D_METHOD("layer_ids"), &CgameTerrainEditLayers::layer_ids);
	ClassDB::bind_method(D_METHOD("has_layer", "id"), &CgameTerrainEditLayers::has_layer);
	ClassDB::bind_method(D_METHOD("get_layer_bounds", "id"), &CgameTerrainEditLayers::get_layer_bounds);

	ClassDB::bind_method(D_METHOD("layer_delta_at", "id", "x", "y"), &CgameTerrainEditLayers::layer_delta_at);
	ClassDB::bind_method(D_METHOD("layer_alpha_at", "id", "x", "y"), &CgameTerrainEditLayers::layer_alpha_at);
	ClassDB::bind_method(D_METHOD("set_layer_texel", "id", "x", "y", "delta", "alpha"), &CgameTerrainEditLayers::set_layer_texel, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("get_layer_region_deltas", "id", "rect"), &CgameTerrainEditLayers::get_layer_region_deltas);
	ClassDB::bind_method(D_METHOD("get_layer_region_alphas", "id", "rect"), &CgameTerrainEditLayers::get_layer_region_alphas);
	ClassDB::bind_method(D_METHOD("write_layer_region", "id", "rect", "delta", "alpha"), &CgameTerrainEditLayers::write_layer_region);
	ClassDB::bind_method(D_METHOD("fill_layer_rect", "id", "rect", "delta", "alpha"), &CgameTerrainEditLayers::fill_layer_rect, DEFVAL(1.0));

	ClassDB::bind_method(D_METHOD("composite_height", "x", "y"), &CgameTerrainEditLayers::composite_height);
	ClassDB::bind_method(D_METHOD("composite_region", "rect"), &CgameTerrainEditLayers::composite_region);

	ClassDB::bind_method(D_METHOD("apply_brush", "layer_id", "brush", "center", "radius", "strength", "falloff", "target_height", "seed_value", "curve"), &CgameTerrainEditLayers::apply_brush, DEFVAL(FALLOFF_SMOOTH), DEFVAL(0.0), DEFVAL(0), DEFVAL(Ref<Curve>()));

	ClassDB::bind_method(D_METHOD("setup_splat", "count"), &CgameTerrainEditLayers::setup_splat);
	ClassDB::bind_method(D_METHOD("splat_count"), &CgameTerrainEditLayers::splat_count);
	ClassDB::bind_method(D_METHOD("splat_weights", "x", "y"), &CgameTerrainEditLayers::splat_weights);
	ClassDB::bind_method(D_METHOD("paint_splat", "material", "center", "radius", "strength", "falloff", "curve"), &CgameTerrainEditLayers::paint_splat, DEFVAL(FALLOFF_SMOOTH), DEFVAL(Ref<Curve>()));

	ClassDB::bind_method(D_METHOD("undo_bytes"), &CgameTerrainEditLayers::undo_bytes);
	ClassDB::bind_method(D_METHOD("undo_depth"), &CgameTerrainEditLayers::undo_depth);
	ClassDB::bind_method(D_METHOD("can_undo"), &CgameTerrainEditLayers::can_undo);
	ClassDB::bind_method(D_METHOD("can_redo"), &CgameTerrainEditLayers::can_redo);
	ClassDB::bind_method(D_METHOD("undo"), &CgameTerrainEditLayers::undo);
	ClassDB::bind_method(D_METHOD("redo"), &CgameTerrainEditLayers::redo);

	ClassDB::bind_method(D_METHOD("take_dirty_chunks"), &CgameTerrainEditLayers::take_dirty_chunks);
	ClassDB::bind_method(D_METHOD("collision_jobs", "max_per_frame"), &CgameTerrainEditLayers::collision_jobs);
	ClassDB::bind_method(D_METHOD("pending_collision_count"), &CgameTerrainEditLayers::pending_collision_count);

	ClassDB::bind_method(D_METHOD("export_chunk_heights", "chunk"), &CgameTerrainEditLayers::export_chunk_heights);
	ClassDB::bind_method(D_METHOD("build_chunk_mesh", "chunk", "cell_size"), &CgameTerrainEditLayers::build_chunk_mesh);

	BIND_ENUM_CONSTANT(BLEND_ADD);
	BIND_ENUM_CONSTANT(BLEND_MAX);
	BIND_ENUM_CONSTANT(BLEND_REPLACE);
	BIND_ENUM_CONSTANT(BRUSH_RAISE);
	BIND_ENUM_CONSTANT(BRUSH_LOWER);
	BIND_ENUM_CONSTANT(BRUSH_SMOOTH);
	BIND_ENUM_CONSTANT(BRUSH_FLATTEN);
	BIND_ENUM_CONSTANT(BRUSH_NOISE);
	BIND_ENUM_CONSTANT(BRUSH_ERODE);
	BIND_ENUM_CONSTANT(FALLOFF_LINEAR);
	BIND_ENUM_CONSTANT(FALLOFF_SMOOTH);
	BIND_ENUM_CONSTANT(FALLOFF_SPHERE);
	BIND_ENUM_CONSTANT(FALLOFF_CONSTANT);
}
