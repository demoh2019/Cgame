extends RefCounted
## Code-built PCG graphs (engine module `pcg_graph`) for the world's dressing and for server-side loot/encounter spots.
## Everything here is a pure builder: it returns a fresh PCGGraph resource (nodes, connections, exposed parameters) or
## null when the running engine has no PCG classes, so the game still runs on stock Godot builds.
##
## Graph parameters (override them through PCGContext/PCGComponent3D `overrides`): see the *_PARAMETERS of each builder.

const CLASS_GRAPH := "PCGGraph"
const CLASS_EXECUTOR := "PCGGraphExecutor"

## Test switch: pretend the engine has no PCG classes.
static var simulate_missing := false

## Loot tiers produced by the loot graph (asset attribute value == tier).
const LOOT_TIERS := 4
## Per-biome density multipliers of the ground clutter (biomes of WorldGen.biome_at).
const CLUTTER_BIOME_DENSITY := {"plains": 0.55, "forest": 1.0, "swamp": 0.8, "beach": 0.3, "mountain": 0.7}


static func available() -> bool:
	return not simulate_missing and ClassDB.class_exists(CLASS_GRAPH) and ClassDB.class_exists(CLASS_EXECUTOR)


## Builds a node of `type`, sets properties, binds exposed parameters ({property: parameter}) and adds it to the graph.
static func _add(graph, type: String, title: String, props: Dictionary = {}, binds: Dictionary = {}) -> int:
	var node = ClassDB.instantiate(type)
	node.set_title(title)
	for key in props:
		node.set(key, props[key])
	for key in binds:
		node.bind_parameter(key, binds[key])
	return graph.add_node(node)


static func _chain(graph, ids: Array) -> void:
	for i in range(1, ids.size()):
		graph.connect_nodes(ids[i - 1], ids[i], 0)


static func _new_graph(parameters: Dictionary):
	var graph = ClassDB.instantiate(CLASS_GRAPH)
	for key in parameters:
		graph.set_parameter(key, parameters[key])
	return graph


## Problems of a graph: empty when it is sound (no cycle, no dangling connection or parameter binding).
static func problems(graph) -> PackedStringArray:
	if graph == null:
		return PackedStringArray(["graph is null"])
	return graph.validate()


# --- (a) Roadside dressing --------------------------------------------------------------------------------------------

## Props along the road polylines (context user_data["roads"]), kept out of settlements (context exclusions).
## Asset attribute: 0 barrel, 1 crate, 2 basket, 3 bench, 4 stool.
const ROADSIDE_PARAMETERS := {"spacing": 22.0, "lateral_offset": 3.2, "scale_min": 0.8, "scale_max": 1.2, "exclusion_margin": 6.0}


static func roadside_dressing():
	if not available():
		return null
	var graph = _new_graph(ROADSIDE_PARAMETERS)
	var spline := _add(graph, "PCGSplineSamplerNode", "Road edge", {"source_key": "roads", "both_sides": true, "face_along": true},
		{"spacing": "spacing", "lateral_offset": "lateral_offset"})
	var transform := _add(graph, "PCGTransformNode", "Jitter", {"random_yaw": true, "offset_min": Vector3(-1.2, 0, -1.2), "offset_max": Vector3(1.2, 0, 1.2), "snap_to_ground": true},
		{"scale_min": "scale_min", "scale_max": "scale_max"})
	var exclusion := _add(graph, "PCGExclusionFilterNode", "Keep out of settlements", {}, {"margin": "exclusion_margin"})
	var surface := _add(graph, "PCGSurfaceFilterNode", "Dry ground", {"max_slope_degrees": 30.0, "exclude_water": true})
	var thin := _add(graph, "PCGDensityNoiseNode", "Sparse", {"frequency": 0.015, "octaves": 2, "mode": 0, "contrast": 1.6})
	var density := _add(graph, "PCGDensityFilterNode", "Thin out", {"min_density": 0.3})
	var rules := _add(graph, "PCGAssetRuleNode", "Props", {"rules": [
		{"asset": 0, "weight": 3.0}, {"asset": 1, "weight": 3.0}, {"asset": 2, "weight": 2.0},
		{"asset": 3, "weight": 2.0}, {"asset": 4, "weight": 2.0}]})
	_chain(graph, [spline, transform, exclusion, surface, thin, density, rules])
	graph.set_output_node_id(rules)
	return graph


