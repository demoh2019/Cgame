extends RefCounted
## Lightning sparks authored as a VFX graph: bounce and spawn embers on impact.

const VfxPresets = preload("res://scripts/client/vfx_presets.gd")
const VfxGraph = preload("res://scripts/client/vfx_graph.gd")


func run(t) -> void:
	t.current = "vfx presets"
	var holder := Node3D.new()
	t.eq(VfxPresets.spawn(holder, VfxPresets.lightning_sparks(0), Vector3.ZERO, 1), null, "Performance spawns no graph effect")
	holder.free()
	var system: Dictionary = VfxGraph.create_system(VfxPresets.lightning_sparks(3), 5)
	VfxGraph.tick(system, 0.02)
	t.eq(VfxGraph.particle_count(system, "sparks"), 110, "Ultra burst size")
	var embers := 0
	for i in 40:
		VfxGraph.tick(system, 0.03)
		embers = maxi(embers, VfxGraph.particle_count(system, "embers"))
	t.check(embers > 0, "sparks hitting the ground spawn embers")
	var positions: PackedVector3Array = VfxGraph.attribute(system, "sparks", "position")
	var below := false
	for p in positions:
		if p.y < -0.01:
			below = true
	t.check(not below, "sparks never sink through the ground")
	var root := Node3D.new()
	var node: Node3D = VfxPresets.spawn(root, VfxPresets.lightning_sparks(2), Vector3(3, 1, 4), 9)
	t.check(node != null and node.get_parent() == root, "effect node is spawned under the scene")
	root.free()
