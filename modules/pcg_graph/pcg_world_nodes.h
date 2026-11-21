/**************************************************************************/
/*  pcg_world_nodes.h                                                     */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// World-building PCG nodes: roads, rivers, settlements, cities, buildings, ruins,
// structures, loot, encounters and environment dressing. Same rules as the core
// nodes: inputs are never mutated and every random draw is derived from node seed
// + point seed + world position, never from the streaming cell.

#include "pcg_node.h"

#define PCGW_ACCESSORS(m_type, m_name) \
	void set_##m_name(m_type p_value); \
	m_type get_##m_name() const { return m_name; }
#define PCGW_BOOL_ACCESSORS(m_name)  \
	void set_##m_name(bool p_value); \
	bool is_##m_name() const { return m_name; }

void register_pcg_world_nodes();

// Minimum spanning tree over input points (+ optional loop edges), each edge routed with A* over
// the height/water samplers. Output: PCGSplineData. (Unreal PCG spline roads / Houdini "Labs Road Generator".)
class PCGRoadNetworkNode : public PCGNode {
	GDCLASS(PCGRoadNetworkNode, PCGNode);
	String source_key = "settlements";
	float grid_step = 4.0;
	float slope_weight = 10.0;
	float water_penalty = 20.0;
	float loop_detour_ratio = 0.0; // 0 = no loops; otherwise add edges whose graph detour exceeds this ratio (> 1).
	int max_extra_edges = 4;
	float road_width = 4.0;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "World"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	// A* on a coarse grid: cost = distance * (1 + slope_weight * grade^2 + water_penalty on water).
	static PackedVector3Array route(int64_t p_seed, const Vector3 &p_from, const Vector3 &p_to, const Ref<PCGContext> &p_context, float p_grid_step, float p_slope_weight = 10.0, float p_water_penalty = 20.0);
	PCGW_ACCESSORS(String, source_key)
	PCGW_ACCESSORS(float, grid_step)
	PCGW_ACCESSORS(float, slope_weight)
	PCGW_ACCESSORS(float, water_penalty)
	PCGW_ACCESSORS(float, loop_detour_ratio)
	PCGW_ACCESSORS(int, max_extra_edges)
	PCGW_ACCESSORS(float, road_width)
};

// Steepest-descent rivers from lattice local maxima, with momentum, pit filling and tributary merging.
class PCGRiverNetworkNode : public PCGNode {
	GDCLASS(PCGRiverNetworkNode, PCGNode);
	float source_spacing = 24.0;
	float min_source_height = 10.0;
	int max_sources = 8;
	float step_length = 2.0;
	float max_length = 400.0;
	float momentum = 0.25;
	float merge_radius = 3.0;
	float max_fill_depth = 1.5;
	float base_width = 1.5;
	float width_growth = 0.15;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 0; }
	virtual String get_category() const override { return "World"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	PCGW_ACCESSORS(float, source_spacing)
	PCGW_ACCESSORS(float, min_source_height)
	PCGW_ACCESSORS(int, max_sources)
	PCGW_ACCESSORS(float, step_length)
	PCGW_ACCESSORS(float, max_length)
	PCGW_ACCESSORS(float, momentum)
	PCGW_ACCESSORS(float, merge_radius)
	PCGW_ACCESSORS(float, max_fill_depth)
	PCGW_ACCESSORS(float, base_width)
	PCGW_ACCESSORS(float, width_growth)
};

