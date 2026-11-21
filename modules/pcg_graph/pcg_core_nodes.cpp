/**************************************************************************/
/*  pcg_core_nodes.cpp                                                    */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_core_nodes.h"

#include "core/object/class_db.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/templates/sort_array.h"

namespace {

// Uniform grid of point indices on XZ for radius queries.
struct PCGSpatialGrid {
	float cell = 1.0;
	HashMap<Vector2i, LocalVector<int>> buckets;

	Vector2i key(const Vector3 &p_position) const {
		return Vector2i((int)Math::floor(p_position.x / cell), (int)Math::floor(p_position.z / cell));
	}
	void insert(const Vector3 &p_position, int p_index) {
		buckets[key(p_position)].push_back(p_index);
	}
	// True when any stored point lies within p_radius (XZ) of p_position.
	bool any_within(const Vector3 &p_position, float p_radius, const PackedVector3Array &p_positions) const {
		const Vector2i k = key(p_position);
		const int reach = (int)Math::ceil(p_radius / cell);
		const float r2 = p_radius * p_radius;
		for (int dz = -reach; dz <= reach; dz++) {
			for (int dx = -reach; dx <= reach; dx++) {
				const HashMap<Vector2i, LocalVector<int>>::ConstIterator E = buckets.find(Vector2i(k.x + dx, k.y + dz));
				if (!E) {
					continue;
				}
				for (const int index : E->value) {
					const Vector3 q = p_positions[index];
					const float ddx = q.x - p_position.x;
					const float ddz = q.z - p_position.z;
					if (ddx * ddx + ddz * ddz <= r2) {
						return true;
					}
				}
			}
		}
		return false;
	}
};

uint64_t point_rand_seed(int64_t p_point_seed, uint64_t p_node_seed) {
	return pcg_mix64((uint64_t)p_point_seed, p_node_seed);
}

} // namespace

// --- Surface sampler ---------------------------------------------------------------------------------------------

Ref<PCGData> PCGSurfaceSamplerNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out;
	out.instantiate();
	const float step = MAX(0.25f, float(resolve("spacing", p_context)));
	const float amount = CLAMP(float(resolve("jitter", p_context)), 0.0f, 1.0f);
	const bool avoid_water = resolve("skip_water", p_context);
	const AABB bounds = p_context->get_bounds();
	const Vector3 lo = bounds.position;
	const Vector3 hi = bounds.position + bounds.size;
	const int x0 = (int)Math::floor(lo.x / step) - 1;
	const int x1 = (int)Math::ceil(hi.x / step) + 1;
	const int z0 = (int)Math::floor(lo.z / step) - 1;
	const int z1 = (int)Math::ceil(hi.z / step) + 1;
	ERR_FAIL_COND_V_MSG(int64_t(x1 - x0) * int64_t(z1 - z0) > 4000000, out, "PCG surface sampler: spacing too small for the bounds.");
	for (int iz = z0; iz <= z1; iz++) {
		for (int ix = x0; ix <= x1; ix++) {
			// Lattice seed: identical for this lattice cell in every streaming tile.
			const uint64_t lattice = pcg_mix64(pcg_mix64(p_seed, (uint64_t)(int64_t)ix), (uint64_t)(int64_t)iz);
			const float jx = (float(pcg_rand01(lattice)) - 0.5f) * amount;
			const float jz = (float(pcg_rand01(pcg_mix64(lattice, 1))) - 0.5f) * amount;
			const float x = (ix + 0.5f + jx) * step;
			const float z = (iz + 0.5f + jz) * step;
			// Half-open bounds so neighbouring tiles never both own a point.
			if (x < lo.x || x >= hi.x || z < lo.z || z >= hi.z) {
				continue;
			}
			if (avoid_water && p_context->sample_water(x, z)) {
				continue;
			}
			const float y = p_context->sample_height(x, z);
			out->add_point(Vector3(x, y, z), p_context->sample_normal(x, z), 1.0, 0.0, 1.0, (int64_t)lattice);
		}
	}
	return out;
}

void PCGSurfaceSamplerNode::set_spacing(float p_value) {
	spacing = MAX(0.25f, p_value);
	emit_changed();
}

void PCGSurfaceSamplerNode::set_jitter(float p_value) {
	jitter = CLAMP(p_value, 0.0f, 1.0f);
	emit_changed();
}

void PCGSurfaceSamplerNode::set_skip_water(bool p_value) {
	skip_water = p_value;
	emit_changed();
}

void PCGSurfaceSamplerNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_spacing", "value"), &PCGSurfaceSamplerNode::set_spacing);
	ClassDB::bind_method(D_METHOD("get_spacing"), &PCGSurfaceSamplerNode::get_spacing);
	ClassDB::bind_method(D_METHOD("set_jitter", "value"), &PCGSurfaceSamplerNode::set_jitter);
	ClassDB::bind_method(D_METHOD("get_jitter"), &PCGSurfaceSamplerNode::get_jitter);
	ClassDB::bind_method(D_METHOD("set_skip_water", "value"), &PCGSurfaceSamplerNode::set_skip_water);
	ClassDB::bind_method(D_METHOD("is_skip_water"), &PCGSurfaceSamplerNode::is_skip_water);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "spacing", PROPERTY_HINT_RANGE, "0.25,256,0.05,or_greater"), "set_spacing", "get_spacing");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "jitter", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_jitter", "get_jitter");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "skip_water"), "set_skip_water", "is_skip_water");
}

// --- Density noise -----------------------------------------------------------------------------------------------

static float lattice_value(uint64_t p_seed, int p_x, int p_z) {
	return float(pcg_rand01(pcg_mix64(pcg_mix64(p_seed, (uint64_t)(int64_t)p_x), (uint64_t)(int64_t)p_z)));
}

