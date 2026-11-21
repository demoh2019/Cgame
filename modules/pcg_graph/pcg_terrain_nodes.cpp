/**************************************************************************/
/*  pcg_terrain_nodes.cpp                                                 */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_terrain_nodes.h"

#include "pcg_core_nodes.h"

#include "core/object/class_db.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "servers/rendering/rendering_device.h"
#include "servers/rendering/rendering_server.h"

namespace {

uint64_t mix2(uint64_t p_seed, int64_t p_a, int64_t p_b) {
	return pcg_mix64(pcg_mix64(p_seed, (uint64_t)p_a), (uint64_t)p_b);
}

uint64_t mix3(uint64_t p_seed, int64_t p_a, int64_t p_b, int64_t p_c) {
	return pcg_mix64(mix2(p_seed, p_a, p_b), (uint64_t)p_c);
}

int floor_div(int p_a, int p_b) {
	int q = p_a / p_b;
	if ((p_a % p_b != 0) && ((p_a < 0) != (p_b < 0))) {
		q--;
	}
	return q;
}

// Copies every float attribute of p_from to p_to (same point count and order).
void copy_attributes(const Ref<PCGPointData> &p_from, const Ref<PCGPointData> &p_to) {
	const PackedStringArray names = p_from->get_attribute_names();
	for (int i = 0; i < names.size(); i++) {
		p_to->set_attribute(StringName(names[i]), p_from->get_attribute(StringName(names[i])));
	}
}

// Uniform grid of points on XZ for radius queries.
struct PointGrid {
	float cell = 1.0;
	HashMap<Vector2i, LocalVector<int>> buckets;
	LocalVector<Vector3> points;

	Vector2i key(const Vector3 &p_position) const {
		return Vector2i((int)Math::floor(p_position.x / cell), (int)Math::floor(p_position.z / cell));
	}
	void insert(const Vector3 &p_position) {
		points.push_back(p_position);
		buckets[key(p_position)].push_back((int)points.size() - 1);
	}
	bool any_within(const Vector3 &p_position, float p_radius) const {
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
					const Vector3 q = points[index];
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

// Small deterministic generator (counter based, no global state).
struct CounterRng {
	uint64_t state = 0;
	explicit CounterRng(uint64_t p_seed) :
			state(p_seed) {}
	double next01() {
		state += 0x9e3779b97f4a7c15ULL;
		return pcg_rand01(state);
	}
	// Inclusive range.
	int range(int p_min, int p_max) {
		if (p_max <= p_min) {
			return p_min;
		}
		return p_min + (int)Math::floor(next01() * double(p_max - p_min + 1));
	}
};

} // namespace

// --- Heightfield -------------------------------------------------------------------------------------------------

Ref<PCGData> PCGHeightfieldNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out;
	out.instantiate();
	const float step = MAX(0.25f, float(resolve("spacing", p_context)));
	const float freq = MAX(0.00001f, float(resolve("frequency", p_context)));
	const int oct = CLAMP(int(resolve("octaves", p_context)), 1, 8);
	const float amp = resolve("amplitude", p_context);
	const float base = resolve("base_height", p_context);
	const bool ridge = resolve("ridged", p_context);
	const int terraces = MAX(0, int(resolve("terrace_steps", p_context)));
	const int iters = CLAMP(int(resolve("erosion_iterations", p_context)), 0, 64);
	const float talus = float(Math::tan(Math::deg_to_rad(double(CLAMP(float(resolve("talus_angle", p_context)), 1.0f, 89.0f))))) * step;
	const AABB bounds = p_context->get_bounds();
	const Vector3 lo = bounds.position;
	const Vector3 hi = bounds.position + bounds.size;

	// Output lattice cells, then a halo of (iterations + 1) cells: erosion is a radius-1 gather per
	// iteration, so the inner cells are exact and identical for any tiling of the same lattice.
	const int ox0 = (int)Math::floor(lo.x / step);
	const int ox1 = (int)Math::ceil(hi.x / step);
	const int oz0 = (int)Math::floor(lo.z / step);
	const int oz1 = (int)Math::ceil(hi.z / step);
	const int pad = iters + 1;
	const int gx0 = ox0 - pad;
	const int gz0 = oz0 - pad;
	const int gw = ox1 - ox0 + 1 + 2 * pad;
	const int gh = oz1 - oz0 + 1 + 2 * pad;
	ERR_FAIL_COND_V_MSG(int64_t(gw) * int64_t(gh) > 4000000, out, "PCG heightfield: spacing too small for the bounds.");

	LocalVector<float> height;
	height.resize((uint32_t)(gw * gh));
	for (int z = 0; z < gh; z++) {
		for (int x = 0; x < gw; x++) {
			const float wx = float(gx0 + x) * step;
			const float wz = float(gz0 + z) * step;
			float n = PCGDensityNoiseNode::value_noise(p_seed, wx, wz, freq, oct);
			if (ridge) {
				n = 1.0f - Math::abs(2.0f * n - 1.0f);
			}
			if (terraces > 0) {
				const float t = n * float(terraces);
				const float whole = Math::floor(t);
				const float frac = t - whole;
				n = (whole + frac * frac * (3.0f - 2.0f * frac)) / float(terraces);
			}
			height[z * gw + x] = base + n * amp;
		}
	}

	if (iters > 0) {
		LocalVector<float> next;
		next.resize(height.size());
		const int offsets[4][2] = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } };
		for (int it = 0; it < iters; it++) {
			for (int z = 0; z < gh; z++) {
				for (int x = 0; x < gw; x++) {
					const float h = height[z * gw + x];
					float delta = 0.0f;
					for (int k = 0; k < 4; k++) {
						const int nx = x + offsets[k][0];
						const int nz = z + offsets[k][1];
						if (nx < 0 || nz < 0 || nx >= gw || nz >= gh) {
							continue;
						}
						const float d = h - height[nz * gw + nx];
						if (d > talus) {
							delta -= 0.25f * (d - talus);
						} else if (-d > talus) {
							delta += 0.25f * (-d - talus);
						}
					}
					next[z * gw + x] = h + delta;
				}
			}
			for (uint32_t i = 0; i < height.size(); i++) {
				height[i] = next[i];
			}
		}
	}

	PackedFloat32Array height01;
	const float inv_amp = 1.0f / MAX(Math::abs(amp), 0.000001f);
	for (int iz = oz0; iz <= oz1; iz++) {
		for (int ix = ox0; ix <= ox1; ix++) {
			const float wx = float(ix) * step;
			const float wz = float(iz) * step;
			// Half-open bounds so neighbouring tiles never both own a point.
			if (wx < lo.x || wx >= hi.x || wz < lo.z || wz >= hi.z) {
				continue;
			}
			const int x = ix - gx0;
			const int z = iz - gz0;
			const float h = height[z * gw + x];
			const float hl = height[z * gw + x - 1];
			const float hr = height[z * gw + x + 1];
			const float hd = height[(z - 1) * gw + x];
			const float hu = height[(z + 1) * gw + x];
			const Vector3 normal = Vector3(hl - hr, 2.0f * step, hd - hu).normalized();
			out->add_point(Vector3(wx, h, wz), normal, 1.0, 0.0, 1.0, (int64_t)mix2(p_seed, ix, iz));
			height01.push_back(CLAMP((h - base) * inv_amp * (amp < 0.0f ? -1.0f : 1.0f), 0.0f, 1.0f));
		}
	}
	out->set_attribute("height01", height01);
	return out;
}

void PCGHeightfieldNode::set_spacing(float p_value) {
	spacing = MAX(0.25f, p_value);
	emit_changed();
}

void PCGHeightfieldNode::set_frequency(float p_value) {
	frequency = MAX(0.00001f, p_value);
	emit_changed();
}

void PCGHeightfieldNode::set_octaves(int p_value) {
	octaves = CLAMP(p_value, 1, 8);
	emit_changed();
}

void PCGHeightfieldNode::set_amplitude(float p_value) {
	amplitude = p_value;
	emit_changed();
}

void PCGHeightfieldNode::set_base_height(float p_value) {
	base_height = p_value;
	emit_changed();
}

void PCGHeightfieldNode::set_ridged(bool p_value) {
	ridged = p_value;
	emit_changed();
}

