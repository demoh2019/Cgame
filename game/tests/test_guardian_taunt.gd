extends RefCounted
## Live server checks: tanking never produces player PvP threat, free energy,
## XP, remote effects or a forged target choice.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "party guardian authority"
	var world := WorldGen.new(41)
	var sim := GameServer.new(world, 41)
	var tank = sim.add_player(41, "Tank")
	var ally = sim.add_player(42, "Ally")
	var rival = sim.add_player(43, "Rival")
	tank.position = _at(world, 310, 0)
	ally.position = _at(world, 313, 0)
	rival.position = _at(world, 313, 1)
	var enemy = Zombie.new(sim.new_id(), "brute", _at(world, 312, 0))
	enemy.target_id = ally.id
	enemy.state = Zombie.State.CHASE
	sim.zombies[enemy.id] = enemy
	var other = Zombie.new(sim.new_id(), "brute", _at(world, 312, 1))
	other.target_id = rival.id
	other.state = Zombie.State.CHASE
	sim.zombies[other.id] = other
	t.eq(sim.cmd_guardian_taunt(41).get("reason"), "not_in_party", "solo cannot redirect aggro")
	t.check(sim.cmd_party_invite(41, 42).get("ok", false), "real nearby invite accepted")
	t.check(sim.cmd_party_accept(42).get("ok", false), "real party formed")
	t.eq(sim.cmd_guardian_taunt(41).get("reason"), "need_melee",
		"unarmed party member cannot use guardian role")
	tank.inventory.add("club_1", 1)
	t.check(tank.inventory.equip("club_1"), "carried melee club equipped")
	var neutral = Zombie.new(sim.new_id(), "walker", _at(world, 311, 2))
	sim.zombies[neutral.id] = neutral
	t.check(not GuardianTaunt.eligible_enemy(neutral, tank.position, [41, 42], world),
		"neutral zombies are not pulled")
	t.check(not GuardianTaunt.eligible_enemy(other, tank.position, [41, 42], world),
		"rival's combat stays independent")
	var before: float = tank.combat_energy
	var result: Dictionary = sim.cmd_guardian_taunt(41)
	t.check(result.get("ok", false), "tank redirects ally's engaged infected")
	t.eq(result.get("count", 0), 1, "only one eligible enemy redirected")
	t.eq(enemy.target_id, tank.id, "server controls new infected target")
	t.eq(enemy.forced_target_id, tank.id, "three-second forced focus stored on server")
	t.near(enemy.forced_target_seconds, GuardianTaunt.FOCUS_SECONDS, 0.001,
		"short aggro focus has bounded duration")
	t.near(tank.combat_energy, before - GuardianTaunt.ENERGY_COST, 0.001,
		"successful ability charges combat energy")
	t.eq(other.target_id, rival.id, "enemy of unrelated player not touched")
	t.eq(neutral.target_id, -1, "neutral stays unprovoked")
	t.eq(sim.cmd_guardian_taunt(41).get("reason"), "cooldown",
		"fast replay cannot bypass cooldown")
	t.near(tank.combat_energy, before - GuardianTaunt.ENERGY_COST, 0.001,
		"rejected request does not charge energy twice")
	t.near(sim.snapshot_for(41)["you"]["guardian_cooldown"],
		GuardianTaunt.COOLDOWN, 0.001, "cooldown comes from server snapshot")
	t.current = "safe-zone and depleted-energy defense"
	var actors := {
		41: {"position": tank.position, "alive": true, "safe": false},
		42: {"position": ally.position, "alive": true, "safe": false}
	}
	enemy._select_target(actors, Vector2(enemy.position.x, enemy.position.z))
	t.eq(enemy.target_id, 41, "active guardian taunt overrides normal hate")
	actors[41]["safe"] = true
	enemy._select_target(actors, Vector2(enemy.position.x, enemy.position.z))
	t.eq(enemy.forced_target_id, -1, "entering safety clears temporary focus")
	t.check(enemy.target_id != 41, "safe guardian no longer targeted")
	tank.guardian_timer = 0.0
	tank.combat_energy = 0.0
	enemy.target_id = 42
	t.eq(sim.cmd_guardian_taunt(41).get("reason"), "no_energy",
		"no energy means no cast")
	t.near(tank.guardian_timer, 0.0, 0.001, "failed cast has no cooldown")
	tank.combat_energy = 100.0
	tank.position = _at(world, 0, 0)
	t.eq(sim.cmd_guardian_taunt(41).get("reason"), "safe_zone",
		"safe hub blocks combat shouts")
	tank.position = _at(world, 310, 0)
	tank.survival.hurt(1000.0)
	t.eq(sim.cmd_guardian_taunt(41).get("reason"), "dead",
		"dead player cannot use guardian skill")
