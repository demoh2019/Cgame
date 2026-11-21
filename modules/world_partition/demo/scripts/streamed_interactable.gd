extends Node3D

# Reusable interactive component. The engine discovers it through a group,
# not through a custom save method on the parent cell script.
@export_enum("chest", "switch", "gate") var kind := "chest"

var active := false
var use_count := 0

func configure(p_kind: String) -> void:
    kind = p_kind

func _ready() -> void:
    add_to_group("streaming_stateful")
    _create_visuals()
    _refresh_visuals()

func _create_visuals() -> void:
    var pedestal := MeshInstance3D.new()
    pedestal.name = "Pedestal"
    var base := BoxMesh.new()
    base.size = Vector3(5.0, 1.2, 4.0)
    pedestal.mesh = base
    pedestal.position.y = 0.6
    add_child(pedestal)

    var feature := MeshInstance3D.new()
    feature.name = "Mechanism"
    var shape := BoxMesh.new()
    shape.size = Vector3(3.0, 2.0, 2.5)
    feature.mesh = shape
    feature.position.y = 2.0
    add_child(feature)

    var indicator := Label3D.new()
    indicator.name = "InteractionLabel"
    indicator.position.y = 4.4
    indicator.font_size = 56
    indicator.pixel_size = 0.01
    add_child(indicator)

func _refresh_visuals() -> void:
    var feature := get_node_or_null("Mechanism") as MeshInstance3D
    var label := get_node_or_null("InteractionLabel") as Label3D
    if feature != null:
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color(0.2, 0.85, 0.47) if active else Color(0.85, 0.37, 0.12)
        mat.roughness = 0.4
        feature.material_override = mat
        feature.rotation.z = -0.35 if active else 0.0
    if label != null:
        match kind:
            "chest":
                label.text = "TREASURE OPENED" if active else "TREASURE CHEST [E]"
            "switch":
                label.text = "ARENA SWITCH ON [E]" if active else "ARENA SWITCH OFF [E]"
            "gate":
                label.text = "CHAMPION GATE OPEN" if active else "CHAMPION GATE LOCKED [E]"

func interact() -> bool:
    if kind != "switch" and active:
        return false
    active = (not active) if kind == "switch" else true
    use_count += 1
    _refresh_visuals()
    return true

func capture_streaming_object_state() -> Dictionary:
    return {"active": active, "uses": use_count}

func restore_streaming_object_state(state: Dictionary) -> void:
    active = bool(state.get("active", false))
    use_count = clampi(int(state.get("uses", 0)), 0, 1000000)
    _refresh_visuals()
