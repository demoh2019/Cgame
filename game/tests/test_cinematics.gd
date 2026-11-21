extends RefCounted
## Cinematic sequence data model and player.

const Seq = preload("res://scripts/client/cinematic_sequence.gd")
const Player = preload("res://scripts/client/cinematic_player.gd")

var _fired: Array = []
var _finished_count: int = 0


func _on_event(event_name: String, args: Array) -> void:
	_fired.append([event_name, args])


func _on_finished() -> void:
	_finished_count += 1


func run(t) -> void:
	t.current = "transform interpolation"
	var s := Seq.new()
	s.length = 10.0
	var qa := Quaternion.IDENTITY
	var qb := Quaternion(Vector3.UP, PI * 0.5)
	s.add_transform_key("cam", {"time": 4.0, "position": Vector3(10, 0, 0), "rotation": qb, "interp": "linear"})
	s.add_transform_key("cam", {"time": 0.0, "position": Vector3.ZERO, "rotation": qa, "interp": "linear"})
	var mid: Transform3D = s.sample_transform("cam", 2.0)
	t.near(mid.origin.x, 5.0, 0.0001, "linear midpoint position")
	var half: Quaternion = mid.basis.get_rotation_quaternion()
	t.near(half.angle_to(qa), PI * 0.25, 0.001, "slerp midpoint is half the rotation")
	t.near(half.angle_to(qb), PI * 0.25, 0.001, "slerp midpoint equidistant")
	t.near(s.sample_transform("cam", -1.0).origin.x, 0.0, 0.0001, "before first key holds first")
	t.near(s.sample_transform("cam", 99.0).origin.x, 10.0, 0.0001, "after last key holds last")
	t.eq(s.sample_transform("none", 1.0), Transform3D.IDENTITY, "missing track is identity")

	var c := Seq.new()
	c.add_transform_key("c", {"time": 0.0, "position": Vector3(0, 0, 0), "interp": "cubic"})
	c.add_transform_key("c", {"time": 1.0, "position": Vector3(1, 0, 0), "interp": "cubic", "rotation": Quaternion(Vector3.UP, 1.0)})
	c.add_transform_key("c", {"time": 2.0, "position": Vector3(1, 1, 0), "interp": "cubic", "rotation": Quaternion(Vector3.UP, 0.5)})
	c.add_transform_key("c", {"time": 3.0, "position": Vector3(3, 1, 0), "interp": "cubic"})
	t.near(c.sample_transform("c", 1.0).origin.distance_to(Vector3(1, 0, 0)), 0.0, 0.0001, "cubic passes through keys")
	t.near(c.sample_transform("c", 2.0).origin.distance_to(Vector3(1, 1, 0)), 0.0, 0.0001, "cubic passes through key 2")
	var cm: Vector3 = c.sample_transform("c", 1.5).origin
	t.check(cm.distance_to(Vector3(1, 0.5, 0)) > 0.001, "cubic differs from linear")
	var q15: Quaternion = c.sample_transform("c", 1.5).basis.get_rotation_quaternion()
	t.near(q15.length(), 1.0, 0.0001, "squad result is unit")
	t.near(c.sample_transform("c", 1.0).basis.get_rotation_quaternion().angle_to(Quaternion(Vector3.UP, 1.0)), 0.0, 0.001, "squad hits key rotation")

	var k := Seq.new()
	k.add_transform_key("k", {"time": 0.0, "position": Vector3.ZERO, "interp": "constant"})
	k.add_transform_key("k", {"time": 2.0, "position": Vector3(5, 0, 0)})
	t.eq(k.sample_transform("k", 1.9).origin.x, 0.0, "constant holds until next key")
	t.eq(k.sample_transform("k", 2.0).origin.x, 5.0, "constant steps at next key")

	t.current = "float easing"
	var f := Seq.new()
	f.add_float_key("fov", {"time": 0.0, "value": 40.0, "ease": "linear"})
	f.add_float_key("fov", {"time": 2.0, "value": 80.0, "ease": "in"})
	f.add_float_key("fov", {"time": 4.0, "value": 20.0, "ease": "constant"})
	f.add_float_key("fov", {"time": 6.0, "value": 0.0})
	t.near(f.sample_float("fov", 1.0), 60.0, 0.0001, "linear ease midpoint")
	t.near(f.sample_float("fov", 3.0), 80.0 + (20.0 - 80.0) * 0.25, 0.0001, "ease-in quarter at half")
	t.near(f.sample_float("fov", 5.0), 20.0, 0.0001, "constant ease holds")
	t.near(f.sample_float("fov", 9.0), 0.0, 0.0001, "holds last value")
	t.near(Seq.apply_ease(0.5, "in_out"), 0.5, 0.0001, "smoothstep midpoint")
	t.near(Seq.apply_ease(0.5, "out"), 0.75, 0.0001, "ease-out midpoint")

	t.current = "events"
	var e := Seq.new()
	e.length = 10.0
	e.add_event("a", 1.0, "one", [1])
	e.add_event("b", 3.0, "three")
	e.add_event("a", 2.0, "two")
	e.add_animation_key("anim", 2.5, "actor", "wave")
	var ev: Array = e.events_between(0.0, 5.0)
	t.eq(ev.size(), 3, "three events in range")
	t.eq(String((ev[0] as Dictionary)["name"]), "one", "events sorted by time")
	t.eq(String((ev[2] as Dictionary)["name"]), "three", "events sorted across tracks")
	t.eq(e.events_between(1.0, 3.0).size(), 2, "half-open includes start excludes end")
	t.eq(e.events_between(1.0001, 2.0).size(), 0, "event at end excluded")
	var once: int = e.events_between(0.0, 1.0).size() + e.events_between(1.0, 2.0).size() + e.events_between(2.0, 3.0).size()
	t.eq(once, 2, "adjacent ranges fire each event once")
	var wrap: Array = e.events_between(2.5, 1.5)
	t.eq(wrap.size(), 2, "wrap range catches tail and head")
	t.eq(String((wrap[0] as Dictionary)["name"]), "three", "wrap fires tail first")
	t.eq(String((wrap[1] as Dictionary)["name"]), "one", "wrap fires head after")
	t.eq(e.animations_between(2.0, 3.0).size(), 1, "animation key crossing")

	t.current = "shots and blends"
	var sh := Seq.new()
	sh.length = 10.0
	sh.add_shot(5.0, 10.0, "camB")
	sh.add_shot(0.0, 5.0, "camA")
	t.eq(String(sh.active_shot(1.0)["camera"]), "camA", "first shot active")
	t.eq(String(sh.active_shot(5.0)["camera"]), "camB", "cut at boundary")
	t.eq(String(sh.active_shot(10.0)["camera"]), "camB", "end holds last shot")
	t.check(sh.active_shot(-1.0).is_empty(), "before any shot is empty")
	var b0: Dictionary = sh.camera_cut_blend(5.0, 1.0)
	t.eq(String(b0["from"]), "camA", "blend from previous")
	t.eq(String(b0["to"]), "camB", "blend to current")
	t.near(float(b0["weight"]), 0.0, 0.0001, "blend starts at 0")
	t.near(float(sh.camera_cut_blend(5.5, 1.0)["weight"]), 0.5, 0.0001, "blend halfway")
	t.near(float(sh.camera_cut_blend(6.5, 1.0)["weight"]), 1.0, 0.0001, "blend done")
	t.eq(String(sh.camera_cut_blend(2.0, 1.0)["to"]), "camA", "first shot has no blend")
	t.near(float(sh.camera_cut_blend(5.0, 0.0)["weight"]), 1.0, 0.0001, "zero blend is hard cut")

	t.current = "serialization"
	var src := Seq.new()
	src.length = 8.0
	src.add_shot(0.0, 8.0, "cam")
	src.add_transform_key("cam", {"time": 0.0, "position": Vector3(1, 2, 3), "rotation": qb, "interp": "cubic"})
	src.add_transform_key("cam", {"time": 4.0, "position": Vector3(4, 5, 6), "interp": "linear"})
	src.add_float_key("fov", {"time": 0.0, "value": 50.0, "ease": "in_out"})
	src.add_float_key("fov", {"time": 4.0, "value": 30.0})
	src.add_event("ev", 2.0, "boom", ["x", 3])
	src.add_animation_key("an", 1.0, "actor", "run")
	var json_text: String = JSON.stringify(src.to_dict())
	var parsed: Variant = JSON.parse_string(json_text)
	var back = Seq.from_dict(parsed as Dictionary)
	t.near(float(back.length), 8.0, 0.0001, "length round-trips")
	var a_t: Transform3D = src.sample_transform("cam", 2.0)
	var b_t: Transform3D = back.sample_transform("cam", 2.0)
	t.near(a_t.origin.distance_to(b_t.origin), 0.0, 0.0001, "transform track round-trips")
	t.near(a_t.basis.get_rotation_quaternion().angle_to(b_t.basis.get_rotation_quaternion()), 0.0, 0.001, "rotation round-trips")
	t.near(src.sample_float("fov", 1.0), back.sample_float("fov", 1.0), 0.0001, "float track round-trips")
	t.eq(back.events_between(0.0, 5.0).size(), 1, "events round-trip")
	t.eq(String((back.events_between(0.0, 5.0)[0] as Dictionary)["name"]), "boom", "event name round-trips")
	t.eq(String(back.active_shot(1.0)["camera"]), "cam", "shots round-trip")
	t.eq(back.animations_between(0.0, 2.0).size(), 1, "animation keys round-trip")

	t.current = "player"
	var seq := Seq.new()
	seq.length = 4.0
	seq.add_shot(0.0, 2.0, "camA")
	seq.add_shot(2.0, 4.0, "camB")
	seq.add_transform_key("camA", {"time": 0.0, "position": Vector3.ZERO})
	seq.add_transform_key("camA", {"time": 2.0, "position": Vector3(10, 0, 0)})
	seq.add_float_key("fov", {"time": 0.0, "value": 40.0})
	seq.add_float_key("fov", {"time": 4.0, "value": 80.0})
	seq.add_event("ev", 1.0, "boom", [7])
	seq.add_event("ev", 3.0, "bang")
	var cam_a := Camera3D.new()
	var cam_b := Camera3D.new()
	var prop := Node3D.new()
	var p = Player.new()
	p.event_fired.connect(_on_event)
	p.finished.connect(_on_finished)
	p.play(seq, {"camA": cam_a, "camB": cam_b})
	t.check(cam_a.current, "first shot camera is current at start")
	p.advance(1.0)
	t.near(cam_a.position.x, 5.0, 0.0001, "player applies transform")
	t.near(cam_a.fov, 50.0, 0.0001, "fov applied to current camera")
	t.eq(_fired.size(), 0, "event at exactly 1.0 not yet fired before reaching it")
	p.advance(0.5)
	t.eq(_fired.size(), 1, "event fires on crossing")
	t.eq(String((_fired[0] as Array)[0]), "boom", "event name passed")
	p.advance(0.0)
	t.eq(_fired.size(), 1, "no refire without progress")
	p.advance(1.0)
	t.check(cam_b.current and not cam_a.current, "camera switches at shot cut")
	p.advance(2.0)
	t.eq(_fired.size(), 2, "second event fired")
	t.eq(_finished_count, 1, "finished emitted once")
	p.advance(1.0)
	t.eq(_finished_count, 1, "no finish after end")

	t.current = "player seek pause scale loop"
	_fired.clear()
	p.play(seq, {"camA": cam_a, "camB": cam_b})
	p.seek(3.0)
	t.near(p.time, 3.0, 0.0001, "seek sets time")
	t.check(cam_b.current, "seek switches camera")
	t.eq(_fired.size(), 0, "seek fires no events")
	p.seek(0.0)
	p.pause()
	p.advance(1.0)
	t.near(p.time, 0.0, 0.0001, "paused does not advance")
	p.resume()
	p.time_scale = 2.0
	p.advance(0.5)
	t.near(p.time, 1.0, 0.0001, "time_scale doubles speed")
	t.eq(_fired.size(), 0, "boom at 1.0 not fired until crossed")
	p.advance(0.01)
	t.eq(_fired.size(), 1, "boom fired after crossing")
	p.time_scale = 1.0
	p.loop = true
	_fired.clear()
	_finished_count = 0
	p.seek(2.5)
	p.advance(2.0)
	t.near(p.time, 0.5, 0.0001, "loop wraps time")
	t.eq(_fired.size(), 1, "loop fires tail event once, head not yet")
	t.eq(_finished_count, 0, "looping never finishes")
	p.advance(0.6)
	t.eq(_fired.size(), 2, "head event fires after wrap")

	p.free()
	cam_a.free()
	cam_b.free()
	prop.free()
