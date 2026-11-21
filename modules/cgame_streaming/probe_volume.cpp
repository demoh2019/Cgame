/**************************************************************************/
/*  probe_volume.cpp                                                      */
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

#include "probe_volume.h"

#include "core/io/marshalls.h"
#include "core/math/random_pcg.h"
#include "core/object/class_db.h"

void ProbeVolume::set_bounds(const AABB &p_bounds) {
	bounds = p_bounds;
}

AABB ProbeVolume::get_bounds() const {
	return bounds;
}

void ProbeVolume::set_base_spacing(real_t p_spacing) {
	base_spacing = MAX(p_spacing, (real_t)0.01);
}

real_t ProbeVolume::get_base_spacing() const {
	return base_spacing;
}

void ProbeVolume::set_hysteresis(real_t p_value) {
	hysteresis = CLAMP(p_value, (real_t)0.0, (real_t)1.0);
}

real_t ProbeVolume::get_hysteresis() const {
	return hysteresis;
}

void ProbeVolume::set_min_hit_distance(real_t p_value) {
	min_hit_distance = p_value;
}

real_t ProbeVolume::get_min_hit_distance() const {
	return min_hit_distance;
}

void ProbeVolume::set_invalid_fraction(real_t p_value) {
	invalid_fraction = p_value;
}

real_t ProbeVolume::get_invalid_fraction() const {
	return invalid_fraction;
}

void ProbeVolume::set_sky_top(const Color &p_color) {
	sky_top = p_color;
	sky_sh_valid = false;
}

Color ProbeVolume::get_sky_top() const {
	return sky_top;
}

void ProbeVolume::set_sky_bottom(const Color &p_color) {
	sky_bottom = p_color;
	sky_sh_valid = false;
}

Color ProbeVolume::get_sky_bottom() const {
	return sky_bottom;
}

void ProbeVolume::set_memory_budget_bytes(int64_t p_bytes) {
	memory_budget_bytes = MAX(p_bytes, (int64_t)0);
}

int64_t ProbeVolume::get_memory_budget_bytes() const {
	return memory_budget_bytes;
}

void ProbeVolume::clear_internal() {
	positions.clear();
	sh.clear();
	sh_loaded.clear();
	valid.clear();
	probe_cell.clear();
	index_of.clear();
	leaf_start.clear();
	leaf_level.clear();
	leaves.clear();
	leaf_count = 0;
	cell_probes.clear();
	resident.clear();
	store.clear();
	cursor = 0;
	sky_sh_valid = false;
}

void ProbeVolume::clear() {
	clear_internal();
}

int ProbeVolume::probe_count() const {
	return positions.size();
}

Vector3 ProbeVolume::probe_position(int p_i) const {
	ERR_FAIL_INDEX_V(p_i, positions.size(), Vector3());
	return positions[p_i];
}

PackedColorArray ProbeVolume::probe_sh(int p_i) const {
	ERR_FAIL_INDEX_V(p_i, positions.size(), PackedColorArray());
	if (!sh_loaded[p_i]) {
		return PackedColorArray();
	}
	return SHLighting::to_array(sh[p_i]);
}

bool ProbeVolume::is_probe_valid(int p_i) const {
	ERR_FAIL_INDEX_V(p_i, positions.size(), false);
	return valid[p_i] != 0;
}

int ProbeVolume::find_probe(const Vector3 &p_pos) const {
	HashMap<Vector3i, int, Vec3iHasher>::ConstIterator it = index_of.find(_key_of(p_pos));
	return it ? it->value : -1;
}

Color ProbeVolume::sky(const Vector3 &p_dir) const {
	return sky_bottom.lerp(sky_top, CLAMP(p_dir.y * 0.5f + 0.5f, 0.0f, 1.0f));
}

Vector3i ProbeVolume::_key_of(const Vector3 &p_pos) const {
	Vector3 rel = p_pos - bounds.position;
	return Vector3i((int32_t)Math::round(rel.x / unit), (int32_t)Math::round(rel.y / unit), (int32_t)Math::round(rel.z / unit));
}

