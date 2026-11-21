extends RefCounted
## Sim editor panels: vehicle, cloth, VFX budget and VFX debugger (headless).

const VehiclePanel = preload("res://addons/cgame_sim_editors/vehicle_panel.gd")
const ClothPanel = preload("res://addons/cgame_sim_editors/cloth_panel.gd")
const BudgetPanel = preload("res://addons/cgame_sim_editors/vfx_budget_panel.gd")
const DebuggerPanel = preload("res://addons/cgame_sim_editors/vfx_debugger_panel.gd")
const VfxBudget = preload("res://scripts/client/vfx_budget.gd")


func _life(v: float) -> Dictionary:
	return {"type": "lifetime_random", "min": v, "max": v}


func run(t) -> void:
	t.current = "vehicle field validation"
	var vp := VehiclePanel.new()
	t.check(vp.set_field("mass", 2100.0), "valid mass accepted")
	t.near(float(vp.get_field("mass")), 2100.0, 0.001, "mass stored")
	t.check(not vp.set_field("gearbox.gear_ratios", [1.0, 2.0, 3.0]), "ascending gear ratios rejected")
	t.check(not vp.last_errors.is_empty(), "rejection explains why")
	t.check(not vp.set_field("gearbox.gear_ratios", [3.0, -1.0]), "negative ratio rejected")
	t.eq((vp.get_field("gearbox.gear_ratios") as Array).size(), 5, "rejected edit leaves config untouched")
	t.check(vp.set_field("gearbox.gear_ratios", [3.4, 2.0, 1.3, 0.9]), "descending ratios accepted")
	t.check(vp.set_field("wheels.0.damping", 3000.0), "indexed wheel field")
	t.check(not vp.set_field("wheels.9.damping", 1.0), "bad index rejected")
	t.check(not vp.set_field("nope.field", 1.0), "unknown path rejected")
	t.check(not vp.set_field("mass", -5.0), "negative mass rejected")

	t.current = "vehicle telemetry and dyno"
	vp.load_preset("dune_buggy")
	var series: Dictionary = vp.simulate(2.0, [{"duration": 0.5}, {"duration": 1.5, "throttle": 1.0}])
	t.eq((series["speed"] as PackedFloat32Array).size(), 120, "speed series length")
	t.eq((series["rpm"] as PackedFloat32Array).size(), 120, "rpm series length")
	t.eq((series["gear"] as PackedFloat32Array).size(), 120, "gear series length")
	var comp: Array = series["compression"]
	t.eq(comp.size(), 4, "compression per wheel")
	t.eq((comp[0] as PackedFloat32Array).size(), 120, "compression series length")
	var speed: PackedFloat32Array = series["speed"]
	t.check(speed[119] > 3.0 and speed[119] < 60.0, "buggy accelerates plausibly")
	var rpm: PackedFloat32Array = series["rpm"]
	t.check(rpm[119] >= 900.0 and rpm[119] <= 9000.0, "rpm in range")
	t.check((comp[0] as PackedFloat32Array)[100] > 0.0, "suspension loaded")
	var dyno: Array[Dictionary] = vp.torque_curve_samples(16)
	t.eq(dyno.size(), 16, "dyno sample count")
	t.near(float(dyno[0]["rpm"]), 1000.0, 0.01, "dyno starts at idle")
	t.near(float(dyno[15]["rpm"]), 7500.0, 0.01, "dyno ends at redline")
	var peak: float = 0.0
	for s in dyno:
		peak = maxf(peak, float(s["torque"]))
	t.check(peak > 200.0 and peak <= 250.0, "dyno peak torque plausible")
	t.check(float(dyno[8]["power_kw"]) > 0.0, "power computed")

	t.current = "vehicle json round trip"
	var path: String = "user://test_sim_editors_vehicle.json"
	vp.set_field("mass", 950.0)
	t.check(vp.save_config(path), "saved")
	var vp2 := VehiclePanel.new()
	t.check(vp2.load_config(path), "loaded")
	t.near(float(vp2.get_field("mass")), 950.0, 0.001, "mass round trips")
	t.check(vp2.get_field("inertia") is Vector3, "Vector3 restored")
	var curve: Array = vp2.get_field("engine.torque_curve")
	t.check(curve[0] is Vector2, "Vector2 restored")
	t.eq(curve.size(), 6, "curve size kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	t.check(not vp2.load_config(path), "missing file fails")
	vp.free()
	vp2.free()

	t.current = "cloth preview"
	var cp := ClothPanel.new()
	var base: Dictionary = cp.stats()
	t.check(int(base["particles"]) > 100, "cloth built from preset")
	t.check(int(base["pinned"]) > 0, "preset pins present")
	cp.set_param("gravity_y", -20.0)
	cp.set_param("compliance_stretch", 0.002)
	t.near(cp.get_param("compliance_stretch"), 0.002, 0.00001, "param mapped to solver")
	t.near((cp.sliders["compliance_stretch"] as HSlider).value, 0.002, 0.00001, "slider tracks value")
	var soft: Dictionary = cp.step_preview(30)
	var stiff_panel := ClothPanel.new()
	var stiff: Dictionary = stiff_panel.step_preview(30)
	t.check(float(soft["max_stretch"]) > float(stiff["max_stretch"]), "softer cloth stretches more")
	t.eq(int(soft["torn_count"]), 0, "no tearing by default")
	cp.set_param("tear_threshold", 1.001)
	cp.set_param("wind_x", 20.0)
	var torn: Dictionary = cp.step_preview(60)
	t.check(int(torn["torn_count"]) > 0, "low tear threshold tears")
	var pts: PackedVector3Array = cp.cloth.call("positions")
	t.check(cp.paint_pins(pts[100], 0.2, true) > 0, "pin painting")
	var exported: Dictionary = cp.export_config()
	t.eq(exported["preset"], "flag", "export preset")
	t.check((exported["pins"] as Array).size() > 0, "export pins")
	t.check(not cp.create("nonexistent"), "unknown preset rejected")
	cp.free()
	stiff_panel.free()

	t.current = "vfx budget panel"
	var bp := BudgetPanel.new()
	t.eq(bp.get_cap("medium", "combat", "effects"), 24, "default medium combat effects")
	t.check(bp.set_cap("medium", "combat", "effects", 2), "set cap")
	t.check(not bp.set_cap("medium", "combat", "effects", 0), "zero cap rejected")
	t.check(not bp.set_cap("bogus", "combat", "effects", 3), "bad tier rejected")
	t.check(bp.set_total("medium", 500), "set total")
	t.check(bp.apply_to(bp.budget), "applied")
	t.eq(bp.budget.max_effects("combat"), 2, "budget uses edited cap")
	t.eq(bp.budget.max_total_particles(), 500, "budget uses edited total")
	bp.budget.set_tier(VfxBudget.Tier.HIGH)
	t.eq(bp.budget.max_effects("combat"), 42, "other tiers keep defaults")
	bp.budget.set_tier(VfxBudget.Tier.MEDIUM)
	t.check(bp.budget.request("combat", 10, 1.0, Vector3.ZERO, Vector3.ZERO), "first accepted")
	t.check(bp.budget.request("combat", 10, 1.0, Vector3.ZERO, Vector3.ZERO), "second accepted")
	t.check(not bp.budget.request("combat", 10, 0.5, Vector3.ZERO, Vector3.ZERO), "third rejected by edited cap")
	var rows: Array[Dictionary] = bp.stats_table()
	t.eq(rows.size(), 6, "stats rows incl. total")
	t.eq(int(rows[0]["effects"]), 2, "live effects counted")
	t.check(not bp.apply_to(VfxBudget.new()), "plain budget cannot be edited")
	var js: String = bp.export_json()
	var parsed: Dictionary = JSON.parse_string(js)
	var tiers: Dictionary = parsed["tiers"]
	var med: Dictionary = tiers["medium"]
	var cats: Dictionary = med["categories"]
	t.eq(int((cats["combat"] as Array)[0]), 2, "export carries edit")
	var bp2 := BudgetPanel.new()
	t.check(bp2.import_json(js), "import")
	t.eq(bp2.budget.max_effects("combat"), 2, "import applies")
	bp.free()
	bp2.free()

	t.current = "vfx debugger"
	var dp := DebuggerPanel.new()
	var asset: Dictionary = {"emitters": {"main": {"max_particles": 200,
		"spawn": [{"type": "spawn_rate", "rate": 60.0}, _life(5.0)],
		"update": [{"type": "gravity", "gravity": Vector3(0, -10, 0)}, {"type": "drag", "drag": 0.5}]}}}
	t.check(not dp.load_asset({}), "empty asset rejected")
	t.check(dp.load_asset(asset, 3), "asset loaded")
	t.eq(dp.emitter_names(), ["main"], "emitter names")
	t.eq(dp.step(1.0), true, "step without breakpoint")
	t.eq(dp.frame, 1, "frame counted")
	t.eq(dp.total(), 60, "60 particles after 1 s")
	var p: Dictionary = dp.inspect("main", 0)
	t.check(p.has("position") and p.has("velocity") and p.has("age"), "attributes present")
	t.check(float(p["lifetime"]) > 4.9, "lifetime attribute")
	t.check(dp.inspect("main", 999).is_empty(), "bad index empty")
	t.check(dp.inspect("nope", 0).is_empty(), "bad emitter empty")
	dp.step(0.1)
	t.check(float((dp.inspect("main", 0))["age"]) > 0.0, "age advances")
	var timings: Array[Dictionary] = dp.timing_table()
	t.check(timings.size() >= 3, "per-module timings recorded")
	t.check(str(timings[0]["module"]).begins_with("main/"), "module key names emitter")
	t.check(int(timings[0]["usec"]) >= int(timings[timings.size() - 1]["usec"]), "timings sorted")
	dp.set_breakpoint("main", 100)
	var stepped: int = dp.run_until_breakpoint(50, 0.1)
	t.check(stepped < 50 and dp.hit_breakpoints.has("main"), "breakpoint halts run")
	t.check(dp.total() >= 100, "particle threshold reached")
	dp.free()

	t.current = "sim editor lifecycle"
	var panels: Array[Control] = [VehiclePanel.new(), ClothPanel.new(), BudgetPanel.new(), DebuggerPanel.new()]
	t.eq(panels.size(), 4, "all panels create")
	for pnl in panels:
		pnl.free()
