extends Area3D

## Physical camp vendor. E sells one available scavenged stack unit;
## B buys one bottle of water while looking at the terminal.
@export var display_name: String = "Станция обмена: E продать, B купить воду"

const SELL_PRIORITY := [
    "infected_sample", "stone_t2", "wood_t2", "fiber_t2",
    "stone_t1", "wood_t1", "fiber_t1"
]


func _ready() -> void:
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(1.5, 1.5, 1.0)
    collision.shape = shape
    add_child(collision)

    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = shape.size
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#cfb368")
    material.metallic = 0.3
    visual.material_override = material
    add_child(visual)


func interact(player: Node) -> void:
    if not player.has_method("trade_sell") or not player.has_method("get_item_count"):
        return
    for item_id in SELL_PRIORITY:
        if int(player.call("get_item_count", item_id)) > 0:
            player.call("trade_sell", item_id, 1)
            return
    player.set("last_message", "Нет пригодных ресурсов для обмена.")


func buy(player: Node) -> void:
    if player.has_method("trade_buy"):
        player.call("trade_buy", "water", 1)
