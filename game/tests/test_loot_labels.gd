extends RefCounted
## Raid and PvE loot markers accurately reflect recipient-specific snapshots.
const LootLabel = preload("res://scripts/shared/loot_label.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")


func run(t) -> void:
	t.current = "world loot label privacy and countdown"
	var awarded := {"raid": true, "reserved": true, "reserved_seconds": 74.2,
		"can_loot": true}
	var outsider := awarded.duplicate()
	outsider["can_loot"] = false
	t.check("your pickup" in LootLabel.for_bag(awarded),
		"eligible player sees positive raid loot permission")
	t.check("locked" in LootLabel.for_bag(outsider),
		"other client sees locked raid loot")
	t.check("75s" in LootLabel.for_bag(outsider),
		"server timer rounds upward instead of unlocking early")
	t.eq(LootLabel.for_bag({"raid": true, "reserved": false, "can_loot": true,
		"reserved_seconds": 0.0}), "RAID CACHE - public",
		"expired boss trophies become openly collectible")
	t.check("PARTY LOOT" in LootLabel.for_bag({
		"raid": false, "reserved": true, "reserved_seconds": 4.0, "can_loot": true
	}), "normal PvE group loot has distinct marker")
	t.eq(LootLabel.for_bag({"raid": false, "reserved": false}), "",
		"normal free-for-all and PvP death bags remain unlabelled")
	t.eq(LootLabel.for_bag({"raid": true, "reserved": true,
		"reserved_seconds": NAN}), "RAID CACHE - public",
		"nonfinite timer never shows a perpetual lock")

	t.current = "actual 3D bag view uses refreshed labels"
	var view := EntityView.new()
	var bag: Dictionary = awarded.duplicate()
	bag.merge({"id": 9, "x": 0.0, "y": 0.0, "z": 0.0})
	var present := {}
	view._touch("bag:9", "bag", bag, present)
	var root: Node3D = view._nodes["bag:9"]
	var label: Label3D = root.get_node("Label")
	t.check(label.visible, "loot marker is visible only for protected bags")
	t.check("RAID CACHE" in label.text, "3D label renders the raid state")
	bag = {"id": 9, "x": 0.0, "y": 0.0, "z": 0.0, "reserved": false}
	view._touch("bag:9", "bag", bag, present)
	t.check(not label.visible, "ordinary free-loot bag clears old raid marker")
	view.free()