Vector3i ProbeVolume::_cell_of_base(const Vector3i &p_bc) {
	return Vector3i(
			(int32_t)Math::floor((double)p_bc.x / (double)CELL_SPAN),
			(int32_t)Math::floor((double)p_bc.y / (double)CELL_SPAN),
			(int32_t)Math::floor((double)p_bc.z / (double)CELL_SPAN));
}

Vector3i ProbeVolume::_base_coord(const Vector3 &p_pos) const {
	Vector3 rel = (p_pos - bounds.position) / base_spacing;
	Vector3i bc((int32_t)Math::floor(rel.x), (int32_t)Math::floor(rel.y), (int32_t)Math::floor(rel.z));
	return Vector3i(CLAMP(bc.x, 0, counts.x - 1), CLAMP(bc.y, 0, counts.y - 1), CLAMP(bc.z, 0, counts.z - 1));
}

Vector3i ProbeVolume::cell_of_position(const Vector3 &p_pos) const {
	return _cell_of_base(_base_coord(p_pos));
}

int ProbeVolume::_probe_at(const Vector3 &p_pos) {
	Vector3i key = _key_of(p_pos);
	HashMap<Vector3i, int, Vec3iHasher>::Iterator it = index_of.find(key);
	if (it) {
		return it->value;
	}
	int idx = positions.size();
	index_of[key] = idx;
	positions.push_back(p_pos);
	sh.push_back(SHLighting::Coeffs());
	sh_loaded.push_back(1);
	valid.push_back(1);
	Vector3i cell = cell_of_position(p_pos);
	probe_cell.push_back(cell);
	cell_probes[cell].push_back(idx);
	resident[cell] = 0;
	return idx;
}

int ProbeVolume::build(const AABB &p_bounds, real_t p_base_spacing, const Callable &p_density_at) {
	clear_internal();
	bounds = p_bounds;
	base_spacing = MAX(p_base_spacing, (real_t)0.01);
	counts = Vector3i(
			MAX(1, (int)Math::ceil(bounds.size.x / base_spacing)),
			MAX(1, (int)Math::ceil(bounds.size.y / base_spacing)),
			MAX(1, (int)Math::ceil(bounds.size.z / base_spacing)));
	unit = base_spacing / (real_t)(1 << MAX_LEVEL);
	leaf_start.resize(counts.x * counts.y * counts.z);
	leaf_level.resize(counts.x * counts.y * counts.z);
	for (int cz = 0; cz < counts.z; cz++) {
		for (int cy = 0; cy < counts.y; cy++) {
			for (int cx = 0; cx < counts.x; cx++) {
				Vector3i bc(cx, cy, cz);
				Vector3 origin = bounds.position + Vector3(bc) * base_spacing;
				Vector3 center = origin + Vector3(0.5, 0.5, 0.5) * base_spacing;
				double d = 0.0;
				if (p_density_at.is_valid()) {
					Variant arg = center;
					const Variant *argp = &arg;
					Variant ret;
					Callable::CallError err;
					p_density_at.callp(&argp, 1, ret, err);
					if (err.error == Callable::CallError::CALL_OK) {
						d = CLAMP((double)ret, 0.0, 1.0);
					}
				}
				int level = 0;
				if (d >= 0.67) {
					level = 2;
				} else if (d >= 0.34) {
					level = 1;
				}
				leaf_start[_flat(bc)] = leaf_count;
				leaf_level[_flat(bc)] = level;
				int n = 1 << level;
				real_t leaf_size = base_spacing / (real_t)n;
				for (int lz = 0; lz < n; lz++) {
					for (int ly = 0; ly < n; ly++) {
						for (int lx = 0; lx < n; lx++) {
							for (int k = 0; k < 8; k++) {
								Vector3 off((real_t)(lx + (k & 1)), (real_t)(ly + ((k >> 1) & 1)), (real_t)(lz + ((k >> 2) & 1)));
								leaves.push_back(_probe_at(origin + off * leaf_size));
							}
							leaf_count++;
						}
					}
				}
			}
		}
	}
	return positions.size();
}

