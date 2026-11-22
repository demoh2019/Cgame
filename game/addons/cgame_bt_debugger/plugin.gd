@tool
extends EditorPlugin
## Editor-side inspector for Cgame's native BehaviorTreeRunner Resource graph.
## This inspects selected nodes in the EDITED scene only, not a remote game
## process. The playable AI demo has a separate T-toggle runtime tree overlay.

const MAX_SCENE_NODES := 512

var _dock: VBoxContainer
var _view: Tree
var _summary: Label
var _details: Label
var _runner: Node
var _selection: EditorSelection


func _enter_tree() -> void:
    _dock = VBoxContainer.new()
    _dock.name = "Cgame AI"
    _dock.custom_minimum_size = Vector2(310, 260)

    var heading := Label.new()
    heading.text = "BehaviorTree Inspector"
    _dock.add_child(heading)

    var toolbar := HBoxContainer.new()
    var refresh := Button.new()
    refresh.text = "Refresh"
    refresh.tooltip_text = "Read the selected scene runner's native task graph"
    refresh.pressed.connect(_refresh)
    toolbar.add_child(refresh)
    _dock.add_child(toolbar)

    _summary = Label.new()
    _summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    # A wrapping label needs a width floor: squeezed to ~30 px in a shared dock it wraps one word per line, demands
    # thousands of pixels of height and pushes the whole editor (bottom panels included) off the window.
    _summary.custom_minimum_size = Vector2(260, 0)
    _dock.add_child(_summary)

    _view = Tree.new()
    _view.columns = 3
    _view.column_titles_visible = true
    _view.hide_root = true
    _view.set_column_title(0, "Task")
    _view.set_column_title(1, "Status")
    _view.set_column_title(2, "μs")
    _view.set_column_expand(0, true)
    _view.set_column_expand(1, false)
    _view.set_column_custom_minimum_width(1, 72)
    _view.set_column_expand(2, false)
    _view.set_column_custom_minimum_width(2, 64)
    _view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _view.item_selected.connect(_on_node_selected)
    _dock.add_child(_view)

    _details = Label.new()
    _details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _details.custom_minimum_size = Vector2(260, 0)
    _details.text = "Select a task to inspect its resource path."
    _dock.add_child(_details)

    add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
    _selection = get_editor_interface().get_selection()
    if _selection != null:
        _selection.selection_changed.connect(_on_selection_changed)
    _on_selection_changed()


func _exit_tree() -> void:
    if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed):
        _selection.selection_changed.disconnect(_on_selection_changed)
    _selection = null
    _runner = null
    if _dock != null:
        remove_control_from_docks(_dock)
        _dock.queue_free()
        _dock = null


func _on_selection_changed() -> void:
    _runner = null
    if not ClassDB.class_exists("BehaviorTreeRunner"):
        _refresh()
        return

    if _selection != null:
        for node in _selection.get_selected_nodes():
            if node is Node and node.is_class("BehaviorTreeRunner"):
                _runner = node
                break

    # Selecting the scene root is also convenient for large game scenes.
    if _runner == null:
        var scene_root: Node = get_editor_interface().get_edited_scene_root()
        _runner = _find_runner(scene_root)
    _refresh()


func _find_runner(scene_root: Node) -> Node:
    if scene_root == null:
        return null
    var pending: Array[Node] = [scene_root]
    var scanned := 0
    while not pending.is_empty() and scanned < MAX_SCENE_NODES:
        var node: Node = pending.pop_back()
        scanned += 1
        if node.is_class("BehaviorTreeRunner"):
            return node
        for child in node.get_children():
            if child is Node:
                pending.append(child)
    return null


func _refresh() -> void:
    if _view == null:
        return
    _view.clear()
    _details.text = "Select a task to inspect its resource path."
    if not ClassDB.class_exists("BehaviorTreeRunner"):
        _summary.text = "Cgame engine required. Stock Godot has no native BehaviorTreeRunner."
        return
    if not is_instance_valid(_runner):
        _summary.text = "Select a scene with a BehaviorTreeRunner to view its task hierarchy."
        return
    if not _runner.has_method("get_tree_snapshot"):
        _summary.text = "This Cgame build does not expose get_tree_snapshot()."
        return

    var snapshot: Dictionary = _runner.call("get_tree_snapshot")
    var nodes: Array = snapshot.get("nodes", [])
    _summary.text = "%s: %d nodes | trace %s | tick %d" % [
        _runner.name, nodes.size(),
        "ON" if bool(snapshot.get("trace_enabled", false)) else "OFF",
        int(snapshot.get("tick_index", 0))]
    if bool(snapshot.get("truncated", false)):
        _summary.text += " | GRAPH TRUNCATED"

    var root_item := _view.create_item()
    var items_by_path: Dictionary = {}
    for element in nodes:
        var data: Dictionary = element
        var path: String = str(data.get("path", ""))
        var parent: TreeItem = items_by_path.get(path.get_base_dir(), root_item)
        var item: TreeItem = _view.create_item(parent)
        items_by_path[path] = item
        item.set_metadata(0, path)
        item.set_text(0, str(data.get("task_class", "Task")))
        var status := int(data.get("status", -1))
        match status:
            0:
                item.set_text(1, "SUCCESS")
                item.set_custom_color(1, Color(0.44, 0.86, 0.52))
            1:
                item.set_text(1, "FAILURE")
                item.set_custom_color(1, Color(0.97, 0.42, 0.4))
            2:
                item.set_text(1, "RUNNING")
                item.set_custom_color(1, Color(1.0, 0.76, 0.35))
            _:
                item.set_text(1, "NOT RUN")
                item.set_custom_color(1, Color(0.58, 0.6, 0.67))
        if bool(data.get("executed", false)):
            item.set_text(2, str(int(data.get("duration_usec", 0))))
        else:
            item.set_text(2, "—")
    if nodes.is_empty():
        _summary.text += " | No root task"
    # Edited-scene instances are not live runtime instances. To inspect
    # the currently running demo, press T inside that game window.


func _on_node_selected() -> void:
    var selected := _view.get_selected()
    if selected == null:
        return
    _details.text = "Path: %s | Edited scene (not remote runtime)" % str(selected.get_metadata(0))
