extends RefCounted
## Albion Destiny Board-style weapon line mastery: fame per weapon family.

const Progression = preload("res://scripts/shared/progression.gd")


func run(t) -> void:
	t.current = "weapon families"
	t.eq(Progression.weapon_family("spear_3"), "spear", "tier suffix is dropped")
	t.eq(Progression.weapon_family("spear_3@2+4"), "spear", "enchant and quality are dropped")
	t.eq(Progression.weapon_family("pistol"), "pistol", "untiered weapons keep their id")
	t.eq(Progression.weapon_family("wood_1"), "", "resources are not weapons")

	t.current = "fame builds mastery of that line only"
	var p := Progression.new()
	t.eq(p.weapon_mastery_level("spear_2"), 0, "novice")
	for i in 40:
		p.award_combat("spear_2", 1000)
	t.check(p.weapon_mastery_level("spear_4@1") > 0, "mastery applies to every tier of the line")
	t.eq(p.weapon_mastery_level("club_2"), 0, "other lines are untouched")
	t.check(p.mastery_item_power("spear_2") > 0, "mastery adds item power to that line")
	t.check(p.mastery_ultimate_multiplier("spear_2") > 1.0, "and strengthens its ultimate")
	t.eq(p.mastery_item_power("club_2"), 0, "but not to other lines")
	t.eq(Progression.mastery_level_for_fame(200000), Progression.MASTERY_MAX_LEVEL, "L100 at 200k fame")
	t.eq(Progression.mastery_level_for_fame(10000000), Progression.MASTERY_MAX_LEVEL, "capped at 100")

	t.current = "mastery persists; bad data is skipped"
	var saved: Dictionary = p.to_dict()
	var restored := Progression.new()
	t.check(restored.load_dict(saved), "save loads")
	t.eq(restored.weapon_mastery_level("spear_2"), p.weapon_mastery_level("spear_2"), "mastery restored")
	saved["weapon_fame"] = {"spear": -5, "club": 1.5, 7: 100}
	var tampered := Progression.new()
	t.check(tampered.load_dict(saved), "malformed mastery does not reject the whole save")
	t.eq(tampered.weapon_fame.size(), 0, "malformed entries are dropped")
	saved.erase("weapon_fame")
	t.check(Progression.new().load_dict(saved), "older saves without mastery still load")