# --- (b) Biome ground clutter -----------------------------------------------------------------------------------------

## Small rocks and stones scattered over the ground, denser by biome.
## Asset attribute: 0..3 rocks, 4..5 stones. Output carries a `cluster` attribute for HLOD grouping.
const CLUTTER_PARAMETERS := {"spacing": 5.0, "jitter": 0.85, "noise_frequency": 0.03, "min_distance": 2.5, "max_slope": 32.0,
	"scale_min": 0.12, "scale_max": 0.42, "cluster_size": 32.0, "exclusion_margin": 2.0}


static func biome_clutter():
	if not available():
		return null
	var graph = _new_graph(CLUTTER_PARAMETERS)
	var sampler := _add(graph, "PCGSurfaceSamplerNode", "Ground lattice", {"skip_water": true}, {"spacing": "spacing", "jitter": "jitter"})
	var noise := _add(graph, "PCGDensityNoiseNode", "Patchiness", {"octaves": 3, "mode": 0, "contrast": 1.8, "bias": 0.1}, {"frequency": "noise_frequency"})
	var biome := _add(graph, "PCGBiomeMaskNode", "Biome density", {"biome_density": CLUTTER_BIOME_DENSITY.duplicate()})
	var density := _add(graph, "PCGDensityFilterNode", "Roll density", {"random_threshold": true})
	var exclusion := _add(graph, "PCGExclusionFilterNode", "Keep out of settlements", {}, {"margin": "exclusion_margin"})
	var surface := _add(graph, "PCGSurfaceFilterNode", "Walkable slopes", {"exclude_water": true}, {"max_slope_degrees": "max_slope"})
	var prune := _add(graph, "PCGSelfPruneNode", "Spacing", {}, {"min_distance": "min_distance"})
	var transform := _add(graph, "PCGTransformNode", "Scale and yaw", {"random_yaw": true, "snap_to_ground": true}, {"scale_min": "scale_min", "scale_max": "scale_max"})
	var rules := _add(graph, "PCGAssetRuleNode", "Rocks by biome", {"rules": [
		{"asset": 0, "weight": 3.0, "biomes": PackedStringArray(["plains", "beach"])},
		{"asset": 1, "weight": 2.0, "biomes": PackedStringArray(["plains", "forest", "swamp"])},
		{"asset": 2, "weight": 3.0, "biomes": PackedStringArray(["forest", "swamp"])},
		{"asset": 3, "weight": 1.0, "biomes": PackedStringArray(["forest", "swamp", "plains"])},
		{"asset": 4, "weight": 3.0, "biomes": PackedStringArray(["mountain", "beach"])},
		{"asset": 5, "weight": 2.0, "biomes": PackedStringArray(["mountain", "plains"])}]})
	var cluster := _add(graph, "PCGClusterNode", "HLOD clusters", {}, {"cluster_size": "cluster_size"})
	_chain(graph, [sampler, exclusion, noise, biome, density, surface, prune, transform, rules, cluster])
	graph.set_output_node_id(cluster)
	return graph


# --- (c) Ruin debris --------------------------------------------------------------------------------------------------

## Rubble, columns and stones around ruined cities (context user_data["ruins"] point list).
## Asset attribute: 0 large rubble, 1 half rubble, 2 column, 3 and 4 stones.
const DEBRIS_PARAMETERS := {"spacing": 6.0, "radius": 70.0, "min_distance": 4.0, "scale_min": 0.7, "scale_max": 1.3}


