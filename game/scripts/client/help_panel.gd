extends PanelContainer
## Every control of the game on one screen (F2). The same keys work in the local and the online client.

const ENTRIES := [
	["MOVE AND FIGHT", [
		["WASD", "move"], ["Shift", "sprint"], ["Space", "dodge"], ["Mouse", "aim; left click attacks"], ["G", "weapon skill"],
		["F1", "guardian taunt"], ["4", "next weapon"], ["5", "equip armor"], ["Wheel", "zoom"]]],
	["GATHER AND CRAFT", [
		["E", "gather / open crate / take loot"], ["C", "crafting window"], ["0", "quick-cook best fish"],
		["T", "cast fishing rod (Shift: baited)"], ["I / Tab", "inventory (click: use or equip; right click: stash)"], ["B", "stash (at the hub)"]]],
	["SURVIVE", [
		["1", "eat"], ["2", "drink bottle"], ["3", "bandage"], ["6", "antiseptic"], ["7", "antibiotics"], ["8", "heat pack"],
		["F / R", "drink from a lake (filter prevents infection)"], [".", "frontier stim"], ["/", "scent salve"], ["Z", "rest at the hub or a fire"]]],
	["BUILD AND DEFEND", [
		["U", "build barricade"], ["H", "repair"], ["Y", "upgrade"], ["X", "dismantle"], ["O", "light campfire"],
		["9", "refuel fire"], ["-", "extinguish fire"], [",", "throw noise decoy"]]],
	["TOWN", [
		["N", "buy water"], ["V", "sell materials (Shift: fish)"], ["P", "accept contract (Shift: turn in, Ctrl: daily bounty)"],
		["K", "skills and perks"], ["Enter", "chat"], ["M", "radar"], ["F2", "this help"], ["F3", "full text readout"]]],
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
		header.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35))
		column.add_child(header)
		for pair in group[1]:
			var row := HBoxContainer.new()
			var key := Label.new()
			key.text = pair[0]
			key.custom_minimum_size = Vector2(62, 0)
			key.add_theme_font_size_override("font_size", 13)
			key.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
			var what := Label.new()
			what.text = pair[1]
			what.add_theme_font_size_override("font_size", 13)
			row.add_child(key)
			row.add_child(what)
			column.add_child(row)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		column.add_child(gap)
