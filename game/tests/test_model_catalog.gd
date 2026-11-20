extends RefCounted
## The world data names models by variant number only; the client maps a number to an installed model. These checks keep
## the two sides consistent, whether the downloaded packs are installed or not.

const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const ModelCatalog = preload("res://scripts/client/model_catalog.gd")


func run(t) -> void:
	t.current = "variant tables"
	t.eq(WorldPoi.PROP_RADII.size(), ModelCatalog.PROPS.size(), "one blocking radius per prop model")
	t.eq(WorldPoi.RUIN_RADII.size(), ModelCatalog.RUINS.size(), "one blocking radius per ruin model")
	t.eq(WorldPoi.CRATE_VARIANTS, ModelCatalog.CRATES.size(), "crate variants match the catalog")
	t.eq(WorldPoi.BUILDING_VARIANTS, ModelCatalog.HOUSES.size(), "house variants match the catalog")
	t.eq(WorldPoi.TOWER_VARIANTS, ModelCatalog.TOWERS.size(), "tower variants match the catalog")
	t.check(WorldPoi.WALL_STONE < ModelCatalog.WALLS.size() and WorldPoi.WALL_WOOD < ModelCatalog.WALLS.size(), "wall variants exist")
	t.eq(WorldPoi.TOWN_CENTER_VARIANT, ModelCatalog.TOWN_CENTER_VARIANT, "the town centre has the same index on both sides")
	var pools := {"RUSTIC_PROPS": WorldPoi.RUSTIC_PROPS, "MARKET_PROPS": WorldPoi.MARKET_PROPS, "MILITARY_PROPS": WorldPoi.MILITARY_PROPS, "RUIN_PROPS": WorldPoi.RUIN_PROPS}
	for pool_name in pools:
		for index in pools[pool_name]:
			t.check(index >= 0 and index < WorldPoi.PROP_RADII.size(), "%s names a real prop (%d)" % [pool_name, index])
	for radius in WorldPoi.PROP_RADII + WorldPoi.RUIN_RADII:
		t.check(radius > 0.0 and radius < 4.0, "blocking radii are sane (%.2f)" % radius)

	t.current = "what the world uses"
	var world := WorldGen.new(1337)
	var kinds: Dictionary = {}
	var props_seen: Dictionary = {}
	var houses_seen: Dictionary = {}
	for rx in range(-8, 9):
		for rz in range(-8, 9):
			for site in world.poi.sites_in_region(rx, rz):
				var content: Dictionary = world.poi.contents(site)
				for item in content["structures"]:
					kinds[item["kind"]] = true
					if item["kind"] == "building":
						houses_seen[item["variant"]] = true
						t.check(item["variant"] >= 0 and item["variant"] < WorldPoi.BUILDING_VARIANTS, "a house variant in range")
					if item["kind"] == "tower":
						t.check(item["variant"] >= 0 and item["variant"] < WorldPoi.TOWER_VARIANTS, "a tower variant in range")
					if item["kind"] == "ruin":
						t.check(item["variant"] >= 0 and item["variant"] < WorldPoi.RUIN_RADII.size(), "a ruin variant in range")
				for prop in content["props"]:
					props_seen[prop["variant"]] = true
					t.check(prop["variant"] >= 0 and prop["variant"] < WorldPoi.PROP_RADII.size(), "a prop variant in range")
					t.near(float(prop["radius"]), float(WorldPoi.PROP_RADII[prop["variant"]]), 0.0001, "a prop blocks with its own radius")
				for crate in content["crates"]:
					t.check(crate["variant"] >= 0 and crate["variant"] < WorldPoi.CRATE_VARIANTS, "a crate variant in range")
	for kind in ["building", "wall", "tower", "workbench", "ruin", "windmill"]:
		t.check(kinds.has(kind), "the island has %s structures" % kind)
	t.check(props_seen.size() >= 14, "most prop models are in use (%d of %d)" % [props_seen.size(), WorldPoi.PROP_RADII.size()])
	t.check(houses_seen.size() >= 6, "several house models are in use (%d)" % houses_seen.size())

	t.current = "fallbacks"
	for list_name in ["houses", "props"]:
		var list: Array = ModelCatalog.HOUSES if list_name == "houses" else ModelCatalog.PROPS
		var installed: Array = ModelCatalog.available(list_name, list)
		t.check(installed.size() <= list.size(), "%s: installed models are a subset" % list_name)
		var picked: Dictionary = ModelCatalog.pick(list_name, list, 12345)
		t.check(picked.is_empty() == installed.is_empty(), "%s: a pick exists exactly when something is installed" % list_name)
	t.check(ModelCatalog.pick("none", [], 3).is_empty(), "an empty list yields no model, so the client uses its fallback")