void ProbeVolume::_compute_probe(int p_i, const Callable &p_trace, int64_t p_seed, int p_salt, SHLighting::Coeffs &r_sh, float &r_inside) {
	RandomPCG rng;
	rng.seed((uint64_t)(p_seed * 1000003 + (int64_t)p_i * 7919 + (int64_t)p_salt * 104729));
	real_t ax = (real_t)rng.random(-1.0, 1.0);
	real_t ay = (real_t)rng.random(-1.0, 1.0) + 1.5f;
	real_t az = (real_t)rng.random(-1.0, 1.0);
	Vector3 axis = Vector3(ax, ay, az).normalized();
	real_t angle = (real_t)rng.randf() * (real_t)Math::TAU;
	Basis rot(axis, angle);
	Vector3 pos = positions[p_i];
	int n = rays;
	float w = 4.0f * (float)Math::PI / (float)n;
	r_sh = SHLighting::Coeffs();
	int inside = 0;
	for (int r = 0; r < n; r++) {
		Vector3 d = rot.xform(SHLighting::fibonacci_dir_native(r, n));
		Variant args[2] = { pos, d };
		const Variant *argp[2] = { &args[0], &args[1] };
		Variant ret;
		Callable::CallError err;
		p_trace.callp(argp, 2, ret, err);
		Dictionary res;
		if (err.error == Callable::CallError::CALL_OK && ret.get_type() == Variant::DICTIONARY) {
			res = ret;
		}
		Color rad;
		bool hit = res.get("hit", false);
		if (hit) {
			double dist = res.get("distance", 0.0);
			bool back = res.get("backface", false);
			if (back || dist < min_hit_distance) {
				inside++;
				continue;
			}
			rad = res.get("color", Color(0, 0, 0));
		} else {
			rad = sky(d);
		}
		SHLighting::accumulate_native(r_sh, d, rad.r * w, rad.g * w, rad.b * w);
	}
	r_inside = (float)inside / (float)n;
}

void ProbeVolume::bake(const Callable &p_trace, int p_rays_per_probe, int64_t p_seed) {
	ERR_FAIL_COND_MSG(!p_trace.is_valid(), "ProbeVolume.bake() needs a valid trace callable.");
	rays = MAX(p_rays_per_probe, 4);
	for (int i = 0; i < (int)positions.size(); i++) {
		SHLighting::Coeffs fresh;
		float inside = 0.0f;
		_compute_probe(i, p_trace, p_seed, 0, fresh, inside);
		if (inside >= invalid_fraction) {
			valid[i] = 0;
			sh[i] = SHLighting::Coeffs();
		} else {
			valid[i] = 1;
			sh[i] = fresh;
		}
	}
	LocalVector<Vector3i> cells;
	for (const KeyValue<Vector3i, PackedInt32Array> &kv : cell_probes) {
		cells.push_back(kv.key);
	}
	for (const Vector3i &c : cells) {
		_touch(c);
	}
}

int ProbeVolume::temporal_update(real_t p_fraction, const Callable &p_trace, int64_t p_seed) {
	int n = positions.size();
	if (n == 0) {
		return 0;
	}
	ERR_FAIL_COND_V_MSG(!p_trace.is_valid(), 0, "ProbeVolume.temporal_update() needs a valid trace callable.");
	int cnt = CLAMP((int)Math::ceil(p_fraction * (real_t)n), 1, n);
	frame++;
	int updated = 0;
	for (int k = 0; k < cnt; k++) {
		int i = (cursor + k) % n;
		if (!resident.has(probe_cell[i])) {
			continue;
		}
		SHLighting::Coeffs fresh;
		float inside = 0.0f;
		_compute_probe(i, p_trace, p_seed, frame, fresh, inside);
		if (inside >= invalid_fraction) {
			valid[i] = 0;
			sh[i] = SHLighting::Coeffs();
		} else {
			if (valid[i] == 0) {
				sh[i] = fresh;
			} else {
				sh[i] = SHLighting::lerp_native(fresh, sh[i], hysteresis);
			}
			valid[i] = 1;
		}
		updated++;
	}
	cursor = (cursor + cnt) % n;
	return updated;
}