// Settlement lots around centers (input 0) and along roads (input 1).
// Attributes: footprint_x, footprint_z, kind (0 house, 1 workshop, 2 well, 3 wall_post), settlement.
class PCGSettlementNode : public PCGNode {
	GDCLASS(PCGSettlementNode, PCGNode);

public:
	enum Kind {
		KIND_HOUSE,
		KIND_WORKSHOP,
		KIND_WELL,
		KIND_WALL_POST,
	};

private:
	String source_key = "settlements";
	int max_lots = 14;
	float radius = 36.0;
	float max_slope = 20.0;
	float road_margin = 2.0;
	float min_footprint = 5.0;
	float max_footprint = 9.0;
	float workshop_chance = 0.2;
	float wall_radius = 0.0; // > 0 adds wall posts on this ring.
	float wall_post_spacing = 8.0;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 2; }
	virtual String get_category() const override { return "World"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	PCGW_ACCESSORS(String, source_key)
	PCGW_ACCESSORS(int, max_lots)
	PCGW_ACCESSORS(float, radius)
	PCGW_ACCESSORS(float, max_slope)
	PCGW_ACCESSORS(float, road_margin)
	PCGW_ACCESSORS(float, min_footprint)
	PCGW_ACCESSORS(float, max_footprint)
	PCGW_ACCESSORS(float, workshop_chance)
	PCGW_ACCESSORS(float, wall_radius)
	PCGW_ACCESSORS(float, wall_post_spacing)
};

// Block subdivision (grid or radial) around centers; emits lot points with a district attribute
// (0 core, 1 residential, 2 industrial) and footprint_x/footprint_z/block.
class PCGCityNode : public PCGNode {
	GDCLASS(PCGCityNode, PCGNode);
	int layout = 0; // 0 grid, 1 radial
	float half_extent = 80.0;
	float block_size = 36.0;
	float street_width = 8.0;
	float lot_size = 12.0;
	float core_radius = 30.0;
	float residential_radius = 60.0;
	float max_slope = 25.0;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "World"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	// Grid blocks (Rect2 in XZ: position = (x, z)) separated by streets, with jittered cuts.
	static Array layout_blocks(int64_t p_seed, const Rect2 &p_rect, float p_block_size, float p_street_width);
	PCGW_ACCESSORS(int, layout)
	PCGW_ACCESSORS(float, half_extent)
	PCGW_ACCESSORS(float, block_size)
	PCGW_ACCESSORS(float, street_width)
	PCGW_ACCESSORS(float, lot_size)
	PCGW_ACCESSORS(float, core_radius)
	PCGW_ACCESSORS(float, residential_radius)
	PCGW_ACCESSORS(float, max_slope)
};

// Lot points -> modular building pieces. Attributes: piece (Piece enum), floor, floors, building.
class PCGBuildingNode : public PCGNode {
	GDCLASS(PCGBuildingNode, PCGNode);

public:
	enum Piece {
		PIECE_FLOOR,
		PIECE_WALL,
		PIECE_CORNER,
		PIECE_DOOR,
		PIECE_WINDOW,
		PIECE_ROOF,
		PIECE_RUBBLE,
	};

private:
	int max_floors = 3;
	float module_size = 2.0;
	float floor_height = 3.0;
	float window_chance = 0.5;
	float default_footprint = 8.0;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "World"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	PCGW_ACCESSORS(int, max_floors)
	PCGW_ACCESSORS(float, module_size)
	PCGW_ACCESSORS(float, floor_height)
	PCGW_ACCESSORS(float, window_chance)
	PCGW_ACCESSORS(float, default_footprint)
};

// Decays building pieces (noise + height above ground) and scatters rubble where walls fell.
class PCGRuinNode : public PCGNode {
	GDCLASS(PCGRuinNode, PCGNode);
	float base_decay = 0.15;
	float height_decay = 0.5;
	float noise_strength = 0.4;
	float noise_frequency = 0.08;
	float floor_height = 3.0;
	float rubble_chance = 0.9;
	float rubble_spread = 2.5;
	int rubble_per_piece = 2;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "World"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	PCGW_ACCESSORS(float, base_decay)
	PCGW_ACCESSORS(float, height_decay)
	PCGW_ACCESSORS(float, noise_strength)
	PCGW_ACCESSORS(float, noise_frequency)
	PCGW_ACCESSORS(float, floor_height)
	PCGW_ACCESSORS(float, rubble_chance)
	PCGW_ACCESSORS(float, rubble_spread)
	PCGW_ACCESSORS(int, rubble_per_piece)
};

