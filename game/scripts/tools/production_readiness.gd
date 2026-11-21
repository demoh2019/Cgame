extends RefCounted
## Test-log parser and Markdown production-readiness (go/no-go) report.
## Original code (MIT-compatible).


## Parses runner output. Returns {suites:{name:{checks,failed,failures,unloadable}},
## total_checks, total_failures, has_total, script_errors:[String], orphan_fails:[String]}.
static func parse_test_log(text: String) -> Dictionary:
	var suites: Dictionary = {}
	var script_errors: Array[String] = []
	var orphan: Array[String] = []
	var total_checks: int = 0
	var total_failures: int = 0
	var has_total: bool = false
	var line_re: RegEx = RegEx.new()
	line_re.compile("^\\s*(\\S+?)(?:\\.gd)?\\s+(\\d+)\\s+checks?\\s+(\\d+)\\s+failed")
	var total_re: RegEx = RegEx.new()
	total_re.compile("TOTAL\\s+(\\d+)\\s+checks?,\\s+(\\d+)\\s+failures?")
	var err_re: RegEx = RegEx.new()
	err_re.compile("(?:res://)?(?:[\\w/]*/)?(test_\\w+)\\.gd")
	var last: String = ""
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.is_empty():
			continue
		var m: RegExMatch = total_re.search(line)
		if m != null:
			total_checks = int(m.get_string(1))
			total_failures = int(m.get_string(2))
			has_total = true
			continue
		if line.begins_with("SCRIPT ERROR") or line.begins_with("ERROR: Failed to load script") or line.begins_with("Parse Error"):
			var em: RegExMatch = err_re.search(line)
			if em != null:
				var sname: String = em.get_string(1)
				var s: Dictionary = _suite(suites, sname)
				s["unloadable"] = true
				last = sname
			script_errors.append(line)
			continue
		if line.begins_with("FAIL"):
			if last != "" and suites.has(last):
				var ls: Dictionary = suites[last]
				var fl: Array = ls["failures"]
				fl.append(line)
			else:
				orphan.append(line)
			continue
		var lm: RegExMatch = line_re.search(line)
		if lm != null:
			var s2: Dictionary = _suite(suites, lm.get_string(1))
			s2["checks"] = int(lm.get_string(2))
			s2["failed"] = int(lm.get_string(3))
			last = lm.get_string(1)
	return {
		"suites": suites, "total_checks": total_checks, "total_failures": total_failures,
		"has_total": has_total, "script_errors": script_errors, "orphan_fails": orphan,
	}


static func _suite(suites: Dictionary, name: String) -> Dictionary:
	if not suites.has(name):
		suites[name] = {"checks": 0, "failed": 0, "failures": [], "unloadable": false}
	var s: Dictionary = suites[name]
	return s


## extra_gates: {gate_name: bool | {"pass": bool, "detail": String}}.
## perf_report: compare_runs result, optionally with "leak" (memory_leak_trend result).
static func report(test_results: Dictionary, perf_report: Dictionary, extra_gates: Dictionary) -> String:
	var failing: Array[String] = []
	var unloadable: Array[String] = []
	var suites: Dictionary = test_results.get("suites", {})
	var names: Array = suites.keys()
	names.sort()
	for n in names:
		var s: Dictionary = suites[n]
		if bool(s["unloadable"]):
			unloadable.append(str(n))
		elif int(s["failed"]) > 0 or not (s["failures"] as Array).is_empty():
			failing.append(str(n))
	var total_failures: int = int(test_results.get("total_failures", 0))
	var script_errors: Array = test_results.get("script_errors", [])
	var orphan: Array = test_results.get("orphan_fails", [])
	var tests_ok: bool = failing.is_empty() and unloadable.is_empty() and total_failures == 0 \
		and script_errors.is_empty() and orphan.is_empty()
	var regressions: Array = perf_report.get("regressions", [])
	var perf_ok: bool = regressions.is_empty()
	var leak: Dictionary = perf_report.get("leak", {})
	var leak_ok: bool = not bool(leak.get("leak", false))
	var gates_ok: bool = true
	var gate_lines: Array[String] = []
	var gnames: Array = extra_gates.keys()
	gnames.sort()
	for g in gnames:
		var v: Variant = extra_gates[g]
		var passed: bool = false
		var detail: String = ""
		if v is Dictionary:
			var vd: Dictionary = v
			passed = bool(vd.get("pass", false))
			detail = str(vd.get("detail", ""))
		else:
			passed = bool(v)
		gates_ok = gates_ok and passed
		gate_lines.append("| %s | %s | %s |" % [g, "PASS" if passed else "FAIL", detail])
	var go: bool = tests_ok and perf_ok and leak_ok and gates_ok
	var md: PackedStringArray = PackedStringArray()
	md.append("# Production readiness")
	md.append("")
	md.append("## Verdict: %s" % ("GO" if go else "NO-GO"))
	md.append("")
	md.append("| Gate | Status |")
	md.append("|---|---|")
	md.append("| Tests | %s |" % ("PASS" if tests_ok else "FAIL"))
	md.append("| Performance | %s |" % ("PASS" if perf_ok else "FAIL"))
	md.append("| Memory leak | %s |" % ("PASS" if leak_ok else "FAIL"))
	md.append("| Extra gates | %s |" % ("PASS" if gates_ok else "FAIL"))
	md.append("")
	md.append("## Tests")
	md.append("")
	md.append("- Suites: %d, total checks: %d, failures: %d" % [names.size(), int(test_results.get("total_checks", 0)), total_failures])
	if failing.is_empty():
		md.append("- Failing suites: none")
	else:
		md.append("- Failing suites:")
		for n in failing:
			var fs: Dictionary = suites[n]
			md.append("  - %s (%d failed)" % [n, int(fs["failed"])])
			for fl in (fs["failures"] as Array):
				md.append("    - %s" % str(fl))
	if unloadable.is_empty():
		md.append("- Unloadable suites: none")
	else:
		md.append("- Unloadable suites: " + ", ".join(unloadable))
	for e in script_errors:
		md.append("- SCRIPT ERROR: %s" % str(e))
	for o in orphan:
		md.append("- %s" % str(o))
	md.append("")
	md.append("## Performance")
	md.append("")
	var pm: Dictionary = perf_report.get("metrics", {})
	if pm.is_empty():
		md.append("No performance comparison supplied.")
	else:
		md.append("| Metric | Baseline | Current | Change | Verdict |")
		md.append("|---|---|---|---|---|")
		var mkeys: Array = pm.keys()
		mkeys.sort()
		for k in mkeys:
			var e2: Dictionary = pm[k]
			md.append("| %s | %.3f | %.3f | %+.1f%% | %s |" % [k, float(e2["baseline"]), float(e2["current"]),
				float(e2["pct"]), "REGRESSION" if bool(e2["regressed"]) else "ok"])
	md.append("")
	md.append("## Memory leak")
	md.append("")
	if leak.is_empty():
		md.append("No soak data supplied.")
	else:
		md.append("- Verdict: %s (slope %.4f/sample, r2 %.2f, growth %.1f%%)" % [
			"LEAK" if not leak_ok else "stable", float(leak.get("slope", 0.0)),
			float(leak.get("r2", 0.0)), float(leak.get("growth_pct", 0.0))])
	if not gate_lines.is_empty():
		md.append("")
		md.append("## Extra gates")
		md.append("")
		md.append("| Gate | Status | Detail |")
		md.append("|---|---|---|")
		md.append_array(PackedStringArray(gate_lines))
	return "\n".join(md) + "\n"
