/**************************************************************************/
/*  probe_volume.h                                                        */
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

#include "sh_lighting.h"

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/variant/callable.h"
#include "core/variant/typed_array.h"

// Adaptive irradiance probe volume with L2 SH probes, temporal radiance-cache style updates
// and LRU-budgeted cell streaming. Geometry is abstracted behind a trace Callable
// (origin: Vector3, dir: Vector3) -> Dictionary {hit: bool, color: Color, distance: float,
// backface: bool (optional)}.
class ProbeVolume : public RefCounted {
	GDCLASS(ProbeVolume, RefCounted);

public:
	static constexpr int MAX_LEVEL = 2;
	// Streaming cell edge, in base bricks.
	static constexpr int CELL_SPAN = 2;
	// Serialized record: s32 index + u8 valid + 27 float32.
	static constexpr int RECORD_BYTES = 4 + 1 + SHLighting::COEFFS * 3 * 4;

private:
	struct Vec3iHasher {
		static _FORCE_INLINE_ uint32_t hash(const Vector3i &p_v) {
			uint32_t h = hash_murmur3_one_32((uint32_t)p_v.x);
			h = hash_murmur3_one_32((uint32_t)p_v.y, h);
			h = hash_murmur3_one_32((uint32_t)p_v.z, h);
			return hash_fmix32(h);
		}
	};

	AABB bounds;
	real_t base_spacing = 2.0;
	real_t hysteresis = 0.7;
	real_t min_hit_distance = 0.02;
	real_t invalid_fraction = 0.5;
	Color sky_top = Color(0.6, 0.75, 1.0);
	Color sky_bottom = Color(0.15, 0.13, 0.12);
	int64_t memory_budget_bytes = 0;

	Vector<Vector3> positions;
	LocalVector<SHLighting::Coeffs> sh;
	LocalVector<uint8_t> sh_loaded;
	LocalVector<uint8_t> valid;
	LocalVector<Vector3i> probe_cell;
	HashMap<Vector3i, int, Vec3iHasher> index_of;
	LocalVector<int> leaf_start;
	LocalVector<int> leaf_level;
	LocalVector<int> leaves;
	int leaf_count = 0;
	Vector3i counts = Vector3i(1, 1, 1);
	real_t unit = 1.0;
	HashMap<Vector3i, PackedInt32Array, Vec3iHasher> cell_probes;
	HashMap<Vector3i, int64_t, Vec3iHasher> resident;
	HashMap<Vector3i, PackedByteArray, Vec3iHasher> store;
	int64_t tick = 0;
	int cursor = 0;
	int frame = 0;
	int rays = 32;
	SHLighting::Coeffs sky_sh;
	bool sky_sh_valid = false;

	_FORCE_INLINE_ int _flat(const Vector3i &p_bc) const { return p_bc.x + counts.x * (p_bc.y + counts.y * p_bc.z); }
	Vector3i _key_of(const Vector3 &p_pos) const;
	static Vector3i _cell_of_base(const Vector3i &p_bc);
	Vector3i _base_coord(const Vector3 &p_pos) const;
	int _probe_at(const Vector3 &p_pos);
	void _touch(const Vector3i &p_cell);
	Color _ambient(const Vector3 &p_normal);
	void _compute_probe(int p_i, const Callable &p_trace, int64_t p_seed, int p_salt, SHLighting::Coeffs &r_sh, float &r_inside);
	void clear_internal();

protected:
	static void _bind_methods();

public:
	void set_bounds(const AABB &p_bounds);
	AABB get_bounds() const;
	void set_base_spacing(real_t p_spacing);
	real_t get_base_spacing() const;
	void set_hysteresis(real_t p_value);
	real_t get_hysteresis() const;
	void set_min_hit_distance(real_t p_value);
	real_t get_min_hit_distance() const;
	void set_invalid_fraction(real_t p_value);
	real_t get_invalid_fraction() const;
	void set_sky_top(const Color &p_color);
	Color get_sky_top() const;
	void set_sky_bottom(const Color &p_color);
	Color get_sky_bottom() const;
	void set_memory_budget_bytes(int64_t p_bytes);
	int64_t get_memory_budget_bytes() const;

	void clear();
	int probe_count() const;
	Vector3 probe_position(int p_i) const;
	PackedColorArray probe_sh(int p_i) const;
	bool is_probe_valid(int p_i) const;
	int find_probe(const Vector3 &p_pos) const;
	Color sky(const Vector3 &p_dir) const;
	Vector3i cell_of_position(const Vector3 &p_pos) const;

	int build(const AABB &p_bounds, real_t p_base_spacing, const Callable &p_density_at);
	void bake(const Callable &p_trace, int p_rays_per_probe, int64_t p_seed);
	int temporal_update(real_t p_fraction, const Callable &p_trace, int64_t p_seed);
	Color sample(const Vector3 &p_pos, const Vector3 &p_normal);

	void touch_cell(const Vector3i &p_cell);
	bool is_cell_resident(const Vector3i &p_cell) const;
	PackedInt32Array cell_probe_ids(const Vector3i &p_cell) const;
	int64_t resident_bytes() const;
	TypedArray<Vector3i> cells_needed(const Vector3 &p_view_pos, real_t p_radius) const;
	PackedByteArray serialize_cell(const Vector3i &p_cell) const;
	bool load_cell(const Vector3i &p_cell, const PackedByteArray &p_bytes);
	PackedByteArray unload_cell(const Vector3i &p_cell);
	bool request_cell(const Vector3i &p_cell);
	int enforce_budget(const Vector3i &p_protect = Vector3i(-99999, -99999, -99999));
};
