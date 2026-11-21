extends VBoxContainer
## Visual VFX budget editor for res://scripts/client/vfx_budget.gd: edit per-category effect and
## particle caps (and the global particle cap) per quality tier, apply them to a live budget,
## show live admission stats and export the table as JSON.
## Original code (UI wiring only). VfxBudget's caps are consts, so edits are applied through a
## subclass that overrides the cap getters.

const VfxBudget = preload("res://scripts/client/vfx_budget.gd")
const TIER_NAMES: PackedStringArray = ["low", "medium", "high", "ultra"]


## A VfxBudget whose caps come from the editor's override table (tier -> category -> [e, p]).
class OverrideBudget extends "res://scripts/client/vfx_budget.gd":
	var overrides: Array = [{}, {}, {}, {}]
	var total_overrides: Array = [-1, -1, -1, -1]

	func max_effects(category: String) -> int:
		var cats: Dictionary = overrides[tier]
		if cats.has(category):
			var pair: Array = cats[category]
			return maxi(1, int(pair[0]))
		return super.max_effects(category)

	func max_particles(category: String) -> int:
		var cats: Dictionary = overrides[tier]
		if cats.has(category):
			var pair: Array = cats[category]
			return maxi(1, int(pair[1]))
		return super.max_particles(category)

	func max_total_particles() -> int:
		var t: int = int(total_overrides[tier])
		return t if t > 0 else super.max_total_particles()


## caps[tier][category] = [max_effects, max_particles]; totals[tier] = global particle cap.
var caps: Array = []
var totals: Array = []
var budget: OverrideBudget = OverrideBudget.new()

var _table: Label


func _init() -> void:
	_table = Label.new()
	add_child(_table)
	reset_defaults()


func categories() -> Array:
	return VfxBudget.CATEGORY_BASE.keys()


## Fills the editable table from the shipped formula (base * tier scale).
func reset_defaults() -> void:
	caps = []
	totals = []
	var probe: OverrideBudget = OverrideBudget.new()
	for tier in TIER_NAMES.size():
		probe.set_tier(tier)
		var row: Dictionary = {}
		for cat in categories():
			row[cat] = [probe.max_effects(str(cat)), probe.max_particles(str(cat))]
		caps.append(row)
		totals.append(probe.max_total_particles())
	apply_to(budget)


func tier_index(tier_name: String) -> int:
	return TIER_NAMES.find(tier_name)


## Edits one cap. `kind` is "effects" or "particles". Values below 1 are rejected.
func set_cap(tier_name: String, category: String, kind: String, value: int) -> bool:
	var ti: int = tier_index(tier_name)
	if ti < 0 or value < 1 or not (kind == "effects" or kind == "particles"):
		return false
	var row: Dictionary = caps[ti]
	var pair: Array = row.get(category, [8, 800])
	pair = pair.duplicate()
	pair[0 if kind == "effects" else 1] = value
	row[category] = pair
	return true


func set_total(tier_name: String, value: int) -> bool:
	var ti: int = tier_index(tier_name)
	if ti < 0 or value < 1:
		return false
	totals[ti] = value
	return true


func get_cap(tier_name: String, category: String, kind: String) -> int:
	var ti: int = tier_index(tier_name)
	if ti < 0:
		return -1
	var row: Dictionary = caps[ti]
	var pair: Array = row.get(category, [8, 800])
	return int(pair[0 if kind == "effects" else 1])


## Pushes the table into an OverrideBudget (the panel's own by default). Returns false when the
## given budget is a plain VfxBudget, whose caps cannot be changed.
func apply_to(target: RefCounted = null) -> bool:
	var b: Variant = target if target != null else budget
	if not (b is OverrideBudget):
		return false
	var ob: OverrideBudget = b
	var ov: Array = []
	for tier in TIER_NAMES.size():
		var row: Dictionary = caps[tier]
		ov.append(row.duplicate(true))
	ob.overrides = ov
	ob.total_overrides = totals.duplicate()
	return true


## Live stats rows for the current tier: [{category, effects, max_effects, particles, max_particles}].
func stats_table() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for cat in categories():
		var name_s: String = str(cat)
		rows.append({
			"category": name_s,
			"effects": budget.active_effects(name_s), "max_effects": budget.max_effects(name_s),
			"particles": budget.active_particles(name_s), "max_particles": budget.max_particles(name_s),
		})
	rows.append({
		"category": "total", "effects": budget.active_effects(), "max_effects": -1,
		"particles": budget.active_particles(), "max_particles": budget.max_total_particles(),
	})
	var text: String = ""
	for r in rows:
		text += "%s %d/%d fx, %d/%d p\n" % [r["category"], r["effects"], r["max_effects"], r["particles"], r["max_particles"]]
	_table.text = text
	return rows


func export_json() -> String:
	var out: Dictionary = {"tiers": {}}
	var tiers: Dictionary = out["tiers"]
	for tier in TIER_NAMES.size():
		tiers[TIER_NAMES[tier]] = {"categories": (caps[tier] as Dictionary).duplicate(true), "total_particles": totals[tier]}
	return JSON.stringify(out, "\t")


func import_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	var tiers: Dictionary = d.get("tiers", {})
	for tier in TIER_NAMES.size():
		if not tiers.has(TIER_NAMES[tier]):
			return false
		var entry: Dictionary = tiers[TIER_NAMES[tier]]
		var cats: Dictionary = entry.get("categories", {})
		var row: Dictionary = {}
		for cat in cats:
			var pair: Array = cats[cat]
			row[cat] = [int(pair[0]), int(pair[1])]
		caps[tier] = row
		totals[tier] = int(entry.get("total_particles", 1))
	return apply_to(budget)
