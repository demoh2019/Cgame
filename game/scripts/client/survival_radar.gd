extends Control
## Live north-up radar for the canonical survival game. World entities are
## read from either the authoritative offline simulation or network snapshots.
## This Control never owns gameplay state or invents unobserved enemies.

const WorldGen = preload("res://scripts/shared/world_gen.gd")

const METERS_RADIUS := 72.0
const REFRESH_INTERVAL := 0.2
const MAP_INSET := 0.44

var world
var sim
var client
var actor_id: int = 0
var _elapsed: float = 0.0


## Ground coordinates: -Z points north, +X east.
static func map_point(origin: Vector2, target: Vector2, map_size: Vector2,
		meters: float = METERS_RADIUS) -> Vector2:
	if meters <= 0.0:
		return map_size * 0.5
	var scale: float = minf(map_size.x, map_size.y) * MAP_INSET / meters
	return map_size * 0.5 + (target - origin) * scale


static func in_range(origin: Vector2, target: Vector2,
		meters: float = METERS_RADIUS) -> bool:
	return (
		meters > 0.0 and origin.is_finite() and target.is_finite()
		and origin.distance_squared_to(target) <= meters * meters
	)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_elapsed = REFRESH_INTERVAL


func _process(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	if _elapsed >= REFRESH_INTERVAL:
		_elapsed = 0.0
		if client != null:
			world = client.world
		queue_redraw()


## Query is shared with tests; the same authoritative positions drive drawing.
func current_position() -> Vector2:
	if sim != null and sim.players.has(actor_id):
		var player = sim.players[actor_id]
		return Vector2(player.position.x, player.position.z)
	if client != null and client.you.has("x") and client.you.has("z"):
		return Vector2(float(client.you["x"]), float(client.you["z"]))
	return Vector2(INF, INF)


func current_yaw() -> float:
	if sim != null and sim.players.has(actor_id):
		return float(sim.players[actor_id].yaw)
	if client != null:
		return float(client.you.get("yaw", 0.0))
	return 0.0


func _paint_pin(at: Vector2, center_world: Vector2, shade: Color,
		pixel_radius: float) -> void:
	if in_range(center_world, at):
		draw_circle(map_point(center_world, at, size), pixel_radius, shade)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.077, 0.09, 0.91), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.38, 0.48, 0.50, 0.9), false, 1.4)
	var center: Vector2 = size * 0.5
	var circle_radius: float = minf(size.x, size.y) * MAP_INSET
	draw_arc(center, circle_radius, 0.0, TAU, 48, Color(0.30, 0.47, 0.53, 0.5), 1.0)
	draw_line(Vector2(center.x, 0), Vector2(center.x, size.y),
		Color(0.25, 0.36, 0.40, 0.32), 1.0)
	draw_line(Vector2(0, center.y), Vector2(size.x, center.y),
		Color(0.25, 0.36, 0.40, 0.32), 1.0)

	if world == null:
		return
	var origin: Vector2 = current_position()
	if not origin.is_finite():
		return
	# Settlement marker. It is a known world location, not a player position.
	_paint_pin(Vector2(9.0, 0.0), origin, Color(0.40, 0.69, 1.0), 6.0)

	var depleted_nodes: Dictionary = {}
	if sim != null:
		depleted_nodes = sim.depleted
	elif client != null:
		depleted_nodes = client.depleted

	var cell: Vector2i = WorldGen.cell_of(origin.x, origin.y)
	for cx in range(cell.x - 1, cell.x + 2):
		for cz in range(cell.y - 1, cell.y + 2):
			var chunk: Dictionary = world.chunk(Vector2i(cx, cz))
			for node in chunk["nodes"]:
				if not depleted_nodes.has(int(node["id"])):
					_paint_pin(Vector2(float(node["x"]), float(node["z"])),
						origin, Color(0.94, 0.76, 0.28), 2.6)
			for crate in chunk["crates"]:
				var opened := false
				if sim != null:
					opened = sim.opened_crates.has(int(crate["id"]))
				elif client != null:
					opened = client.crates_used.has(int(crate["id"]))
				if not opened:
					_paint_pin(Vector2(float(crate["x"]), float(crate["z"])),
						origin, Color(0.33, 0.85, 0.61), 3.2)

	if sim != null:
		for zombie in sim.zombies.values():
			if zombie.is_alive():
				_paint_pin(Vector2(zombie.position.x, zombie.position.z),
					origin, Color(0.99, 0.34, 0.31), 4.0)
		for wall in sim.barricades.values():
			_paint_pin(Vector2(float(wall["x"]), float(wall["z"])),
				origin, Color(0.88, 0.62, 0.25), 3.9)
		for bag in sim.bags.values():
			_paint_pin(Vector2(float(bag["x"]), float(bag["z"])),
				origin, Color(0.41, 0.93, 0.68), 3.0)
	elif client != null:
		for zombie in client.zombies.values():
			_paint_pin(Vector2(float(zombie["x"]), float(zombie["z"])),
				origin, Color(0.99, 0.34, 0.31), 4.0)
		for wall in client.barricades.values():
			_paint_pin(Vector2(float(wall["x"]), float(wall["z"])),
				origin, Color(0.88, 0.62, 0.25), 3.9)
		for bag in client.bags.values():
			_paint_pin(Vector2(float(bag["x"]), float(bag["z"])),
				origin, Color(0.41, 0.93, 0.68), 3.0)

	# Local survivor always stays in the center of a player-following radar.
	var yaw_value: float = current_yaw()
	var facing := Vector2(sin(yaw_value), cos(yaw_value))
	var side := Vector2(-facing.y, facing.x)
	var triangle := PackedVector2Array([
		center + facing * 11.0,
		center - facing * 7.0 + side * 5.0,
		center - facing * 7.0 - side * 5.0,
	])
	draw_colored_polygon(triangle, Color(1.0, 1.0, 0.93))
