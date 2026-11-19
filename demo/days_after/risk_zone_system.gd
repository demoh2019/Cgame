extends Node
## Reads native 3D positions and applies survival gameplay only.
## Future multiplayer must run this server-side instead of trusting clients.

const RISK_RULES = preload("res://risk_zone_rules.gd")

var player: Node3D
var _status: Label


func _ready() -> void:
    var overlay := CanvasLayer.new()
    overlay.name = "RiskZoneOverlay"
    add_child(overlay)
    _status = Label.new()
    _status.name = "ZoneStatus"
    _status.position = Vector2(18, 665)
    _status.add_theme_font_size_override("font_size", 17)
    overlay.add_child(_status)


func _physics_process(delta: float) -> void:
    if player == null or not is_instance_valid(player):
        return
    var position := player.global_position
    if _status != null:
        _status.text = RISK_RULES.zone_description(position)
    if float(player.get("health")) <= 0.0:
        return
    var damage: float = RISK_RULES.danger_damage(delta, position)
    if damage > 0.0:
        player.call("take_damage", damage)
