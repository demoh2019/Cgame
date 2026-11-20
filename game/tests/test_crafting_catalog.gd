extends RefCounted
## Filtering, resource limits and slot-safe bulk craft selection.
const Catalog = preload("res://scripts/shared/crafting_catalog.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func run(t) -> void:
	t.current = "case-insensitive search across names and ingredients"
	t.check(Catalog.matches("bandage", "BANdage"), "output names are searchable")
	t.check(Catalog.matches("plank_1", "wood 1"), "ingredients are searchable")
	t.check(Catalog.matches("axe_1", "stone axe"), "multiple words can match output and inputs")
	t.check(not Catalog.matches("plank_1", "diamond"), "unrelated recipes are hidden")
	t.check(not Catalog.matches("missing_id", ""), "unknown recipe is ignored")

	t.current = "bulk quantity limits use server-equivalent atomic inventory rules"
	var resources := Inventory.new()
	resources.add("wood_1", 100)
	t.eq(Catalog.max_batches(resources, "plank_1"), Catalog.MAX_BATCHES,
		"50 batches are bounded by server request limit")
	t.eq(Catalog.max_batches(resources, "bar_4"), 0, "missing materials cannot craft")
	t.eq(Catalog.max_batches(resources, "nonsense"), 0, "unknown recipe unavailable")
	var before: Dictionary = resources.to_dict()
	t.eq(Catalog.max_batches(resources, "plank_1"), 50, "stable repeat query")
	t.eq(resources.to_dict(), before, "preview does not mutate authoritative-looking inventory")
	var limited := Inventory.new()
	limited.add("cloth_1", 7)
	t.eq(Catalog.max_batches(limited, "bandage"), 3, "resource ratio sets batch limit")

	t.current = "a full input stack can create the output slot"
	var single := Inventory.new(1)
	single.add("cloth_1", 4)
	t.eq(Catalog.max_batches(single, "bandage"), 2,
		"two batches fit after full input use, while one batch cannot")
	t.eq(Crafting.craft(single, "bandage", true, 2), Crafting.Result.OK,
		"MAX decision matches an actual atomic crafting transaction")
	t.eq(single.count("bandage"), 4, "four bandages produced in the freed slot")
	var occupied := Inventory.new(1)
	occupied.add("cloth_1", 3)
	t.eq(Catalog.max_batches(occupied, "bandage"), 0,
		"reject output that would not fit even though ingredients are present")
	t.eq(occupied.count("cloth_1"), 3, "failed preview keeps the bag untouched")

	t.current = "craftable-only filter honors both materials and mastery"
	var stocked := Inventory.new()
	stocked.add("wood_1", 4)
	stocked.add("stone_1", 2)
	var all: Array[Dictionary] = Catalog.entries(stocked, "", false, 1)
	var ready: Array[Dictionary] = Catalog.entries(stocked, "", true, 1)
	t.check(ready.size() < all.size(), "ready-only filter narrows the catalogue")
	var found_plank := false
	var found_tier4 := false
	for entry in ready:
		t.check(bool(entry["ready"]), "all displayed ready rows truly pass checks")
		if entry["id"] == "plank_1":
			found_plank = true
		if int(entry["tier"]) > 1:
			found_tier4 = true
	t.check(found_plank, "planks with available resources appear")
	t.check(not found_tier4, "higher-tier recipes are not shown as ready")
	t.eq(Catalog.entries(stocked, "no-such-thing", false, 1).size(), 0,
		"search with no match shows no recipes")
