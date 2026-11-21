extends RefCounted
## Example procedural content graphs built on pcg_graph.gd.
## Original content; node vocabulary follows the UE5 PCG concepts described in pcg_graph.gd.
##
## forest_scatter()  inputs: volume, landscape, road (spline)      outputs: trees, rocks, floor
## ruins_debris()    inputs: pois (points)                          outputs: debris, ground
## cave_rocks()      inputs: entrances (points)                     outputs: rocks

const PCGGraph = preload("res://scripts/shared/pcg_graph.gd")


static func _link(g: PCGGraph, a: String, ap: String, b: String, bp: String) -> void:
	var err: String = g.link(a, ap, b, bp)
	if err != "":
		push_error("pcg_presets: " + err)


## Dense forest with a cleared corridor around the road; steep ground gets rocks instead of trees.
static func forest_scatter(graph_seed: int = 1337) -> PCGGraph:
	var g := PCGGraph.new()
	g.graph_seed = graph_seed
	g.add_graph_input("in_volume", "volume", "volume")
	g.add_graph_input("in_land", "landscape", "landscape")
	g.add_graph_input("in_road", "road", "spline")
	g.add_node("sample", "surface_sampler", {"spacing": 3.5, "jitter": 0.8})
	g.add_node("noise", "density_noise", {"frequency": 0.03})
	g.add_node("dense", "density_filter", {"min": 0.4})
	g.add_node("xform", "transform_points", {"scale_min": 0.8, "scale_max": 1.4})
	g.add_node("road_pts", "spline_sampler", {"mode": "along", "spacing": 3.0})
	g.add_node("clear", "difference", {"distance": 7.0, "planar": true})
	g.add_node("prune", "self_pruning", {"min_distance": 2.5})
	g.add_node("slope", "partition_by_attribute", {"attribute": "slope", "threshold": 0.8})
	g.add_node("trees", "static_mesh_spawner", {"meshes": [{"id": "pine", "weight": 3.0}, {"id": "spruce", "weight": 1.0}]})
	g.add_node("rocks", "static_mesh_spawner", {"mesh_id": "rock_mossy"})
	g.add_node("floor", "material_layer_output", {"layer": "forest_floor", "strength": 1.0})
	g.add_graph_output("out_trees", "trees", "mesh_instances")
	g.add_graph_output("out_rocks", "rocks", "mesh_instances")
	g.add_graph_output("out_floor", "floor", "layer_weights")
	_link(g, "in_volume", "out", "sample", "volume")
	_link(g, "in_land", "out", "sample", "landscape")
	_link(g, "sample", "out", "noise", "in")
	_link(g, "noise", "out", "dense", "in")
	_link(g, "dense", "out", "xform", "in")
	_link(g, "in_road", "out", "road_pts", "spline")
	_link(g, "in_land", "out", "road_pts", "landscape")
	_link(g, "xform", "out", "clear", "in")
	_link(g, "road_pts", "out", "clear", "other")
	_link(g, "clear", "out", "prune", "in")
	_link(g, "prune", "out", "slope", "in")
	_link(g, "slope", "above", "trees", "in")
	_link(g, "slope", "below", "rocks", "in")
	_link(g, "slope", "above", "floor", "in")
	_link(g, "trees", "out", "out_trees", "in")
	_link(g, "rocks", "out", "out_rocks", "in")
	_link(g, "floor", "out", "out_floor", "in")
	return g


## Rubble clusters stamped onto each point of interest.
static func ruins_debris(graph_seed: int = 4242) -> PCGGraph:
	var g := PCGGraph.new()
	g.graph_seed = graph_seed
	g.add_graph_input("in_pois", "pois", "points")
	g.add_node("cluster_vol", "constant_volume", {"center": Vector3(0, 1, 0), "size": Vector3(14, 2, 14)})
	g.add_node("cluster", "surface_sampler", {"spacing": 2.2, "jitter": 0.9})
	g.add_node("stamp", "copy_points")
	g.add_node("noise", "density_noise", {"frequency": 0.2, "min_value": 0.2})
	g.add_node("keep", "density_filter", {"min": 0.35})
	g.add_node("xform", "transform_points", {"scale_min": 0.5, "scale_max": 1.6})
	g.add_node("prune", "self_pruning", {"min_distance": 1.2})
	g.add_node("debris", "static_mesh_spawner", {"meshes": [
		{"id": "debris_brick", "weight": 4.0}, {"id": "debris_beam", "weight": 1.0}, {"id": "rubble_pile", "weight": 2.0}]})
	g.add_node("ground", "material_layer_output", {"layer": "rubble_ground"})
	g.add_graph_output("out_debris", "debris", "mesh_instances")
	g.add_graph_output("out_ground", "ground", "layer_weights")
	_link(g, "cluster_vol", "out", "cluster", "volume")
	_link(g, "cluster", "out", "stamp", "source")
	_link(g, "in_pois", "out", "stamp", "target")
	_link(g, "stamp", "out", "noise", "in")
	_link(g, "noise", "out", "keep", "in")
	_link(g, "keep", "out", "xform", "in")
	_link(g, "xform", "out", "prune", "in")
	_link(g, "prune", "out", "debris", "in")
	_link(g, "prune", "out", "ground", "in")
	_link(g, "debris", "out", "out_debris", "in")
	_link(g, "ground", "out", "out_ground", "in")
	return g


## Boulders ringing each cave mouth, with the opening itself kept clear.
static func cave_rocks(graph_seed: int = 9001) -> PCGGraph:
	var g := PCGGraph.new()
	g.graph_seed = graph_seed
	g.add_graph_input("in_entrances", "entrances", "points")
	g.add_node("ring_vol", "constant_volume", {"center": Vector3(0, 1, 0), "size": Vector3(16, 2, 16)})
	g.add_node("ring", "surface_sampler", {"spacing": 1.6, "jitter": 0.7})
	g.add_node("stamp", "copy_points")
	g.add_node("mouth", "difference", {"distance": 3.0, "planar": true})
	g.add_node("noise", "density_noise", {"frequency": 0.15})
	g.add_node("keep", "density_filter", {"min": 0.3})
	g.add_node("xform", "transform_points", {"scale_min": 0.6, "scale_max": 2.2})
	g.add_node("prune", "self_pruning", {"min_distance": 1.0})
	g.add_node("rocks", "static_mesh_spawner", {"meshes": [{"id": "cave_boulder", "weight": 2.0}, {"id": "cave_slab", "weight": 1.0}]})
	g.add_graph_output("out_rocks", "rocks", "mesh_instances")
	_link(g, "ring_vol", "out", "ring", "volume")
	_link(g, "ring", "out", "stamp", "source")
	_link(g, "in_entrances", "out", "stamp", "target")
	_link(g, "stamp", "out", "mouth", "in")
	_link(g, "in_entrances", "out", "mouth", "other")
	_link(g, "mouth", "out", "noise", "in")
	_link(g, "noise", "out", "keep", "in")
	_link(g, "keep", "out", "xform", "in")
	_link(g, "xform", "out", "prune", "in")
	_link(g, "prune", "out", "rocks", "in")
	_link(g, "rocks", "out", "out_rocks", "in")
	return g
