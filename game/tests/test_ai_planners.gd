extends RefCounted
## HTN and GOAP planners plus the example raid / scavenger domain.

const HTNPlanner = preload("res://scripts/shared/htn_planner.gd")
const GOAPPlanner = preload("res://scripts/shared/goap_planner.gd")
const InfectedRaidDomain = preload("res://scripts/shared/infected_raid_domain.gd")


func run(t) -> void:
	t.current = "htn backtracking"
	var domain: Dictionary = {
		"root": [
			{"preconditions": {"a": true}, "subtasks": ["need_key", "open"]},
			{"preconditions": {}, "subtasks": ["kick"]},
		],
		"need_key": {"preconditions": {"has_key": true}, "effects": {}},
		"open": {"preconditions": {}, "effects": {"open": true}},
		"kick": {"preconditions": {}, "effects": {"open": true}},
	}
	t.eq(HTNPlanner.plan(domain, "root", {"a": true}), ["kick"] as Array[String], "falls back to second method when first dead-ends")
	t.eq(HTNPlanner.plan(domain, "root", {"a": true, "has_key": true}), ["need_key", "open"] as Array[String], "first viable method wins")
	t.eq(HTNPlanner.plan(domain, "root", {"a": true}), HTNPlanner.plan(domain, "root", {"a": true}), "deterministic")
	t.check(HTNPlanner.plan(domain, "missing", {}).is_empty(), "unknown task yields no plan")
	var bad: Dictionary = {"root": [{"preconditions": {"x": 1}, "subtasks": ["p"]}], "p": {"preconditions": {}, "effects": {}}}
	t.check(HTNPlanner.plan(bad, "root", {"x": 2}).is_empty(), "no applicable method yields no plan")

	t.current = "htn state simulation and step cap"
	var seq: Dictionary = {
		"root": [{"preconditions": {}, "subtasks": ["a", "b"]}],
		"a": {"preconditions": {}, "effects": {"done_a": true}},
		"b": {"preconditions": {"done_a": true}, "effects": {}},
	}
	t.eq(HTNPlanner.plan(seq, "root", {}), ["a", "b"] as Array[String], "effects feed later preconditions")
	var loop: Dictionary = {"root": [{"preconditions": {}, "subtasks": ["root"]}]}
	t.check(HTNPlanner.plan(loop, "root", {}).is_empty(), "recursive domain terminates at the step cap")
	t.check(HTNPlanner.plan(seq, "root", {}, 1).is_empty(), "tiny step cap aborts planning")

	t.current = "goap plans"
	var actions: Array = [
		{"name": "buy", "cost": 5.0, "preconditions": {"money": true}, "effects": {"food": true}},
		{"name": "hunt", "cost": 2.0, "preconditions": {"weapon": true}, "effects": {"food": true}},
		{"name": "craft", "cost": 1.0, "preconditions": {}, "effects": {"weapon": true}},
		{"name": "steal", "cost": 9.0, "preconditions": {}, "effects": {"money": true}},
	]
	t.eq(GOAPPlanner.plan(actions, {}, {"food": true}), ["craft", "hunt"] as Array[String], "picks the cheapest chain")
	t.eq(GOAPPlanner.plan(actions, {"money": true}, {"food": true}), ["craft", "hunt"] as Array[String], "owning money still prefers the cheaper craft+hunt chain")
	t.check(GOAPPlanner.plan(actions, {}, {"food": true}).size() == 2, "plan length")
	t.check(GOAPPlanner.plan(actions, {"food": true}, {"food": true}).is_empty(), "already satisfied is an empty plan")
	t.check(GOAPPlanner.plan(actions, {}, {"teleport": true}).is_empty(), "unreachable goal yields empty plan")
	t.check(GOAPPlanner.plan(actions, {}, {"food": true}, 1).is_empty(), "node cap aborts the search")
	var ties: Array = [
		{"name": "first", "cost": 1.0, "preconditions": {}, "effects": {"g": true}},
		{"name": "second", "cost": 1.0, "preconditions": {}, "effects": {"g": true}},
	]
	t.eq(GOAPPlanner.plan(ties, {}, {"g": true}), ["first"] as Array[String], "ties break by insertion order")

	t.current = "infected raid domain"
	var dom: Dictionary = InfectedRaidDomain.htn_domain()
	var base: Dictionary = {"low_health": false, "enraged": false, "surrounded": false, "adds_alive": false, "target_far": false, "stamina_ok": true}
	t.eq(HTNPlanner.plan(dom, "boss_turn", base), ["slam"] as Array[String], "boss slams by default")
	var far: Dictionary = base.duplicate()
	far["target_far"] = true
	t.eq(HTNPlanner.plan(dom, "boss_turn", far), ["charge", "slam"] as Array[String], "boss charges a distant target")
	var hurt: Dictionary = base.duplicate()
	hurt["low_health"] = true
	t.eq(HTNPlanner.plan(dom, "boss_turn", hurt), ["roar", "enrage", "slam"] as Array[String], "boss enrages when low")
	var swarmed: Dictionary = base.duplicate()
	swarmed["surrounded"] = true
	t.eq(HTNPlanner.plan(dom, "boss_turn", swarmed), ["roar", "summon_adds"] as Array[String], "boss summons adds when surrounded")
	var acts: Array = InfectedRaidDomain.goap_actions()
	var hungry: Dictionary = {"hungry": true, "threatened": false, "knows_food": false, "at_food": false}
	t.eq(GOAPPlanner.plan(acts, hungry, {"hungry": false}), ["find_food", "go_to_food", "eat"] as Array[String], "scavenger forages when safe")
	var scared: Dictionary = hungry.duplicate()
	scared["threatened"] = true
	t.eq(GOAPPlanner.plan(acts, scared, {"hungry": false}), ["flee", "find_food", "go_to_food", "eat"] as Array[String], "scavenger flees first")
