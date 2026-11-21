extends RefCounted
## Documentation generator: header, const/signal/func extraction and Markdown rendering.

const DocsGenerator = preload("res://scripts/tools/docs_generator.gd")

const SAMPLE := """extends RefCounted
## Sample planner for the doc generator test. It plans things.
##
## Layout:
##   {"cost": int}

const MAX_DEPTH := 8  ## trailing doc
## Quality tiers.
const TIERS: Array[String] = ["low", "high"]

## Emitted when a plan finishes.
signal plan_done(ok: bool)

var undocumented: int = 0
## Documented counter.
var counter: int = 0

## Plans a route.
## Second doc line.
static func plan(start: Vector3,
		goal: Vector3 = Vector3.ZERO, flags: PackedStringArray = PackedStringArray([":"])) -> Array:
	## inner comment is not a doc
	return [start, goal]

# plain comment is ignored
func no_docs() -> void:
	pass

## Hidden.
func _private_helper() -> void:
	pass
"""


func run(t) -> void:
	t.current = "docs generator extraction"
	var info: Dictionary = DocsGenerator.extract(SAMPLE)
	var header: String = info["header"]
	t.check(header.begins_with("Sample planner for the doc generator test."), "header comment captured")
	t.check(header.contains("{\"cost\": int}"), "header keeps indented layout lines")
	var consts: Array = info["consts"]
	t.eq(consts.size(), 2, "two constants")
	var first_const: Dictionary = consts[0]
	t.eq(first_const["name"], "MAX_DEPTH", "const name")
	t.eq(first_const["doc"], "trailing doc", "trailing ## doc used")
	var second_const: Dictionary = consts[1]
	t.eq(second_const["name"], "TIERS", "typed const name")
	t.eq(second_const["doc"], "Quality tiers.", "preceding doc attached to const")
	var sigs: Array = info["signals"]
	t.eq(sigs.size(), 1, "one signal")
	var sig_item: Dictionary = sigs[0]
	t.eq(sig_item["name"], "plan_done", "signal name")
	t.eq(sig_item["doc"], "Emitted when a plan finishes.", "signal doc")
	var vars_doc: Array = info["vars"]
	t.eq(vars_doc.size(), 1, "only documented vars are listed")
	var funcs: Array = info["funcs"]
	t.eq(funcs.size(), 2, "public funcs only")
	var plan: Dictionary = funcs[0]
	t.eq(plan["name"], "plan", "func name")
	t.check(bool(plan["is_static"]), "static flag")
	t.eq(plan["sig"], "static func plan(start: Vector3, goal: Vector3 = Vector3.ZERO, flags: PackedStringArray = PackedStringArray([\":\"])) -> Array", "multi-line signature joined, colon in string kept")
	t.eq(plan["doc"], "Plans a route.\nSecond doc line.", "multi-line func doc")
	var plain: Dictionary = funcs[1]
	t.eq(plain["name"], "no_docs", "second func name")
	t.eq(plain["doc"], "", "plain # comment is not a doc")
	t.eq(info["private_count"], 1, "private func counted, not listed")

	t.current = "docs generator rendering"
	var page: String = DocsGenerator.render_page("sample.gd", "res://scripts/shared/sample.gd", info)
	t.check(page.begins_with("# sample.gd\n"), "page title")
	t.check(page.contains("\n> Sample planner for the doc generator test.\n"), "summary line is the first sentence")
	t.check(page.contains("## Overview"), "overview heading")
	t.check(page.contains("## Constants"), "constants heading")
	t.check(page.contains("## Signals"), "signals heading")
	t.check(page.contains("## Functions"), "functions heading")
	t.check(page.contains("### `plan`"), "per-function heading")
	t.check(page.contains("```gdscript\nstatic func plan("), "signature fenced as gdscript")
	t.check(page.contains("```text\nSample planner"), "indented header is fenced to keep layout")
	t.check(page.contains("1 private function(s)"), "private count noted")
	t.check(not page.contains("_private_helper"), "private names are not listed")
	t.eq(DocsGenerator.summary_of(""), "(no header comment)", "empty header summary")

	t.current = "docs generator cli args"
	var args: Dictionary = DocsGenerator.parse_args(PackedStringArray(["--path", "res://scripts/shared", "--out", "/tmp/x"]))
	t.eq(args["path"], "res://scripts/shared", "--path parsed")
	t.eq(args["out"], "/tmp/x", "--out parsed")
