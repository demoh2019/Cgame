extends RefCounted
## Room acoustics (RT60, impulse response) and portal propagation.

const AcousticRooms = preload("res://scripts/client/acoustic_rooms.gd")
const AudioPortals = preload("res://scripts/client/audio_portals.gd")


func _rt_mid(room: Dictionary, key: String) -> float:
	var v: Vector3 = room[key]
	return v.y


func run(t) -> void:
	t.current = "room rt60"
	var concrete: Dictionary = {"floor": "concrete", "ceiling": "concrete", "walls": "concrete"}
	var carpet: Dictionary = {"floor": "carpet", "ceiling": "carpet", "walls": "carpet"}
	var small: Dictionary = AcousticRooms.room_from_box(Vector3(4, 3, 4), concrete)
	var big: Dictionary = AcousticRooms.room_from_box(Vector3(20, 8, 20), concrete)
	var soft: Dictionary = AcousticRooms.room_from_box(Vector3(4, 3, 4), carpet)
	t.near(float(small["volume"]), 48.0, 0.001, "box volume")
	t.check(_rt_mid(big, "rt60_sabine") > _rt_mid(small, "rt60_sabine"), "RT60 grows with volume")
	t.check(_rt_mid(soft, "rt60_sabine") < _rt_mid(small, "rt60_sabine"), "RT60 falls with absorption")
	var sab: Vector3 = small["rt60_sabine"]
	var eyr: Vector3 = small["rt60_eyring"]
	t.check(eyr.x <= sab.x and eyr.y <= sab.y and eyr.z <= sab.z, "Eyring <= Sabine")
	var carpet_eyr: Vector3 = soft["rt60_eyring"]
	var carpet_sab: Vector3 = soft["rt60_sabine"]
	t.check(carpet_eyr.y < carpet_sab.y, "Eyring is strictly shorter for absorbent rooms")
	t.check(float(small["early_reflection_delay_msec"]) > 0.0, "early reflection delay")
	var rv: Dictionary = small["reverb"]
	t.check(float(rv["room_size"]) >= 0.0 and float(rv["room_size"]) <= 1.0, "reverb room size in range")
	t.check(rv.has("damping") and rv.has("wet") and rv.has("predelay_msec"), "reverb settings complete")

	t.current = "impulse response"
	var rt: Vector3 = Vector3(0.8, 0.6, 0.3)
	var ir: PackedFloat32Array = AcousticRooms.impulse_response(rt, 8000, 1.0, 7)
	t.eq(ir.size(), 8000, "IR length")
	var peak: float = 0.0
	for s in ir:
		peak = maxf(peak, absf(s))
	t.near(peak, 1.0, 0.0001, "IR normalised")
	var early: float = 0.0
	var late: float = 0.0
	for i in 800:
		early += ir[i] * ir[i]
		late += ir[ir.size() - 1 - i] * ir[ir.size() - 1 - i]
	t.check(early > late * 20.0, "IR decays")
	var again: PackedFloat32Array = AcousticRooms.impulse_response(rt, 8000, 1.0, 7)
	t.check(ir == again, "IR deterministic per seed")
	var other: PackedFloat32Array = AcousticRooms.impulse_response(rt, 8000, 1.0, 8)
	t.check(ir != other, "IR differs per seed")

	t.current = "portals"
	var p := AudioPortals.new()
	p.add_room("a", Vector3(0, 0, 0))
	p.add_room("b", Vector3(10, 0, 0))
	p.add_room("c", Vector3(20, 0, 0))
	p.add_room("d", Vector3(10, 0, 20))
	p.add_room("island", Vector3(100, 0, 100))
	var ab: int = p.add_portal("a", "b", Vector3(5, 0, 0))
	var bc: int = p.add_portal("b", "c", Vector3(15, 0, 0))
	var ad: int = p.add_portal("a", "d", Vector3(0, 0, 10))
	var dc: int = p.add_portal("d", "c", Vector3(20, 0, 10))
	var src: Vector3 = Vector3(0, 0, 0)
	var lis: Vector3 = Vector3(20, 0, 0)
	var res: Dictionary = p.propagate("a", src, "c", lis)
	var path: Array = res["path"]
	t.eq(path, [ab, bc], "shortest route through b")
	t.near(float(res["distance"]), 20.0, 0.001, "straight-through distance")
	t.near(float(res["attenuation_db"]), 0.0, 0.001, "open portals do not attenuate")
	t.near(float(res["diffraction_cutoff_hz"]), AudioPortals.MAX_CUTOFF_HZ, 1.0, "straight path keeps full bandwidth")
	var vp: Vector3 = res["virtual_position"]
	t.check(vp.x < lis.x and vp.distance_to(lis) > 19.0, "virtual position on the portal side of the listener")
	t.near(vp.z, 0.0, 0.001, "virtual position along portal direction")

	var same: Dictionary = p.propagate("a", Vector3(1, 0, 0), "a", Vector3(4, 0, 0))
	var same_path: Array = same["path"]
	t.check(same_path.is_empty(), "same room has no portals")
	t.near(float(same["distance"]), 3.0, 0.001, "same room direct distance")
	var svp: Vector3 = same["virtual_position"]
	t.check(svp.is_equal_approx(Vector3(1, 0, 0)), "same room keeps source position")

	p.set_openness(bc, 0.0)
	var closed: Dictionary = p.propagate("a", src, "c", lis)
	t.check(float(closed["attenuation_db"]) > float(res["attenuation_db"]) + 1.0, "closed portal attenuates")

	# Bend: listener round the corner through the d route only.
	var q := AudioPortals.new()
	q.add_room("a", Vector3.ZERO)
	q.add_room("b", Vector3(10, 0, 0))
	q.add_room("c", Vector3(10, 0, 10))
	q.add_portal("a", "b", Vector3(5, 0, 0))
	q.add_portal("b", "c", Vector3(10, 0, 5))
	var bent: Dictionary = q.propagate("a", Vector3(0, 0, 0), "c", Vector3(10, 0, 10))
	t.check(float(bent["bend_angle"]) > 0.5, "route bends")
	t.check(float(bent["diffraction_cutoff_hz"]) < float(res["diffraction_cutoff_hz"]) * 0.5, "bend lowers cutoff")
	t.check(AudioPortals.cutoff_for_bend(2.0) < AudioPortals.cutoff_for_bend(0.5), "cutoff monotonic in bend")

	var blocked: Dictionary = p.propagate("a", src, "island", Vector3(100, 0, 100))
	t.check(blocked.get("blocked", false) == true, "no route is blocked")
	# unused portal ids silence the unused-variable warnings
	t.check(ad != dc, "distinct portal ids")
