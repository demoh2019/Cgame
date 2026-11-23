extends RefCounted
## Loot beam colours by loot value.
const LootBeam = preload("res://scripts/client/loot_beam.gd")
const DropBounce = preload("res://scripts/client/loot_drop_bounce.gd")


func run(t) -> void:
	t.current = "loot beams by value"
	t.eq(LootBeam.color_for({}).a, 0.0, "ordinary public loot has no beam")
	t.check(LootBeam.color_for({"raid": true}).r > 0.9, "raid caches glow legendary orange")
	t.check(LootBeam.color_for({"supply_drop": true}).b > 0.9, "supply drops glow blue")
	t.eq(LootBeam.color_for({"reserved": true, "can_loot": false}).a, 0.0, "locked loot has no beam")
	var root := Node3D.new()
	root.add_child(LootBeam.make())
	LootBeam.update(root, {"raid": true})
	t.check((root.get_node("LootBeam") as Node3D).visible, "beam shows for raid loot")
	LootBeam.update(root, {})
	t.check(not (root.get_node("LootBeam") as Node3D).visible, "and hides when it becomes ordinary")
	root.free()

	t.current = "cosmetic loot drop always settles and handles invalid timing"
	t.eq(DropBounce.height(NAN), 0.0, "invalid time cannot enter an unbounded bounce loop")
	t.eq(DropBounce.height(INF), 0.0, "infinite age immediately rests")
	t.eq(DropBounce.height(0.0, -1.0), 0.0, "negative drop height is rejected")
	t.eq(DropBounce.height(0.5, INF), 0.0, "infinite height cannot stall the render thread")
	t.eq(DropBounce.settle_time(NAN), 0.0, "invalid drop height has no settling time")
	t.eq(DropBounce.squash(NAN), 1.0, "invalid squash time does not deform a mesh")
	t.near(DropBounce.height(DropBounce.settle_time() + 0.1), 0.0, 0.0001,
		"normal loot mesh is resting after the final bounce")
	var bag := Node3D.new()
	var mesh := Node3D.new()
	mesh.position = Vector3(0.0, 0.35, 0.0)
	mesh.scale = Vector3(1.5, 1.25, 0.9)
	bag.add_child(mesh)
	DropBounce.apply(bag, 0.05, 2)
	t.check(mesh.position.y > 0.35, "high quality plays an airborne drop animation")
	var previous_age: float = float(bag.get_meta("drop_age"))
	DropBounce.apply(bag, NAN, 2)
	t.eq(float(bag.get_meta("drop_age")), previous_age,
		"broken frame delta does not corrupt the animation state")
	DropBounce.apply(bag, 0.02, 0)
	t.near(mesh.position.y, 0.35, 0.0001,
		"switching to low quality immediately places bag back on the ground")
	t.eq(mesh.scale, Vector3(1.5, 1.25, 0.9),
		"quality transition restores the original mesh proportions")
	t.eq(float(bag.get_meta("drop_age")), -1.0,
		"disabled animation does not restart on quality upgrade")
	DropBounce.apply(bag, 0.1, 2)
	t.near(mesh.position.y, 0.35, 0.0001, "graphics upgrade never relaunches old loot")
	bag.free()
