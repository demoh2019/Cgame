extends SceneTree
## godot --headless --path game --script res://tests/run_all.gd
## Runs every test_*.gd that does not need a network. Each test script has a `run(t)` method.

const TestCase = preload("res://tests/test_case.gd")
const SUITES := [
	"res://tests/test_world_gen.gd",
	"res://tests/test_inventory.gd",
	"res://tests/test_encumbrance.gd",
	"res://tests/test_crafting.gd",
	"res://tests/test_ammunition_loop.gd",
	"res://tests/test_progression.gd",
	"res://tests/test_fishing.gd",
	"res://tests/test_fishing_display.gd",
	"res://tests/test_fishing_tiers.gd",
	"res://tests/test_survival_combat.gd",
	"res://tests/test_infection.gd",
	"res://tests/test_weather.gd",
	"res://tests/test_field_water.gd",
	"res://tests/test_thermal_wrap.gd",
	"res://tests/test_weapon_skills.gd",
	"res://tests/test_combat_mastery.gd",
	"res://tests/test_scavenging.gd",
	"res://tests/test_stamina.gd",
	"res://tests/test_evasion.gd",
	"res://tests/test_movement.gd",
	"res://tests/test_zombie_ai.gd",
	"res://tests/test_world_cycle.gd",
	"res://tests/test_camp_rest.gd",
	"res://tests/test_field_campfire.gd",
	"res://tests/test_field_cooking.gd",
	"res://tests/test_zombie_pack.gd",
	"res://tests/test_sound.gd",
	"res://tests/test_game_server.gd",
	"res://tests/test_zone_risk.gd",
	"res://tests/test_secure_stash.gd",
	"res://tests/test_barricades.gd",
	"res://tests/test_structure_tiers.gd",
	"res://tests/test_base_sieges.gd",
	"res://tests/test_world_persistence.gd",
	"res://tests/test_world_backup.gd",
	"res://tests/test_dismantle.gd",
	"res://tests/test_vendor.gd",
	"res://tests/test_player_trade.gd",
	"res://tests/test_market_board.gd",
	"res://tests/test_contracts.gd",
	"res://tests/test_survival_radar.gd",
	"res://tests/test_save_validation.gd",
]


func _initialize() -> void:
	var total_checks := 0
	var failures: Array[String] = []
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null:
			failures.append("%s: could not load" % path)
			continue
		var suite = script.new()
		var t := TestCase.new()
		var started := Time.get_ticks_msec()
		suite.run(t)
		total_checks += t.checks
		failures.append_array(t.failures)
		print("%-34s %4d checks  %3d failed  %4d ms" % [path.get_file(), t.checks, t.failures.size(), Time.get_ticks_msec() - started])
	for failure in failures:
		printerr("FAIL " + failure)
	print("TOTAL %d checks, %d failures" % [total_checks, failures.size()])
	quit(1 if failures.size() > 0 else 0)
