extends RefCounted
## Platform services abstraction and certification-style checks.

const PS = preload("res://scripts/shared/platform_services.gd")
const CertChecks = preload("res://scripts/tools/cert_checks.gd")

const TMP := "user://test_platform_services"


func _rm_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_rm_tree("%s/%s" % [path, sub])
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute("%s/%s" % [path, file_name])
	DirAccess.remove_absolute(path)


func run(t) -> void:
	_rm_tree(TMP)

	t.current = "desktop save atomicity and backup"
	var desk := PS.DesktopBackend.new(TMP + "/a")
	var ps := PS.new(desk)
	t.eq(ps.save_game("slot", {"v": 1}), PS.SaveResult.OK, "first save ok")
	t.eq(ps.save_game("slot", {"v": 2}), PS.SaveResult.OK, "second save ok")
	var loaded: Dictionary = ps.load_game("slot")
	t.eq(int((loaded["data"] as Dictionary)["v"]), 2, "latest save loads")
	t.eq(loaded["source"], PS.RecoverSource.MAIN, "loaded from main")
	desk.corrupt_main("slot")
	loaded = ps.load_game("slot")
	t.eq(loaded["result"], PS.SaveResult.OK, "corrupt main recovers")
	t.eq(loaded["source"], PS.RecoverSource.BACKUP, "recovered from backup")
	t.eq(int((loaded["data"] as Dictionary)["v"]), 1, "backup holds previous save")
	t.eq(ps.load_game("missing")["result"], PS.SaveResult.NOT_FOUND, "missing slot reported")
	t.check(PS.decode_save("CGS1:1:{}".to_utf8_buffer()).is_empty(), "bad checksum rejected")
	desk.interrupt_before_commit = true
	t.eq(ps.save_game("slot", {"v": 3}), PS.SaveResult.INTERRUPTED, "interrupted write reported")
	desk.interrupt_before_commit = false
	t.check(FileAccess.file_exists(TMP + "/a/slot.tmp"), "interrupted write leaves only a temp file")
	t.eq(int((ps.load_game("slot")["data"] as Dictionary)["v"]), 1, "main still readable after interruption")

	t.current = "quota handling"
	var mock := PS.MockConsoleBackend.new()
	var mps := PS.new(mock)
	t.eq(mps.save_game("q", {"v": 1}), PS.SaveResult.OK, "save under no quota")
	mock.quota_bytes = mock.save_used_bytes() + 2
	t.eq(mps.save_game("q", {"v": 2, "pad": "x".repeat(100)}), PS.SaveResult.QUOTA_EXCEEDED, "quota exceeded reported")
	t.eq(int((mps.load_game("q")["data"] as Dictionary)["v"]), 1, "old save untouched after quota failure")
	var dq := PS.DesktopBackend.new(TMP + "/q")
	dq.quota_bytes = 20
	t.eq(PS.new(dq).save_game("q", {"pad": "x".repeat(100)}), PS.SaveResult.QUOTA_EXCEEDED, "desktop quota enforced")

	t.current = "sign-out mid-session"
	var sb := PS.MockConsoleBackend.new()
	var sps := PS.new(sb)
	t.check(sps.start_session(0), "session starts")
	sb.sign_out()
	t.check(not sps.session_active, "session ends on sign-out")
	t.check(sps.last_session_end_reason.begins_with("signed_out"), "reason recorded")
	t.eq(sps.save_game("s", {}), PS.SaveResult.NO_USER, "save refused without user")
	t.eq(sps.load_game("s")["result"], PS.SaveResult.NO_USER, "load refused without user")
	t.check(not sps.start_session(0), "cannot start session signed out")

	t.current = "controller disconnect"
	var cb := PS.MockConsoleBackend.new()
	var cps := PS.new(cb)
	cps.start_session(0)
	t.check(not cps.should_pause(), "running with controller")
	cb.disconnect_controller(0)
	t.check(cps.should_pause() and cps.paused_for_controller, "paused when controller lost")
	cb.reconnect_controller(0)
	t.check(not cps.should_pause(), "resumes when controller returns")
	t.eq(cb.controller_owner(0), "user1", "controller paired to user")

	t.current = "suspend during save"
	var xb := PS.MockConsoleBackend.new()
	var xps := PS.new(xb)
	xps.save_game("s", {"v": 1})
	xb.interrupt_before_commit = true
	t.eq(xps.save_game("s", {"v": 2}), PS.SaveResult.INTERRUPTED, "save cut short")
	xb.interrupt_before_commit = false
	xb.suspend()
	t.check(xps.should_pause(), "paused while suspended")
	t.eq(xps.save_game("s", {"v": 9}), PS.SaveResult.SUSPENDED, "no save while suspended")
	t.eq(xps.load_game("s")["result"], PS.SaveResult.SUSPENDED, "no load while suspended")
	xb.resume()
	var after: Dictionary = xps.load_game("s")
	t.eq(after["result"], PS.SaveResult.OK, "save valid after resume")
	t.eq(int((after["data"] as Dictionary)["v"]), 1, "previous data survived")
	t.check(not xps.should_pause(), "unpaused after resume")

	t.current = "achievements"
	var ach := PS.new(PS.DesktopBackend.new(TMP + "/ach"))
	t.check(ach.unlock_achievement("a1"), "first unlock is new")
	t.check(not ach.unlock_achievement("a1"), "second unlock is a no-op")
	t.check(ach.backend.is_achievement_unlocked("a1"), "persisted")
	t.eq(ach.backend.achievement_ids().size(), 1, "single entry")

	t.current = "restrictions, presence, entitlements"
	var rb := PS.MockConsoleBackend.new()
	var rps := PS.new(rb)
	rb.set_restriction("chat", true)
	t.check(not rps.can_use_chat(), "chat blocked by parental control")
	rb.set_network(false)
	t.check(not rps.network_available() and not rps.can_use_online(), "offline blocks online")
	rb.grant_entitlement("dlc1")
	t.check(rps.has_entitlement("dlc1") and not rps.has_entitlement("dlc2"), "entitlements")
	rps.set_presence("In raid")
	t.eq(rb.presence(), "In raid", "presence set")
	rb.scripted_text = ["toolongname"]
	t.eq(str(rps.request_text("Name", 5)["text"]), "toolo", "text clamped")

	t.current = "cert checks report"
	var checks := CertChecks.Checks.new()
	checks.scratch_root = TMP + "/cert"
	var results: Array = checks.run_all({})
	t.check(results.size() >= 12, "report has results")
	var report := checks.to_markdown(results)
	t.check(report.contains("PASS") and report.contains("MANUAL"), "markdown has statuses")
	t.check(report.contains("| Status | Check | Detail |"), "markdown has table")
	for r in results:
		var d: Dictionary = r
		if str(d["id"]).begins_with("save") or d["id"] in ["suspend", "controller", "signout", "offline", "achievements"]:
			t.eq(d["status"], "PASS", "cert check %s passes" % d["id"])
	_rm_tree(TMP)