void PCGHeightfieldNode::set_terrace_steps(int p_value) {
	terrace_steps = MAX(0, p_value);
	emit_changed();
}

void PCGHeightfieldNode::set_erosion_iterations(int p_value) {
	erosion_iterations = CLAMP(p_value, 0, 64);
	emit_changed();
}

void PCGHeightfieldNode::set_talus_angle(float p_value) {
	talus_angle = CLAMP(p_value, 1.0f, 89.0f);
	emit_changed();
}

void PCGHeightfieldNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_spacing", "value"), &PCGHeightfieldNode::set_spacing);
	ClassDB::bind_method(D_METHOD("get_spacing"), &PCGHeightfieldNode::get_spacing);
	ClassDB::bind_method(D_METHOD("set_frequency", "value"), &PCGHeightfieldNode::set_frequency);
	ClassDB::bind_method(D_METHOD("get_frequency"), &PCGHeightfieldNode::get_frequency);
	ClassDB::bind_method(D_METHOD("set_octaves", "value"), &PCGHeightfieldNode::set_octaves);
	ClassDB::bind_method(D_METHOD("get_octaves"), &PCGHeightfieldNode::get_octaves);
	ClassDB::bind_method(D_METHOD("set_amplitude", "value"), &PCGHeightfieldNode::set_amplitude);
	ClassDB::bind_method(D_METHOD("get_amplitude"), &PCGHeightfieldNode::get_amplitude);
	ClassDB::bind_method(D_METHOD("set_base_height", "value"), &PCGHeightfieldNode::set_base_height);
	ClassDB::bind_method(D_METHOD("get_base_height"), &PCGHeightfieldNode::get_base_height);
	ClassDB::bind_method(D_METHOD("set_ridged", "value"), &PCGHeightfieldNode::set_ridged);
	ClassDB::bind_method(D_METHOD("is_ridged"), &PCGHeightfieldNode::is_ridged);
	ClassDB::bind_method(D_METHOD("set_terrace_steps", "value"), &PCGHeightfieldNode::set_terrace_steps);
	ClassDB::bind_method(D_METHOD("get_terrace_steps"), &PCGHeightfieldNode::get_terrace_steps);
	ClassDB::bind_method(D_METHOD("set_erosion_iterations", "value"), &PCGHeightfieldNode::set_erosion_iterations);
	ClassDB::bind_method(D_METHOD("get_erosion_iterations"), &PCGHeightfieldNode::get_erosion_iterations);
	ClassDB::bind_method(D_METHOD("set_talus_angle", "value"), &PCGHeightfieldNode::set_talus_angle);
	ClassDB::bind_method(D_METHOD("get_talus_angle"), &PCGHeightfieldNode::get_talus_angle);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "spacing", PROPERTY_HINT_RANGE, "0.25,256,0.05,or_greater"), "set_spacing", "get_spacing");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "frequency", PROPERTY_HINT_RANGE, "0.0001,1,0.0001,or_greater"), "set_frequency", "get_frequency");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "octaves", PROPERTY_HINT_RANGE, "1,8,1"), "set_octaves", "get_octaves");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "amplitude", PROPERTY_HINT_RANGE, "-1000,1000,0.1,or_less,or_greater"), "set_amplitude", "get_amplitude");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "base_height", PROPERTY_HINT_RANGE, "-1000,1000,0.1,or_less,or_greater"), "set_base_height", "get_base_height");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "ridged"), "set_ridged", "is_ridged");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "terrace_steps", PROPERTY_HINT_RANGE, "0,64,1,or_greater"), "set_terrace_steps", "get_terrace_steps");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "erosion_iterations", PROPERTY_HINT_RANGE, "0,64,1"), "set_erosion_iterations", "get_erosion_iterations");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "talus_angle", PROPERTY_HINT_RANGE, "1,89,0.5"), "set_talus_angle", "get_talus_angle");
}

// --- Terrain sample ----------------------------------------------------------------------------------------------

Ref<PCGData> PCGTerrainSampleNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	Ref<PCGPointData> out;
	out.instantiate();
	const float step = MAX(0.01f, float(resolve("normal_step", p_context)));
	PackedFloat32Array slope;
	PackedFloat32Array height;
	for (int i = 0; i < in->get_point_count(); i++) {
		const Vector3 p = in->get_position(i);
		const float y = p_context->sample_height(p.x, p.z);
		const Vector3 normal = p_context->sample_normal(p.x, p.z, step);
		out->add_point(Vector3(p.x, y, p.z), normal, in->get_density(i), in->get_yaw(i), in->get_scale(i), in->get_seed(i));
		slope.push_back(float(Math::rad_to_deg(Math::acos(CLAMP(double(normal.y), -1.0, 1.0)))));
		height.push_back(y);
	}
	copy_attributes(in, out);
	out->set_attribute("slope", slope);
	out->set_attribute("height", height);
	return out;
}

void PCGTerrainSampleNode::set_normal_step(float p_value) {
	normal_step = MAX(0.01f, p_value);
	emit_changed();
}

void PCGTerrainSampleNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_normal_step", "value"), &PCGTerrainSampleNode::set_normal_step);
	ClassDB::bind_method(D_METHOD("get_normal_step"), &PCGTerrainSampleNode::get_normal_step);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "normal_step", PROPERTY_HINT_RANGE, "0.01,16,0.01,or_greater"), "set_normal_step", "get_normal_step");
}

// --- Biome classify ----------------------------------------------------------------------------------------------

int PCGBiomeClassifyNode::classify(const Array &p_rules, float p_temperature, float p_moisture, int p_default) {
	for (int i = 0; i < p_rules.size(); i++) {
		if (p_rules[i].get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary rule = p_rules[i];
		const float min_t = rule.get("min_temp", Variant(-1.0e9f));
		const float max_t = rule.get("max_temp", Variant(1.0e9f));
		const float min_m = rule.get("min_moisture", Variant(-1.0e9f));
		const float max_m = rule.get("max_moisture", Variant(1.0e9f));
		if (p_temperature >= min_t && p_temperature <= max_t && p_moisture >= min_m && p_moisture <= max_m) {
			return int(rule.get("index", Variant(p_default)));
		}
	}
	return p_default;
}

Ref<PCGData> PCGBiomeClassifyNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out = points_input(p_inputs, 0)->duplicate_points();
	const float temp_freq = MAX(0.00001f, float(resolve("temperature_frequency", p_context)));
	const float moist_freq = MAX(0.00001f, float(resolve("moisture_frequency", p_context)));
	const int oct = CLAMP(int(resolve("noise_octaves", p_context)), 1, 8);
	const float lapse = resolve("lapse_rate", p_context);
	const Array rule_table = resolve("rules", p_context);
	const int fallback = resolve("default_biome", p_context);
	const bool from_context = resolve("use_context_biome", p_context);
	const Dictionary names = resolve("biome_names", p_context);
	const uint64_t temp_seed = pcg_mix64(p_seed, 0x7e3b1ULL);
	const uint64_t moist_seed = pcg_mix64(p_seed, 0x30157ULL);
	PackedFloat32Array biome;
	PackedFloat32Array temperature;
	PackedFloat32Array moisture;
	for (int i = 0; i < out->get_point_count(); i++) {
		const Vector3 p = out->get_position(i);
		const float t = PCGDensityNoiseNode::value_noise(temp_seed, p.x, p.z, temp_freq, oct) - lapse * MAX(0.0f, p.y);
		const float m = PCGDensityNoiseNode::value_noise(moist_seed, p.x, p.z, moist_freq, oct);
		int index = fallback;
		if (from_context) {
			const String name = p_context->sample_biome(p.x, p.z);
			if (names.has(name)) {
				index = int(names[name]);
			}
		} else {
			index = classify(rule_table, t, m, fallback);
		}
		biome.push_back(float(index));
		temperature.push_back(t);
		moisture.push_back(m);
	}
	out->set_attribute("biome", biome);
	out->set_attribute("temperature", temperature);
	out->set_attribute("moisture", moisture);
	return out;
}

void PCGBiomeClassifyNode::set_temperature_frequency(float p_value) {
	temperature_frequency = MAX(0.00001f, p_value);
	emit_changed();
}