Color ProbeVolume::_ambient(const Vector3 &p_normal) {
	if (!sky_sh_valid) {
		sky_sh = SHLighting::from_sky_native(Vector3(), Color(0, 0, 0), sky_top, sky_bottom, 64);
		sky_sh_valid = true;
	}
	return SHLighting::irradiance_native(sky_sh, p_normal);
}

Color ProbeVolume::sample(const Vector3 &p_pos, const Vector3 &p_normal) {
	if (positions.is_empty()) {
		return _ambient(p_normal);
	}
	Vector3 rel = (p_pos - bounds.position) / base_spacing;
	Vector3 ext(counts);
	if (rel.x < 0.0f || rel.y < 0.0f || rel.z < 0.0f || rel.x > ext.x || rel.y > ext.y || rel.z > ext.z) {
		return _ambient(p_normal);
	}
	Vector3i bc = _base_coord(p_pos);
	_touch(_cell_of_base(bc));
	int level = leaf_level[_flat(bc)];
	int n = 1 << level;
	Vector3 lf = (rel - Vector3(bc)) * (real_t)n;
	Vector3i li(CLAMP((int)Math::floor(lf.x), 0, n - 1), CLAMP((int)Math::floor(lf.y), 0, n - 1), CLAMP((int)Math::floor(lf.z), 0, n - 1));
	Vector3 t = lf - Vector3(li);
	int start = leaf_start[_flat(bc)];
	int leaf = start + li.x + n * (li.y + n * li.z);
	SHLighting::Coeffs acc;
	float total = 0.0f;
	Vector3 nrm = p_normal.normalized();
	for (int k = 0; k < 8; k++) {
		int ox = k & 1;
		int oy = (k >> 1) & 1;
		int oz = (k >> 2) & 1;
		int idx = leaves[leaf * 8 + k];
		if (valid[idx] == 0) {
			continue;
		}
		if (!resident.has(probe_cell[idx])) {
			continue;
		}
		float wx = ox == 1 ? t.x : 1.0f - t.x;
		float wy = oy == 1 ? t.y : 1.0f - t.y;
		float wz = oz == 1 ? t.z : 1.0f - t.z;
		float w = wx * wy * wz;
		if (w <= 0.0f) {
			continue;
		}
		Vector3 to_probe = positions[idx] - p_pos;
		if (to_probe.length_squared() > 1e-10f) {
			float facing = (to_probe.normalized().dot(nrm) + 1.0f) * 0.5f;
			w *= facing * facing + 0.2f;
		}
		SHLighting::Coeffs scaled = SHLighting::scale_native(sh[idx], w);
		SHLighting::add_native(acc, scaled);
		total += w;
	}
	if (total <= 1e-6f) {
		return _ambient(p_normal);
	}
	return SHLighting::irradiance_native(SHLighting::scale_native(acc, 1.0f / total), nrm);
}

void ProbeVolume::_touch(const Vector3i &p_cell) {
	HashMap<Vector3i, int64_t, Vec3iHasher>::Iterator it = resident.find(p_cell);
	if (it) {
		tick++;
		it->value = tick;
	}
}

void ProbeVolume::touch_cell(const Vector3i &p_cell) {
	_touch(p_cell);
}

bool ProbeVolume::is_cell_resident(const Vector3i &p_cell) const {
	return resident.has(p_cell);
}

PackedInt32Array ProbeVolume::cell_probe_ids(const Vector3i &p_cell) const {
	HashMap<Vector3i, PackedInt32Array, Vec3iHasher>::ConstIterator it = cell_probes.find(p_cell);
	return it ? it->value : PackedInt32Array();
}

