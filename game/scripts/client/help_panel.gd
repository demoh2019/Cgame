extends PanelContainer
## Every control of the game on one screen (F2). The same keys work in the local and the online client.

const ENTRIES := [
	["MOVE AND FIGHT", [
		["WASD", "move"], ["Shift", "sprint"], ["F4", "ride / dismount crafted bike"], ["[", "toggle crafted bike dynamo lamp: night light or stealth"], ["PgUp", "service bike drive on foot"], ["PgDn", "repair damaged bike frame"], ["Space", "dodge"], ["Mouse", "aim; left click attacks"], ["G", "weapon skill"],
		["F1", "guardian taunt"], ["Delete", "prepare ranged sight kit"], ["End", "sharpen melee weapon"], ["4", "next weapon"], ["5", "equip armor"], ["Wheel", "zoom"]]],
	["GATHER AND CRAFT", [
		["E", "interact with aimed resource / pick up / loot"], ["Hold E", "collect nearby resources"], ["Hold LMB", "mine rocks / chop trees"], ["Shift+E / Shift+Q", "collect up to five nearby PvE bags"], ["C", "crafting window"], ["0", "quick-cook best fish"], ["Shift+0", "craft fish stew from fish, clean water and wood at a fire"],
		["T", "cast fishing rod (Shift: baited)"], ["I / Tab", "inventory (click: use or equip; right click: stash)"], ["B", "stash (at the hub)"]]],
	["SURVIVE", [
		["1", "eat"], ["Ctrl+1", "smart safe food"], ["Shift+1", "eat fish stew: restores hunger and thirst"], ["2", "drink bottle"], ["Ctrl+2", "smart safe drink"], ["3", "bandage"], ["Shift+3", "trauma kit"], ["Ctrl+3", "smart medicine"], ["6", "antiseptic"], ["7", "antibiotics"], ["8", "heat pack"], ["F11", "herbal poultice"],
		["R", "drink from lake (untreated water risks infection)"], ["Ctrl+R", "fill canteen (charcoal filter)"],
		["Ctrl+Shift+R", "boil water at lake and live fire (2 wood)"], [".", "frontier stim"], ["/", "scent salve (Shift: quiet sprint wraps)"], [";", "spore filter"], ["Z", "rest at the hub or a fire"]]],
	["BUILD AND DEFEND", [
		["U", "build barricade"], ["H", "repair"], ["Y", "upgrade"], ["X", "dismantle"], ["O", "light campfire"], ["Shift+O", "arm crafted infected camp alarm (3 min)"],
		["9", "refuel fire (Shift: stormproof briquette)"], ["-", "extinguish fire"], [",", "throw noise decoy"],
		["F5", "throw ember flask (PvE fire)"], ["F6 / F7", "pitch / pack field tarp"], ["Home", "return charm"], ["Alt+T", "storm cast"]]],
	["TOWN", [
		["N", "buy water"], ["V", "sell materials (Shift: fish)"], ["P", "accept contract (Shift: turn in, Ctrl: daily bounty)"],
		["K", "skills and perks"], ["J", "map: drag pans, wheel zooms, click waypoint, Shift+click party ping, right clears"], ["Enter", "chat"], ["M", "radar"], ["F2", "this help"], ["`", "full text readout"], ["F3", "survey ruins"], ["Ctrl+F11", "graphics quality preset"]]],
]

var _built := false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func toggle() -> void:
	if not _built:
		_build()
	visible = not visible
	if visible:
		set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _build() -> void:
	_built = true
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "CONTROLS   (F2 closes)"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	box.add_child(columns)
	var cols: Array = []
	for i in 3:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		columns.add_child(column)
		cols.append(column)
	var placement := [0, 0, 1, 2, 2] # Which column each group goes to.
	var index := 0
	for group in ENTRIES:
		var column: VBoxContainer = cols[placement[index]]
		index += 1
		var header := Label.new()
		header.text = group[0]
		header.add_theme_font_size_override("font_size", 14)
		header.add_theme_color_override("font_color", Color(0.45, 0.22, 0.1))
		column.add_child(header)
		for pair in group[1]:
			var row := HBoxContainer.new()
			var key := Label.new()
			key.text = pair[0]
			key.custom_minimum_size = Vector2(62, 0)
			key.add_theme_font_size_override("font_size", 13)
			key.add_theme_color_override("font_color", Color(0.18, 0.32, 0.5))
			var what := Label.new()
			what.text = pair[1]
			what.add_theme_font_size_override("font_size", 13)
			row.add_child(key)
			row.add_child(what)
			column.add_child(row)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		column.add_child(gap)
