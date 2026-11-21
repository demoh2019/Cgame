extends SceneTree

const Attributes = preload("res://addons/visual_quality/attribute_component.gd")
const Combatant = preload("res://addons/visual_quality/combat_component.gd")


func _initialize() -> void:
	assert(is_equal_approx(Combatant.compute_damage(100.0, 0.0), 100.0))
	assert(is_equal_approx(Combatant.compute_damage(100.0, 100.0), 50.0))
	assert(Combatant.compute_damage(-10.0, 10.0) == 0.0)
	assert(Combatant.compute_damage(NAN, 10.0) == 0.0)
	var stats = Attributes.new()
	var combat = Combatant.new()
	combat.attributes = stats
	combat.team_id = Combatant.TEAM_HOSTILE
	combat.armor = 0.0
	var deaths: Array[int] = []
	combat.defeated.connect(func() -> void: deaths.append(1))
	assert(not combat.can_receive_hit(Combatant.TEAM_HOSTILE))
	assert(combat.receive_damage(20.0, Combatant.TEAM_HOSTILE) == 0.0)
	assert(combat.receive_damage(20.0, Combatant.TEAM_PLAYER, 2.0) == 20.0)
	assert(stats.health == 80.0)
	assert(combat.is_stunned())
	assert(combat.receive_damage(90.0, Combatant.TEAM_PLAYER) == 0.0)
	combat._physics_process(2.1)
	assert(not combat.is_stunned())
	assert(combat.receive_damage(200.0, Combatant.TEAM_PLAYER) == 80.0)
	assert(not combat.is_alive())
	assert(deaths.size() == 1)
	assert(combat.receive_damage(20.0, Combatant.TEAM_PLAYER) == 0.0)
	assert(deaths.size() == 1)
	combat.restore_health(55.0, 0.4)
	assert(combat.is_alive() and combat.is_stunned())
	assert(stats.health == 55.0)
	combat._physics_process(0.5)
	assert(not combat.is_stunned())
	assert(not combat.apply_stun(INF))
	assert(combat.apply_stun(20.0))
	assert(combat.stun_remaining <= 10.0)
	stats.free()
	combat.free()
	print("WorldCombatant3D: damage, teams, stun, i-frames and one-shot death passed")
	quit(0)
