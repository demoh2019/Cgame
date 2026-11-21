extends SceneTree
## Certification-style readiness checks built only from PUBLIC best practices (atomic saves, suspend/resume
## safety, controller-loss prompts, offline handling, readable text, safe areas, localisation, load times,
## Steam Deck verification criteria). These do NOT replace any platform holder's official certification.
##   godot --headless --path game --script res://scripts/tools/cert_checks.gd -- [--out report.md] [--soak soak.json]
##       [--load-budget-s 15] [--min-font-px 12]
## Results are PASS, FAIL or MANUAL (cannot be decided automatically). Exit code 1 if any check is FAIL.

const PlatformServices = preload("res://scripts/shared/platform_services.gd")

const STATUS_PASS := "PASS"
const STATUS_FAIL := "FAIL"
const STATUS_MANUAL := "MANUAL"


func _initialize() -> void:
	var args: Dictionary = {}
	var argv := OS.get_cmdline_user_args()
	var i := 0
	while i < argv.size():
		if argv[i].begins_with("--") and i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
			args[argv[i].substr(2)] = argv[i + 1]
			i += 1
		i += 1
	var options: Dictionary = {}
	if args.has("soak"):
		options["soak_json"] = str(args["soak"])
	if args.has("load-budget-s"):
		options["load_budget_s"] = float(args["load-budget-s"])
	if args.has("min-font-px"):
		options["min_font_px"] = float(args["min-font-px"])
	var checks := Checks.new()
	var results := checks.run_all(options)
	var report := checks.to_markdown(results)
	if args.has("out"):
		var f := FileAccess.open(str(args["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(report)
			f.close()
	print(report)
	quit(1 if checks.count(results, STATUS_FAIL) > 0 else 0)


class Checks extends RefCounted:
	const PS = preload("res://scripts/shared/platform_services.gd")
	const UiLocalization = preload("res://scripts/client/ui_localization.gd")

	var scratch_root: String = "user://cert_checks_tmp"

	func _res(id: String, title: String, status: String, detail: String) -> Dictionary:
		return {"id": id, "title": title, "status": status, "detail": detail}

	func run_all(options: Dictionary = {}) -> Array:
		var out: Array = []
		out.append(check_save_atomic_backup())
		out.append(check_save_interrupted())
		out.append(check_quota_handling())
		out.append(check_suspend_resume())
		out.append(check_controller_disconnect())
		out.append(check_sign_out())
		out.append(check_offline())
		out.append(check_restrictions_and_text_input())
		out.append(check_achievements_idempotent())
		out.append(check_min_text_size(float(options.get("min_font_px", 12.0))))
		out.append(check_safe_area())
		out.append(check_localization())
		out.append(check_load_time(float(options.get("load_budget_s", 15.0))))
		out.append(check_soak(str(options.get("soak_json", ""))))
		out.append(check_glyphs())
		out.append(check_deck_readability(float(options.get("min_font_px", 12.0))))
		_cleanup()
		return out

	func count(results: Array, status: String) -> int:
		var n: int = 0
		for r in results:
			if (r as Dictionary)["status"] == status:
				n += 1
		return n

	func to_markdown(results: Array) -> String:
		var lines: PackedStringArray = []
		lines.append("# Cgame certification-style readiness report")
		lines.append("")
		lines.append("Based on public best practices only. Not a platform certification. PASS %d / FAIL %d / MANUAL %d" % [
			count(results, "PASS"), count(results, "FAIL"), count(results, "MANUAL")])
		lines.append("")
		lines.append("| Status | Check | Detail |")
		lines.append("|---|---|---|")
		for r in results:
			var d: Dictionary = r
			lines.append("| %s | %s | %s |" % [d["status"], d["title"], str(d["detail"]).replace("|", "/")])
		lines.append("")
		return "\n".join(lines)

	# ---- helpers -------------------------------------------------------------------------------------------------
	func _desktop(sub: String) -> PS.DesktopBackend:
		return PS.DesktopBackend.new("%s/%s" % [scratch_root, sub])

	func _cleanup() -> void:
		_rm_tree(scratch_root)

	func _rm_tree(path: String) -> void:
		if not DirAccess.dir_exists_absolute(path):
			return
		for sub in DirAccess.get_directories_at(path):
			_rm_tree("%s/%s" % [path, sub])
		for file_name in DirAccess.get_files_at(path):
			DirAccess.remove_absolute("%s/%s" % [path, file_name])
		DirAccess.remove_absolute(path)

	func _scan(dir: String, pattern: RegEx, found: Array, max_depth: int = 6) -> void:
		if max_depth < 0:
			return
		for sub in DirAccess.get_directories_at(dir):
			_scan("%s/%s" % [dir, sub], pattern, found, max_depth - 1)
		for file_name in DirAccess.get_files_at(dir):
			if not file_name.ends_with(".gd"):
				continue
			var path := "%s/%s" % [dir, file_name]
			var text := FileAccess.get_file_as_string(path)
			for m in pattern.search_all(text):
				found.append({"path": path, "match": m})

	# ---- checks --------------------------------------------------------------------------------------------------
	func check_save_atomic_backup() -> Dictionary:
		var title := "Save corruption resilience (atomic write + backup)"
		var be := _desktop("atomic")
		var ps := PS.new(be)
		ps.save_game("s", {"v": 1})
		ps.save_game("s", {"v": 2})
		be.corrupt_main("s")
		var loaded := ps.load_game("s")
		var ok: bool = loaded["result"] == PS.SaveResult.OK and loaded["source"] == PS.RecoverSource.BACKUP \
			and int((loaded["data"] as Dictionary).get("v", 0)) == 1
		return _res("save_atomic", title, STATUS_PASS if ok else STATUS_FAIL,
			"corrupt main recovered from backup" if ok else "corrupt main did not recover from backup")

	func check_save_interrupted() -> Dictionary:
		var title := "Interrupted save leaves previous save valid"
		var be := _desktop("interrupt")
		var ps := PS.new(be)
		ps.save_game("s", {"v": 1})
		be.interrupt_before_commit = true
		var r := ps.save_game("s", {"v": 2})
		be.interrupt_before_commit = false
		var loaded := ps.load_game("s")
		var ok: bool = r == PS.SaveResult.INTERRUPTED and loaded["result"] == PS.SaveResult.OK \
			and int((loaded["data"] as Dictionary).get("v", 0)) == 1
		return _res("save_interrupt", title, STATUS_PASS if ok else STATUS_FAIL, "old save intact" if ok else "old save lost")

	func check_quota_handling() -> Dictionary:
		var title := "Save quota exceeded handled without data loss"
		var be := PS.MockConsoleBackend.new()
		var ps := PS.new(be)
		ps.save_game("s", {"v": 1})
		be.quota_bytes = be.save_used_bytes() + 4
		var r := ps.save_game("s", {"v": 2, "pad": "x".repeat(200)})
		var loaded := ps.load_game("s")
		var ok: bool = r == PS.SaveResult.QUOTA_EXCEEDED and int((loaded["data"] as Dictionary).get("v", 0)) == 1
		return _res("save_quota", title, STATUS_PASS if ok else STATUS_FAIL,
			"QUOTA_EXCEEDED reported, existing save kept" if ok else "quota path lost data or hid the error")

	func check_suspend_resume() -> Dictionary:
		var title := "Suspend/resume during load and save"
		var be := PS.MockConsoleBackend.new()
		var ps := PS.new(be)
		ps.save_game("s", {"v": 1})
		be.suspend()
		var during_save := ps.save_game("s", {"v": 2})
		var during_load: int = ps.load_game("s")["result"]
		be.resume()
		var after := ps.load_game("s")
		var ok: bool = during_save == PS.SaveResult.SUSPENDED and during_load == PS.SaveResult.SUSPENDED \
			and after["result"] == PS.SaveResult.OK and int((after["data"] as Dictionary).get("v", 0)) == 1 \
			and not ps.should_pause()
		return _res("suspend", title, STATUS_PASS if ok else STATUS_FAIL,
			"I/O deferred while suspended, save valid after resume" if ok else "suspend handling broken")

	func check_controller_disconnect() -> Dictionary:
		var title := "Controller disconnect pauses and prompts"
		var be := PS.MockConsoleBackend.new()
		var ps := PS.new(be)
		ps.start_session(0)
		be.disconnect_controller(0)
		var paused := ps.should_pause()
		be.reconnect_controller(0)
		var ok: bool = paused and not ps.should_pause()
		return _res("controller", title, STATUS_PASS if ok else STATUS_FAIL,
			"paused on loss, resumed on reconnect (UI prompt itself: verify manually)" if ok else "no pause on controller loss")

	func check_sign_out() -> Dictionary:
		var title := "Sign-out mid-session ends session and blocks saves"
		var be := PS.MockConsoleBackend.new()
		var ps := PS.new(be)
		ps.start_session(0)
		be.sign_out()
		var ok: bool = not ps.session_active and ps.save_game("s", {}) == PS.SaveResult.NO_USER
		return _res("signout", title, STATUS_PASS if ok else STATUS_FAIL, "session ended, saves refused" if ok else "session survived sign-out")

	func check_offline() -> Dictionary:
		var title := "Offline handling (local play and saves keep working)"
		var be := PS.MockConsoleBackend.new()
		var ps := PS.new(be)
		be.set_network(false)
		var saved := ps.save_game("s", {"v": 1})
		var ok: bool = saved == PS.SaveResult.OK and not ps.network_available() and not ps.can_use_online()
		return _res("offline", title, STATUS_PASS if ok else STATUS_FAIL,
			"local saves OK, online features gated (server-join error messaging: verify manually)" if ok else "offline path broken")

	func check_restrictions_and_text_input() -> Dictionary:
		var title := "Parental controls and text input fallback"
		var be := PS.MockConsoleBackend.new()
		var ps := PS.new(be)
		be.set_restriction("chat", true)
		be.scripted_text = ["abcdefghij"]
		var typed := ps.request_text("Name", 4)
		var ok: bool = not ps.can_use_chat() and bool(typed["ok"]) and str(typed["text"]) == "abcd"
		return _res("restrictions", title, STATUS_PASS if ok else STATUS_FAIL,
			"chat gated by restriction, text length clamped" if ok else "restriction/text input wrong")

	func check_achievements_idempotent() -> Dictionary:
		var title := "Achievements unlock once"
		var ps := PS.new(_desktop("ach"))
		var first := ps.unlock_achievement("first_blood")
		var second := ps.unlock_achievement("first_blood")
		var ok: bool = first and not second and ps.backend.achievement_ids().size() == 1
		return _res("achievements", title, STATUS_PASS if ok else STATUS_FAIL, "idempotent" if ok else "duplicate unlock")

	func _font_sizes() -> Array:
		var found: Array = []
		var rx := RegEx.new()
		rx.compile("font_size\"?\\s*[,=]\\s*(\\d+)")
		_scan("res://scripts/client", rx, found)
		return found

	func check_min_text_size(min_px: float) -> Dictionary:
		var title := "Minimum text size (>= %d px at 720p design size)" % int(min_px)
		var small: Array = []
		var total: int = 0
		for entry in _font_sizes():
			total += 1
			var m: RegExMatch = (entry as Dictionary)["match"]
			if float(m.get_string(1)) < min_px:
				small.append("%s:%s" % [str((entry as Dictionary)["path"]).get_file(), m.get_string(1)])
		if total == 0:
			return _res("min_text", title, STATUS_MANUAL, "no literal font sizes found, review theme manually")
		if small.is_empty():
			return _res("min_text", title, STATUS_PASS, "%d literal sizes scanned, none below %d" % [total, int(min_px)])
		return _res("min_text", title, STATUS_FAIL, "%d of %d literal sizes below %d px (e.g. %s)" % [
			small.size(), total, int(min_px), ", ".join(PackedStringArray(small.slice(0, 4)))])

	func check_safe_area() -> Dictionary:
		var title := "Safe area / title-safe margins"
		var found: Array = []
		var rx := RegEx.new()
		rx.compile("get_display_safe_area|safe_area|SAFE_MARGIN")
		_scan("res://scripts/client", rx, found)
		if found.is_empty():
			return _res("safe_area", title, STATUS_FAIL, "no safe-area handling found in scripts/client; HUD anchors to raw screen edges")
		return _res("safe_area", title, STATUS_MANUAL, "%d references found; verify on a TV-sized overscan test image" % found.size())

	func check_localization() -> Dictionary:
		var title := "Localization completeness"
		var ru: Dictionary = UiLocalization.RU
		var empty: Array[String] = []
		var mismatch: Array[String] = []
		var rx := RegEx.new()
		rx.compile("%[sdfi]|\\{\\w+\\}")
		for key in ru.keys():
			var tr_text := str(ru[key])
			if tr_text.strip_edges() == "":
				empty.append(str(key))
			elif rx.search_all(str(key)).size() != rx.search_all(tr_text).size():
				mismatch.append(str(key))
		var missing: Array = UiLocalization.missing_entries()
		if not empty.is_empty() or not mismatch.is_empty():
			return _res("localization", title, STATUS_FAIL, "%d empty, %d placeholder mismatches" % [empty.size(), mismatch.size()])
		if not missing.is_empty():
			return _res("localization", title, STATUS_FAIL, "%d UI strings without translation" % missing.size())
		return _res("localization", title, STATUS_PASS, "%d RU entries, no empty values or placeholder mismatches (only en+ru exist)" % ru.size())

	func check_load_time(budget_s: float) -> Dictionary:
		var title := "Loading time budget (<= %.0f s, headless desktop)" % budget_s
		var scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			return _res("load_time", title, STATUS_MANUAL, "no main scene to time")
		var t0 := Time.get_ticks_msec()
		var res := ResourceLoader.load(scene_path)
		var elapsed_s := float(Time.get_ticks_msec() - t0) / 1000.0
		if res == null:
			return _res("load_time", title, STATUS_FAIL, "main scene failed to load")
		var detail := "main scene loaded in %.2f s (target hardware must be measured manually)" % elapsed_s
		return _res("load_time", title, STATUS_PASS if elapsed_s <= budget_s else STATUS_FAIL, detail)

	func check_soak(path: String) -> Dictionary:
		var title := "Crash-free soak (soak_test.gd results)"
		if path == "" or not FileAccess.file_exists(path):
			return _res("soak", title, STATUS_MANUAL, "no soak JSON supplied (run scripts/tools/soak_test.gd --out)")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			return _res("soak", title, STATUS_FAIL, "soak JSON unreadable")
		var data: Dictionary = parsed
		var verdict: Dictionary = data.get("verdict", {})
		if verdict.is_empty():
			return _res("soak", title, STATUS_MANUAL, "soak JSON has no verdict block")
		var bad: bool = bool(verdict.get("p95_over_budget", false)) or bool(verdict.get("leak_detected", false))
		return _res("soak", title, STATUS_FAIL if bad else STATUS_PASS,
			"p95_over_budget=%s leak_detected=%s" % [verdict.get("p95_over_budget", false), verdict.get("leak_detected", false)])

	func check_glyphs() -> Dictionary:
		var title := "Controller glyphs (Steam Deck / gamepad prompts)"
		var found: Array = []
		var rx := RegEx.new()
		rx.compile("(?i)glyph|button_prompt")
		_scan("res://scripts/client", rx, found)
		if found.is_empty():
			return _res("glyphs", title, STATUS_FAIL, "no controller glyph/prompt code found")
		return _res("glyphs", title, STATUS_MANUAL, "glyph code present (%d refs); verify prompts switch with last-used device" % found.size())

	func check_deck_readability(min_px: float) -> Dictionary:
		var title := "1280x800 readability (Steam Deck)"
		var vw := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1152))
		var vh := float(ProjectSettings.get_setting("display/window/size/viewport_height", 648))
		var stretch: String = str(ProjectSettings.get_setting("display/window/stretch/mode", "disabled"))
		var scale: float = minf(1280.0 / vw, 800.0 / vh) if stretch != "disabled" else 1.0
		var small: int = 0
		for entry in _font_sizes():
			var m: RegExMatch = (entry as Dictionary)["match"]
			if float(m.get_string(1)) * scale < min_px:
				small += 1
		if small > 0:
			return _res("deck_readability", title, STATUS_FAIL, "%d literal sizes below %d px at 1280x800 (scale %.2f)" % [small, int(min_px), scale])
		return _res("deck_readability", title, STATUS_MANUAL, "literal sizes OK at scale %.2f; confirm visually on device" % scale)
