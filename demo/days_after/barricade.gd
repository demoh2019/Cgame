extends StaticBody3D
## A repairable, destructible player-built obstacle with native 3D collision.
## Construction consumes gathered materials in BuildingSystem; repairs consume
## a separate wood unit only after validation. No new engine API is needed.

signal destroyed

const MAX_HEALTH: float = 120.0
const REPAIR_AMOUNT: float = 40.0
const REPAIR_COST := {"wood_t1": 1}
const SIZE := Vector3(1.8, 1.4, 0.5)

var health: float = MAX_HEALTH
var display_name: String = "баррикада (E — ремонт)"
var _visual: MeshInstance3D


func _ready() -> void:
    collision_layer = 1
    collision_mask = 0
    add_to_group("player_barricades")

    var collision := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = SIZE
    collision.shape = box
    add_child(collision)

    _visual = MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = SIZE
    _visual.mesh = mesh
    add_child(_visual)
    _refresh_material()


func _refresh_material() -> void:
    if _visual == null:
        return
    var material := StandardMaterial3D.new()
    material.roughness = 0.9
    var fraction := health / MAX_HEALTH
    material.albedo_color = Color("#5a4334").lerp(Color("#a88959"), fraction)
    _visual.material_override = material


func take_damage(amount: float) -> void:
    if amount <= 0.0 or not is_finite(amount) or health <= 0.0:
        return
    health = maxf(0.0, health - amount)
    _refresh_material()
    if health <= 0.0:
        destroyed.emit()
        queue_free()


func interact(player: Node) -> void:
    if health <= 0.0 or not player.has_method("try_spend_items"):
        return
    if float(player.get("health")) <= 0.0:
        return
    if health >= MAX_HEALTH:
        player.set("last_message", "Баррикада не требует ремонта.")
        return
    if not bool(player.call("try_spend_items", REPAIR_COST)):
        player.set("last_message", "Для ремонта нужна древесина T1.")
        return
    health = minf(MAX_HEALTH, health + REPAIR_AMOUNT)
    _refresh_material()
    player.set("last_message", "Баррикада отремонтирована. Прочность %d/%d." % [roundi(health), roundi(MAX_HEALTH)])
