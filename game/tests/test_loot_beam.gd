extends RefCounted
## Loot beam colours by loot value.
const LootBeam = preload("res://scripts/client/loot_beam.gd")


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
