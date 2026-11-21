extends RefCounted
## Example data for the AI planners. Data only, no behaviour.
##  - htn_domain(): raid boss decision tree for HTNPlanner (Horizon-style):
##    enrage when low health, summon adds when surrounded, else charge/slam.
##  - goap_actions(): scavenger infected for GOAPPlanner (F.E.A.R.-style):
##    find food, eat, or flee when threatened.


static func htn_domain() -> Dictionary:
	return {
		"boss_turn": [
			{"preconditions": {"low_health": true, "enraged": false}, "subtasks": ["enrage_phase"]},
			{"preconditions": {"surrounded": true, "adds_alive": false}, "subtasks": ["summon_adds_phase"]},
			{"preconditions": {"target_far": true}, "subtasks": ["charge_phase"]},
			{"preconditions": {}, "subtasks": ["slam_phase"]},
		],
		"enrage_phase": [
			{"preconditions": {}, "subtasks": ["roar", "enrage", "slam"]},
		],
		"summon_adds_phase": [
			{"preconditions": {}, "subtasks": ["roar", "summon_adds"]},
		],
		"charge_phase": [
			{"preconditions": {"stamina_ok": true}, "subtasks": ["charge", "slam"]},
			{"preconditions": {}, "subtasks": ["roar", "charge"]},
		],
		"slam_phase": [
			{"preconditions": {}, "subtasks": ["slam"]},
		],
		"roar": {"preconditions": {}, "effects": {"roared": true}},
		"enrage": {"preconditions": {"enraged": false}, "effects": {"enraged": true}},
		"summon_adds": {"preconditions": {"adds_alive": false}, "effects": {"adds_alive": true}},
		"charge": {"preconditions": {"target_far": true}, "effects": {"target_far": false}},
		"slam": {"preconditions": {"target_far": false}, "effects": {"target_hit": true}},
	}


static func goap_actions() -> Array:
	return [
		{"name": "find_food", "cost": 3.0, "preconditions": {"threatened": false, "knows_food": false}, "effects": {"knows_food": true}},
		{"name": "go_to_food", "cost": 2.0, "preconditions": {"knows_food": true, "threatened": false}, "effects": {"at_food": true}},
		{"name": "eat", "cost": 1.0, "preconditions": {"at_food": true, "threatened": false}, "effects": {"hungry": false}},
		{"name": "scavenge_corpse", "cost": 9.0, "preconditions": {"threatened": false}, "effects": {"hungry": false}},
		{"name": "flee", "cost": 1.0, "preconditions": {"threatened": true}, "effects": {"threatened": false}},
	]