void PCGBiomeClassifyNode::set_moisture_frequency(float p_value) {
	moisture_frequency = MAX(0.00001f, p_value);
	emit_changed();
}

void PCGBiomeClassifyNode::set_noise_octaves(int p_value) {
	noise_octaves = CLAMP(p_value, 1, 8);
	emit_changed();
}

void PCGBiomeClassifyNode::set_lapse_rate(float p_value) {
	lapse_rate = p_value;
	emit_changed();
}

void PCGBiomeClassifyNode::set_rules(const Array &p_value) {
	rules = p_value;
	emit_changed();
}

void PCGBiomeClassifyNode::set_default_biome(int p_value) {
	default_biome = p_value;
	emit_changed();
}

void PCGBiomeClassifyNode::set_use_context_biome(bool p_value) {
	use_context_biome = p_value;
	emit_changed();
}

void PCGBiomeClassifyNode::set_biome_names(const Dictionary &p_value) {
	biome_names = p_value;
	emit_changed();
}

void PCGBiomeClassifyNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_temperature_frequency", "value"), &PCGBiomeClassifyNode::set_temperature_frequency);
	ClassDB::bind_method(D_METHOD("get_temperature_frequency"), &PCGBiomeClassifyNode::get_temperature_frequency);
	ClassDB::bind_method(D_METHOD("set_moisture_frequency", "value"), &PCGBiomeClassifyNode::set_moisture_frequency);
	ClassDB::bind_method(D_METHOD("get_moisture_frequency"), &PCGBiomeClassifyNode::get_moisture_frequency);
	ClassDB::bind_method(D_METHOD("set_noise_octaves", "value"), &PCGBiomeClassifyNode::set_noise_octaves);
	ClassDB::bind_method(D_METHOD("get_noise_octaves"), &PCGBiomeClassifyNode::get_noise_octaves);
	ClassDB::bind_method(D_METHOD("set_lapse_rate", "value"), &PCGBiomeClassifyNode::set_lapse_rate);
	ClassDB::bind_method(D_METHOD("get_lapse_rate"), &PCGBiomeClassifyNode::get_lapse_rate);
	ClassDB::bind_method(D_METHOD("set_rules", "value"), &PCGBiomeClassifyNode::set_rules);
	ClassDB::bind_method(D_METHOD("get_rules"), &PCGBiomeClassifyNode::get_rules);
	ClassDB::bind_method(D_METHOD("set_default_biome", "value"), &PCGBiomeClassifyNode::set_default_biome);
	ClassDB::bind_method(D_METHOD("get_default_biome"), &PCGBiomeClassifyNode::get_default_biome);
	ClassDB::bind_method(D_METHOD("set_use_context_biome", "value"), &PCGBiomeClassifyNode::set_use_context_biome);
	ClassDB::bind_method(D_METHOD("is_use_context_biome"), &PCGBiomeClassifyNode::is_use_context_biome);
	ClassDB::bind_method(D_METHOD("set_biome_names", "value"), &PCGBiomeClassifyNode::set_biome_names);
	ClassDB::bind_method(D_METHOD("get_biome_names"), &PCGBiomeClassifyNode::get_biome_names);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "temperature_frequency", PROPERTY_HINT_RANGE, "0.0001,1,0.0001,or_greater"), "set_temperature_frequency", "get_temperature_frequency");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "moisture_frequency", PROPERTY_HINT_RANGE, "0.0001,1,0.0001,or_greater"), "set_moisture_frequency", "get_moisture_frequency");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "noise_octaves", PROPERTY_HINT_RANGE, "1,8,1"), "set_noise_octaves", "get_noise_octaves");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lapse_rate", PROPERTY_HINT_RANGE, "0,1,0.0001,or_greater"), "set_lapse_rate", "get_lapse_rate");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "rules"), "set_rules", "get_rules");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "default_biome"), "set_default_biome", "get_default_biome");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_context_biome"), "set_use_context_biome", "is_use_context_biome");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "biome_names"), "set_biome_names", "get_biome_names");
}

// --- Vegetation --------------------------------------------------------------------------------------------------

static Dictionary make_vegetation_layer(const String &p_name, float p_density, float p_spacing, float p_avoid, const Array &p_assets, float p_scale_min, float p_scale_max) {
	Dictionary layer;
	layer["name"] = p_name;
	layer["density"] = p_density;
	layer["min_spacing"] = p_spacing;
	layer["avoid_radius"] = p_avoid;
	layer["assets"] = p_assets;
	layer["scale_min"] = p_scale_min;
	layer["scale_max"] = p_scale_max;
	return layer;
}

PCGVegetationNode::PCGVegetationNode() {
	Array canopy_assets;
	canopy_assets.push_back(0);
	canopy_assets.push_back(1);
	Array understory_assets;
	understory_assets.push_back(2);
	understory_assets.push_back(3);
	Array ground_assets;
	ground_assets.push_back(4);
	layers.push_back(make_vegetation_layer("canopy", 0.3f, 6.0f, 0.0f, canopy_assets, 0.9f, 1.4f));
	layers.push_back(make_vegetation_layer("understory", 0.5f, 2.5f, 2.5f, understory_assets, 0.7f, 1.1f));
	layers.push_back(make_vegetation_layer("ground_cover", 0.8f, 0.8f, 1.0f, ground_assets, 0.5f, 1.0f));
}

namespace {
struct VegetationCandidate {
	uint64_t key;
	uint64_t seed;
	int index;
};
struct VegetationCandidateLess {
	bool operator()(const VegetationCandidate &a, const VegetationCandidate &b) const {
		if (a.key != b.key) {
			return a.key < b.key;
		}
		return a.index < b.index;
	}
};
} // namespace

Ref<PCGData> PCGVegetationNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> in = points_input(p_inputs, 0);
	Ref<PCGPointData> out;
	out.instantiate();
	const Array defs = resolve("layers", p_context);
	PackedFloat32Array asset_attr;
	PackedFloat32Array layer_attr;
	PointGrid placed; // Points of every earlier layer.
	placed.cell = 4.0f;
	for (int l = 0; l < defs.size(); l++) {
		if (defs[l].get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary def = defs[l];
		const float density = CLAMP(float(def.get("density", Variant(1.0f))), 0.0f, 1.0f);
		const float spacing = MAX(0.0f, float(def.get("min_spacing", Variant(0.0f))));
		const float avoid = MAX(0.0f, float(def.get("avoid_radius", Variant(0.0f))));
		const float scale_min = def.get("scale_min", Variant(1.0f));
		const float scale_max = def.get("scale_max", Variant(1.0f));
		const Array assets = def.get("assets", Variant(Array()));
		const uint64_t layer_seed = pcg_mix64(p_seed, (uint64_t)l + 0x51ULL);

		LocalVector<VegetationCandidate> candidates;
		for (int i = 0; i < in->get_point_count(); i++) {
			const uint64_t rs = pcg_mix64((uint64_t)in->get_seed(i), layer_seed);
			if (pcg_rand01(rs) >= double(density) * double(in->get_density(i))) {
				continue;
			}
			VegetationCandidate c;
			c.key = pcg_mix64(rs, 7);
			c.seed = rs;
			c.index = i;
			candidates.push_back(c);
		}
		candidates.sort_custom<VegetationCandidateLess>();

		PointGrid own;
		own.cell = MAX(0.5f, spacing);
		LocalVector<VegetationCandidate> accepted;
		for (const VegetationCandidate &c : candidates) {
			const Vector3 p = in->get_position(c.index);
			if (avoid > 0.0f && placed.any_within(p, avoid)) {
				continue;
			}
			if (spacing > 0.0f && own.any_within(p, spacing)) {
				continue;
			}
			own.insert(p);
			accepted.push_back(c);
		}

		for (const VegetationCandidate &c : accepted) {
			const Vector3 p = in->get_position(c.index);
			const float yaw = float(pcg_rand01(pcg_mix64(c.seed, 1)) * Math::TAU);
			const float scale = Math::lerp(scale_min, scale_max, float(pcg_rand01(pcg_mix64(c.seed, 3))));
			out->add_point(p, in->get_normal(c.index), 1.0, yaw, scale, (int64_t)c.seed);
			float asset = -1.0f;
			if (!assets.is_empty()) {
				const int pick = MIN((int)Math::floor(pcg_rand01(pcg_mix64(c.seed, 2)) * double(assets.size())), assets.size() - 1);
				asset = float(int(assets[pick]));
			}
			asset_attr.push_back(asset);
			layer_attr.push_back(float(l));
			placed.insert(p);
		}
	}
	out->set_attribute("asset", asset_attr);
	out->set_attribute("layer", layer_attr);
	return out;
}