float PCGDensityNoiseNode::value_noise(uint64_t p_seed, float p_x, float p_z, float p_frequency, int p_octaves) {
	float total = 0.0;
	float amplitude = 1.0;
	float norm = 0.0;
	float f = p_frequency;
	for (int o = 0; o < MAX(1, p_octaves); o++) {
		const uint64_t octave_seed = pcg_mix64(p_seed, (uint64_t)o);
		const float x = p_x * f;
		const float z = p_z * f;
		const int xi = (int)Math::floor(x);
		const int zi = (int)Math::floor(z);
		float tx = x - xi;
		float tz = z - zi;
		tx = tx * tx * (3.0f - 2.0f * tx);
		tz = tz * tz * (3.0f - 2.0f * tz);
		const float a = lattice_value(octave_seed, xi, zi);
		const float b = lattice_value(octave_seed, xi + 1, zi);
		const float c = lattice_value(octave_seed, xi, zi + 1);
		const float d = lattice_value(octave_seed, xi + 1, zi + 1);
		total += Math::lerp(Math::lerp(a, b, tx), Math::lerp(c, d, tx), tz) * amplitude;
		norm += amplitude;
		amplitude *= 0.5f;
		f *= 2.0f;
	}
	return total / norm;
}

Ref<PCGData> PCGDensityNoiseNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out = points_input(p_inputs, 0)->duplicate_points();
	const float freq = resolve("frequency", p_context);
	const int oct = resolve("octaves", p_context);
	const int m = resolve("mode", p_context);
	const float k = resolve("contrast", p_context);
	const float b = resolve("bias", p_context);
	for (int i = 0; i < out->get_point_count(); i++) {
		const Vector3 p = out->get_position(i);
		float n = value_noise(p_seed, p.x, p.z, freq, oct);
		n = CLAMP((n - 0.5f) * k + 0.5f + b, 0.0f, 1.0f);
		float d = out->get_density(i);
		switch (m) {
			case MODE_SET:
				d = n;
				break;
			case MODE_ADD:
				d = CLAMP(d + n, 0.0f, 1.0f);
				break;
			default:
				d *= n;
				break;
		}
		out->set_density(i, d);
	}
	return out;
}

void PCGDensityNoiseNode::set_frequency(float p_value) {
	frequency = MAX(0.00001f, p_value);
	emit_changed();
}

void PCGDensityNoiseNode::set_octaves(int p_value) {
	octaves = CLAMP(p_value, 1, 8);
	emit_changed();
}

void PCGDensityNoiseNode::set_mode(Mode p_value) {
	mode = p_value;
	emit_changed();
}

void PCGDensityNoiseNode::set_contrast(float p_value) {
	contrast = p_value;
	emit_changed();
}

void PCGDensityNoiseNode::set_bias(float p_value) {
	bias = p_value;
	emit_changed();
}

void PCGDensityNoiseNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_frequency", "value"), &PCGDensityNoiseNode::set_frequency);
	ClassDB::bind_method(D_METHOD("get_frequency"), &PCGDensityNoiseNode::get_frequency);
	ClassDB::bind_method(D_METHOD("set_octaves", "value"), &PCGDensityNoiseNode::set_octaves);
	ClassDB::bind_method(D_METHOD("get_octaves"), &PCGDensityNoiseNode::get_octaves);
	ClassDB::bind_method(D_METHOD("set_mode", "value"), &PCGDensityNoiseNode::set_mode);
	ClassDB::bind_method(D_METHOD("get_mode"), &PCGDensityNoiseNode::get_mode);
	ClassDB::bind_method(D_METHOD("set_contrast", "value"), &PCGDensityNoiseNode::set_contrast);
	ClassDB::bind_method(D_METHOD("get_contrast"), &PCGDensityNoiseNode::get_contrast);
	ClassDB::bind_method(D_METHOD("set_bias", "value"), &PCGDensityNoiseNode::set_bias);
	ClassDB::bind_method(D_METHOD("get_bias"), &PCGDensityNoiseNode::get_bias);
	ClassDB::bind_static_method("PCGDensityNoiseNode", D_METHOD("value_noise", "seed", "x", "z", "frequency", "octaves"), &PCGDensityNoiseNode::value_noise);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "frequency", PROPERTY_HINT_RANGE, "0.0001,1,0.0001,or_greater"), "set_frequency", "get_frequency");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "octaves", PROPERTY_HINT_RANGE, "1,8,1"), "set_octaves", "get_octaves");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "mode", PROPERTY_HINT_ENUM, "Set,Multiply,Add"), "set_mode", "get_mode");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "contrast", PROPERTY_HINT_RANGE, "0,8,0.01"), "set_contrast", "get_contrast");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bias", PROPERTY_HINT_RANGE, "-1,1,0.01"), "set_bias", "get_bias");
	BIND_ENUM_CONSTANT(MODE_SET);
	BIND_ENUM_CONSTANT(MODE_MULTIPLY);
	BIND_ENUM_CONSTANT(MODE_ADD);
}

// --- Density filter ----------------------------------------------------------------------------------------------

Ref<PCGData> PCGDensityFilterNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const float lo = resolve("min_density", p_context);
	const float hi = resolve("max_density", p_context);
	const bool draw = resolve("random_threshold", p_context);
	PackedInt32Array keep;
	for (int i = 0; i < in->get_point_count(); i++) {
		const float d = in->get_density(i);
		if (d < lo || d > hi) {
			continue;
		}
		if (draw && float(pcg_rand01(point_rand_seed(in->get_seed(i), p_seed))) >= d) {
			continue;
		}
		keep.push_back(i);
	}
	return in->select(keep);
}

void PCGDensityFilterNode::set_min_density(float p_value) {
	min_density = p_value;
	emit_changed();
}

void PCGDensityFilterNode::set_max_density(float p_value) {
	max_density = p_value;
	emit_changed();
}

