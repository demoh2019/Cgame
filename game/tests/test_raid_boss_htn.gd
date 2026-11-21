extends RefCounted
## The raid boss HTN layer opens with the reaching cone when a slam cannot land.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")


class FakeBoss:
	var target_id: int = -1
	var position: Vector3 = Vector3.ZERO


func run(t) -> void:
	t.current = "raid boss htn"
	var world = WorldGen.new(4321)
	var server := GameServer.new(world, 5)
	var hero = server.add_player(950, "Hero")
	var boss := FakeBoss.new()
	boss.position = Vector3(500, 0, 500)
	boss.target_id = hero.id
	hero.position = boss.position + Vector3(RaidEncounter.SLAM_RADIUS * 0.5, 0, 0)
	t.eq(server._raid_boss_plan(boss), "slam", "a target inside the slam radius gets slammed")
	hero.position = boss.position + Vector3(RaidEncounter.SLAM_RADIUS + 4.0, 0, 0)
	t.eq(server._raid_boss_plan(boss), "charge", "a distant target draws the reaching strike")
	boss.target_id = -1
	t.eq(server._raid_boss_plan(boss), "slam", "no target falls back to the slam cycle")
