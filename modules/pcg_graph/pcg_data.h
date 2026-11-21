/**************************************************************************/
/*  pcg_data.h                                                            */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// Data flowing along PCG graph edges (Unreal PCG "PCGData"): point sets with
// per-point attributes, spline/polyline sets, and parameter sets. Every data
// object hashes its content so the executor can cache and recompute only what
// changed (incremental graph recalculation).

#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

#include <cstring>

// Deterministic, platform-independent mixing (splitmix64 finaliser).
static inline uint64_t pcg_mix64(uint64_t p_a, uint64_t p_b) {
	uint64_t z = p_a ^ (p_b + 0x9e3779b97f4a7c15ULL + (p_a << 6) + (p_a >> 2));
	z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
	z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
	return z ^ (z >> 31);
}

static inline uint64_t pcg_hash_double(uint64_t p_h, double p_value) {
	uint64_t bits = 0;
	if (p_value == 0.0) {
		p_value = 0.0; // Fold -0.0 into 0.0.
	}
	memcpy(&bits, &p_value, sizeof(bits));
	return pcg_mix64(p_h, bits);
}

// Uniform [0, 1) from a seed.
static inline double pcg_rand01(uint64_t p_seed) {
	return double(pcg_mix64(p_seed, 0x632be59bd9b4e019ULL) >> 11) * (1.0 / 9007199254740992.0);
}

class PCGData : public RefCounted {
	GDCLASS(PCGData, RefCounted);

protected:
	static void _bind_methods();

public:
	virtual String get_data_type() const { return "Data"; }
	virtual uint64_t compute_content_hash() const { return 0; }
	int64_t get_content_hash() const { return (int64_t)compute_content_hash(); }
};

class PCGPointData : public PCGData {
	GDCLASS(PCGPointData, PCGData);

	PackedVector3Array positions;
	PackedVector3Array normals;
	PackedFloat32Array density;
	PackedFloat32Array yaw;
	PackedFloat32Array scale;
	PackedInt64Array seeds;
	Dictionary attributes; // StringName -> PackedFloat32Array, one value per point.

protected:
	static void _bind_methods();

public:
	virtual String get_data_type() const override { return "Points"; }
	virtual uint64_t compute_content_hash() const override;

	int get_point_count() const { return positions.size(); }
	void add_point(const Vector3 &p_position, const Vector3 &p_normal = Vector3(0, 1, 0), float p_density = 1.0, float p_yaw = 0.0, float p_scale = 1.0, int64_t p_seed = 0);
	void clear();

	Vector3 get_position(int p_index) const;
	Vector3 get_normal(int p_index) const;
	float get_density(int p_index) const;
	float get_yaw(int p_index) const;
	float get_scale(int p_index) const;
	int64_t get_seed(int p_index) const;
	void set_position(int p_index, const Vector3 &p_position);
	void set_density(int p_index, float p_density);
	void set_yaw(int p_index, float p_yaw);
	void set_scale(int p_index, float p_scale);

	PackedVector3Array get_positions() const { return positions; }
	PackedVector3Array get_normals() const { return normals; }
	PackedFloat32Array get_densities() const { return density; }
	PackedFloat32Array get_yaws() const { return yaw; }
	PackedFloat32Array get_scales() const { return scale; }
	PackedInt64Array get_seeds() const { return seeds; }

	bool has_attribute(const StringName &p_name) const;
	PackedStringArray get_attribute_names() const;
	PackedFloat32Array get_attribute(const StringName &p_name) const; // Zero-filled when missing.
	float get_attribute_value(const StringName &p_name, int p_index, float p_default = 0.0) const;
	void set_attribute(const StringName &p_name, const PackedFloat32Array &p_values);
	void set_attribute_value(const StringName &p_name, int p_index, float p_value);

	// New point set with the given indices, in order, attributes included.
	Ref<PCGPointData> select(const PackedInt32Array &p_indices) const;
	void append(const Ref<PCGPointData> &p_other);
	Ref<PCGPointData> duplicate_points() const;
	// Transform per point: position, yaw about Y, uniform scale, tilted to the normal when requested.
	Transform3D get_point_transform(int p_index, bool p_align_to_normal = false) const;
	AABB get_bounds() const;
};

// One or more polylines (roads, rivers, walls). Unreal "PCGSplineData".
class PCGSplineData : public PCGData {
	GDCLASS(PCGSplineData, PCGData);

	TypedArray<PackedVector3Array> polylines;
	PackedFloat32Array widths; // Per polyline, optional.

protected:
	static void _bind_methods();

public:
	virtual String get_data_type() const override { return "Spline"; }
	virtual uint64_t compute_content_hash() const override;

	void add_polyline(const PackedVector3Array &p_points, float p_width = 0.0);
	int get_polyline_count() const { return polylines.size(); }
	PackedVector3Array get_polyline(int p_index) const;
	float get_width(int p_index) const;
	TypedArray<PackedVector3Array> get_polylines() const { return polylines; }
	void set_polylines(const TypedArray<PackedVector3Array> &p_polylines);
	static float polyline_length(const PackedVector3Array &p_points);
	// Distance from p_point to the nearest segment of any polyline (XZ plane).
	float distance_xz(const Vector3 &p_point) const;
};

// Named values (graph parameters, budgets, rule tables).
class PCGParamData : public PCGData {
	GDCLASS(PCGParamData, PCGData);

	Dictionary values;

protected:
	static void _bind_methods();

public:
	virtual String get_data_type() const override { return "Params"; }
	virtual uint64_t compute_content_hash() const override;

	void set_values(const Dictionary &p_values) { values = p_values; }
	Dictionary get_values() const { return values; }
	void set_value(const StringName &p_key, const Variant &p_value) { values[p_key] = p_value; }
	Variant get_value(const StringName &p_key, const Variant &p_default = Variant()) const { return values.get(p_key, p_default); }
};
