extends SceneTree

const Blend = preload("res://scripts/hlod_blend.gd")

func _near(a: float, b: float) -> bool:
    return absf(a - b) < 0.00001

func _initialize() -> void:
    assert(_near(Blend.detail_opacity(0.5, 0.0, 1.25, 2.25), 0.0))
    assert(_near(Blend.detail_opacity(0.5, 0.4, 1.25, 2.25), 1.0))
    var midpoint: float = Blend.detail_opacity(1.75, 0.4, 1.25, 2.25)
    assert(_near(midpoint, 0.5))
    assert(_near(midpoint + (1.0 - midpoint), 1.0))
    assert(_near(Blend.detail_opacity(2.25, 0.4, 1.25, 2.25), 0.0))
    assert(Blend.detail_opacity(2.0, 0.4, 2.25, 3.25) > midpoint)
    assert(_near(Blend.detail_opacity(0.5, 200.0, 1.25, 2.25), 1.0))
    assert(_near(Blend.detail_opacity(0.5, -2.0, 1.25, 2.25), 0.0))
    quit()