void PCGDensityFilterNode::set_random_threshold(bool p_value) {
	random_threshold = p_value;
	emit_changed();
}

void PCGDensityFilterNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_min_density", "value"), &PCGDensityFilterNode::set_min_density);
	ClassDB::bind_method(D_METHOD("get_min_density"), &PCGDensityFilterNode::get_min_density);
	ClassDB::bind_method(D_METHOD("set_max_density", "value"), &PCGDensityFilterNode::set_max_density);
	ClassDB::bind_method(D_METHOD("get_max_density"), &PCGDensityFilterNode::get_max_density);
	ClassDB::bind_method(D_METHOD("set_random_threshold", "value"), &PCGDensityFilterNode::set_random_threshold);
	ClassDB::bind_method(D_METHOD("is_random_threshold"), &PCGDensityFilterNode::is_random_threshold);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_density", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_min_density", "get_min_density");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_density", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_max_density", "get_max_density");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "random_threshold"), "set_random_threshold", "is_random_threshold");
}

// --- Surface filter ----------------------------------------------------------------------------------------------

Ref<PCGData> PCGSurfaceFilterNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const float min_slope = Math::deg_to_rad(float(resolve("min_slope_degrees", p_context)));
	const float max_slope = Math::deg_to_rad(float(resolve("max_slope_degrees", p_context)));
	const float lo = resolve("min_height", p_context);
	const float hi = resolve("max_height", p_context);
	const bool no_water = resolve("exclude_water", p_context);
	PackedInt32Array keep;
	for (int i = 0; i < in->get_point_count(); i++) {
		const Vector3 p = in->get_position(i);
		const float slope = Math::acos(CLAMP(in->get_normal(i).normalized().y, -1.0f, 1.0f));
		if (slope < min_slope || slope > max_slope || p.y < lo || p.y > hi) {
			continue;
		}
		if (no_water && p_context->sample_water(p.x, p.z)) {
			continue;
		}
		keep.push_back(i);
	}
	return in->select(keep);
}

void PCGSurfaceFilterNode::set_min_slope_degrees(float p_value) {
	min_slope_degrees = p_value;
	emit_changed();
}

void PCGSurfaceFilterNode::set_max_slope_degrees(float p_value) {
	max_slope_degrees = p_value;
	emit_changed();
}

void PCGSurfaceFilterNode::set_min_height(float p_value) {
	min_height = p_value;
	emit_changed();
}

void PCGSurfaceFilterNode::set_max_height(float p_value) {
	max_height = p_value;
	emit_changed();
}

void PCGSurfaceFilterNode::set_exclude_water(bool p_value) {
	exclude_water = p_value;
	emit_changed();
}

void PCGSurfaceFilterNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_min_slope_degrees", "value"), &PCGSurfaceFilterNode::set_min_slope_degrees);
	ClassDB::bind_method(D_METHOD("get_min_slope_degrees"), &PCGSurfaceFilterNode::get_min_slope_degrees);
	ClassDB::bind_method(D_METHOD("set_max_slope_degrees", "value"), &PCGSurfaceFilterNode::set_max_slope_degrees);
	ClassDB::bind_method(D_METHOD("get_max_slope_degrees"), &PCGSurfaceFilterNode::get_max_slope_degrees);
	ClassDB::bind_method(D_METHOD("set_min_height", "value"), &PCGSurfaceFilterNode::set_min_height);
	ClassDB::bind_method(D_METHOD("get_min_height"), &PCGSurfaceFilterNode::get_min_height);
	ClassDB::bind_method(D_METHOD("set_max_height", "value"), &PCGSurfaceFilterNode::set_max_height);
	ClassDB::bind_method(D_METHOD("get_max_height"), &PCGSurfaceFilterNode::get_max_height);
	ClassDB::bind_method(D_METHOD("set_exclude_water", "value"), &PCGSurfaceFilterNode::set_exclude_water);
	ClassDB::bind_method(D_METHOD("is_exclude_water"), &PCGSurfaceFilterNode::is_exclude_water);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_slope_degrees", PROPERTY_HINT_RANGE, "0,90,0.1"), "set_min_slope_degrees", "get_min_slope_degrees");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_slope_degrees", PROPERTY_HINT_RANGE, "0,90,0.1"), "set_max_slope_degrees", "get_max_slope_degrees");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_height"), "set_min_height", "get_min_height");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_height"), "set_max_height", "get_max_height");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "exclude_water"), "set_exclude_water", "is_exclude_water");
}

// --- Biome mask --------------------------------------------------------------------------------------------------

Ref<PCGData> PCGBiomeMaskNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const PackedStringArray allowed = resolve("biomes", p_context);
	const bool flip = resolve("invert", p_context);
	const Dictionary weights = resolve("biome_density", p_context);
	PackedInt32Array keep;
	PackedFloat32Array scaled;
	for (int i = 0; i < in->get_point_count(); i++) {
		const Vector3 p = in->get_position(i);
		const String biome = p_context->sample_biome(p.x, p.z);
		bool inside = allowed.is_empty() || allowed.has(biome);
		if (flip) {
			inside = !inside;
		}
		if (!inside) {
			continue;
		}
		const float factor = weights.has(biome) ? float(weights[biome]) : 1.0f;
		if (factor <= 0.0f) {
			continue;
		}
		keep.push_back(i);
		scaled.push_back(CLAMP(in->get_density(i) * factor, 0.0f, 1.0f));
	}
	Ref<PCGPointData> out = in->select(keep);
	for (int i = 0; i < scaled.size(); i++) {
		out->set_density(i, scaled[i]);
	}
	return out;
}

void PCGBiomeMaskNode::set_biomes(const PackedStringArray &p_value) {
	biomes = p_value;
	emit_changed();
}

