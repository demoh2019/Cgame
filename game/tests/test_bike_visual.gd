extends RefCounted
## Rendering stays an isolated 3D presentation; server movement remains authoritative.

const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")


func run(t) -> void:
	t.current = "bike geometry"
	var visual := TrailBikeVisual.new()
	visual.build()
	t.eq(visual.wheel_count(), 2, "procedural bicycle has two animated wheels")
	t.check(visual.get_node_or_null("WheelRear") != null, "rear wheel exists")
	t.check(visual.get_node_or_null("WheelFront") != null, "front wheel exists")
	var children: int = visual.get_child_count()
	visual.build()
	t.eq(visual.get_child_count(), children, "building twice does not duplicate geometry")

	t.current = "mount visibility and wheel animation"
	visual.set_riding(false, 7.5, 0.1)
	t.eq(visual.visible, false, "not riding does not show a floating bike")
	var front: Node3D = visual.get_node("WheelFront")
	var angle: float = front.rotation.x
	visual.set_riding(true, 0.0, 0.1)
	t.eq(front.rotation.x, angle, "stationary wheels do not spin")
	visual.set_riding(true, 5.0, 0.1)
	t.check(absf(front.rotation.x - angle) > 0.01, "wheels turn when bike moves")
	t.eq(visual.visible, true, "mounted player has visible bike")
	visual.set_riding(false)
	t.eq(visual.visible, false, "dismount hides bicycle")
	visual.free()