void PCGVegetationNode::set_layers(const Array &p_value) {
	layers = p_value;
	emit_changed();
}

void PCGVegetationNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_layers", "value"), &PCGVegetationNode::set_layers);
	ClassDB::bind_method(D_METHOD("get_layers"), &PCGVegetationNode::get_layers);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "layers"), "set_layers", "get_layers");
}

// --- Caves -------------------------------------------------------------------------------------------------------

Ref<PCGData> PCGCaveNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out;
	out.instantiate();
	const float vs = MAX(0.1f, float(resolve("voxel_size", p_context)));
	const float fill = CLAMP(float(resolve("fill_percent", p_context)), 0.0f, 1.0f);
	const int iters = CLAMP(int(resolve("iterations", p_context)), 0, 16);
	const int birth = CLAMP(int(resolve("birth_limit", p_context)), 0, 26);
	const int survival = CLAMP(int(resolve("survival_limit", p_context)), 0, 26);
	const int worms = CLAMP(int(resolve("worms_per_region", p_context)), 0, 16);
	const int worm_len = CLAMP(int(resolve("worm_length", p_context)), 1, 512);
	const float worm_rad = CLAMP(float(resolve("worm_radius", p_context)), 0.5f, 8.0f);
	const int region = CLAMP(int(resolve("worm_region", p_context)), 8, 256);
	const AABB bounds = p_context->get_bounds();
	const Vector3 lo = bounds.position;
	const Vector3 hi = bounds.position + bounds.size;

	// Output voxel range, then a halo of (iterations + 1): each automaton step reads radius 1, so the inner
	// voxels equal the ones of any other bounds sharing the voxel lattice.
	const int ix0 = (int)Math::floor(lo.x / vs - 0.5f);
	const int ix1 = (int)Math::ceil(hi.x / vs - 0.5f);
	const int iy0 = (int)Math::floor(lo.y / vs - 0.5f);
	const int iy1 = (int)Math::ceil(hi.y / vs - 0.5f);
	const int iz0 = (int)Math::floor(lo.z / vs - 0.5f);
	const int iz1 = (int)Math::ceil(hi.z / vs - 0.5f);
	const int pad = iters + 1;
	const int gx0 = ix0 - pad;
	const int gy0 = iy0 - pad;
	const int gz0 = iz0 - pad;
	const int gw = ix1 - ix0 + 1 + 2 * pad;
	const int gh = iy1 - iy0 + 1 + 2 * pad;
	const int gd = iz1 - iz0 + 1 + 2 * pad;
	const int64_t total = int64_t(gw) * int64_t(gh) * int64_t(gd);
	ERR_FAIL_COND_V_MSG(total <= 0 || total > 3000000, out, "PCG cave: voxel grid too large for the bounds.");

	const uint64_t cave_seed = pcg_mix64(p_seed, 0xCA7EULL);
	LocalVector<uint8_t> solid;
	solid.resize((uint32_t)total);
	for (int z = 0; z < gd; z++) {
		for (int y = 0; y < gh; y++) {
			for (int x = 0; x < gw; x++) {
				const uint64_t s = mix3(cave_seed, gx0 + x, gy0 + y, gz0 + z);
				solid[(z * gh + y) * gw + x] = pcg_rand01(s) < double(fill) ? 1 : 0;
			}
		}
	}

	if (iters > 0) {
		LocalVector<uint8_t> next;
		next.resize(solid.size());
		for (int it = 0; it < iters; it++) {
			for (int z = 0; z < gd; z++) {
				for (int y = 0; y < gh; y++) {
					for (int x = 0; x < gw; x++) {
						int count = 0;
						for (int dz = -1; dz <= 1; dz++) {
							for (int dy = -1; dy <= 1; dy++) {
								for (int dx = -1; dx <= 1; dx++) {
									if (dx == 0 && dy == 0 && dz == 0) {
										continue;
									}
									const int nx = x + dx;
									const int ny = y + dy;
									const int nz = z + dz;
									if (nx < 0 || ny < 0 || nz < 0 || nx >= gw || ny >= gh || nz >= gd) {
										continue;
									}
									count += solid[(nz * gh + ny) * gw + nx];
								}
							}
						}
						const int idx = (z * gh + y) * gw + x;
						next[idx] = solid[idx] ? (count >= survival ? 1 : 0) : (count >= birth ? 1 : 0);
					}
				}
			}
			for (uint32_t i = 0; i < solid.size(); i++) {
				solid[i] = next[i];
			}
		}
	}

	// Worm tunnels: start points live on a world lattice of "region" voxels, so every bounds that
	// touches a worm carves exactly the same tunnel.
	if (worms > 0) {
		const int reach = worm_len + (int)Math::ceil(worm_rad) + 2;
		const int rx0 = floor_div(gx0 - reach, region);
		const int rx1 = floor_div(gx0 + gw - 1 + reach, region);
		const int ry0 = floor_div(gy0 - reach, region);
		const int ry1 = floor_div(gy0 + gh - 1 + reach, region);
		const int rz0 = floor_div(gz0 - reach, region);
		const int rz1 = floor_div(gz0 + gd - 1 + reach, region);
		const int64_t region_count = int64_t(rx1 - rx0 + 1) * int64_t(ry1 - ry0 + 1) * int64_t(rz1 - rz0 + 1);
		ERR_FAIL_COND_V_MSG(region_count * worms > 200000, out, "PCG cave: too many worm regions for the bounds.");
		const uint64_t worm_seed = pcg_mix64(cave_seed, 0x3017ULL);
		for (int rz = rz0; rz <= rz1; rz++) {
			for (int ry = ry0; ry <= ry1; ry++) {
				for (int rx = rx0; rx <= rx1; rx++) {
					for (int w = 0; w < worms; w++) {
						const uint64_t ws = pcg_mix64(mix3(worm_seed, rx, ry, rz), (uint64_t)w);
						Vector3 p(
								float(rx * region) + float(pcg_rand01(pcg_mix64(ws, 1))) * float(region),
								float(ry * region) + float(pcg_rand01(pcg_mix64(ws, 2))) * float(region),
								float(rz * region) + float(pcg_rand01(pcg_mix64(ws, 3))) * float(region));
						Vector3 dir(float(pcg_rand01(pcg_mix64(ws, 4))) - 0.5f, (float(pcg_rand01(pcg_mix64(ws, 5))) - 0.5f) * 0.5f, float(pcg_rand01(pcg_mix64(ws, 6))) - 0.5f);
						if (dir.length_squared() < 0.0001f) {
							dir = Vector3(1, 0, 0);
						}
						dir.normalize();
						for (int s = 0; s < worm_len; s++) {
							const uint64_t ss = pcg_mix64(ws, 100 + (uint64_t)s);
							const Vector3 jitter(float(pcg_rand01(pcg_mix64(ss, 1))) - 0.5f, float(pcg_rand01(pcg_mix64(ss, 2))) - 0.5f, float(pcg_rand01(pcg_mix64(ss, 3))) - 0.5f);
							dir += jitter * 0.7f;
							if (dir.length_squared() < 0.0001f) {
								dir = Vector3(1, 0, 0);
							}
							dir.normalize();
							p += dir;
							const int cx0 = MAX(gx0, (int)Math::floor(p.x - worm_rad));
							const int cx1 = MIN(gx0 + gw - 1, (int)Math::ceil(p.x + worm_rad));
							const int cy0 = MAX(gy0, (int)Math::floor(p.y - worm_rad));
							const int cy1 = MIN(gy0 + gh - 1, (int)Math::ceil(p.y + worm_rad));
							const int cz0 = MAX(gz0, (int)Math::floor(p.z - worm_rad));
							const int cz1 = MIN(gz0 + gd - 1, (int)Math::ceil(p.z + worm_rad));
							for (int cz = cz0; cz <= cz1; cz++) {
								for (int cy = cy0; cy <= cy1; cy++) {
									for (int cx = cx0; cx <= cx1; cx++) {
										const Vector3 c(float(cx) + 0.5f, float(cy) + 0.5f, float(cz) + 0.5f);
										if (c.distance_squared_to(p) <= worm_rad * worm_rad) {
											solid[((cz - gz0) * gh + (cy - gy0)) * gw + (cx - gx0)] = 0;
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}

	PackedFloat32Array floor_attr;
	PackedFloat32Array wall_attr;
	for (int iz = iz0; iz <= iz1; iz++) {
		for (int iy = iy0; iy <= iy1; iy++) {
			for (int ix = ix0; ix <= ix1; ix++) {
				const Vector3 center((float(ix) + 0.5f) * vs, (float(iy) + 0.5f) * vs, (float(iz) + 0.5f) * vs);
				if (center.x < lo.x || center.x >= hi.x || center.y < lo.y || center.y >= hi.y || center.z < lo.z || center.z >= hi.z) {
					continue;
				}
				const int x = ix - gx0;
				const int y = iy - gy0;
				const int z = iz - gz0;
				if (solid[(z * gh + y) * gw + x]) {
					continue;
				}
				const bool sxm = solid[(z * gh + y) * gw + x - 1];
				const bool sxp = solid[(z * gh + y) * gw + x + 1];
				const bool sym = solid[(z * gh + y - 1) * gw + x];
				const bool syp = solid[(z * gh + y + 1) * gw + x];
				const bool szm = solid[((z - 1) * gh + y) * gw + x];
				const bool szp = solid[((z + 1) * gh + y) * gw + x];
				if (!(sxm || sxp || sym || syp || szm || szp)) {
					continue;
				}
				Vector3 normal;
				normal.x = (sxm ? 1.0f : 0.0f) - (sxp ? 1.0f : 0.0f);
				normal.y = (sym ? 1.0f : 0.0f) - (syp ? 1.0f : 0.0f);
				normal.z = (szm ? 1.0f : 0.0f) - (szp ? 1.0f : 0.0f);
				if (normal.length_squared() < 0.0001f) {
					normal = Vector3(0, 1, 0);
				}
				normal.normalize();
				out->add_point(center, normal, 1.0, 0.0, 1.0, (int64_t)mix3(p_seed, ix, iy, iz));
				floor_attr.push_back(sym ? 1.0f : 0.0f);
				wall_attr.push_back((sxm || sxp || szm || szp) ? 1.0f : 0.0f);
			}
		}
	}
	out->set_attribute("cave_floor", floor_attr);
	out->set_attribute("cave_wall", wall_attr);
	return out;
}

void PCGCaveNode::set_voxel_size(float p_value) {
	voxel_size = MAX(0.1f, p_value);
	emit_changed();
}

void PCGCaveNode::set_fill_percent(float p_value) {
	fill_percent = CLAMP(p_value, 0.0f, 1.0f);
	emit_changed();
}

void PCGCaveNode::set_iterations(int p_value) {
	iterations = CLAMP(p_value, 0, 16);
	emit_changed();
}

void PCGCaveNode::set_birth_limit(int p_value) {
	birth_limit = CLAMP(p_value, 0, 26);
	emit_changed();
}

void PCGCaveNode::set_survival_limit(int p_value) {
	survival_limit = CLAMP(p_value, 0, 26);
	emit_changed();
}

void PCGCaveNode::set_worms_per_region(int p_value) {
	worms_per_region = CLAMP(p_value, 0, 16);
	emit_changed();
}

void PCGCaveNode::set_worm_length(int p_value) {
	worm_length = CLAMP(p_value, 1, 512);
	emit_changed();
}

void PCGCaveNode::set_worm_radius(float p_value) {
	worm_radius = CLAMP(p_value, 0.5f, 8.0f);
	emit_changed();
}

void PCGCaveNode::set_worm_region(int p_value) {
	worm_region = CLAMP(p_value, 8, 256);
	emit_changed();
}

void PCGCaveNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_voxel_size", "value"), &PCGCaveNode::set_voxel_size);
	ClassDB::bind_method(D_METHOD("get_voxel_size"), &PCGCaveNode::get_voxel_size);
	ClassDB::bind_method(D_METHOD("set_fill_percent", "value"), &PCGCaveNode::set_fill_percent);
	ClassDB::bind_method(D_METHOD("get_fill_percent"), &PCGCaveNode::get_fill_percent);
	ClassDB::bind_method(D_METHOD("set_iterations", "value"), &PCGCaveNode::set_iterations);
	ClassDB::bind_method(D_METHOD("get_iterations"), &PCGCaveNode::get_iterations);
	ClassDB::bind_method(D_METHOD("set_birth_limit", "value"), &PCGCaveNode::set_birth_limit);
	ClassDB::bind_method(D_METHOD("get_birth_limit"), &PCGCaveNode::get_birth_limit);
	ClassDB::bind_method(D_METHOD("set_survival_limit", "value"), &PCGCaveNode::set_survival_limit);
	ClassDB::bind_method(D_METHOD("get_survival_limit"), &PCGCaveNode::get_survival_limit);
	ClassDB::bind_method(D_METHOD("set_worms_per_region", "value"), &PCGCaveNode::set_worms_per_region);
	ClassDB::bind_method(D_METHOD("get_worms_per_region"), &PCGCaveNode::get_worms_per_region);
	ClassDB::bind_method(D_METHOD("set_worm_length", "value"), &PCGCaveNode::set_worm_length);
	ClassDB::bind_method(D_METHOD("get_worm_length"), &PCGCaveNode::get_worm_length);
	ClassDB::bind_method(D_METHOD("set_worm_radius", "value"), &PCGCaveNode::set_worm_radius);
	ClassDB::bind_method(D_METHOD("get_worm_radius"), &PCGCaveNode::get_worm_radius);
	ClassDB::bind_method(D_METHOD("set_worm_region", "value"), &PCGCaveNode::set_worm_region);
	ClassDB::bind_method(D_METHOD("get_worm_region"), &PCGCaveNode::get_worm_region);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "voxel_size", PROPERTY_HINT_RANGE, "0.1,16,0.05,or_greater"), "set_voxel_size", "get_voxel_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "fill_percent", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_fill_percent", "get_fill_percent");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations", PROPERTY_HINT_RANGE, "0,16,1"), "set_iterations", "get_iterations");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "birth_limit", PROPERTY_HINT_RANGE, "0,26,1"), "set_birth_limit", "get_birth_limit");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "survival_limit", PROPERTY_HINT_RANGE, "0,26,1"), "set_survival_limit", "get_survival_limit");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "worms_per_region", PROPERTY_HINT_RANGE, "0,16,1"), "set_worms_per_region", "get_worms_per_region");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "worm_length", PROPERTY_HINT_RANGE, "1,512,1"), "set_worm_length", "get_worm_length");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "worm_radius", PROPERTY_HINT_RANGE, "0.5,8,0.1"), "set_worm_radius", "get_worm_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "worm_region", PROPERTY_HINT_RANGE, "8,256,1"), "set_worm_region", "get_worm_region");
}

// --- Dungeon -----------------------------------------------------------------------------------------------------

namespace {
struct BSPNode {
	Rect2i area;
	int left = -1;
	int right = -1;
	int room = -1;
};

void bsp_split(LocalVector<BSPNode> &r_nodes, int p_index, int p_depth, CounterRng &r_rng, int p_min_leaf, int p_max_depth) {
	const Rect2i a = r_nodes[p_index].area;
	const bool can_cut_x = a.size.x >= 2 * p_min_leaf;
	const bool can_cut_y = a.size.y >= 2 * p_min_leaf;
	if (p_depth >= p_max_depth || (!can_cut_x && !can_cut_y)) {
		return;
	}
	bool cut_x = can_cut_x;
	if (can_cut_x && can_cut_y) {
		if (float(a.size.x) > float(a.size.y) * 1.25f) {
			cut_x = true;
		} else if (float(a.size.y) > float(a.size.x) * 1.25f) {
			cut_x = false;
		} else {
			cut_x = r_rng.next01() < 0.5;
		}
	}
	BSPNode first;
	BSPNode second;
	if (cut_x) {
		const int cut = r_rng.range(p_min_leaf, a.size.x - p_min_leaf);
		first.area = Rect2i(a.position.x, a.position.y, cut, a.size.y);
		second.area = Rect2i(a.position.x + cut, a.position.y, a.size.x - cut, a.size.y);
	} else {
		const int cut = r_rng.range(p_min_leaf, a.size.y - p_min_leaf);
		first.area = Rect2i(a.position.x, a.position.y, a.size.x, cut);
		second.area = Rect2i(a.position.x, a.position.y + cut, a.size.x, a.size.y - cut);
	}
	const int li = (int)r_nodes.size();
	r_nodes.push_back(first);
	const int ri = (int)r_nodes.size();
	r_nodes.push_back(second);
	r_nodes[p_index].left = li;
	r_nodes[p_index].right = ri;
	bsp_split(r_nodes, li, p_depth + 1, r_rng, p_min_leaf, p_max_depth);
	bsp_split(r_nodes, ri, p_depth + 1, r_rng, p_min_leaf, p_max_depth);
}

int bsp_pick_room(const LocalVector<BSPNode> &p_nodes, int p_index, CounterRng &r_rng) {
	int index = p_index;
	while (p_nodes[index].room < 0 && p_nodes[index].left >= 0) {
		index = r_rng.next01() < 0.5 ? p_nodes[index].left : p_nodes[index].right;
	}
	return p_nodes[index].room;
}
} // namespace

Dictionary PCGDungeonNode::generate_layout(int64_t p_seed, const Rect2i &p_rect, int p_min_room, int p_max_room, int p_max_depth, int p_padding) {
	Array rooms;
	Array corridors;
	const int pad = MAX(0, p_padding);
	const int min_room = MAX(1, p_min_room);
	const int max_room = MAX(min_room, p_max_room);
	const int min_leaf = min_room + 2 * pad;
	CounterRng rng(pcg_mix64((uint64_t)p_seed, 0xD06E0ULL));

	LocalVector<BSPNode> nodes;
	BSPNode root;
	root.area = p_rect;
	nodes.push_back(root);
	bsp_split(nodes, 0, 0, rng, min_leaf, MAX(0, p_max_depth));

	// One room per leaf; a leaf keeps `pad` free tiles on every side, so rooms of different leaves never touch.
	for (uint32_t i = 0; i < nodes.size(); i++) {
		if (nodes[i].left >= 0) {
			continue;
		}
		const Rect2i a = nodes[i].area;
		const int free_w = a.size.x - 2 * pad;
		const int free_h = a.size.y - 2 * pad;
		if (free_w < min_room || free_h < min_room) {
			continue;
		}
		const int rw = rng.range(min_room, MIN(max_room, free_w));
		const int rh = rng.range(min_room, MIN(max_room, free_h));
		const int rx = a.position.x + pad + rng.range(0, free_w - rw);
		const int ry = a.position.y + pad + rng.range(0, free_h - rh);
		nodes[i].room = rooms.size();
		rooms.push_back(Rect2i(rx, ry, rw, rh));
	}

	// Every internal node joins one room of each child subtree: by induction all rooms are connected.
	for (uint32_t i = 0; i < nodes.size(); i++) {
		if (nodes[i].left < 0) {
			continue;
		}
		const int room_a = bsp_pick_room(nodes, nodes[i].left, rng);
		const int room_b = bsp_pick_room(nodes, nodes[i].right, rng);
		if (room_a < 0 || room_b < 0) {
			continue;
		}
		const Rect2i ra = rooms[room_a];
		const Rect2i rb = rooms[room_b];
		const Vector2i a = ra.position + ra.size / 2;
		const Vector2i b = rb.position + rb.size / 2;
		const Vector2i corner = rng.next01() < 0.5 ? Vector2i(b.x, a.y) : Vector2i(a.x, b.y);
		PackedVector2Array path;
		path.push_back(Vector2(a.x, a.y));
		path.push_back(Vector2(corner.x, corner.y));
		path.push_back(Vector2(b.x, b.y));
		corridors.push_back(path);
	}

	Dictionary result;
	result["rooms"] = rooms;
	result["corridors"] = corridors;
	return result;
}

Ref<PCGData> PCGDungeonNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out;
	out.instantiate();
	const float tile = MAX(0.1f, float(resolve("tile_size", p_context)));
	const int min_room = resolve("min_room_size", p_context);
	const int max_room = resolve("max_room_size", p_context);
	const int depth = resolve("max_depth", p_context);
	const int pad = resolve("padding", p_context);
	const AABB bounds = p_context->get_bounds();
	const Rect2i rect((int)Math::floor(bounds.position.x / tile), (int)Math::floor(bounds.position.z / tile), (int)Math::floor(bounds.size.x / tile), (int)Math::floor(bounds.size.z / tile));
	ERR_FAIL_COND_V_MSG(int64_t(rect.size.x) * int64_t(rect.size.y) > 4000000, out, "PCG dungeon: tile size too small for the bounds.");
	const Dictionary layout = generate_layout((int64_t)p_seed, rect, min_room, max_room, depth, pad);
	const Array rooms = layout["rooms"];
	const Array corridors = layout["corridors"];

	HashMap<Vector2i, int> room_of;
	LocalVector<Vector2i> room_tiles;
	for (int id = 0; id < rooms.size(); id++) {
		const Rect2i r = rooms[id];
		for (int y = r.position.y; y < r.position.y + r.size.y; y++) {
			for (int x = r.position.x; x < r.position.x + r.size.x; x++) {
				room_of[Vector2i(x, y)] = id;
				room_tiles.push_back(Vector2i(x, y));
			}
		}
	}
	HashMap<Vector2i, int> corridor_seen;
	LocalVector<Vector2i> corridor_tiles;
	for (int c = 0; c < corridors.size(); c++) {
		const PackedVector2Array path = corridors[c];
		for (int k = 0; k + 1 < path.size(); k++) {
			Vector2i cell((int)path[k].x, (int)path[k].y);
			const Vector2i end((int)path[k + 1].x, (int)path[k + 1].y);
			const Vector2i dir(end.x > cell.x ? 1 : (end.x < cell.x ? -1 : 0), end.y > cell.y ? 1 : (end.y < cell.y ? -1 : 0));
			for (int guard = 0; guard < 1000000; guard++) {
				if (!room_of.has(cell) && !corridor_seen.has(cell)) {
					corridor_seen[cell] = 1;
					corridor_tiles.push_back(cell);
				}
				if (cell == end || (dir.x == 0 && dir.y == 0)) {
					break;
				}
				cell += dir;
			}
		}
	}

	PackedFloat32Array room_attr;
	PackedFloat32Array kind_attr;
	const float y = bounds.position.y;
	for (const Vector2i &cell : room_tiles) {
		out->add_point(Vector3((float(cell.x) + 0.5f) * tile, y, (float(cell.y) + 0.5f) * tile), Vector3(0, 1, 0), 1.0, 0.0, 1.0, (int64_t)mix2(p_seed, cell.x, cell.y));
		room_attr.push_back(float(room_of[cell]));
		kind_attr.push_back(0.0f);
	}
	const Vector2i neighbours[4] = { Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1) };
	for (const Vector2i &cell : corridor_tiles) {
		int door_room = -1;
		for (int k = 0; k < 4; k++) {
			const Vector2i n = cell + neighbours[k];
			if (room_of.has(n)) {
				door_room = room_of[n];
				break;
			}
		}
		out->add_point(Vector3((float(cell.x) + 0.5f) * tile, y, (float(cell.y) + 0.5f) * tile), Vector3(0, 1, 0), 1.0, 0.0, 1.0, (int64_t)mix2(p_seed, cell.x, cell.y));
		room_attr.push_back(float(door_room));
		kind_attr.push_back(door_room >= 0 ? 1.0f : 2.0f);
	}
	out->set_attribute("room", room_attr);
	out->set_attribute("kind", kind_attr);
	return out;
}

void PCGDungeonNode::set_tile_size(float p_value) {
	tile_size = MAX(0.1f, p_value);
	emit_changed();
}

void PCGDungeonNode::set_min_room_size(int p_value) {
	min_room_size = MAX(1, p_value);
	emit_changed();
}

void PCGDungeonNode::set_max_room_size(int p_value) {
	max_room_size = MAX(1, p_value);
	emit_changed();
}

void PCGDungeonNode::set_max_depth(int p_value) {
	max_depth = CLAMP(p_value, 0, 12);
	emit_changed();
}

void PCGDungeonNode::set_padding(int p_value) {
	padding = MAX(0, p_value);
	emit_changed();
}

void PCGDungeonNode::_bind_methods() {
	ClassDB::bind_static_method("PCGDungeonNode", D_METHOD("generate_layout", "seed", "rect", "min_room", "max_room", "max_depth", "padding"), &PCGDungeonNode::generate_layout, DEFVAL(4), DEFVAL(10), DEFVAL(4), DEFVAL(1));
	ClassDB::bind_method(D_METHOD("set_tile_size", "value"), &PCGDungeonNode::set_tile_size);
	ClassDB::bind_method(D_METHOD("get_tile_size"), &PCGDungeonNode::get_tile_size);
	ClassDB::bind_method(D_METHOD("set_min_room_size", "value"), &PCGDungeonNode::set_min_room_size);
	ClassDB::bind_method(D_METHOD("get_min_room_size"), &PCGDungeonNode::get_min_room_size);
	ClassDB::bind_method(D_METHOD("set_max_room_size", "value"), &PCGDungeonNode::set_max_room_size);
	ClassDB::bind_method(D_METHOD("get_max_room_size"), &PCGDungeonNode::get_max_room_size);
	ClassDB::bind_method(D_METHOD("set_max_depth", "value"), &PCGDungeonNode::set_max_depth);
	ClassDB::bind_method(D_METHOD("get_max_depth"), &PCGDungeonNode::get_max_depth);
	ClassDB::bind_method(D_METHOD("set_padding", "value"), &PCGDungeonNode::set_padding);
	ClassDB::bind_method(D_METHOD("get_padding"), &PCGDungeonNode::get_padding);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tile_size", PROPERTY_HINT_RANGE, "0.1,16,0.05,or_greater"), "set_tile_size", "get_tile_size");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "min_room_size", PROPERTY_HINT_RANGE, "1,64,1,or_greater"), "set_min_room_size", "get_min_room_size");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_room_size", PROPERTY_HINT_RANGE, "1,128,1,or_greater"), "set_max_room_size", "get_max_room_size");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_depth", PROPERTY_HINT_RANGE, "0,12,1"), "set_max_depth", "get_max_depth");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "padding", PROPERTY_HINT_RANGE, "0,8,1,or_greater"), "set_padding", "get_padding");
}

