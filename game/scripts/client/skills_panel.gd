extends PanelContainer
## The skill tree window (K): one tab per branch, every skill with its level and progress, the perks it unlocks,
## and the bonuses you have right now. Buying a perk is a request to the server, which decides.

const Skills = preload("res://scripts/shared/skills.gd")

var client
var _title: Label
var _tabs: TabContainer
var _bonus_label: Label
var _dirty := true
var _refresh_timer := 0.0
var _last_signature := ""


func setup(p_client) -> void:
	client = p_client
	client.snapshot_received.connect(func() -> void: _dirty = true)
	custom_minimum_size = Vector2(820, 560)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	background.set_border_width_all(2)
	background.border_color = Color(0.9, 0.75, 0.3)
	background.set_content_margin_all(10)
	add_theme_stylebox_override("panel", background)
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(800, 440)
	box.add_child(_tabs)
	_bonus_label = Label.new()
	_bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_bonus_label.custom_minimum_size = Vector2(800, 50)
	box.add_child(_bonus_label)


func toggle() -> void:
	visible = not visible
	_dirty = true
	if visible:
		set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _process(delta: float) -> void:
	if not visible or client == null:
		return
	_refresh_timer += delta
	if _dirty and _refresh_timer >= 0.25:
		_refresh_timer = 0.0
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	var skills = client.skills
	var signature := str(skills.to_dict()) + str(client.skill_points)
	if signature == _last_signature:
		return
	_last_signature = signature
	var current_tab := _tabs.current_tab
	for child in _tabs.get_children():
		child.queue_free()
	_title.text = "Skills    total level %d    unspent points: %d    (K closes)" % [skills.total_level(), client.skill_points]
	for branch_id in Skills.BRANCHES:
		var branch: Dictionary = Skills.BRANCHES[branch_id]
		var scroll := ScrollContainer.new()
		scroll.name = String(branch["name"])
		var list := VBoxContainer.new()
		list.custom_minimum_size = Vector2(770, 0)
		scroll.add_child(list)
		for skill_id in branch["skills"]:
			_add_skill(list, skills, String(skill_id))
		_tabs.add_child(scroll)
	_tabs.current_tab = clampi(current_tab, 0, _tabs.get_child_count() - 1)
	var lines: Array[String] = []
	var bonuses: Dictionary = skills.all_bonuses()
	for name in bonuses:
		lines.append(Skills.describe_bonus(String(name), float(bonuses[name])))
	_bonus_label.text = "Active bonuses: " + (", ".join(lines) if not lines.is_empty() else "none yet - every action trains a skill")


func _add_skill(list: VBoxContainer, skills, skill_id: String) -> void:
	var info: Dictionary = Skills.SKILLS[skill_id]
	var level: int = skills.level(skill_id)
	var header := HBoxContainer.new()
	list.add_child(header)
	var name_label := Label.new()
	name_label.text = "%s   level %d%s" % [info["name"], level, " (MAX)" if level >= Skills.MAX_LEVEL else ""]
	name_label.custom_minimum_size = Vector2(260, 0)
	name_label.add_theme_font_size_override("font_size", 16)
	header.add_child(name_label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(240, 18)
	bar.max_value = 1.0
	bar.value = skills.progress(skill_id)
	bar.show_percentage = false
	header.add_child(bar)
	var xp_label := Label.new()
	xp_label.text = "  %d xp   trained by: %s" % [int(skills.xp[skill_id]), info["trained_by"]]
	xp_label.add_theme_font_size_override("font_size", 12)
	header.add_child(xp_label)
	var passives: Array[String] = []
	for bonus_name in info["passive"]:
		passives.append(Skills.describe_bonus(String(bonus_name), float(info["passive"][bonus_name]) * float(level - 1)))
	var passive_label := Label.new()
	passive_label.text = "    from levels: " + ", ".join(passives)
	passive_label.add_theme_font_size_override("font_size", 12)
	list.add_child(passive_label)
	for perk_id in Skills.PERKS:
		var perk: Dictionary = Skills.PERKS[perk_id]
		if perk["skill"] != skill_id:
			continue
		var rank: int = skills.rank(perk_id)
		var need: Dictionary = skills.next_rank_requirement(perk_id)
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var text := "    %s  %d/%d  -  %s" % [perk["name"], rank, perk["max_rank"], perk["desc"]]
		var buyable := false
		if need.is_empty():
			text += "   [maxed]"
		else:
			text += "   [level %d, %d point%s]" % [need["level"], need["cost"], "s" if int(need["cost"]) != 1 else ""]
			if perk.has("requires"):
				text += "   needs %s %d" % [Skills.PERKS[perk["requires"]]["name"], int(perk.get("requires_rank", 1))]
			buyable = level >= int(need["level"]) and client.skill_points >= int(need["cost"]) and (not perk.has("requires") or skills.rank(String(perk["requires"])) >= int(perk.get("requires_rank", 1)))
		button.text = text
		button.disabled = not buyable
		button.pressed.connect(func() -> void: client.buy_perk(perk_id))
		list.add_child(button)
	list.add_child(HSeparator.new())
