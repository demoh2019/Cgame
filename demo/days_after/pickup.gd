extends Area3D
## Resource pickup collected by world.gd when the survivor presses E.

var item_type := "scrap"
var quantity := 1
var bob_time := 0.0
var origin_height := 0.0


func configure(type_name: String, amount: int) -> void:
    item_type = type_name
    quantity = maxi(1, amount)


func _ready() -> void:
    collision_layer = 0
    collision_mask = 0
    monitoring = false
    add_to_group("loot")
    origin_height = position.y

    var visual := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = 0.36
    mesh.height = 0.72
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    match item_type:
        "food":
            material.albedo_color = Color(0.94, 0.70, 0.22)
        "water":
            material.albedo_color = Color(0.21, 0.72, 0.94)
        _:
            material.albedo_color = Color(0.66, 0.65, 0.63)
    visual.material_override = material
    add_child(visual)


func _process(delta: float) -> void:
    bob_time += delta
    position.y = origin_height + sin(bob_time * 2.5) * 0.12