// --- GPU density -------------------------------------------------------------------------------------------------

namespace {

// 64-bit arithmetic of pcg_mix64 emulated on uvec2 (x = low word, y = high word), so the shader walks
// exactly the same lattice hashes as PCGDensityNoiseNode::value_noise.
const char *GPU_NOISE_SHADER = R"(#version 450
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Positions {
	float xz[];
} positions;

layout(set = 0, binding = 1, std430) restrict writeonly buffer Values {
	float values[];
} result;

layout(push_constant, std430) uniform Params {
	uint seed_lo;
	uint seed_hi;
	float frequency;
	uint octaves;
	uint count;
	uint pad0;
	uint pad1;
	uint pad2;
} params;

const uvec2 C_GOLDEN = uvec2(0x7f4a7c15u, 0x9e3779b9u);
const uvec2 C_MUL1 = uvec2(0x1ce4e5b9u, 0xbf58476du);
const uvec2 C_MUL2 = uvec2(0x133111ebu, 0x94d049bbu);
const uvec2 C_RAND = uvec2(0xd9b4e019u, 0x632be59bu);

uvec2 add64(uvec2 a, uvec2 b) {
	uint lo = a.x + b.x;
	uint carry = lo < a.x ? 1u : 0u;
	return uvec2(lo, a.y + b.y + carry);
}

uvec2 shl64(uvec2 a, uint n) {
	return uvec2(a.x << n, (a.y << n) | (a.x >> (32u - n)));
}

uvec2 shr64(uvec2 a, uint n) {
	return uvec2((a.x >> n) | (a.y << (32u - n)), a.y >> n);
}

uvec2 mul64(uvec2 a, uvec2 b) {
	uint hi;
	uint lo;
	umulExtended(a.x, b.x, hi, lo);
	return uvec2(lo, hi + a.x * b.y + a.y * b.x);
}

uvec2 mix64(uvec2 a, uvec2 b) {
	uvec2 t = add64(add64(add64(b, C_GOLDEN), shl64(a, 6u)), shr64(a, 2u));
	uvec2 z = a ^ t;
	z = mul64(z ^ shr64(z, 30u), C_MUL1);
	z = mul64(z ^ shr64(z, 27u), C_MUL2);
	return z ^ shr64(z, 31u);
}

uvec2 from_int(int v) {
	return uvec2(uint(v), v < 0 ? 0xffffffffu : 0u);
}

float rand01(uvec2 seed) {
	uvec2 m = mix64(seed, C_RAND);
	uvec2 v = shr64(m, 11u);
	return (float(v.y) * 4294967296.0 + float(v.x)) * 1.1102230246251565e-16;
}

float lattice_value(uvec2 seed, int x, int z) {
	return rand01(mix64(mix64(seed, from_int(x)), from_int(z)));
}

float value_noise(uvec2 seed, float px, float pz, float freq, uint octaves) {
	float total = 0.0;
	float amplitude = 1.0;
	float norm = 0.0;
	float f = freq;
	for (uint o = 0u; o < max(1u, octaves); o++) {
		uvec2 octave_seed = mix64(seed, uvec2(o, 0u));
		float x = px * f;
		float z = pz * f;
		int xi = int(floor(x));
		int zi = int(floor(z));
		float tx = x - float(xi);
		float tz = z - float(zi);
		tx = tx * tx * (3.0 - 2.0 * tx);
		tz = tz * tz * (3.0 - 2.0 * tz);
		float a = lattice_value(octave_seed, xi, zi);
		float b = lattice_value(octave_seed, xi + 1, zi);
		float c = lattice_value(octave_seed, xi, zi + 1);
		float d = lattice_value(octave_seed, xi + 1, zi + 1);
		float ab = a + (b - a) * tx;
		float cd = c + (d - c) * tx;
		total += (ab + (cd - ab) * tz) * amplitude;
		norm += amplitude;
		amplitude *= 0.5;
		f *= 2.0;
	}
	return total / norm;
}

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= params.count) {
		return;
	}
	result.values[i] = value_noise(uvec2(params.seed_lo, params.seed_hi), positions.xz[2u * i], positions.xz[2u * i + 1u], params.frequency, params.octaves);
}
)";