static func ruin_debris():
	if not available():
		return null
	var graph = _new_graph(DEBRIS_PARAMETERS)
	var ruins := _add(graph, "PCGPointSourceNode", "Ruin centres", {"source_key": "ruins", "clip_to_bounds": false})
	var sampler := _add(graph, "PCGSurfaceSamplerNode", "Ground lattice", {"skip_water": true, "jitter": 0.9}, {"spacing": "spacing"})
	var query := _add(graph, "PCGSpatialQueryNode", "Near a ruin", {"mode": 1}, {"radius": "radius"})
	var surface := _add(graph, "PCGSurfaceFilterNode", "Walkable slopes", {"max_slope_degrees": 40.0, "exclude_water": true})
	var prune := _add(graph, "PCGSelfPruneNode", "Spacing", {}, {"min_distance": "min_distance"})
	var transform := _add(graph, "PCGTransformNode", "Scale and yaw", {"random_yaw": true, "snap_to_ground": true}, {"scale_min": "scale_min", "scale_max": "scale_max"})
	var rules := _add(graph, "PCGAssetRuleNode", "Debris", {"rules": [
		{"asset": 0, "weight": 2.0}, {"asset": 1, "weight": 3.0}, {"asset": 2, "weight": 1.0},
		{"asset": 3, "weight": 2.0}, {"asset": 4, "weight": 2.0}]})
	_chain(graph, [sampler, query, surface, prune, transform, rules])
	graph.connect_nodes(ruins, query, 1)
	graph.set_output_node_id(rules)
	return graph


# --- (d) Server loot caches -------------------------------------------------------------------------------------------

## Candidate cache spots (context user_data["pois"]: {position, density = tier / LOOT_TIERS}) become caches of loot tier
## 1..LOOT_TIERS (asset attribute); a spot never rolls a tier above its own density.
const LOOT_PARAMETERS := {"max_per_chunk": 3}


static func loot_caches():
	if not available():
		return null
	var graph = _new_graph(LOOT_PARAMETERS)
	var source := _add(graph, "PCGPointSourceNode", "POIs and ruins", {"source_key": "pois", "clip_to_bounds": true})
	var rules := _add(graph, "PCGAssetRuleNode", "Loot tier", {"rules": [
		{"asset": 1, "weight": 4.0, "min_density": 0.0},
		{"asset": 2, "weight": 3.0, "min_density": 0.5},
		{"asset": 3, "weight": 2.0, "min_density": 0.75},
		{"asset": 4, "weight": 1.0, "min_density": 1.0}], "drop_unmatched": true})
	var limit := _add(graph, "PCGCountLimitNode", "Budget", {}, {"max_points": "max_per_chunk"})
	_chain(graph, [source, rules, limit])
	graph.set_output_node_id(limit)
	return graph


# --- (e) Encounter spots ----------------------------------------------------------------------------------------------

## Where a roaming infected group may stand. The caller passes safe zones and settlements as context exclusions.
const ENCOUNTER_PARAMETERS := {"spacing": 24.0, "exclusion_margin": 40.0, "min_distance": 38.0, "max_per_chunk": 2}


static func encounter_spots():
	if not available():
		return null
	var graph = _new_graph(ENCOUNTER_PARAMETERS)
	var sampler := _add(graph, "PCGSurfaceSamplerNode", "Ground lattice", {"skip_water": true, "jitter": 1.0}, {"spacing": "spacing"})
	var exclusion := _add(graph, "PCGExclusionFilterNode", "Safe zones and settlements", {}, {"margin": "exclusion_margin"})
	var surface := _add(graph, "PCGSurfaceFilterNode", "Walkable slopes", {"max_slope_degrees": 30.0, "exclude_water": true})
	var prune := _add(graph, "PCGSelfPruneNode", "Spread out", {}, {"min_distance": "min_distance"})
	var limit := _add(graph, "PCGCountLimitNode", "Budget", {}, {"max_points": "max_per_chunk"})
	_chain(graph, [sampler, exclusion, surface, prune, limit])
	graph.set_output_node_id(limit)
	return graph


## Every builder by name, for tests and tooling.
static func all_builders() -> Dictionary:
	return {"roadside": roadside_dressing, "clutter": biome_clutter, "debris": ruin_debris, "loot": loot_caches, "encounters": encounter_spots}
