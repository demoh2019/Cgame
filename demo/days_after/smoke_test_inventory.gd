extends SceneTree

## Regression test for the Days After scavenging loop.
## Run: cgame --headless --path demo/days_after --script res://smoke_test_inventory.gd
## Does not require main.gd, textures, an editor, or external assets.

var failures := 0


func _initialize() -> void:
    call_deferred("_run")


func _expect(condition: bool, description: String) -> void:
    if not condition:
        failures += 1
        push_error("Days After inventory: " + description)


func _make_player() -> CharacterBody3D:
    var player := load("res://player.gd").new() as CharacterBody3D
    player.name = "Player"

    var body_collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.35
    capsule.height = 1.8
    body_collision.shape = capsule
    player.add_child(body_collision)

    # player.gd accesses these nodes through @onready paths.
    var head := Node3D.new()
    head.name = "Head"
    player.add_child(head)
    var camera := Camera3D.new()
    camera.name = "Camera3D"
    head.add_child(camera)
    var ray := RayCast3D.new()
    ray.name = "AimRay"
    ray.target_position = Vector3(0.0, 0.0, -3.0)
    ray.collide_with_areas = true
    camera.add_child(ray)

    root.add_child(player)
    return player


func _make_pickup(kind: String, amount: int) -> Area3D:
    var pickup := load("res://pickup.gd").new() as Area3D
    pickup.set("item_type", kind)
    pickup.set("quantity", amount)
    root.add_child(pickup)
    return pickup


func _run() -> void:
    var player := _make_player()
    await process_frame

    _expect(player.get_node_or_null("Head/Camera3D/AimRay") != null,
            "player's aim ray was not created")
    _expect(is_equal_approx(float(player.get("health")), 100.0),
            "new player should begin with 100 health")

    var food := _make_pickup("food", 2)
    food.call("interact", player)
    food.call("interact", player)
    _expect(int(player.get("food_count")) == 2,
            "a pickup must transfer its quantity exactly once")
    _expect(bool(food.get("collected")), "picked-up food must be marked collected")

    player.set("hunger", 65.0)
    player.call("consume_food")
    _expect(int(player.get("food_count")) == 1,
            "eating must consume exactly one food item")
    _expect(is_equal_approx(float(player.get("hunger")), 100.0),
            "hunger must be clamped at 100")

    var water := _make_pickup("water", 1)
    water.call("interact", player)
    _expect(int(player.get("water_count")) == 1, "water pickup was not transferred")
    player.set("thirst", 40.0)
    player.call("consume_water")
    _expect(int(player.get("water_count")) == 0,
            "drinking must consume exactly one water item")
    _expect(is_equal_approx(float(player.get("thirst")), 85.0),
            "drinking should restore 45 thirst")

    player.call("consume_water")
    _expect(int(player.get("water_count")) == 0,
            "empty inventory should never become negative")

    var invalid := _make_pickup("unsupported_type", 3)
    invalid.call("interact", player)
    _expect(not bool(invalid.get("collected")),
            "unsupported pickups must not disappear")
    _expect(int(player.get("food_count")) == 1,
            "unsupported pickups must not modify inventory")

    var negative := _make_pickup("food", -4)
    negative.call("interact", player)
    _expect(int(player.get("food_count")) == 1,
            "negative pickup quantity must not modify inventory")

    player.queue_free()
    invalid.queue_free()
    negative.queue_free()
    await process_frame

    if failures == 0:
        print("PASS: Days After player, food, water, one-shot pickup, and inventory bounds.")
    quit(0 if failures == 0 else 1)
