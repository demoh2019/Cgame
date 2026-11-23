extends RefCounted
## World map must accept keyboard focus when opened via J, including when
## an ancestor overlay disables focus recursively. Regresses Control warning:
## "This control can't grab focus" from world_map.gd:118.

const WorldMap = preload("res://scripts/client/world_map.gd")


func run(t) -> void:
	t.current = "world map keyboard focus survives disabled parent"
	var parent := Control.new()
	parent.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	var map := WorldMap.new()
	parent.add_child(map)
	map.setup(null)
	t.eq(map.focus_mode, Control.FOCUS_ALL,
		"world map explicitly allows keyboard focus")
	t.eq(map.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_ENABLED,
		"world map overrides parent focus disabling")
	t.eq(map.get_focus_mode_with_override(), Control.FOCUS_ALL,
		"recursive parent settings cannot silently block map shortcuts")
	t.eq(map.accessibility_name, "World map",
		"keyboard-focusable map has an accessibility label")
	# The J shortcut toggles the same map control. Populate a dummy site to
	# avoid generating POIs: no world or client needed for the focus check.
	map._sites.append({})
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null or scene_tree.root == null:
		t.check(false, "scene tree is available for map focus validation")
		parent.free()
		return
	scene_tree.root.add_child(parent)
	map.toggle()
	t.check(map.visible, "J toggle opens the map")
	t.check(map.has_focus(), "the open map really receives keyboard focus")
	map.toggle()
	t.check(not map.visible, "J toggle closes the map")
	parent.free()