void PCGBiomeMaskNode::set_invert(bool p_value) {
	invert = p_value;
	emit_changed();
}

void PCGBiomeMaskNode::set_biome_density(const Dictionary &p_value) {
	biome_density = p_value;
	emit_changed();
}

void PCGBiomeMaskNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_biomes", "value"), &PCGBiomeMaskNode::set_biomes);
	ClassDB::bind_method(D_METHOD("get_biomes"), &PCGBiomeMaskNode::get_biomes);
	ClassDB::bind_method(D_METHOD("set_invert", "value"), &PCGBiomeMaskNode::set_invert);
	ClassDB::bind_method(D_METHOD("is_invert"), &PCGBiomeMaskNode::is_invert);
	ClassDB::bind_method(D_METHOD("set_biome_density", "value"), &PCGBiomeMaskNode::set_biome_density);
	ClassDB::bind_method(D_METHOD("get_biome_density"), &PCGBiomeMaskNode::get_biome_density);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "biomes"), "set_biomes", "get_biomes");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "invert"), "set_invert", "is_invert");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "biome_density"), "set_biome_density", "get_biome_density");
}

// --- Exclusion volumes -------------------------------------------------------------------------------------------

Ref<PCGData> PCGExclusionFilterNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const float grow = resolve("margin", p_context);
	PackedInt32Array keep;
	for (int i = 0; i < in->get_point_count(); i++) {
		if (!p_context->is_excluded(in->get_position(i), grow)) {
			keep.push_back(i);
		}
	}
	return in->select(keep);
}

void PCGExclusionFilterNode::set_margin(float p_value) {
	margin = p_value;
	emit_changed();
}

void PCGExclusionFilterNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_margin", "value"), &PCGExclusionFilterNode::set_margin);
	ClassDB::bind_method(D_METHOD("get_margin"), &PCGExclusionFilterNode::get_margin);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "margin", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater"), "set_margin", "get_margin");
}

// --- Spatial query -----------------------------------------------------------------------------------------------

Ref<PCGData> PCGSpatialQueryNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const float r = MAX(0.0f, float(resolve("radius", p_context)));
	const int m = resolve("mode", p_context);
	Ref<PCGSplineData> spline;
	Ref<PCGPointData> other;
	if (p_inputs.size() > 1) {
		spline = p_inputs[1];
		other = p_inputs[1];
	}
	PCGSpatialGrid grid;
	grid.cell = MAX(0.5f, r);
	PackedVector3Array other_positions;
	if (other.is_valid()) {
		other_positions = other->get_positions();
		for (int i = 0; i < other_positions.size(); i++) {
			grid.insert(other_positions[i], i);
		}
	}
	PackedInt32Array keep;
	for (int i = 0; i < in->get_point_count(); i++) {
		const Vector3 p = in->get_position(i);
		bool near = false;
		if (other.is_valid()) {
			near = grid.any_within(p, r, other_positions);
		} else if (spline.is_valid()) {
			near = spline->distance_xz(p) <= r;
		}
		if ((m == MODE_KEEP_INSIDE) == near) {
			keep.push_back(i);
		}
	}
	return in->select(keep);
}

void PCGSpatialQueryNode::set_radius(float p_value) {
	radius = MAX(0.0f, p_value);
	emit_changed();
}

void PCGSpatialQueryNode::set_mode(Mode p_value) {
	mode = p_value;
	emit_changed();
}

void PCGSpatialQueryNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_radius", "value"), &PCGSpatialQueryNode::set_radius);
	ClassDB::bind_method(D_METHOD("get_radius"), &PCGSpatialQueryNode::get_radius);
	ClassDB::bind_method(D_METHOD("set_mode", "value"), &PCGSpatialQueryNode::set_mode);
	ClassDB::bind_method(D_METHOD("get_mode"), &PCGSpatialQueryNode::get_mode);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "radius", PROPERTY_HINT_RANGE, "0,256,0.1,or_greater"), "set_radius", "get_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "mode", PROPERTY_HINT_ENUM, "Keep Outside,Keep Inside"), "set_mode", "get_mode");
	BIND_ENUM_CONSTANT(MODE_KEEP_OUTSIDE);
	BIND_ENUM_CONSTANT(MODE_KEEP_INSIDE);
}

// --- Self prune --------------------------------------------------------------------------------------------------

Ref<PCGData> PCGSelfPruneNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const float r = MAX(0.0f, float(resolve("min_distance", p_context)));
	const int n = in->get_point_count();
	// Priority: higher density first, then a seed-derived tiebreak (stable, order independent).
	LocalVector<int> order;
	order.resize(n);
	for (int i = 0; i < n; i++) {
		order[i] = i;
	}
	struct Priority {
		const PCGPointData *points;
		uint64_t seed;
		bool operator()(int a, int b) const {
			const float da = points->get_density(a);
			const float db = points->get_density(b);
			if (da != db) {
				return da > db;
			}
			const uint64_t sa = point_rand_seed(points->get_seed(a), seed);
			const uint64_t sb = point_rand_seed(points->get_seed(b), seed);
			if (sa != sb) {
				return sa < sb;
			}
			return a < b;
		}
	};
	SortArray<int, Priority> priority_sort;
	priority_sort.compare = Priority{ in.ptr(), p_seed };
	priority_sort.sort(order.ptr(), order.size());
	PCGSpatialGrid grid;
	grid.cell = MAX(0.5f, r);
	PackedVector3Array positions = in->get_positions();
	PackedInt32Array keep;
	for (uint32_t k = 0; k < order.size(); k++) {
		const int i = order[k];
		if (r > 0.0f && grid.any_within(positions[i], r, positions)) {
			continue;
		}
		grid.insert(positions[i], i);
		keep.push_back(i);
	}
	keep.sort(); // Keep the input order for stable downstream results.
	return in->select(keep);
}