struct GpuNoiseParams {
	uint32_t seed_lo;
	uint32_t seed_hi;
	float frequency;
	uint32_t octaves;
	uint32_t count;
	uint32_t pad[3];
};

// Returns false (and leaves r_values untouched) when no local RenderingDevice exists or anything fails.
bool run_gpu_noise(uint64_t p_seed, const PackedVector3Array &p_positions, float p_frequency, int p_octaves, PackedFloat32Array &r_values) {
	const int count = p_positions.size();
	if (count <= 0 || count > 65535 * 64) {
		return false;
	}
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return false;
	}
	RenderingDevice *rd = rs->create_local_rendering_device();
	if (rd == nullptr) {
		return false;
	}

	bool ok = false;
	RID shader;
	RID input_buffer;
	RID output_buffer;
	RID pipeline;
	do {
		String error;
		const Vector<uint8_t> spirv = rd->shader_compile_spirv_from_source(RenderingDevice::SHADER_STAGE_COMPUTE, String(GPU_NOISE_SHADER), RenderingDevice::SHADER_LANGUAGE_GLSL, &error, false);
		if (spirv.is_empty()) {
			break;
		}
		RenderingDevice::ShaderStageSPIRVData stage;
		stage.shader_stage = RenderingDevice::SHADER_STAGE_COMPUTE;
		stage.spirv = spirv;
		Vector<RenderingDevice::ShaderStageSPIRVData> stages;
		stages.push_back(stage);
		shader = rd->shader_create_from_spirv(stages);
		if (!shader.is_valid()) {
			break;
		}

		LocalVector<float> xz;
		xz.resize((uint32_t)count * 2);
		for (int i = 0; i < count; i++) {
			const Vector3 p = p_positions[i];
			xz[i * 2] = p.x;
			xz[i * 2 + 1] = p.z;
		}
		const uint32_t input_size = (uint32_t)count * 2 * sizeof(float);
		const uint32_t output_size = (uint32_t)count * sizeof(float);
		input_buffer = rd->storage_buffer_create(input_size, Span<uint8_t>(reinterpret_cast<const uint8_t *>(xz.ptr()), input_size));
		output_buffer = rd->storage_buffer_create(output_size);
		if (!input_buffer.is_valid() || !output_buffer.is_valid()) {
			break;
		}

		Vector<RenderingDevice::Uniform> uniforms;
		uniforms.push_back(RenderingDevice::Uniform(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER, 0, input_buffer));
		uniforms.push_back(RenderingDevice::Uniform(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER, 1, output_buffer));
		const RID uniform_set = rd->uniform_set_create(uniforms, shader, 0);
		if (!uniform_set.is_valid()) {
			break;
		}
		pipeline = rd->compute_pipeline_create(shader);
		if (!pipeline.is_valid()) {
			break;
		}

		GpuNoiseParams params;
		params.seed_lo = (uint32_t)(p_seed & 0xffffffffULL);
		params.seed_hi = (uint32_t)(p_seed >> 32);
		params.frequency = p_frequency;
		params.octaves = (uint32_t)p_octaves;
		params.count = (uint32_t)count;
		params.pad[0] = params.pad[1] = params.pad[2] = 0;

		const RenderingDevice::ComputeListID list = rd->compute_list_begin();
		rd->compute_list_bind_compute_pipeline(list, pipeline);
		rd->compute_list_bind_uniform_set(list, uniform_set, 0);
		rd->compute_list_set_push_constant(list, &params, sizeof(params));
		rd->compute_list_dispatch(list, ((uint32_t)count + 63) / 64, 1, 1);
		rd->compute_list_end();
		rd->submit();
		rd->sync();

		const Vector<uint8_t> bytes = rd->buffer_get_data(output_buffer);
		if ((uint32_t)bytes.size() != output_size) {
			break;
		}
		PackedFloat32Array values;
		values.resize(count);
		memcpy(values.ptrw(), bytes.ptr(), output_size);
		r_values = values;
		ok = true;
	} while (false);

	if (pipeline.is_valid()) {
		rd->free_rid(pipeline);
	}
	if (input_buffer.is_valid()) {
		rd->free_rid(input_buffer);
	}
	if (output_buffer.is_valid()) {
		rd->free_rid(output_buffer);
	}
	if (shader.is_valid()) {
		rd->free_rid(shader);
	}
	memdelete(rd);
	return ok;
}

} // namespace

