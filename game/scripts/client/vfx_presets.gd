extends RefCounted
## Gameplay effects authored as VFX-graph assets (vfx_graph.gd). Each preset is
## pure data: spawn/update modules plus event routing between emitters.

const VfxGraphNode = preload("res://scripts/client/vfx_graph_node.gd")

## Particle counts per graphics level; Performance keeps the old burst only.
const SPARK_COUNTS := [0, 40, 70, 110]


## Lightning ground strike: white-hot sparks that bounce off the ground and
## spawn short-lived embers on impact (collision event routing).
static func lightning_sparks(level: int) -> Dictionary:
	var sparks: int = int(SPARK_COUNTS[clampi(level, 0, 3)])
	return {"emitters": {
		"sparks": {"max_particles": sparks, "spawn": [
				{"type": "spawn_burst", "count": sparks},
				{"type": "lifetime_random", "min": 0.6, "max": 1.3},
				{"type": "initial_position_sphere", "radius": 0.4, "center": Vector3(0, 0.3, 0)},
				{"type": "initial_velocity", "direction": Vector3.UP, "spread": 70.0, "speed_min": 4.0, "speed_max": 11.0},
				{"type": "initial_size", "min": 0.05, "max": 0.12}],
			"update": [
				{"type": "gravity", "gravity": Vector3(0, -14.0, 0)},
				{"type": "drag", "drag": 0.6},
				{"type": "color_over_life", "stops": [[0.0, Color(1.6, 1.6, 2.2, 1.0)], [0.35, Color(1.4, 0.8, 0.3, 1.0)], [1.0, Color(0.6, 0.15, 0.05, 0.0)]]},
				{"type": "size_over_life", "stops": [[0.0, 1.0], [1.0, 0.3]]},
				{"type": "collide_plane", "normal": Vector3.UP, "offset": 0.0, "restitution": 0.35, "friction": 0.3,
					"on_event": {"emitter": "embers", "count": 1}}]},
		"embers": {"max_particles": sparks, "spawn": [
				{"type": "lifetime_random", "min": 0.4, "max": 0.9},
				{"type": "initial_size", "min": 0.04, "max": 0.07},
				{"type": "initial_velocity", "direction": Vector3.UP, "spread": 50.0, "speed_min": 0.3, "speed_max": 1.2}],
			"update": [
				{"type": "drag", "drag": 2.0},
				{"type": "color_over_life", "stops": [[0.0, Color(1.2, 0.5, 0.15, 0.9)], [1.0, Color(0.3, 0.05, 0.0, 0.0)]]}]},
	}}


## Spawns a self-freeing effect node at a world position; null when disabled.
static func spawn(parent: Node3D, asset: Dictionary, at: Vector3, seed_value: int) -> Node3D:
	if parent == null or not at.is_finite():
		return null
	var emitters: Dictionary = asset.get("emitters", {})
	var any := false
	for key in emitters:
		if int((emitters[key] as Dictionary).get("max_particles", 0)) > 0:
			any = true
	if not any:
		return null
	var node: Node3D = VfxGraphNode.new()
	node.set("one_shot", true)
	node.name = "VfxGraphEffect"
	parent.add_child(node)
	node.global_position = at
	node.call("setup", asset, seed_value)
	return node