void PCGSelfPruneNode::set_min_distance(float p_value) {
	min_distance = MAX(0.0f, p_value);
	emit_changed();
}

void PCGSelfPruneNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_min_distance", "value"), &PCGSelfPruneNode::set_min_distance);
	ClassDB::bind_method(D_METHOD("get_min_distance"), &PCGSelfPruneNode::get_min_distance);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_distance", PROPERTY_HINT_RANGE, "0,256,0.1,or_greater"), "set_min_distance", "get_min_distance");
}

// --- Transform ---------------------------------------------------------------------------------------------------

Ref<PCGData> PCGTransformNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out = points_input(p_inputs, 0)->duplicate_points();
	const bool spin = resolve("random_yaw", p_context);
	const float s0 = resolve("scale_min", p_context);
	const float s1 = resolve("scale_max", p_context);
	const Vector3 o0 = resolve("offset_min", p_context);
	const Vector3 o1 = resolve("offset_max", p_context);
	const bool snap = resolve("snap_to_ground", p_context);
	for (int i = 0; i < out->get_point_count(); i++) {
		const uint64_t s = point_rand_seed(out->get_seed(i), p_seed);
		if (spin) {
			out->set_yaw(i, float(pcg_rand01(pcg_mix64(s, 1)) * Math::TAU));
		}
		out->set_scale(i, out->get_scale(i) * Math::lerp(s0, s1, float(pcg_rand01(pcg_mix64(s, 2)))));
		const Vector3 offset(Math::lerp(o0.x, o1.x, float(pcg_rand01(pcg_mix64(s, 3)))),
				Math::lerp(o0.y, o1.y, float(pcg_rand01(pcg_mix64(s, 4)))),
				Math::lerp(o0.z, o1.z, float(pcg_rand01(pcg_mix64(s, 5)))));
		Vector3 p = out->get_position(i) + offset;
		if (snap) {
			p.y = p_context->sample_height(p.x, p.z) + offset.y;
		}
		out->set_position(i, p);
	}
	return out;
}

void PCGTransformNode::set_random_yaw(bool p_value) {
	random_yaw = p_value;
	emit_changed();
}

void PCGTransformNode::set_scale_min(float p_value) {
	scale_min = p_value;
	emit_changed();
}

void PCGTransformNode::set_scale_max(float p_value) {
	scale_max = p_value;
	emit_changed();
}

void PCGTransformNode::set_offset_min(const Vector3 &p_value) {
	offset_min = p_value;
	emit_changed();
}

void PCGTransformNode::set_offset_max(const Vector3 &p_value) {
	offset_max = p_value;
	emit_changed();
}

void PCGTransformNode::set_snap_to_ground(bool p_value) {
	snap_to_ground = p_value;
	emit_changed();
}

void PCGTransformNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_random_yaw", "value"), &PCGTransformNode::set_random_yaw);
	ClassDB::bind_method(D_METHOD("is_random_yaw"), &PCGTransformNode::is_random_yaw);
	ClassDB::bind_method(D_METHOD("set_scale_min", "value"), &PCGTransformNode::set_scale_min);
	ClassDB::bind_method(D_METHOD("get_scale_min"), &PCGTransformNode::get_scale_min);
	ClassDB::bind_method(D_METHOD("set_scale_max", "value"), &PCGTransformNode::set_scale_max);
	ClassDB::bind_method(D_METHOD("get_scale_max"), &PCGTransformNode::get_scale_max);
	ClassDB::bind_method(D_METHOD("set_offset_min", "value"), &PCGTransformNode::set_offset_min);
	ClassDB::bind_method(D_METHOD("get_offset_min"), &PCGTransformNode::get_offset_min);
	ClassDB::bind_method(D_METHOD("set_offset_max", "value"), &PCGTransformNode::set_offset_max);
	ClassDB::bind_method(D_METHOD("get_offset_max"), &PCGTransformNode::get_offset_max);
	ClassDB::bind_method(D_METHOD("set_snap_to_ground", "value"), &PCGTransformNode::set_snap_to_ground);
	ClassDB::bind_method(D_METHOD("is_snap_to_ground"), &PCGTransformNode::is_snap_to_ground);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "random_yaw"), "set_random_yaw", "is_random_yaw");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "scale_min", PROPERTY_HINT_RANGE, "0.01,10,0.01"), "set_scale_min", "get_scale_min");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "scale_max", PROPERTY_HINT_RANGE, "0.01,10,0.01"), "set_scale_max", "get_scale_max");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "offset_min"), "set_offset_min", "get_offset_min");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "offset_max"), "set_offset_max", "get_offset_max");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "snap_to_ground"), "set_snap_to_ground", "is_snap_to_ground");
}

// --- Merge -------------------------------------------------------------------------------------------------------

Ref<PCGData> PCGMergeNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out;
	out.instantiate();
	for (int i = 0; i < p_inputs.size(); i++) {
		Ref<PCGPointData> points = p_inputs[i];
		if (points.is_valid()) {
			out->append(points);
		}
	}
	return out;
}

void PCGMergeNode::set_input_count(int p_value) {
	input_count = CLAMP(p_value, 1, 16);
	emit_changed();
}

void PCGMergeNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_input_count", "value"), &PCGMergeNode::set_input_count);
	ClassDB::bind_method(D_METHOD("get_input_count_property"), &PCGMergeNode::get_input_count_property);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "input_count", PROPERTY_HINT_RANGE, "1,16,1"), "set_input_count", "get_input_count_property");
}

// --- Spline sampler ----------------------------------------------------------------------------------------------

