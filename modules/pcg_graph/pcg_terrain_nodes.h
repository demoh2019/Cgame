/**************************************************************************/
/*  pcg_terrain_nodes.h                                                   */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// Terrain / biome / vegetation / cave / dungeon / GPU nodes for the PCG graph
// (Unreal PCG "Procedural Terrain/Biome/Vegetation/Cave/Dungeon Graph" and
// Houdini Engine heightfield style workflows). Same rules as the core nodes:
// never mutate inputs, all randomness is derived from world-space coordinates
// and the node seed so results never depend on how the world is cut into cells.

#include "pcg_node.h"

#include "core/math/rect2i.h"

// Regular heightfield grid over the bounds, y from fractal value noise.
// Outputs one point per lattice cell (lattice anchored at world origin, half-open bounds), normal from
// finite differences, attribute "height01". Thermal erosion runs on a padded grid so tiles stay seamless.
class PCGHeightfieldNode : public PCGNode {
	GDCLASS(PCGHeightfieldNode, PCGNode);
	float spacing = 2.0;
	float frequency = 0.01;
	int octaves = 5;
	float amplitude = 20.0;
	float base_height = 0.0;
	bool ridged = false;
	int terrace_steps = 0;
	int erosion_iterations = 0;
	float talus_angle = 40.0;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 0; }
	virtual String get_category() const override { return "Terrain"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_spacing(float p_value);
	float get_spacing() const { return spacing; }
	void set_frequency(float p_value);
	float get_frequency() const { return frequency; }
	void set_octaves(int p_value);
	int get_octaves() const { return octaves; }
	void set_amplitude(float p_value);
	float get_amplitude() const { return amplitude; }
	void set_base_height(float p_value);
	float get_base_height() const { return base_height; }
	void set_ridged(bool p_value);
	bool is_ridged() const { return ridged; }
	void set_terrace_steps(int p_value);
	int get_terrace_steps() const { return terrace_steps; }
	void set_erosion_iterations(int p_value);
	int get_erosion_iterations() const { return erosion_iterations; }
	void set_talus_angle(float p_value);
	float get_talus_angle() const { return talus_angle; }
};

// Replaces y/normal of input points with the context height sampler; adds "slope" (degrees) and "height".
class PCGTerrainSampleNode : public PCGNode {
	GDCLASS(PCGTerrainSampleNode, PCGNode);
	float normal_step = 0.5;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Terrain"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_normal_step(float p_value);
	float get_normal_step() const { return normal_step; }
};

// Temperature/moisture noise (+ altitude lapse rate) classified by a rule table into attribute "biome".
// Rules: Array of {"index", "min_temp", "max_temp", "min_moisture", "max_moisture"}; the first match wins.
// Also writes "temperature" and "moisture". With use_context_biome the context biome sampler is mapped to
// indices through biome_names (Dictionary name -> index) instead.
class PCGBiomeClassifyNode : public PCGNode {
	GDCLASS(PCGBiomeClassifyNode, PCGNode);
	float temperature_frequency = 0.004;
	float moisture_frequency = 0.006;
	int noise_octaves = 3;
	float lapse_rate = 0.0; // Temperature drop per world unit of altitude (y).
	Array rules;
	int default_biome = 0;
	bool use_context_biome = false;
	Dictionary biome_names;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "Biome"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	// Rule table lookup; returns p_default when nothing matches.
	static int classify(const Array &p_rules, float p_temperature, float p_moisture, int p_default);
	void set_temperature_frequency(float p_value);
	float get_temperature_frequency() const { return temperature_frequency; }
	void set_moisture_frequency(float p_value);
	float get_moisture_frequency() const { return moisture_frequency; }
	void set_noise_octaves(int p_value);
	int get_noise_octaves() const { return noise_octaves; }
	void set_lapse_rate(float p_value);
	float get_lapse_rate() const { return lapse_rate; }
	void set_rules(const Array &p_value);
	Array get_rules() const { return rules; }
	void set_default_biome(int p_value);
	int get_default_biome() const { return default_biome; }
	void set_use_context_biome(bool p_value);
	bool is_use_context_biome() const { return use_context_biome; }
	void set_biome_names(const Dictionary &p_value);
	Dictionary get_biome_names() const { return biome_names; }
};