bool PCGGpuDensityNode::is_gpu_available() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return false;
	}
	RenderingDevice *rd = rs->create_local_rendering_device();
	if (rd == nullptr) {
		return false;
	}
	memdelete(rd);
	return true;
}

PackedFloat32Array PCGGpuDensityNode::compute_noise(uint64_t p_seed, const PackedVector3Array &p_positions, float p_frequency, int p_octaves, bool p_allow_gpu, bool *r_used_gpu) {
	const int oct = CLAMP(p_octaves, 1, 8);
	PackedFloat32Array values;
	if (r_used_gpu) {
		*r_used_gpu = false;
	}
	if (p_allow_gpu && run_gpu_noise(p_seed, p_positions, p_frequency, oct, values)) {
		if (r_used_gpu) {
			*r_used_gpu = true;
		}
		return values;
	}
	values.resize(p_positions.size());
	for (int i = 0; i < p_positions.size(); i++) {
		const Vector3 p = p_positions[i];
		values.set(i, PCGDensityNoiseNode::value_noise(p_seed, p.x, p.z, p_frequency, oct));
	}
	return values;
}

Ref<PCGData> PCGGpuDensityNode::execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const {
	Ref<PCGPointData> out = points_input(p_inputs, 0)->duplicate_points();
	const float freq = MAX(0.00001f, float(resolve("frequency", p_context)));
	const int oct = CLAMP(int(resolve("octaves", p_context)), 1, 8);
	const int m = resolve("mode", p_context);
	const float k = resolve("contrast", p_context);
	const float b = resolve("bias", p_context);
	const bool gpu = resolve("use_gpu", p_context);
	const PackedFloat32Array noise = compute_noise(p_seed, out->get_positions(), freq, oct, gpu);
	for (int i = 0; i < out->get_point_count(); i++) {
		const float n = CLAMP((noise[i] - 0.5f) * k + 0.5f + b, 0.0f, 1.0f);
		float d = out->get_density(i);
		switch (m) {
			case 0:
				d = n;
				break;
			case 2:
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

void PCGGpuDensityNode::set_frequency(float p_value) {
	frequency = MAX(0.00001f, p_value);
	emit_changed();
}

void PCGGpuDensityNode::set_octaves(int p_value) {
	octaves = CLAMP(p_value, 1, 8);
	emit_changed();
}

void PCGGpuDensityNode::set_mode(int p_value) {
	mode = CLAMP(p_value, 0, 2);
	emit_changed();
}

void PCGGpuDensityNode::set_contrast(float p_value) {
	contrast = p_value;
	emit_changed();
}

void PCGGpuDensityNode::set_bias(float p_value) {
	bias = p_value;
	emit_changed();
}

void PCGGpuDensityNode::set_use_gpu(bool p_value) {
	use_gpu = p_value;
	emit_changed();
}

void PCGGpuDensityNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_frequency", "value"), &PCGGpuDensityNode::set_frequency);
	ClassDB::bind_method(D_METHOD("get_frequency"), &PCGGpuDensityNode::get_frequency);
	ClassDB::bind_method(D_METHOD("set_octaves", "value"), &PCGGpuDensityNode::set_octaves);
	ClassDB::bind_method(D_METHOD("get_octaves"), &PCGGpuDensityNode::get_octaves);
	ClassDB::bind_method(D_METHOD("set_mode", "value"), &PCGGpuDensityNode::set_mode);
	ClassDB::bind_method(D_METHOD("get_mode"), &PCGGpuDensityNode::get_mode);
	ClassDB::bind_method(D_METHOD("set_contrast", "value"), &PCGGpuDensityNode::set_contrast);
	ClassDB::bind_method(D_METHOD("get_contrast"), &PCGGpuDensityNode::get_contrast);
	ClassDB::bind_method(D_METHOD("set_bias", "value"), &PCGGpuDensityNode::set_bias);
	ClassDB::bind_method(D_METHOD("get_bias"), &PCGGpuDensityNode::get_bias);
	ClassDB::bind_method(D_METHOD("set_use_gpu", "value"), &PCGGpuDensityNode::set_use_gpu);
	ClassDB::bind_method(D_METHOD("is_use_gpu"), &PCGGpuDensityNode::is_use_gpu);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "frequency", PROPERTY_HINT_RANGE, "0.0001,1,0.0001,or_greater"), "set_frequency", "get_frequency");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "octaves", PROPERTY_HINT_RANGE, "1,8,1"), "set_octaves", "get_octaves");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "mode", PROPERTY_HINT_ENUM, "Set,Multiply,Add"), "set_mode", "get_mode");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "contrast", PROPERTY_HINT_RANGE, "0,8,0.01,or_greater"), "set_contrast", "get_contrast");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bias", PROPERTY_HINT_RANGE, "-1,1,0.01"), "set_bias", "get_bias");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_gpu"), "set_use_gpu", "is_use_gpu");
}

// --- Registration ------------------------------------------------------------------------------------------------

void register_pcg_terrain_nodes() {
	GDREGISTER_CLASS(PCGHeightfieldNode);
	GDREGISTER_CLASS(PCGTerrainSampleNode);
	GDREGISTER_CLASS(PCGBiomeClassifyNode);
	GDREGISTER_CLASS(PCGVegetationNode);
	GDREGISTER_CLASS(PCGCaveNode);
	GDREGISTER_CLASS(PCGDungeonNode);
	GDREGISTER_CLASS(PCGGpuDensityNode);
}
