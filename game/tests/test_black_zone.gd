extends RefCounted
## Albion-style black zone: open full-loot PvP without infamy; red zone still punishes murder.

const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _spot(world, zone: int) -> Vector2:
	for x in range(100, 3000, 11):
		if world.zone_at(float(x), 0.0) == zone and not world.is_safe(float(x), 0.0) and not world.is_water(float(x), 0.0):
			return Vector2(x, 0)
	return Vector2.INF


func _kill(server, world, at: Vector2, a, b) -> void:
	a.position = Vector3(at.x, world.height_at(at.x, at.y), at.y)
	b.position = Vector3(at.x + 1.0, world.height_at(at.x + 1.0, at.y), at.y)
	b.survival.health = 1.0
	server._damage_target(a, {"kind": "player", "id": b.id}, 40.0, "melee")


func run(t) -> void:
	t.current = "lawless black zone"
	t.check(ZoneRisk.lawless(3), "black is lawless")
	t.check(not ZoneRisk.lawless(2), "red is not")
	var world = WorldGen.new(97531)
	var server := GameServer.new(world, 17)
	var black := _spot(world, 3)
	var red := _spot(world, 2)
	t.check(black != Vector2.INF and red != Vector2.INF, "found red and black ground")
	var a = server.add_player(1201, "Raider")
	var b = server.add_player(1202, "Victim")
	var c = server.add_player(1203, "Victim2")
	for p in [a, b, c]:
		p.inventory = Inventory.new()
	_kill(server, world, black, a, b)
	t.check(not server._alive(b), "black-zone kill happened")
	t.eq(a.pvp_infamy, 0.0, "black-zone kills cost no infamy")
	_kill(server, world, red, a, c)
	t.check(a.pvp_infamy > 0.0, "red-zone murder still raises infamy")
