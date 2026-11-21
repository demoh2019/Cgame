extends SceneTree

const Attributes = preload("res://addons/visual_quality/attribute_component.gd")
const Combatant = preload("res://addons/visual_quality/combat_component.gd")
const Sentry = preload("res://addons/visual_quality/hostile_sentry.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage = Node3D.new()
	root.add_child(stage)
	var player = Node3D.new()
	stage.add_child(player)
	var hp = Attributes.new()
	player.add_child(hp)
	var target = Combatant.new()
	target.attributes = hp
	target.team_id = Combatant.TEAM_PLAYER
	player.add_child(target)
	var enemy = Sentry.new()
	enemy.player = player
	enemy.player_combatant = target
	stage.add_child(enemy)
	assert(enemy.combatant.is_alive())
	assert(enemy.get_node("SentryCollider") is CollisionShape3D)
	assert(enemy.save_sentry_state().is_empty())
	assert(enemy.combatant.receive_damage(40.0, Combatant.TEAM_PLAYER) > 0.0)
	var state: Dictionary = enemy.save_sentry_state()
	assert(state.has("sentry_health"))
	assert(float(state["sentry_health"]) < 100.0)
	enemy.load_sentry_state(state)
	assert(is_equal_approx(enemy.attributes.health, float(state["sentry_health"])))
	enemy.load_sentry_state({"sentry_health": 0.0})
	assert(not enemy.combatant.is_alive())
	assert(enemy.collision_layer == 0)
	enemy.load_sentry_state({})
	assert(enemy.combatant.is_alive())
	assert(enemy.collision_layer == 1)
	enemy.set_ai_enabled(false)
	assert(not enemy.is_physics_processing())
	enemy.set_ai_enabled(true)
	assert(enemy.is_physics_processing())
	stage.queue_free()
	print("WorldHostileSentry3D: combat body, state restore and AI sleep passed")
	quit(0)
