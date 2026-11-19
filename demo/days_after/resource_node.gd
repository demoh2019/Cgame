extends Area3D

## Harvestable world resource. Gathering rules and inventory belong to the
## player, while this node provides a finite deposit with interaction collision.

@export_enum("wood", "stone", "fiber") var resource_kind: String = "wood"
@export_range(1, 5) var tier: int = 1
@export_range(1, 10) var yield_count: int = 2
@export var display_name: String = "Ресурсы"

var depleted: bool = false
@export_range(1.0, 600.0) var respawn_seconds: float = 45.0
var _respawn_timer: Timer


func _ready() -> void:
    var collision := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = 0.85
    collision.shape = shape
    add_child(collision)

    var visual := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.35
    mesh.bottom_radius = 0.5
    mesh.height = 0.7
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    match resource_kind:
        "wood":
            material.albedo_color = Color("#80583b")
        "stone":
            material.albedo_color = Color("#939a9c")
        "fiber":
            material.albedo_color = Color("#5a9f69")
    if tier > 1:
        material.emission_enabled = true
        material.emission = material.albedo_color * 0.2
    visual.material_override = material
    add_child(visual)

    _respawn_timer = Timer.new()
    _respawn_timer.name = "RespawnTimer"
    _respawn_timer.one_shot = true
    _respawn_timer.wait_time = respawn_seconds
    add_child(_respawn_timer)
    _respawn_timer.timeout.connect(_restore)


func interact(player: Node) -> void:
    if depleted or not player.has_method("try_gather"):
        return
    if bool(player.call("try_gather", resource_kind, tier, yield_count)):
        depleted = true
        visible = false
        set_deferred("collision_layer", 0)
        _respawn_timer.start()


func _restore() -> void:
    depleted = false
    visible = true
    set_deferred("collision_layer", 1)