Ref<PCGSplineData> PCGSplineSamplerNode::spline_from_variant(const Variant &p_value) {
	Ref<PCGSplineData> spline = p_value;
	if (spline.is_valid()) {
		return spline;
	}
	spline.instantiate();
	if (p_value.get_type() == Variant::PACKED_VECTOR3_ARRAY) {
		spline->add_polyline(p_value);
	} else if (p_value.get_type() == Variant::ARRAY) {
		const Array lines = p_value;
		for (int i = 0; i < lines.size(); i++) {
			if (lines[i].get_type() == Variant::PACKED_VECTOR3_ARRAY) {
				spline->add_polyline(lines[i]);
			} else if (lines[i].get_type() == Variant::DICTIONARY) {
				const Dictionary line = lines[i];
				spline->add_polyline(line.get("points", PackedVector3Array()), line.get("width", 0.0));
			}
		}
	}
	return spline;
}

Ref<PCGData> PCGSplineSamplerNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out;
	out.instantiate();
	Ref<PCGSplineData> spline;
	if (!p_inputs.is_empty()) {
		spline = p_inputs[0];
	}
	if (spline.is_null()) {
		spline = spline_from_variant(p_context->get_user_data().get(String(resolve("source_key", p_context)), Variant()));
	}
	const float step = MAX(0.25f, float(resolve("spacing", p_context)));
	const float lateral = resolve("lateral_offset", p_context);
	const bool two = resolve("both_sides", p_context);
	const bool along = resolve("face_along", p_context);
	const bool ground = resolve("project_to_ground", p_context);
	const AABB bounds = p_context->get_bounds();
	for (int l = 0; l < spline->get_polyline_count(); l++) {
		const PackedVector3Array line = spline->get_polyline(l);
		const float half_width = spline->get_width(l) * 0.5f;
		float travelled = 0.0;
		float next = step * 0.5f;
		for (int s = 1; s < line.size(); s++) {
			const Vector3 a = line[s - 1];
			const Vector3 b = line[s];
			const float length = a.distance_to(b);
			if (length <= 0.0001f) {
				continue;
			}
			const Vector3 dir = (b - a) / length;
			const Vector3 side = Vector3(-dir.z, 0, dir.x).normalized();
			while (next <= travelled + length) {
				const Vector3 base = a + dir * (next - travelled);
				const int sides = two ? 2 : 1;
				for (int k = 0; k < sides; k++) {
					const float sign = k == 0 ? 1.0f : -1.0f;
					Vector3 p = base + side * sign * (lateral + half_width);
					if (p.x < bounds.position.x || p.x >= bounds.position.x + bounds.size.x || p.z < bounds.position.z || p.z >= bounds.position.z + bounds.size.z) {
						continue;
					}
					if (ground) {
						p.y = p_context->sample_height(p.x, p.z);
					}
					// Seed from the polyline index, sample index and side: stable for the same spline.
					const uint64_t point_seed = pcg_mix64(pcg_mix64(pcg_mix64(p_seed, (uint64_t)l), (uint64_t)(int64_t)Math::round(next / step)), (uint64_t)k);
					const float facing = along ? Math::atan2(dir.x, dir.z) : 0.0f;
					out->add_point(p, ground ? p_context->sample_normal(p.x, p.z) : Vector3(0, 1, 0), 1.0, facing, 1.0, (int64_t)point_seed);
				}
				next += step;
			}
			travelled += length;
		}
	}
	return out;
}

void PCGSplineSamplerNode::set_source_key(const String &p_value) {
	source_key = p_value;
	emit_changed();
}

void PCGSplineSamplerNode::set_spacing(float p_value) {
	spacing = MAX(0.25f, p_value);
	emit_changed();
}

void PCGSplineSamplerNode::set_lateral_offset(float p_value) {
	lateral_offset = p_value;
	emit_changed();
}

void PCGSplineSamplerNode::set_both_sides(bool p_value) {
	both_sides = p_value;
	emit_changed();
}

void PCGSplineSamplerNode::set_face_along(bool p_value) {
	face_along = p_value;
	emit_changed();
}

void PCGSplineSamplerNode::set_project_to_ground(bool p_value) {
	project_to_ground = p_value;
	emit_changed();
}

void PCGSplineSamplerNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_source_key", "value"), &PCGSplineSamplerNode::set_source_key);
	ClassDB::bind_method(D_METHOD("get_source_key"), &PCGSplineSamplerNode::get_source_key);
	ClassDB::bind_method(D_METHOD("set_spacing", "value"), &PCGSplineSamplerNode::set_spacing);
	ClassDB::bind_method(D_METHOD("get_spacing"), &PCGSplineSamplerNode::get_spacing);
	ClassDB::bind_method(D_METHOD("set_lateral_offset", "value"), &PCGSplineSamplerNode::set_lateral_offset);
	ClassDB::bind_method(D_METHOD("get_lateral_offset"), &PCGSplineSamplerNode::get_lateral_offset);
	ClassDB::bind_method(D_METHOD("set_both_sides", "value"), &PCGSplineSamplerNode::set_both_sides);
	ClassDB::bind_method(D_METHOD("is_both_sides"), &PCGSplineSamplerNode::is_both_sides);
	ClassDB::bind_method(D_METHOD("set_face_along", "value"), &PCGSplineSamplerNode::set_face_along);
	ClassDB::bind_method(D_METHOD("is_face_along"), &PCGSplineSamplerNode::is_face_along);
	ClassDB::bind_method(D_METHOD("set_project_to_ground", "value"), &PCGSplineSamplerNode::set_project_to_ground);
	ClassDB::bind_method(D_METHOD("is_project_to_ground"), &PCGSplineSamplerNode::is_project_to_ground);
	ClassDB::bind_static_method("PCGSplineSamplerNode", D_METHOD("spline_from_variant", "value"), &PCGSplineSamplerNode::spline_from_variant);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "source_key"), "set_source_key", "get_source_key");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "spacing", PROPERTY_HINT_RANGE, "0.25,256,0.05,or_greater"), "set_spacing", "get_spacing");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lateral_offset"), "set_lateral_offset", "get_lateral_offset");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "both_sides"), "set_both_sides", "is_both_sides");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "face_along"), "set_face_along", "is_face_along");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "project_to_ground"), "set_project_to_ground", "is_project_to_ground");
}