// Layered vegetation (canopy / understory / ground cover) from candidate points.
// layers: Array of {"name", "density", "min_spacing", "avoid_radius", "assets": Array[int], "scale_min", "scale_max"}.
// Layers are placed in order; a layer keeps "avoid_radius" away from every point of the earlier layers.
// Output attributes: "asset" (int id or -1) and "layer" (index).
class PCGVegetationNode : public PCGNode {
	GDCLASS(PCGVegetationNode, PCGNode);
	Array layers;

protected:
	static void _bind_methods();

public:
	PCGVegetationNode();
	virtual String get_category() const override { return "Vegetation"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_layers(const Array &p_value);
	Array get_layers() const { return layers; }
};

// 3D cellular-automata caves on a voxel grid (+ optional worm tunnels). Voxel state is seeded per world
// voxel coordinate and the automaton runs on a padded grid, so neighbouring bounds tile exactly.
// Outputs surface voxels (open voxels touching solid) with "cave_floor"/"cave_wall" and a normal toward open space.
class PCGCaveNode : public PCGNode {
	GDCLASS(PCGCaveNode, PCGNode);
	float voxel_size = 1.0;
	float fill_percent = 0.5;
	int iterations = 4;
	int birth_limit = 14; // Open voxel becomes solid with at least this many solid neighbours (of 26).
	int survival_limit = 13; // Solid voxel stays solid with at least this many solid neighbours.
	int worms_per_region = 0;
	int worm_length = 48;
	float worm_radius = 1.5; // In voxels.
	int worm_region = 32; // Worm start lattice, in voxels.

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 0; }
	virtual String get_category() const override { return "Cave"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	void set_voxel_size(float p_value);
	float get_voxel_size() const { return voxel_size; }
	void set_fill_percent(float p_value);
	float get_fill_percent() const { return fill_percent; }
	void set_iterations(int p_value);
	int get_iterations() const { return iterations; }
	void set_birth_limit(int p_value);
	int get_birth_limit() const { return birth_limit; }
	void set_survival_limit(int p_value);
	int get_survival_limit() const { return survival_limit; }
	void set_worms_per_region(int p_value);
	int get_worms_per_region() const { return worms_per_region; }
	void set_worm_length(int p_value);
	int get_worm_length() const { return worm_length; }
	void set_worm_radius(float p_value);
	float get_worm_radius() const { return worm_radius; }
	void set_worm_region(int p_value);
	int get_worm_region() const { return worm_region; }
};

// BSP dungeon: rooms in leaves, L-shaped corridors joining sibling subtrees (so every room is reachable).
// Output points are tiles: attribute "room" (room id, -1 for corridors) and "kind" (0 floor, 1 door, 2 corridor).
class PCGDungeonNode : public PCGNode {
	GDCLASS(PCGDungeonNode, PCGNode);
	float tile_size = 1.0;
	int min_room_size = 4;
	int max_room_size = 10;
	int max_depth = 4;
	int padding = 1;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 0; }
	virtual String get_category() const override { return "Dungeon"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	// {"rooms": Array[Rect2i], "corridors": Array[PackedVector2Array]} (tile coordinates, corridor = corner list).
	static Dictionary generate_layout(int64_t p_seed, const Rect2i &p_rect, int p_min_room = 4, int p_max_room = 10, int p_max_depth = 4, int p_padding = 1);
	void set_tile_size(float p_value);
	float get_tile_size() const { return tile_size; }
	void set_min_room_size(int p_value);
	int get_min_room_size() const { return min_room_size; }
	void set_max_room_size(int p_value);
	int get_max_room_size() const { return max_room_size; }
	void set_max_depth(int p_value);
	int get_max_depth() const { return max_depth; }
	void set_padding(int p_value);
	int get_padding() const { return padding; }
};

// Value-noise density for all input points, computed with a RenderingDevice compute shader when one can be
// created, otherwise (headless, no GPU, any failure) on the CPU with PCGDensityNoiseNode::value_noise.
// GPU results are float32 with their own FMA/rounding and may differ from the CPU in the last bits:
// use this node for cosmetic layers only (never for placement decisions that must be reproducible).
class PCGGpuDensityNode : public PCGNode {
	GDCLASS(PCGGpuDensityNode, PCGNode);
	float frequency = 0.02;
	int octaves = 3;
	int mode = 1; // 0 set, 1 multiply, 2 add (same as PCGDensityNoiseNode::Mode).
	float contrast = 1.0;
	float bias = 0.0;
	bool use_gpu = true;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "GPU"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	// Raw noise (0..1) per position (x, z used). r_used_gpu reports which path ran.
	static PackedFloat32Array compute_noise(uint64_t p_seed, const PackedVector3Array &p_positions, float p_frequency, int p_octaves, bool p_allow_gpu, bool *r_used_gpu = nullptr);
	static bool is_gpu_available();
	void set_frequency(float p_value);
	float get_frequency() const { return frequency; }
	void set_octaves(int p_value);
	int get_octaves() const { return octaves; }
	void set_mode(int p_value);
	int get_mode() const { return mode; }
	void set_contrast(float p_value);
	float get_contrast() const { return contrast; }
	void set_bias(float p_value);
	float get_bias() const { return bias; }
	void set_use_gpu(bool p_value);
	bool is_use_gpu() const { return use_gpu; }
};

void register_pcg_terrain_nodes();
