extends RefCounted
## Personal world-map click navigation remains valid and unreplicated.
const Navigation = preload("res://scripts/shared/travel_navigation.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WorldMap = preload("res://scripts/client/world_map.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


func run(t) -> void:
	t.current = "pointer projects to world coordinates and refuses off-island clicks"
	var panel := Rect2(Vector2(100.0, 50.0), Vector2(500.0, 500.0))
	t.eq(Navigation.world_from_map(panel.get_center(), panel,
		WorldMap.SPAN, WorldGen.WORLD_RADIUS), Vector2.ZERO,
		"map centre is the safe hub")
	var target := Vector2(1250.0, -890.0)
	var click := panel.position + (target / WorldMap.SPAN + Vector2(0.5, 0.5)) * panel.size
	var computed: Vector2 = Navigation.world_from_map(
		click, panel, WorldMap.SPAN, WorldGen.WORLD_RADIUS)
	t.near(computed.x, target.x, 0.01, "east coordinate matches true island position")
	t.near(computed.y, target.y, 0.01, "north coordinate matches true island position")
	t.check(not Navigation.world_from_map(Vector2(50, 80), panel,
		WorldMap.SPAN, WorldGen.WORLD_RADIUS).is_finite(), "outside map ignored")
	t.check(not Navigation.world_from_map(Vector2(598, 300), panel,
		WorldMap.SPAN, WorldGen.WORLD_RADIUS).is_finite(), "ocean margin ignored")
	t.check(not Navigation.world_from_map(Vector2(INF, 300), panel,
		WorldMap.SPAN, WorldGen.WORLD_RADIUS).is_finite(), "invalid pointer ignored")
	t.check(not Navigation.world_from_map(panel.get_center(), Rect2(),
		WorldMap.SPAN, WorldGen.WORLD_RADIUS).is_finite(), "undrawn map ignored")
	t.check(not Navigation.world_from_map(panel.get_center(), panel,
		0.0, WorldGen.WORLD_RADIUS).is_finite(), "invalid projection refused")

	t.current = "map pin and radar share one private client-only destination"
	var map := WorldMap.new()
	var radar := Radar.new()
	map.personal_waypoint_changed.connect(radar.set_personal_waypoint)
	t.check(map.set_waypoint(target), "valid island coordinate accepted")
	t.eq(map.waypoint, target, "world map stores the clicked destination")
	t.eq(radar.personal_waypoint, target, "signal updates local radar immediately")
	t.check(not map.set_waypoint(Vector2(INF, 0)), "nonfinite target ignored")
	t.check(not map.set_waypoint(Vector2(3500, 0)), "beyond island radius ignored")
	t.eq(radar.personal_waypoint, target, "rejected updates preserve current route")
	t.eq(Navigation.compass(Vector2.ZERO, target), "NE",
		"navigation uses the same eight-way compass as caravan markers")
	t.check(Navigation.distance_meters(Vector2.ZERO, target) > 0,
		"map can display distance from live player position")
	map.clear_waypoint()
	t.check(not map.waypoint.is_finite(), "right-click clearing removes map pin")
	t.check(not radar.personal_waypoint.is_finite(), "clearing also removes radar pointer")
	radar.set_personal_waypoint(Vector2(4000, 0))
	t.check(not radar.personal_waypoint.is_finite(), "radar itself refuses forged off-map targets")
	map.free()
	radar.free()