// --- Point source ------------------------------------------------------------------------------------------------

Ref<PCGData> PCGPointSourceNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out;
	out.instantiate();
	const Variant source = p_context->get_user_data().get(String(resolve("source_key", p_context)), Variant());
	const bool clip = resolve("clip_to_bounds", p_context);
	const AABB bounds = p_context->get_bounds();
	Array items;
	if (source.get_type() == Variant::PACKED_VECTOR3_ARRAY) {
		const PackedVector3Array list = source;
		for (int i = 0; i < list.size(); i++) {
			items.push_back(list[i]);
		}
	} else if (source.get_type() == Variant::ARRAY) {
		items = source;
	}
	Vector<String> attribute_names;
	Vector<PackedFloat32Array> attribute_values;
	for (int i = 0; i < items.size(); i++) {
		Vector3 p;
		Dictionary extra;
		if (items[i].get_type() == Variant::VECTOR3) {
			p = items[i];
		} else if (items[i].get_type() == Variant::DICTIONARY) {
			extra = items[i];
			p = extra.get("position", Vector3());
		} else {
			continue;
		}
		if (clip && (p.x < bounds.position.x || p.x >= bounds.position.x + bounds.size.x || p.z < bounds.position.z || p.z >= bounds.position.z + bounds.size.z)) {
			continue;
		}
		const uint64_t point_seed = pcg_mix64(pcg_hash_double(pcg_hash_double(p_seed, p.x), p.z), (uint64_t)i);
		out->add_point(p, Vector3(0, 1, 0), float(extra.get("density", 1.0)), float(extra.get("yaw", 0.0)), float(extra.get("scale", 1.0)), (int64_t)point_seed);
		const int index = out->get_point_count() - 1;
		Array keys = extra.keys();
		for (int k = 0; k < keys.size(); k++) {
			const String key = keys[k];
			if (key == "position" || key == "density" || key == "yaw" || key == "scale") {
				continue;
			}
			const Variant value = extra[keys[k]];
			if (value.get_type() == Variant::FLOAT || value.get_type() == Variant::INT || value.get_type() == Variant::BOOL) {
				out->set_attribute_value(key, index, float(value));
			}
		}
	}
	return out;
}

void PCGPointSourceNode::set_source_key(const String &p_value) {
	source_key = p_value;
	emit_changed();
}

void PCGPointSourceNode::set_clip_to_bounds(bool p_value) {
	clip_to_bounds = p_value;
	emit_changed();
}

void PCGPointSourceNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_source_key", "value"), &PCGPointSourceNode::set_source_key);
	ClassDB::bind_method(D_METHOD("get_source_key"), &PCGPointSourceNode::get_source_key);
	ClassDB::bind_method(D_METHOD("set_clip_to_bounds", "value"), &PCGPointSourceNode::set_clip_to_bounds);
	ClassDB::bind_method(D_METHOD("is_clip_to_bounds"), &PCGPointSourceNode::is_clip_to_bounds);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "source_key"), "set_source_key", "get_source_key");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "clip_to_bounds"), "set_clip_to_bounds", "is_clip_to_bounds");
}

// --- Asset rules -------------------------------------------------------------------------------------------------

Ref<PCGData> PCGAssetRuleNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const Array table = resolve("rules", p_context);
	const bool drop = resolve("drop_unmatched", p_context);
	const String name = resolve("attribute", p_context);
	PackedInt32Array keep;
	PackedFloat32Array chosen;
	for (int i = 0; i < in->get_point_count(); i++) {
		const Vector3 p = in->get_position(i);
		const float slope = Math::rad_to_deg(Math::acos(CLAMP(in->get_normal(i).normalized().y, -1.0f, 1.0f)));
		String biome;
		bool biome_sampled = false;
		float total = 0.0;
		LocalVector<int> candidates;
		LocalVector<float> weights;
		for (int r = 0; r < table.size(); r++) {
			const Dictionary rule = table[r];
			const float weight = rule.get("weight", 1.0);
			if (weight <= 0.0f) {
				continue;
			}
			if (slope < float(rule.get("min_slope", 0.0)) || slope > float(rule.get("max_slope", 90.0))) {
				continue;
			}
			if (p.y < float(rule.get("min_height", -100000.0)) || p.y > float(rule.get("max_height", 100000.0))) {
				continue;
			}
			if (in->get_density(i) < float(rule.get("min_density", 0.0))) {
				continue;
			}
			const PackedStringArray rule_biomes = rule.get("biomes", PackedStringArray());
			if (!rule_biomes.is_empty()) {
				if (!biome_sampled) {
					biome = p_context->sample_biome(p.x, p.z);
					biome_sampled = true;
				}
				if (!rule_biomes.has(biome)) {
					continue;
				}
			}
			candidates.push_back(int(rule.get("asset", r)));
			weights.push_back(weight);
			total += weight;
		}
		if (candidates.is_empty()) {
			if (!drop) {
				keep.push_back(i);
				chosen.push_back(-1.0);
			}
			continue;
		}
		float pick = float(pcg_rand01(point_rand_seed(in->get_seed(i), p_seed))) * total;
		int asset = candidates[candidates.size() - 1];
		for (uint32_t c = 0; c < candidates.size(); c++) {
			pick -= weights[c];
			if (pick < 0.0f) {
				asset = candidates[c];
				break;
			}
		}
		keep.push_back(i);
		chosen.push_back(float(asset));
	}
	Ref<PCGPointData> out = in->select(keep);
	out->set_attribute(name, chosen);
	return out;
}