int64_t ProbeVolume::resident_bytes() const {
	int64_t total = 0;
	for (const KeyValue<Vector3i, int64_t> &kv : resident) {
		HashMap<Vector3i, PackedInt32Array, Vec3iHasher>::ConstIterator it = cell_probes.find(kv.key);
		if (it) {
			total += (int64_t)it->value.size() * RECORD_BYTES;
		}
	}
	return total;
}

namespace {
struct CellDist {
	double dist;
	Vector3i cell;
};

struct CellDistLess {
	bool operator()(const CellDist &p_a, const CellDist &p_b) const {
		if (p_a.dist != p_b.dist) {
			return p_a.dist < p_b.dist;
		}
		if (p_a.cell.x != p_b.cell.x) {
			return p_a.cell.x < p_b.cell.x;
		}
		if (p_a.cell.y != p_b.cell.y) {
			return p_a.cell.y < p_b.cell.y;
		}
		return p_a.cell.z < p_b.cell.z;
	}
};
} //namespace

TypedArray<Vector3i> ProbeVolume::cells_needed(const Vector3 &p_view_pos, real_t p_radius) const {
	LocalVector<CellDist> pairs;
	real_t cell_size = base_spacing * (real_t)CELL_SPAN;
	for (const KeyValue<Vector3i, PackedInt32Array> &kv : cell_probes) {
		Vector3 lo = bounds.position + Vector3(kv.key) * cell_size;
		Vector3 closest(
				CLAMP(p_view_pos.x, lo.x, lo.x + cell_size),
				CLAMP(p_view_pos.y, lo.y, lo.y + cell_size),
				CLAMP(p_view_pos.z, lo.z, lo.z + cell_size));
		double dist = closest.distance_to(p_view_pos);
		if (dist <= p_radius) {
			pairs.push_back({ dist, kv.key });
		}
	}
	pairs.sort_custom<CellDistLess>();
	TypedArray<Vector3i> out;
	for (const CellDist &p : pairs) {
		out.push_back(p.cell);
	}
	return out;
}

PackedByteArray ProbeVolume::serialize_cell(const Vector3i &p_cell) const {
	if (!resident.has(p_cell)) {
		HashMap<Vector3i, PackedByteArray, Vec3iHasher>::ConstIterator sit = store.find(p_cell);
		return sit ? sit->value : PackedByteArray();
	}
	HashMap<Vector3i, PackedInt32Array, Vec3iHasher>::ConstIterator it = cell_probes.find(p_cell);
	PackedInt32Array ids = it ? it->value : PackedInt32Array();
	PackedByteArray buf;
	buf.resize(4 + ids.size() * RECORD_BYTES);
	uint8_t *w = buf.ptrw();
	encode_uint32((uint32_t)ids.size(), w);
	int off = 4;
	for (int idx : ids) {
		encode_uint32((uint32_t)idx, w + off);
		w[off + 4] = valid[idx];
		const SHLighting::Coeffs &s = sh[idx];
		int o = off + 5;
		for (int j = 0; j < SHLighting::COEFFS; j++) {
			encode_float(s.c[j][0], w + o);
			encode_float(s.c[j][1], w + o + 4);
			encode_float(s.c[j][2], w + o + 8);
			o += 12;
		}
		off += RECORD_BYTES;
	}
	return buf;
}

bool ProbeVolume::load_cell(const Vector3i &p_cell, const PackedByteArray &p_bytes) {
	if (p_bytes.size() < 4 || !cell_probes.has(p_cell)) {
		return false;
	}
	const uint8_t *r = p_bytes.ptr();
	int count = (int32_t)decode_uint32(r);
	if (count < 0 || (int64_t)p_bytes.size() != 4 + (int64_t)count * RECORD_BYTES) {
		return false;
	}
	int off = 4;
	for (int k = 0; k < count; k++) {
		int idx = (int32_t)decode_uint32(r + off);
		if (idx < 0 || idx >= (int)positions.size()) {
			return false;
		}
		valid[idx] = r[off + 4];
		SHLighting::Coeffs s;
		int o = off + 5;
		for (int j = 0; j < SHLighting::COEFFS; j++) {
			s.c[j][0] = decode_float(r + o);
			s.c[j][1] = decode_float(r + o + 4);
			s.c[j][2] = decode_float(r + o + 8);
			o += 12;
		}
		sh[idx] = s;
		sh_loaded[idx] = 1;
		off += RECORD_BYTES;
	}
	store.erase(p_cell);
	resident[p_cell] = 0;
	_touch(p_cell);
	enforce_budget(p_cell);
	return true;
}

