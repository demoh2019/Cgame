/**************************************************************************/
/*  pcg_core_nodes.h                                                      */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// Built-in PCG nodes. Rules shared by all of them:
//  * Never mutate inputs (outputs may be cached and shared).
//  * Randomness comes from per-point seeds (derived from world-space lattice
//    coordinates) mixed with the node seed, so results do not depend on how the
//    world is cut into streaming cells or the order cells are generated in.

#include "pcg_node.h"

// Jittered lattice of points on the terrain inside the context bounds (Unreal "Surface Sampler").
class PCGSurfaceSamplerNode : public PCGNode {
	GDCLASS(PCGSurfaceSamplerNode, PCGNode);
	float spacing = 4.0;
	float jitter = 0.8;
	bool skip_water = true;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 0; }
	virtual String get_category() const override { return "Sampler"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_spacing(float p_value);
	float get_spacing() const { return spacing; }
	void set_jitter(float p_value);
	float get_jitter() const { return jitter; }
	void set_skip_water(bool p_value);
	bool is_skip_water() const { return skip_water; }
};

// Deterministic fractal value noise written into density (density masks).
class PCGDensityNoiseNode : public PCGNode {
	GDCLASS(PCGDensityNoiseNode, PCGNode);

public:
	enum Mode {
		MODE_SET,
		MODE_MULTIPLY,
		MODE_ADD,
	};

private:
	float frequency = 0.02;
	int octaves = 3;
	Mode mode = MODE_MULTIPLY;
	float contrast = 1.0;
	float bias = 0.0;

protected:
	static void _bind_methods();

public:
	static float value_noise(uint64_t p_seed, float p_x, float p_z, float p_frequency, int p_octaves);
	virtual String get_category() const override { return "Density"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_frequency(float p_value);
	float get_frequency() const { return frequency; }
	void set_octaves(int p_value);
	int get_octaves() const { return octaves; }
	void set_mode(Mode p_value);
	Mode get_mode() const { return mode; }
	void set_contrast(float p_value);
	float get_contrast() const { return contrast; }
	void set_bias(float p_value);
	float get_bias() const { return bias; }
};

// Keeps points by density range and/or a density-weighted random draw.
class PCGDensityFilterNode : public PCGNode {
	GDCLASS(PCGDensityFilterNode, PCGNode);
	float min_density = 0.0;
	float max_density = 1.0;
	bool random_threshold = true;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Density"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_min_density(float p_value);
	float get_min_density() const { return min_density; }
	void set_max_density(float p_value);
	float get_max_density() const { return max_density; }
	void set_random_threshold(bool p_value);
	bool is_random_threshold() const { return random_threshold; }
};

// Slope, height and water filter (PCG surface filters).
class PCGSurfaceFilterNode : public PCGNode {
	GDCLASS(PCGSurfaceFilterNode, PCGNode);
	float min_slope_degrees = 0.0;
	float max_slope_degrees = 35.0;
	float min_height = -10000.0;
	float max_height = 10000.0;
	bool exclude_water = true;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Filter"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_min_slope_degrees(float p_value);
	float get_min_slope_degrees() const { return min_slope_degrees; }
	void set_max_slope_degrees(float p_value);
	float get_max_slope_degrees() const { return max_slope_degrees; }
	void set_min_height(float p_value);
	float get_min_height() const { return min_height; }
	void set_max_height(float p_value);
	float get_max_height() const { return max_height; }
	void set_exclude_water(bool p_value);
	bool is_exclude_water() const { return exclude_water; }
};

// Biome mask: keeps points in listed biomes and scales density per biome (PCG biome masks).
class PCGBiomeMaskNode : public PCGNode {
	GDCLASS(PCGBiomeMaskNode, PCGNode);
	PackedStringArray biomes;
	bool invert = false;
	Dictionary biome_density; // biome -> density multiplier

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Filter"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_biomes(const PackedStringArray &p_value);
	PackedStringArray get_biomes() const { return biomes; }
	void set_invert(bool p_value);
	bool is_invert() const { return invert; }
	void set_biome_density(const Dictionary &p_value);
	Dictionary get_biome_density() const { return biome_density; }
};

// Removes points inside the context's exclusion volumes, grown by a margin (PCG exclusion volumes).
class PCGExclusionFilterNode : public PCGNode {
	GDCLASS(PCGExclusionFilterNode, PCGNode);
	float margin = 0.0;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Filter"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_margin(float p_value);
	float get_margin() const { return margin; }
};

// Spatial query between two point sets (and an optional spline set): keep A points near / far from B.
class PCGSpatialQueryNode : public PCGNode {
	GDCLASS(PCGSpatialQueryNode, PCGNode);

public:
	enum Mode {
		MODE_KEEP_OUTSIDE,
		MODE_KEEP_INSIDE,
	};

private:
	float radius = 4.0;
	Mode mode = MODE_KEEP_OUTSIDE;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 2; }
	virtual String get_category() const override { return "Spatial"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_radius(float p_value);
	float get_radius() const { return radius; }
	void set_mode(Mode p_value);
	Mode get_mode() const { return mode; }
};

// Minimum-distance pruning (blue-noise thinning): denser and then lower-seed points win.
class PCGSelfPruneNode : public PCGNode {
	GDCLASS(PCGSelfPruneNode, PCGNode);
	float min_distance = 3.0;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Spatial"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_min_distance(float p_value);
	float get_min_distance() const { return min_distance; }
};

// Random yaw/scale/offset per point.
class PCGTransformNode : public PCGNode {
	GDCLASS(PCGTransformNode, PCGNode);
	bool random_yaw = true;
	float scale_min = 0.8;
	float scale_max = 1.25;
	Vector3 offset_min;
	Vector3 offset_max;
	bool snap_to_ground = false;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Transform"; }
	virtual bool uses_environment() const override { return snap_to_ground; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_random_yaw(bool p_value);
	bool is_random_yaw() const { return random_yaw; }
	void set_scale_min(float p_value);
	float get_scale_min() const { return scale_min; }
	void set_scale_max(float p_value);
	float get_scale_max() const { return scale_max; }
	void set_offset_min(const Vector3 &p_value);
	Vector3 get_offset_min() const { return offset_min; }
	void set_offset_max(const Vector3 &p_value);
	Vector3 get_offset_max() const { return offset_max; }
	void set_snap_to_ground(bool p_value);
	bool is_snap_to_ground() const { return snap_to_ground; }
};

// Union of up to `input_count` point sets.
class PCGMergeNode : public PCGNode {
	GDCLASS(PCGMergeNode, PCGNode);
	int input_count = 2;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return input_count; }
	virtual String get_category() const override { return "Utility"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_input_count(int p_value);
	int get_input_count_property() const { return input_count; }
};

// Points along polylines: from an upstream spline, or context.user_data[source_key] (PCG spline sampling).
class PCGSplineSamplerNode : public PCGNode {
	GDCLASS(PCGSplineSamplerNode, PCGNode);
	String source_key = "roads";
	float spacing = 6.0;
	float lateral_offset = 0.0;
	bool both_sides = true;
	bool face_along = true;
	bool project_to_ground = true;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Sampler"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	static Ref<PCGSplineData> spline_from_variant(const Variant &p_value);
	void set_source_key(const String &p_value);
	String get_source_key() const { return source_key; }
	void set_spacing(float p_value);
	float get_spacing() const { return spacing; }
	void set_lateral_offset(float p_value);
	float get_lateral_offset() const { return lateral_offset; }
	void set_both_sides(bool p_value);
	bool is_both_sides() const { return both_sides; }
	void set_face_along(bool p_value);
	bool is_face_along() const { return face_along; }
	void set_project_to_ground(bool p_value);
	bool is_project_to_ground() const { return project_to_ground; }
};

// Points injected by the game: context.user_data[source_key] = Array of Vector3 or {"position", ...attributes}.
class PCGPointSourceNode : public PCGNode {
	GDCLASS(PCGPointSourceNode, PCGNode);
	String source_key = "points";
	bool clip_to_bounds = true;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 0; }
	virtual String get_category() const override { return "Sampler"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_source_key(const String &p_value);
	String get_source_key() const { return source_key; }
	void set_clip_to_bounds(bool p_value);
	bool is_clip_to_bounds() const { return clip_to_bounds; }
};

// Asset rules: weighted choice among assets whose conditions match each point; writes attribute "asset".
// Rule: {"asset": int, "weight": float, "biomes": PackedStringArray, "min_slope": deg, "max_slope": deg,
//        "min_height": float, "max_height": float, "min_density": float}
class PCGAssetRuleNode : public PCGNode {
	GDCLASS(PCGAssetRuleNode, PCGNode);
	Array rules;
	bool drop_unmatched = true;
	String attribute = "asset";

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Asset"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_rules(const Array &p_value);
	Array get_rules() const { return rules; }
	void set_drop_unmatched(bool p_value);
	bool is_drop_unmatched() const { return drop_unmatched; }
	void set_attribute(const String &p_value);
	String get_attribute() const { return attribute; }
};

// Groups points into world-grid clusters (attribute "cluster") for batched instancing and HLOD.
class PCGClusterNode : public PCGNode {
	GDCLASS(PCGClusterNode, PCGNode);
	float cluster_size = 32.0;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Utility"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	static int cluster_id(const Vector3 &p_position, float p_size);
	void set_cluster_size(float p_value);
	float get_cluster_size() const { return cluster_size; }
};

// Deterministic budget: keeps at most max_points (highest density, then seed order).
class PCGCountLimitNode : public PCGNode {
	GDCLASS(PCGCountLimitNode, PCGNode);
	int max_points = 16;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Utility"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_max_points(int p_value);
	int get_max_points() const { return max_points; }
};

// Sets a constant attribute on every point (tags such as "loot_tier" or "encounter").
class PCGAttributeSetNode : public PCGNode {
	GDCLASS(PCGAttributeSetNode, PCGNode);
	String attribute = "tag";
	float value = 1.0;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Utility"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_attribute(const String &p_value);
	String get_attribute() const { return attribute; }
	void set_value(float p_value);
	float get_value() const { return value; }
};

// Marks the graph result; passes its input through.
class PCGOutputNode : public PCGNode {
	GDCLASS(PCGOutputNode, PCGNode);

protected:
	static void _bind_methods() {}

public:
	virtual String get_category() const override { return "Utility"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
};

VARIANT_ENUM_CAST(PCGDensityNoiseNode::Mode);
VARIANT_ENUM_CAST(PCGSpatialQueryNode::Mode);
