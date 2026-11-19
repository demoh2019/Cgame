extends CanvasLayer
## Optional tactical overlay. Does not modify or own gameplay rules.

const Minimap = preload("res://minimap.gd")

var map_control: Control


func _ready() -> void:
    layer = 9
    map_control = Minimap.new()
    map_control.name = "Minimap"
    add_child(map_control)
    map_control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    map_control.offset_left = -220.0
    map_control.offset_top = 16.0
    map_control.offset_right = -16.0
    map_control.offset_bottom = 220.0

    var legend := Label.new()
    legend.name = "Legend"
    legend.text = "M: карта | красный: заражённые\nжёлтый: сырьё | зелёный: припасы | синий: убежище"
    legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(legend)
    legend.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    legend.offset_left = -330.0
    legend.offset_right = -14.0
    legend.offset_top = 224.0
    legend.offset_bottom = 276.0


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
        map_control.visible = not map_control.visible
        var legend := get_node_or_null("Legend") as Control
        if legend != null:
            legend.visible = map_control.visible