void PCGAssetRuleNode::set_rules(const Array &p_value) {
	rules = p_value;
	emit_changed();
}

void PCGAssetRuleNode::set_drop_unmatched(bool p_value) {
	drop_unmatched = p_value;
	emit_changed();
}

void PCGAssetRuleNode::set_attribute(const String &p_value) {
	attribute = p_value;
	emit_changed();
}

void PCGAssetRuleNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_rules", "value"), &PCGAssetRuleNode::set_rules);
	ClassDB::bind_method(D_METHOD("get_rules"), &PCGAssetRuleNode::get_rules);
	ClassDB::bind_method(D_METHOD("set_drop_unmatched", "value"), &PCGAssetRuleNode::set_drop_unmatched);
	ClassDB::bind_method(D_METHOD("is_drop_unmatched"), &PCGAssetRuleNode::is_drop_unmatched);
	ClassDB::bind_method(D_METHOD("set_attribute", "value"), &PCGAssetRuleNode::set_attribute);
	ClassDB::bind_method(D_METHOD("get_attribute"), &PCGAssetRuleNode::get_attribute);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "rules"), "set_rules", "get_rules");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "drop_unmatched"), "set_drop_unmatched", "is_drop_unmatched");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "attribute"), "set_attribute", "get_attribute");
}

// --- Clusters ----------------------------------------------------------------------------------------------------

int PCGClusterNode::cluster_id(const Vector3 &p_position, float p_size) {
	const float size = MAX(1.0f, p_size);
	const int cx = (int)Math::floor(p_position.x / size);
	const int cz = (int)Math::floor(p_position.z / size);
	// Fits a float attribute exactly (24-bit mantissa).
	return int(pcg_mix64((uint64_t)(int64_t)cx, (uint64_t)(int64_t)cz) & 0xFFFFFF);
}

Ref<PCGData> PCGClusterNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out = points_input(p_inputs, 0)->duplicate_points();
	const float size = resolve("cluster_size", p_context);
	PackedFloat32Array ids;
	ids.resize(out->get_point_count());
	for (int i = 0; i < out->get_point_count(); i++) {
		ids.set(i, float(cluster_id(out->get_position(i), size)));
	}
	out->set_attribute("cluster", ids);
	return out;
}

void PCGClusterNode::set_cluster_size(float p_value) {
	cluster_size = MAX(1.0f, p_value);
	emit_changed();
}

void PCGClusterNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cluster_size", "value"), &PCGClusterNode::set_cluster_size);
	ClassDB::bind_method(D_METHOD("get_cluster_size"), &PCGClusterNode::get_cluster_size);
	ClassDB::bind_static_method("PCGClusterNode", D_METHOD("cluster_id", "position", "size"), &PCGClusterNode::cluster_id);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cluster_size", PROPERTY_HINT_RANGE, "1,1024,1,or_greater"), "set_cluster_size", "get_cluster_size");
}

// --- Count limit -------------------------------------------------------------------------------------------------

Ref<PCGData> PCGCountLimitNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	const int limit = MAX(0, int(resolve("max_points", p_context)));
	if (in->get_point_count() <= limit) {
		return in;
	}
	LocalVector<int> order;
	for (int i = 0; i < in->get_point_count(); i++) {
		order.push_back(i);
	}
	struct Rank {
		const PCGPointData *points;
		uint64_t seed;
		bool operator()(int a, int b) const {
			const float da = points->get_density(a);
			const float db = points->get_density(b);
			if (da != db) {
				return da > db;
			}
			return point_rand_seed(points->get_seed(a), seed) < point_rand_seed(points->get_seed(b), seed);
		}
	};
	SortArray<int, Rank> rank_sort;
	rank_sort.compare = Rank{ in.ptr(), p_seed };
	rank_sort.sort(order.ptr(), order.size());
	PackedInt32Array keep;
	for (int i = 0; i < limit; i++) {
		keep.push_back(order[i]);
	}
	keep.sort();
	return in->select(keep);
}

void PCGCountLimitNode::set_max_points(int p_value) {
	max_points = MAX(0, p_value);
	emit_changed();
}

void PCGCountLimitNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_max_points", "value"), &PCGCountLimitNode::set_max_points);
	ClassDB::bind_method(D_METHOD("get_max_points"), &PCGCountLimitNode::get_max_points);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_points", PROPERTY_HINT_RANGE, "0,100000,1,or_greater"), "set_max_points", "get_max_points");
}

// --- Attribute set -----------------------------------------------------------------------------------------------

Ref<PCGData> PCGAttributeSetNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out = points_input(p_inputs, 0)->duplicate_points();
	PackedFloat32Array values;
	values.resize(out->get_point_count());
	values.fill(float(resolve("value", p_context)));
	out->set_attribute(String(resolve("attribute", p_context)), values);
	return out;
}

void PCGAttributeSetNode::set_attribute(const String &p_value) {
	attribute = p_value;
	emit_changed();
}

void PCGAttributeSetNode::set_value(float p_value) {
	value = p_value;
	emit_changed();
}

void PCGAttributeSetNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_attribute", "value"), &PCGAttributeSetNode::set_attribute);
	ClassDB::bind_method(D_METHOD("get_attribute"), &PCGAttributeSetNode::get_attribute);
	ClassDB::bind_method(D_METHOD("set_value", "value"), &PCGAttributeSetNode::set_value);
	ClassDB::bind_method(D_METHOD("get_value"), &PCGAttributeSetNode::get_value);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "attribute"), "set_attribute", "get_attribute");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "value"), "set_value", "get_value");
}

// --- Output ------------------------------------------------------------------------------------------------------

Ref<PCGData> PCGOutputNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	if (!p_inputs.is_empty() && p_inputs[0].is_valid()) {
		return p_inputs[0];
	}
	return Ref<PCGData>(memnew(PCGPointData));
}
