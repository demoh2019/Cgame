extends RefCounted
## Population simulation LOD (herds, promote/demote) and group formations.

const PopulationLOD = preload("res://scripts/shared/population_lod.gd")
const Formations = preload("res://scripts/shared/formations.gd")


func _make(seed_value: int) -> PopulationLOD:
	var p := PopulationLOD.new()
	p.setup(10, 10, 64.0, seed_value)
	p.dwell_time = 1.0
	p.max_herd_size = 30
	return p


func _seed_herds(p: PopulationLOD) -> void:
	p.add_herd(11, {"walker": 12, "runner": 3})
	p.add_herd(55, {"walker": 20})
	p.add_herd(88, {"walker": 5, "brute": 2})
	p.add_herd(23, {"runner": 9})


func _snapshot(p: PopulationLOD) -> String:
	var parts: PackedStringArray = []
	for id in p.herd_ids():
		var h: Dictionary = p.herds[id]
		parts.append("%d:%d:%d" % [id, int(h["region"]), int(h["count"])])
	return ",".join(parts)


func _brute_best(slots: PackedVector2Array, members: PackedVector2Array) -> float:
	var used: Array[bool] = []
	used.resize(slots.size())
	used.fill(false)
	return _brute(slots, members, 0, used)


func _brute(slots: PackedVector2Array, members: PackedVector2Array, i: int, used: Array[bool]) -> float:
	if i == members.size():
		return 0.0
	var best := INF
	for j in range(slots.size()):
		if used[j]:
			continue
		used[j] = true
		best = minf(best, members[i].distance_to(slots[j]) + _brute(slots, members, i + 1, used))
		used[j] = false
	return best


func _valid_assignment(a: PackedInt32Array, slot_count: int) -> bool:
	var seen: Dictionary = {}
	for s in a:
		if s < 0:
			continue
		if s >= slot_count or seen.has(s):
			return false
		seen[s] = true
	return true