PackedByteArray ProbeVolume::unload_cell(const Vector3i &p_cell) {
	PackedByteArray bytes = serialize_cell(p_cell);
	if (!resident.has(p_cell)) {
		return bytes;
	}
	store[p_cell] = bytes;
	PackedInt32Array ids = cell_probes[p_cell];
	for (int idx : ids) {
		sh[idx] = SHLighting::Coeffs();
		sh_loaded[idx] = 0;
	}
	resident.erase(p_cell);
	return bytes;
}

bool ProbeVolume::request_cell(const Vector3i &p_cell) {
	if (resident.has(p_cell)) {
		_touch(p_cell);
		return true;
	}
	HashMap<Vector3i, PackedByteArray, Vec3iHasher>::Iterator it = store.find(p_cell);
	if (it) {
		PackedByteArray bytes = it->value;
		return load_cell(p_cell, bytes);
	}
	return false;
}

int ProbeVolume::enforce_budget(const Vector3i &p_protect) {
	if (memory_budget_bytes <= 0) {
		return 0;
	}
	int evicted = 0;
	while (resident_bytes() > memory_budget_bytes && resident.size() > 1) {
		Vector3i oldest;
		int64_t best = INT64_MAX;
		int64_t newest = -1;
		for (const KeyValue<Vector3i, int64_t> &kv : resident) {
			newest = MAX(newest, kv.value);
		}
		for (const KeyValue<Vector3i, int64_t> &kv : resident) {
			if (kv.key == p_protect || kv.value == newest) {
				continue;
			}
			if (kv.value < best) {
				best = kv.value;
				oldest = kv.key;
			}
		}
		if (best == INT64_MAX) {
			break;
		}
		unload_cell(oldest);
		evicted++;
	}
	return evicted;
}

