extends RefCounted
## Server raid AoE telegraph is an actual visual, with bounded local lifetime.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const RaidTelegraph = preload("res://scripts/client/raid_telegraph.gd")


func run(t) -> void:
	t.current = "raid danger circle validates server event fields"
	var world := WorldGen.new(24)
	var marker := RaidTelegraph.new()
	t.check(not marker.visible, "raid marker begins hidden")
	var warning := {"type": "raid_warning", "id": 1337,
		"x": 800.0, "z": 100.0, "radius": RaidEncounter.SLAM_RADIUS,
		"seconds": RaidEncounter.SLAM_WARNING}
	t.check(marker.consume(warning, world), "real slam warning creates visible overlay")
	t.check(marker.visible, "danger circle is shown")
	t.eq(marker.encounter_id, 1337, "warning is bound to encounter ID")
	t.near(marker.remaining_seconds, RaidEncounter.SLAM_WARNING, 0.0001,
		"countdown uses server-provided warning window")
	t.near(marker.position.x, 800.0, 0.0001, "warning uses authoritative world X")
	t.near(marker.position.z, 100.0, 0.0001, "warning uses authoritative world Z")
	t.near(marker.position.y, world.height_at(800.0, 100.0) + 0.16, 0.001,
		"warning circle is anchored to world terrain")
	t.near((marker.get_node("DangerDisk").mesh as CylinderMesh).top_radius,
		RaidEncounter.SLAM_RADIUS, 0.0001, "real mesh matches lethal radius")
	for value in [NAN, INF, -2.0, 100.0]:
		var bad: Dictionary = warning.duplicate(true)
		bad["radius"] = value
		t.check(not marker.consume(bad, world), "invalid oversized/risky radius rejected")
	t.check(marker.visible, "bad follow-up warning cannot erase legitimate telegraph")
	var invalid: Dictionary = warning.duplicate(true)
	invalid["seconds"] = INF
	t.check(not marker.consume(invalid, world), "infinite timer rejected")
	invalid = warning.duplicate(true)
	invalid["x"] = NAN
	t.check(not marker.consume(invalid, world), "non-finite coordinates rejected")
	invalid = warning.duplicate(true)
	invalid["id"] = 0
	t.check(not marker.consume(invalid, world), "missing boss identity rejected")

	t.current = "countdown, stale events, slam resolution and cleanup"
	marker._process(0.75)
	t.check(marker.visible, "warning persists during telegraph window")
	t.near(marker.remaining_seconds, RaidEncounter.SLAM_WARNING - 0.75, 0.01,
		"countdown advances with frame delta")
	t.check(not marker.consume({"type": "raid_slam", "id": 9000}, world),
		"old boss slam cannot clear new encounter")
	t.check(marker.visible, "new warning stays visible after unrelated slam")
	t.check(marker.consume({"type": "raid_slam", "id": 1337}, world),
		"matching server slam dismisses area circle")
	t.check(not marker.visible, "warning disappears after impact")
	t.eq(marker.encounter_id, -1, "boss ID cleared with visual")
	t.check(marker.consume(warning, world), "later warning can display again")
	marker._process(10.0)
	t.check(not marker.visible, "expired telegraph is automatically hidden")
	t.near(marker.remaining_seconds, 0.0, 0.0001,
		"expired marker does not keep phantom countdown")
	t.check(marker.consume(warning, world), "new attack can show after expiration")
	t.check(marker.consume({"type": "raid_defeated", "id": 1337}, world),
		"boss defeat clears pending attack circle")
	t.check(not marker.visible, "victory does not leave stale marker")
	t.check(marker.consume(warning, world), "warning can be armed for retreat")
	t.check(marker.consume({"type": "raid_expired", "id": 1337}, world),
		"encounter timeout also clears the telegraph")
	marker.free()