// Prefab stamping. Rule: {"id": int, "radius": float, "min_slope": deg, "max_slope": deg, "biomes": PackedStringArray, "weight": float}.
// Output attributes: structure (rule id), footprint_radius.
class PCGStructureNode : public PCGNode {
	GDCLASS(PCGStructureNode, PCGNode);
	Array rules;
	float min_gap = 0.0;

protected:
	static void _bind_methods();

public:
	virtual String get_category() const override { return "World"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	PCGW_ACCESSORS(Array, rules)
	PCGW_ACCESSORS(float, min_gap)
};

// Loot spots. Rarity rule: {"table": int, "weight": float, "min_tier": int, "max_tier": int}.
// Input 0 = candidate spots, input 1 (optional) = structures used for max-per-structure grouping.
// Output attributes: loot_tier, loot_table.
class PCGLootPlacementNode : public PCGNode {
	GDCLASS(PCGLootPlacementNode, PCGNode);
	Array rarity_rules;
	PackedFloat32Array tier_bands; // Distance-from-origin thresholds; tier = number of bands passed.
	String tier_attribute = "tier";
	Vector3 origin;
	int max_per_structure = 4;
	float min_spacing = 1.5;
	float chance = 1.0;
	float group_cell = 16.0;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 2; }
	virtual String get_category() const override { return "World"; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	PCGW_ACCESSORS(Array, rarity_rules)
	PCGW_ACCESSORS(PackedFloat32Array, tier_bands)
	PCGW_ACCESSORS(String, tier_attribute)
	PCGW_ACCESSORS(Vector3, origin)
	PCGW_ACCESSORS(int, max_per_structure)
	PCGW_ACCESSORS(float, min_spacing)
	PCGW_ACCESSORS(float, chance)
	PCGW_ACCESSORS(float, group_cell)
};

// Encounter groups away from settlements/roads. Inputs: 0 candidates, 1 and 2 = points or splines to avoid.
// Output attributes: group_size, difficulty.
class PCGEncounterPlacementNode : public PCGNode {
	GDCLASS(PCGEncounterPlacementNode, PCGNode);
	float min_point_distance = 40.0;
	float min_spline_distance = 15.0;
	float min_spacing = 30.0;
	PackedFloat32Array difficulty_bands;
	Vector3 origin;
	int group_size_min = 2;
	int group_size_max = 5;
	float max_slope = 30.0;
	float chance = 1.0;
	int max_count = 64;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 3; }
	virtual String get_category() const override { return "World"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	PCGW_ACCESSORS(float, min_point_distance)
	PCGW_ACCESSORS(float, min_spline_distance)
	PCGW_ACCESSORS(float, min_spacing)
	PCGW_ACCESSORS(PackedFloat32Array, difficulty_bands)
	PCGW_ACCESSORS(Vector3, origin)
	PCGW_ACCESSORS(int, group_size_min)
	PCGW_ACCESSORS(int, group_size_max)
	PCGW_ACCESSORS(float, max_slope)
	PCGW_ACCESSORS(float, chance)
	PCGW_ACCESSORS(int, max_count)
};

// Clutter around sources. Rule: {"asset": int, "attribute": String (optional), "value": float, "count_min": int,
// "count_max": int, "ring_min": float, "ring_max": float, "chance": float, "scale_min": float, "scale_max": float,
// "face_outward": bool}. Input 1 (optional splines) gets lamps every lamp_spacing.
class PCGEnvironmentDressingNode : public PCGNode {
	GDCLASS(PCGEnvironmentDressingNode, PCGNode);
	Array rules;
	int lamp_asset = 0;
	float lamp_spacing = 0.0;
	float lamp_offset = 2.5;
	int max_points = 20000;

protected:
	static void _bind_methods();

public:
	virtual int get_input_count() const override { return 2; }
	virtual String get_category() const override { return "World"; }
	virtual bool uses_environment() const override { return true; }
	virtual Ref<PCGData> execute(const Vector<Ref<PCGData>> &p_inputs, const Ref<PCGContext> &p_context, uint64_t p_seed) const override;
	PCGW_ACCESSORS(Array, rules)
	PCGW_ACCESSORS(int, lamp_asset)
	PCGW_ACCESSORS(float, lamp_spacing)
	PCGW_ACCESSORS(float, lamp_offset)
	PCGW_ACCESSORS(int, max_points)
};
