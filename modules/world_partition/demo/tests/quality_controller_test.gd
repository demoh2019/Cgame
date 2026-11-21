extends SceneTree
const Controller = preload("res://scripts/streaming_quality.gd")

func _initialize() -> void:
    var controller = Controller.new()
    assert(controller.level == 1)
    var balanced: Dictionary = controller.get_profile()
    assert(balanced["proxy_load"] == 4)
    assert(balanced["unload_budget"] == 16)
    balanced["proxy_load"] = 999
    assert(controller.get_profile()["proxy_load"] == 4)

    # Low FPS must downgrade only after a complete sampling window.
    assert(not controller.sample(1.0, 44.0))
    assert(not controller.sample(1.0, 44.0))
    assert(controller.sample(1.0, 44.0))
    assert(controller.level == 0)

    # The cooldown suppresses immediate changes, even at high FPS.
    for i in 10:
        assert(not controller.sample(1.0, 65.0))
    assert(controller.level == 0)
    for i in 2:
        assert(not controller.sample(1.0, 65.0))
    assert(controller.sample(1.0, 65.0))
    assert(controller.level == 1)

    # Manual override must block automatic changes and clamp tier values.
    controller.automatic = false
    for i in 12:
        assert(not controller.sample(1.0, 12.0))
    assert(controller.level == 1)
    assert(controller.set_level(999))
    assert(controller.level == 2)
    assert(not controller.set_level(2))
    assert(controller.get_profile()["detail_load"] == 2)
    assert(controller.get_profile()["unload_budget"] == 32)
    assert(not controller.sample(-1.0, 45.0))
    quit()