void ProbeVolume::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_bounds", "bounds"), &ProbeVolume::set_bounds);
	ClassDB::bind_method(D_METHOD("get_bounds"), &ProbeVolume::get_bounds);
	ClassDB::bind_method(D_METHOD("set_base_spacing", "spacing"), &ProbeVolume::set_base_spacing);
	ClassDB::bind_method(D_METHOD("get_base_spacing"), &ProbeVolume::get_base_spacing);
	ClassDB::bind_method(D_METHOD("set_hysteresis", "hysteresis"), &ProbeVolume::set_hysteresis);
	ClassDB::bind_method(D_METHOD("get_hysteresis"), &ProbeVolume::get_hysteresis);
	ClassDB::bind_method(D_METHOD("set_min_hit_distance", "distance"), &ProbeVolume::set_min_hit_distance);
	ClassDB::bind_method(D_METHOD("get_min_hit_distance"), &ProbeVolume::get_min_hit_distance);
	ClassDB::bind_method(D_METHOD("set_invalid_fraction", "fraction"), &ProbeVolume::set_invalid_fraction);
	ClassDB::bind_method(D_METHOD("get_invalid_fraction"), &ProbeVolume::get_invalid_fraction);
	ClassDB::bind_method(D_METHOD("set_sky_top", "color"), &ProbeVolume::set_sky_top);
	ClassDB::bind_method(D_METHOD("get_sky_top"), &ProbeVolume::get_sky_top);
	ClassDB::bind_method(D_METHOD("set_sky_bottom", "color"), &ProbeVolume::set_sky_bottom);
	ClassDB::bind_method(D_METHOD("get_sky_bottom"), &ProbeVolume::get_sky_bottom);
	ClassDB::bind_method(D_METHOD("set_memory_budget_bytes", "bytes"), &ProbeVolume::set_memory_budget_bytes);
	ClassDB::bind_method(D_METHOD("get_memory_budget_bytes"), &ProbeVolume::get_memory_budget_bytes);

	ClassDB::bind_method(D_METHOD("clear"), &ProbeVolume::clear);
	ClassDB::bind_method(D_METHOD("probe_count"), &ProbeVolume::probe_count);
	ClassDB::bind_method(D_METHOD("probe_position", "index"), &ProbeVolume::probe_position);
	ClassDB::bind_method(D_METHOD("probe_sh", "index"), &ProbeVolume::probe_sh);
	ClassDB::bind_method(D_METHOD("is_probe_valid", "index"), &ProbeVolume::is_probe_valid);
	ClassDB::bind_method(D_METHOD("find_probe", "pos"), &ProbeVolume::find_probe);
	ClassDB::bind_method(D_METHOD("sky", "dir"), &ProbeVolume::sky);
	ClassDB::bind_method(D_METHOD("cell_of_position", "pos"), &ProbeVolume::cell_of_position);
	ClassDB::bind_method(D_METHOD("build", "bounds", "base_spacing", "density_at"), &ProbeVolume::build);
	ClassDB::bind_method(D_METHOD("bake", "trace", "rays_per_probe", "seed"), &ProbeVolume::bake);
	ClassDB::bind_method(D_METHOD("temporal_update", "fraction", "trace", "seed"), &ProbeVolume::temporal_update);
	ClassDB::bind_method(D_METHOD("sample", "pos", "normal"), &ProbeVolume::sample);
	ClassDB::bind_method(D_METHOD("touch_cell", "cell"), &ProbeVolume::touch_cell);
	ClassDB::bind_method(D_METHOD("is_cell_resident", "cell"), &ProbeVolume::is_cell_resident);
	ClassDB::bind_method(D_METHOD("cell_probe_ids", "cell"), &ProbeVolume::cell_probe_ids);
	ClassDB::bind_method(D_METHOD("resident_bytes"), &ProbeVolume::resident_bytes);
	ClassDB::bind_method(D_METHOD("cells_needed", "view_pos", "radius"), &ProbeVolume::cells_needed);
	ClassDB::bind_method(D_METHOD("serialize_cell", "cell"), &ProbeVolume::serialize_cell);
	ClassDB::bind_method(D_METHOD("load_cell", "cell", "bytes"), &ProbeVolume::load_cell);
	ClassDB::bind_method(D_METHOD("unload_cell", "cell"), &ProbeVolume::unload_cell);
	ClassDB::bind_method(D_METHOD("request_cell", "cell"), &ProbeVolume::request_cell);
	ClassDB::bind_method(D_METHOD("enforce_budget", "protect"), &ProbeVolume::enforce_budget, DEFVAL(Vector3i(-99999, -99999, -99999)));

	ADD_PROPERTY(PropertyInfo(Variant::AABB, "bounds"), "set_bounds", "get_bounds");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "base_spacing", PROPERTY_HINT_RANGE, "0.01,1000,0.01,or_greater,suffix:m"), "set_base_spacing", "get_base_spacing");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hysteresis", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_hysteresis", "get_hysteresis");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_hit_distance", PROPERTY_HINT_RANGE, "0,10,0.001,or_greater"), "set_min_hit_distance", "get_min_hit_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "invalid_fraction", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_invalid_fraction", "get_invalid_fraction");
	ADD_PROPERTY(PropertyInfo(Variant::COLOR, "sky_top"), "set_sky_top", "get_sky_top");
	ADD_PROPERTY(PropertyInfo(Variant::COLOR, "sky_bottom"), "set_sky_bottom", "get_sky_bottom");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "memory_budget_bytes", PROPERTY_HINT_RANGE, "0,4294967296,1,or_greater"), "set_memory_budget_bytes", "get_memory_budget_bytes");

	BIND_CONSTANT(MAX_LEVEL);
	BIND_CONSTANT(CELL_SPAN);
	BIND_CONSTANT(RECORD_BYTES);
}
