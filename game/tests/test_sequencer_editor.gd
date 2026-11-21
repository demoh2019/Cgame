extends RefCounted
## Cinematic sequencer editor panel + camera rail.

const SequencerPanel = preload("res://addons/cgame_sequencer/sequencer_panel.gd")
const CameraRail = preload("res://addons/cgame_sequencer/camera_rail.gd")
const CinematicSequence = preload("res://scripts/client/cinematic_sequence.gd")


func run(t) -> void:
	var panel: Control = SequencerPanel.new()
	var seq: CinematicSequence = CinematicSequence.new()
	panel.open(seq)

	t.current = "tracks and keys"
	var cam_track: Dictionary = panel.add_track("transform", "cam")
	var fov_track: Dictionary = panel.add_track("float", "fov")
	var ev_track: Dictionary = panel.add_track("event", "fx")
	var an_track: Dictionary = panel.add_track("animation", "anim")
	t.eq(panel.list_tracks().size(), 4, "four tracks listed")
	t.eq(panel.add_track("bogus", "x").size(), 0, "unknown kind rejected")
	panel.add_key(cam_track, 0.0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	panel.add_key(cam_track, 2.0, Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))
	var i1: int = panel.add_key(fov_track, 1.0, 60.0)
	var i0: int = panel.add_key(fov_track, 0.0, 40.0)
	t.eq(i1, 0, "first fov key index")
	t.eq(i0, 0, "earlier key sorts first")
	t.eq(panel.key_count(fov_track), 2, "two fov keys")
	panel.add_key(ev_track, 1.5, "boom")
	panel.add_key(an_track, 0.5, {"target": "rig", "animation": "walk"})
	t.eq(seq.event_tracks["fx"].size(), 1, "event key in sequence")
	t.eq(String((seq.animation_tracks["anim"][0] as Dictionary)["animation"]), "walk", "animation key stored")
	var moved: int = panel.move_key(fov_track, 0, 3.0)
	t.eq(moved, 1, "moved key re-sorted to the end")
	t.near(float(panel.key_at(fov_track, 0)["time"]), 1.0, 0.0001, "other key now first")
	panel.delete_key(fov_track, 0)
	t.eq(panel.key_count(fov_track), 1, "key deleted")
	panel.add_lens_key(0.5, 35.0)
	t.eq(panel.key_count(fov_track), 2, "lens helper reuses fov track")

	t.current = "snapping"
	panel.fps = 30.0
	t.near(panel.snap_time(0.51), 15.0 / 30.0, 0.0001, "snaps to nearest frame")
	t.near(panel.snap_time(1.0 / 30.0 + 0.004), 1.0 / 30.0, 0.0001, "snaps down")
	panel.fps = 24.0
	t.near(panel.snap_time(1.01), 24.0 / 24.0, 0.0001, "24 fps whole second")
	panel.fps = 30.0

	t.current = "shot reorder ripple"
	var p2: Control = SequencerPanel.new()
	var s2: CinematicSequence = CinematicSequence.new()
	p2.open(s2)
	p2.add_shot(0.0, 2.0, "a")
	p2.add_shot(2.0, 5.0, "b")
	p2.add_shot(5.0, 6.0, "c")
	var tk: Dictionary = p2.add_track("float", "fov")
	p2.add_key(tk, 1.0, 10.0)
	p2.add_key(tk, 3.0, 20.0)
	p2.add_key(tk, 5.5, 30.0)
	p2.reorder_shot(0, 2)  # a to the end: b, c, a
	t.eq(String((s2.shots[0] as Dictionary)["camera"]), "b", "b first")
	t.eq(String((s2.shots[1] as Dictionary)["camera"]), "c", "c second")
	t.eq(String((s2.shots[2] as Dictionary)["camera"]), "a", "a last")
	t.near(float((s2.shots[0] as Dictionary)["start"]), 0.0, 0.0001, "b starts at 0")
	t.near(float((s2.shots[1] as Dictionary)["start"]), 3.0, 0.0001, "c ripples to 3")
	t.near(float((s2.shots[2] as Dictionary)["start"]), 4.0, 0.0001, "a ripples to 4")
	t.near(float((s2.shots[2] as Dictionary)["end"]), 6.0, 0.0001, "total span preserved")
	var kt: Array = []
	for k in (s2.float_tracks["fov"] as Array):
		kt.append(float((k as Dictionary)["time"]))
	t.near(kt[0], 1.0, 0.0001, "key in a (t=1) moves to 5")  # sorted: b-key 3->1 first
	t.near(kt[1], 3.5, 0.0001, "key in c (5.5) moves to 3.5")
	t.near(kt[2], 5.0, 0.0001, "key in a moved to 5")
	p2.undo()
	t.near(float((s2.shots[0] as Dictionary)["end"]), 2.0, 0.0001, "undo restores shot order")
	t.near(float((s2.float_tracks["fov"][0] as Dictionary)["time"]), 1.0, 0.0001, "undo restores keys")
	p2.free()

	t.current = "scrubbing"
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	var cam := Camera3D.new()
	root.add_child(cam)
	panel.bind("cam", cam)
	panel.add_shot(0.0, 5.0, "cam")
	panel.scrub(1.0)
	t.near(cam.position.x, 5.0, 0.001, "scrub moves the bound camera")
	t.near(cam.fov, 36.0, 0.01, "fov driven by lens track")
	panel.scrub(2.0)
	t.near(cam.position.x, 10.0, 0.001, "scrub to key end")
	panel.blend_seconds = 0.5
	panel.add_shot(5.0, 8.0, "cam2")
	var bl: Dictionary = panel.blend_preview(5.25)
	t.eq(String(bl["from"]), "cam", "blend from previous camera")
	t.near(float(bl["weight"]), 0.5, 0.0001, "blend weight halfway")
	cam.queue_free()

	t.current = "undo redo"
	var p3: Control = SequencerPanel.new()
	var s3: CinematicSequence = CinematicSequence.new()
	p3.open(s3)
	var tr3: Dictionary = p3.add_track("float", "aperture")
	p3.add_key(tr3, 1.0, 2.0)
	p3.add_key(tr3, 2.0, 4.0)
	t.check(p3.can_undo(), "can undo")
	p3.undo()
	t.eq(p3.key_count(tr3), 1, "undo removes last key")
	p3.redo()
	t.eq(p3.key_count(tr3), 2, "redo restores key")
	p3.undo()
	p3.undo()
	p3.undo()
	t.check(not s3.float_tracks.has("aperture"), "undo reaches empty sequence")
	t.check(not p3.can_undo(), "undo stack exhausted")
	p3.redo()
	t.check(s3.float_tracks.has("aperture"), "empty track survives redo")
	p3.add_key(tr3, 0.0, 1.0)
	t.check(not p3.can_redo(), "new edit clears redo")
	p3.free()

	t.current = "save load"
	var path := "user://test_sequencer_editor.json"
	t.check(panel.save(path), "save ok")
	var p4: Control = SequencerPanel.new()
	t.check(p4.load(path), "load ok")
	t.eq(p4.sequence.shots.size(), panel.sequence.shots.size(), "shots round trip")
	t.eq(p4.list_tracks().size(), 4, "tracks round trip")
	t.near(p4.sequence.sample_transform("cam", 1.0).origin.x, 5.0, 0.001, "transform keys round trip")
	t.check(not p4.load("user://definitely_missing.json"), "missing file fails")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	t.check(not FileAccess.file_exists(path), "temp file removed")
	p4.free()
	panel.free()

	t.current = "camera rail"
	var rail: RefCounted = CameraRail.new()
	for p in [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10), Vector3(0, 5, 10)]:
		rail.add_point(p)
	var total: float = rail.length()
	t.check(total > 30.0 and total < 45.0, "rail length plausible")
	t.near(rail.position_at_distance(0.0).distance_to(Vector3.ZERO), 0.0, 0.001, "starts at first point")
	t.near(rail.position_at_distance(total).distance_to(Vector3(0, 5, 10)), 0.0, 0.001, "ends at last point")
	var step: float = total / 40.0
	var min_s: float = INF
	var max_s: float = 0.0
	var prev: Vector3 = rail.position_at_distance(0.0)
	for i in range(1, 41):
		var cur: Vector3 = rail.position_at_distance(step * float(i))
		var dd: float = cur.distance_to(prev)
		min_s = minf(min_s, dd)
		max_s = maxf(max_s, dd)
		prev = cur
	t.check(min_s > step * 0.93 and max_s < step * 1.001, "uniform speed along arc length")

	t.current = "rail bake"
	var s5: CinematicSequence = CinematicSequence.new()
	var written: int = rail.bake_to_track(s5, "cam", 0.0, 4.0, 10.0)
	t.eq(written, 41, "one key per frame plus end")
	t.eq((s5.transform_tracks["cam"] as Array).size(), 41, "keys in sequence")
	var mid: Transform3D = s5.sample_transform("cam", 2.0)
	t.near(mid.origin.distance_to(rail.position_at_distance(total * 0.5)), 0.0, 0.001, "mid key at half distance")
	var fwd: Vector3 = -mid.basis.z
	t.check(fwd.dot(rail.tangent_at_distance(total * 0.5)) > 0.99, "camera looks along the path")
	var s6: CinematicSequence = CinematicSequence.new()
	var focus_pt := Vector3(5, 0, 5)
	rail.bake_to_track(s6, "cam", 0.0, 4.0, 10.0, null, focus_pt)
	var m6: Transform3D = s6.sample_transform("cam", 1.0)
	var want: Vector3 = (focus_pt - m6.origin).normalized()
	t.check((-m6.basis.z).dot(want) > 0.999, "camera looks at target")
	var s7: CinematicSequence = CinematicSequence.new()
	var ease_curve := Curve.new()
	ease_curve.add_point(Vector2(0, 0), 0.0, 0.0)
	ease_curve.add_point(Vector2(1, 1), 0.0, 0.0)
	rail.bake_to_track(s7, "cam", 0.0, 4.0, 10.0, ease_curve)
	var half: Vector3 = s7.sample_transform("cam", 0.4).origin
	t.check(rail.position_at_distance(0.0).distance_to(half) < total * 0.1, "speed curve slows the start")

	t.current = "focus track"
	var n: int = CameraRail.focus_track_from_target(s6, "cam", "focus_distance", 0.0, 4.0, 10.0, focus_pt)
	t.eq(n, 41, "focus keys written")
	var f1: float = s6.sample_float("focus_distance", 1.0)
	var c1: Vector3 = s6.sample_transform("cam", 1.0).origin
	t.near(f1, c1.distance_to(focus_pt), 0.001, "focus distance equals camera-target distance")
	var c0: Vector3 = s6.sample_transform("cam", 0.0).origin
	t.near(s6.sample_float("focus_distance", 0.0), c0.distance_to(focus_pt), 0.001, "focus at start")