func run(t) -> void:
	t.current = "population conservation across tick"
	var p := _make(7)
	_seed_herds(p)
	var total0 := p.total_population()
	t.eq(total0, 51, "initial population")
	p.add_attractor("noise", p.region_center(75), 10.0, 600.0)
	for i in range(300):
		p.tick(1.0)
		if p.total_population() != total0:
			break
	t.eq(p.total_population(), total0, "migrate/merge/split keep the total")
	t.check(int(p.stats()["migrations"]) > 0, "herds migrated")
	t.eq(p.composition_total("brute"), 2, "composition by type is conserved")
	t.eq(p.composition_total("walker"), 37, "walker count is conserved")

	t.current = "merge and split"
	var m := _make(3)
	m.add_herd(44, {"walker": 10})
	m.add_herd(44, {"walker": 8})
	m.tick(0.1)
	t.eq(m.herds.size(), 1, "herds meeting in a region merge")
	t.eq(m.abstract_count(), 18, "merge keeps counts")
	var s := _make(3)
	s.add_herd(44, {"walker": 50, "runner": 20})
	s.tick(0.1)
	t.check(s.herds.size() >= 2, "oversized herd splits")
	for k in range(200):
		s.tick(0.5)
	var ok_size := true
	for id in s.herds.keys():
		var hh: Dictionary = s.herds[id]
		if int(hh["count"]) > s.max_herd_size:
			ok_size = false
	t.check(ok_size, "after repeated splits every herd is within max size")
	t.eq(s.abstract_count(), 70, "split keeps counts")
	t.eq(s.composition_total("runner"), 20, "split keeps composition")

	t.current = "herds move toward attractors"
	var a := _make(11)
	a.randomness = 0.2
	var hid := a.add_herd(0, {"walker": 10})
	var target := a.region_center(99)
	a.add_attractor("noise", target, 10.0, 2000.0)
	var d0 := a.region_center(0).distance_to(target)
	for i in range(120):
		a.tick(1.0)
	var h: Dictionary = a.herds[hid]
	var d1 := (h["pos"] as Vector2).distance_to(target)
	t.check(d1 < d0 * 0.5, "herd closes on the attractor")
	t.check(a.attraction(99) > a.attraction(0), "attraction grows toward the source")
	a.add_attractor("night", Vector2(0, 0), 5.0, 100.0)
	a.set_night(true)
	t.check(a.night, "night flag set")

	t.current = "local attraction bounds and day-night transitions"
	var night_test := _make(2026)
	var night_region := 44
	night_test.add_attractor("night", night_test.region_center(night_region), 7.0, 110.0)
	t.near(night_test.attraction(night_region), 0.0, 0.00001,
			"night attraction remains dormant during daylight")
	night_test.set_night(true)
	t.check(night_test.attraction(night_region) > 0.0,
			"night attraction activates immediately without an extra tick")
	night_test.set_night(false)
	t.near(night_test.attraction(night_region), 0.0, 0.00001,
			"night attraction disappears immediately after sunrise")
	night_test.set_night(true)
	t.check(night_test.attraction(night_region) > 0.0,
			"night attraction returns after a second dusk")

	# Slow all-regions reference: local bounding must never change the
	# deterministic attraction field, including off-map, overlapping and
	# long-range sources.
	var field := PopulationLOD.new()
	field.setup(48, 36, 32.0, 91, Vector2(-400.0, -300.0))
	field.set_night(true)
	var slow := PackedFloat32Array()
	slow.resize(field.region_count())
	slow.fill(0.0)
	var attr_rng := RandomNumberGenerator.new()
	attr_rng.seed = 81239
	for i in 48:
		var kind: String = "night" if i % 7 == 0 else "noise"
		var center: Vector2 = Vector2(attr_rng.randf_range(-600.0, 1500.0),
				attr_rng.randf_range(-500.0, 1100.0))
		var radius: float = attr_rng.randf_range(1.0, 420.0)
		var strength: float = attr_rng.randf_range(0.1, 11.0)
		field.add_attractor(kind, center, strength, radius)
		var weight: float = float(field.kind_weight.get(kind, 1.0))
		for region in field.region_count():
			var distance: float = field.region_center(region).distance_to(center)
			if distance < radius:
				slow[region] += strength * weight * (1.0 - distance / radius)
	var largest_error := 0.0
	for region in field.region_count():
		largest_error = maxf(largest_error, absf(field.attraction(region) - slow[region]))
	t.check(largest_error < 0.0001,
			"bounded attraction matches complete-grid reference (max error %f)" % largest_error)

	t.current = "per-player signals refresh without piling up"
	var signals := _make(706)
	var first_center: Vector2 = signals.region_center(44)
	var second_center: Vector2 = signals.region_center(77)
	signals.add_attractor("loot", first_center, 1.0, 20.0)
	signals.set_source_attractor("noise", 4, first_center, 2.0, 100.0, 0.5)
	t.eq(signals.active_attractor_count(), 2,
			"independent loot event and one sourced noise signal coexist")
	for i in 80:
		signals.set_source_attractor("noise", 4, second_center, 4.0, 90.0, 0.5)
	t.eq(signals.active_attractor_count(), 2,
			"eighty updates from one player cannot accumulate overlapping signals")
	t.check(signals.attraction(77) > signals.attraction(44),
			"the source follows the player position and updates signal strength")
	signals.set_source_attractor("noise", 5, first_center, 1.0, 30.0, 0.5)
	signals.set_source_attractor("night", 4, second_center, 6.0, 30.0, 0.5)
	t.eq(signals.active_attractor_count(), 4,
			"different sources and different event kinds remain independent")
	signals.set_night(true)
	t.check(signals.attraction(77) > 4.0, "a refreshed nighttime signal attracts herds")
	signals.tick(0.25)
	t.eq(signals.active_attractor_count(), 4, "live signals survive partial TTL decay")
	signals.tick(0.26)
	t.eq(signals.active_attractor_count(), 1, "expired player signals are all evicted")
	signals.set_source_attractor("noise", 4, first_center, 3.0, 30.0, 1.0)
	t.eq(signals.active_attractor_count(), 2,
			"an expired source can be registered again without using stale references")
	signals.clear_attractors()
	t.eq(signals.active_attractor_count(), 0, "clearing attractors forgets their source keys")
	signals.set_source_attractor("noise", 4, second_center, 1.0, 30.0, 0.5)
	t.eq(signals.active_attractor_count(), 1,
			"cleared source keys do not conceal freshly active effects")
	signals.setup(10, 10, 64.0, 706)
	t.eq(signals.active_attractor_count(), 0, "reinitialization drops all previous signals")
	signals.set_source_attractor("noise", 4, first_center, 1.0, 30.0, 0.5)
	t.eq(signals.active_attractor_count(), 1, "source identifiers can be reused after reset")
	signals.set_source_attractor("noise", 4, Vector2.INF, 1.0, 30.0, 1.0)
	signals.set_source_attractor("noise", 4, first_center, 1.0, INF, 1.0)
	t.eq(signals.active_attractor_count(), 1, "nonfinite network-derived positions and radii are rejected")

	t.current = "independent nests honor shared regional cap"
	var nests := _make(772)
	nests.add_herd(44, {"walker": 2})
	nests.add_spawner(44, "walker", 4.0, 9)
	nests.add_spawner(44, "runner", 4.0, 9)
	nests._rules_pass(1.0)
	t.eq(nests.herd_region_count(44), 9,
			"two spawners share one cap rather than each filling it separately")
	t.eq(int(nests.stats()["spawned"]), 7,
			"spawn accounting reflects only new agents accepted by regional cap")
	nests._rules_pass(2.0)
	t.eq(nests.herd_region_count(44), 9, "a capped region cannot overfill on later passes")
	nests.set_decay(44, 2.0)
	nests._rules_pass(1.0)
	t.eq(nests.herd_region_count(44), 9,
			"newly opened capacity from decay is replenished without exceeding cap")
	t.eq(nests.abstract_count() + int(nests.stats()["decayed"]),
			2 + int(nests.stats()["spawned"]), "decay and shared spawn caps conserve accounting")

	t.current = "determinism"
	var p1 := _make(99)
	var p2 := _make(99)
	var p3 := _make(100)
	for q in [p1, p2, p3]:
		_seed_herds(q)
		q.add_attractor("loot", Vector2(300, 300), 5.0, 500.0)
		for i in range(60):
			q.tick(0.5)
	t.eq(_snapshot(p1), _snapshot(p2), "same seed gives the same world")
	t.check(_snapshot(p1) != _snapshot(p3), "different seed diverges")

	t.current = "promotion near players and budget"
	var pr := _make(5)
	pr.promote_radius = 100.0
	pr.max_concrete_agents = 25
	pr.add_herd(55, {"walker": 20, "runner": 10})
	var player := PackedVector2Array([pr.region_center(55) + Vector2(30, 0)])
	pr.tick(0.01, player)
	var before := pr.total_population()
	t.eq(pr.promote(0, player).size(), 0, "far region is not promoted")
	var specs := pr.promote(55, player)
	t.eq(specs.size(), 25, "promotion capped by the budget")
	t.eq(pr.total_population(), before, "promote conserves the total")
	t.eq(pr.concrete_count, 25, "concrete counter tracks agents")
	t.eq(pr.herd_region_count(55), 5, "remainder stays abstract")
	t.eq(pr.promote(55, player).size(), 0, "no budget left, no more promotion")
	var near_ok := true
	for spec in specs:
		if (spec["position"] as Vector2).distance_to(pr.region_center(55)) > 64.0:
			near_ok = false
	t.check(near_ok, "spawn positions lie in the region")
	var far_only := PackedVector2Array([Vector2(5000, 5000)])
	var pr2 := _make(5)
	pr2.add_herd(55, {"walker": 5})
	t.eq(pr2.promote(55, far_only).size(), 0, "no player nearby means no promotion")
	t.eq(pr2.regions_near(PackedVector2Array([pr2.region_center(55)])).size(), 1, "regions_near finds the herd region")

	t.current = "sparse promotion regions match the full grid"
	var sparse := PopulationLOD.new()
	sparse.setup(70, 56, 32.0, 812, Vector2(-600.0, -500.0))
	sparse.promote_radius = 128.0
	sparse.max_concrete_agents = 2048
	var sparse_rng := RandomNumberGenerator.new()
	sparse_rng.seed = 21891
	for i in 180:
		sparse.add_herd(sparse_rng.randi_range(0, sparse.region_count() - 1),
				{"walker": sparse_rng.randi_range(1, 9)})
	sparse.add_herd(987, {"runner": 5})
	sparse.add_herd(123, {}) # Empty herd must not count as an occupied region.
	var probe_positions := PackedVector2Array([
		sparse.region_center(987),
		sparse.region_center(19),
		sparse.region_center(3400),
		Vector2(5000.0, 5000.0),
	])
	var expected_regions := PackedInt32Array()
	for region in sparse.region_count():
		if sparse.herd_region_count(region) <= 0:
			continue
		var center: Vector2 = sparse.region_center(region)
		var near: bool = false
		for probe in probe_positions:
			if center.distance_to(probe) <= sparse.promote_radius + sparse.cell_size * 0.5:
				near = true
				break
		if near:
			expected_regions.append(region)
	t.eq(sparse.regions_near(probe_positions), expected_regions,
			"sparse occupied-region lookup matches exhaustive sorted promotion list")
	t.eq(sparse.regions_near(PackedVector2Array()).size(), 0,
			"empty player positions produce no promoted regions")
	t.check(sparse.regions_near(probe_positions).has(987),
			"an occupied target region is promoted near its player")
	var before_promote: int = sparse.herd_region_count(987)
	var promoted: Array = sparse.promote(987, PackedVector2Array([sparse.region_center(987)]))
	t.eq(promoted.size(), before_promote, "all local herds are promoted within budget")
	t.check(not sparse.regions_near(PackedVector2Array([sparse.region_center(987)])).has(987),
			"an emptied promoted region disappears immediately from the sparse query")
	sparse.demote(promoted, 987)
	t.check(sparse.regions_near(PackedVector2Array([sparse.region_center(987)])).has(987),
			"demoted agents immediately reappear as a promotable region")

	t.current = "demote restores herd"
	var d := _make(5)
	d.add_herd(55, {"walker": 14, "runner": 6})
	var pl := PackedVector2Array([d.region_center(55)])
	d.tick(0.01, pl)
	var sp := d.promote(55, pl)
	t.eq(sp.size(), 20, "all promoted")
	t.eq(d.abstract_count(), 0, "herd emptied by promotion")
	d.demote(sp, 55)
	t.eq(d.abstract_count(), 20, "demote folds agents back")
	t.eq(d.concrete_count, 0, "concrete counter back to zero")
	t.eq(d.composition_total("walker"), 14, "walkers restored")
	t.eq(d.composition_total("runner"), 6, "runners restored")
	d.demote([{"type": "walker"}], 40)
	t.eq(d.abstract_count(), 21, "demoting foreign agents adds them")
	t.eq(d.concrete_count, 0, "counter never goes negative")

	t.current = "decay and respawn rules"
	var r := _make(2)
	r.add_herd(30, {"walker": 10})
	r.set_decay(30, 1.0)
	for i in range(6):
		r.tick(1.0)
	t.check(r.abstract_count() < 10, "decay removes agents")
	t.eq(r.abstract_count() + int(r.stats()["decayed"]), 10, "decay is accounted")
	var sp2 := _make(2)
	sp2.add_spawner(12, "walker", 2.0, 6)
	for i in range(20):
		sp2.tick(1.0)
	t.eq(sp2.herd_region_count(12), 6, "spawner stops at its cap")

	t.current = "formation slots"
	for kind in Formations.KINDS:
		for n in [1, 2, 5, 9, 16]:
			var sl := Formations.slots(kind, n, 2.0)
			t.eq(sl.size(), n, "%s slot count %d" % [kind, n])
			var min_d := INF
			for i in range(sl.size()):
				for j in range(i + 1, sl.size()):
					min_d = minf(min_d, sl[i].distance_to(sl[j]))
			if n > 1:
				t.check(min_d >= 2.0 - 0.001, "%s slots keep spacing (n=%d)" % [kind, n])
	var col := Formations.slots("column", 4, 3.0)
	t.near(col[3].x, -9.0, 0.001, "column trails behind leader")
	var tg := Formations.targets(Vector2(10, 10), PI * 0.5, "column", 3, 2.0)
	t.near(tg[1].x, 10.0, 0.001, "rotated column x")
	t.near(tg[1].y, 8.0, 0.001, "rotated column y")
	var lin := Formations.slots("line", 3, 2.0)
	t.near(lin[0].y + lin[2].y, 0.0, 0.001, "line is centred")
	t.eq(Formations.slots("wedge", 0, 2.0).size(), 0, "empty formation")

	t.current = "formation assignment"
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var optimal := true
	for trial in range(25):
		var nn := 2 + trial % 5
		var sw := PackedVector2Array()
		var mm := PackedVector2Array()
		for i in range(nn):
			sw.append(Vector2(rng.randf_range(0, 50), rng.randf_range(0, 50)))
			mm.append(Vector2(rng.randf_range(0, 50), rng.randf_range(0, 50)))
		var asg := Formations.assign(sw, mm)
		if not _valid_assignment(asg, nn):
			optimal = false
		elif absf(Formations.assignment_cost(sw, mm, asg) - _brute_best(sw, mm)) > 0.0001:
			optimal = false
	t.check(optimal, "Hungarian equals brute force on small cases")
	var sw2 := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	var mm2 := PackedVector2Array([Vector2(19, 1), Vector2(1, 1), Vector2(11, 1)])
	var asg2 := Formations.assign(sw2, mm2)
	t.eq(Array(asg2), [2, 0, 1], "members take their nearby slots")
	var sw3 := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var mm3 := PackedVector2Array([Vector2(0, 1), Vector2(10, 1), Vector2(500, 500)])
	var asg3 := Formations.assign(sw3, mm3)
	t.eq(Array(asg3), [0, 1, -1], "surplus member gets no slot")
	var big_n := 100
	var big_s := Formations.slots("circle", big_n, 1.5)
	var big_m := PackedVector2Array()
	for i in range(big_n):
		big_m.append(Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60)))
	var big_a := Formations.assign(big_s, big_m)
	t.check(_valid_assignment(big_a, big_n), "greedy fallback is a valid matching")
	var all_assigned := true
	for s2 in big_a:
		if s2 < 0:
			all_assigned = false
	t.check(all_assigned, "greedy fallback assigns every member")
	var h64 := Formations.assign(Formations.slots("line", 64, 1.0), big_m.slice(0, 64))
	t.check(_valid_assignment(h64, 64), "Hungarian at the 64 limit is valid")

	t.current = "formation smoothing"
	var from_s := Formations.slots("line", 4, 2.0)
	var to_s := Formations.slots("column", 4, 2.0)
	var mid := Formations.blend(from_s, to_s, 0.5)
	t.near(mid[0].distance_to(from_s[0].lerp(to_s[0], 0.5)), 0.0, 0.0001, "blend midpoint")
	var cur := from_s
	for i in range(120):
		cur = Formations.smooth(cur, to_s, 0.05)
	t.near(cur[3].distance_to(to_s[3]), 0.0, 0.01, "smoothing converges to the goal")
	var grown := Formations.smooth(from_s, Formations.slots("line", 6, 2.0), 0.0)
	t.eq(grown.size(), 6, "smoothing handles a larger group")

	t.current = "obstacle-aware slot shifting"
	var wall := func(pt: Vector2) -> bool:
		return not (pt.x > -3.0 and pt.x < 3.0 and pt.y > -1.0 and pt.y < 12.0)
	var base := Formations.targets(Vector2(0, 0), 0.0, "line", 7, 2.0)
	# Line along y from -6..6 crosses the wall block at x in (-3,3), y in (-1,12).
	var blocked_before := 0
	for pt in base:
		if not wall.call(pt):
			blocked_before += 1
	t.check(blocked_before > 0, "scenario has blocked slots")
	var fixed := Formations.shift_slots(base, wall, Vector2(-10, 0), 2.0)
	t.eq(fixed.size(), base.size(), "shifting keeps the slot count")
	var all_walkable := true
	for pt in fixed:
		if not wall.call(pt):
			all_walkable = false
	t.check(all_walkable, "every shifted slot is walkable")
	var untouched := true
	for i in range(base.size()):
		if wall.call(base[i]) and base[i] != fixed[i]:
			untouched = false
	t.check(untouched, "walkable slots are not moved")
	var tiny := func(pt: Vector2) -> bool:
		return pt.distance_to(Vector2(-10, 0)) < 0.5
	var squeezed := Formations.shift_slots(PackedVector2Array([Vector2(5, 5)]), tiny, Vector2(-10, 0), 2.0, 2)
	t.check(tiny.call(squeezed[0]), "falls back to the leader when nothing is nearby")
