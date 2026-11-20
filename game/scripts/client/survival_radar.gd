extends Control
## Live north-up radar for the canonical survival game. World entities are
## read from either the authoritative offline simulation or network snapshots.
## This Control never owns gameplay state or invents unobserved enemies.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const RuinSurvey = preload("res://scripts/shared/ruin_survey.gd")
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")
const RaidCone = preload("res://scripts/shared/raid_cone.gd")

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


## Only a local actor or the local private network snapshot may supply
## waypoint coordinates. Other players' snapshots never carry these fields.
func current_caravan() -> Dictionary:
	if sim != null:
		if sim.players.has(actor_id):
			return sim.players[actor_id].caravan_view.duplicate(true)
		return {}
	if client != null:
		return client.you.get("caravan", {}).duplicate(true)
	return {}


func current_rally() -> Dictionary:
	if sim != null:
		return sim.parties.state_for(actor_id, sim.time).get("rally", {}).duplicate(true)
	if client != null:
		return client.you.get("party", {}).get("rally", {}).duplicate(true)
	return {}


## Draw an in-range beacon or an offscreen edge arrow in one shared style.
func _draw_waypoint(origin: Vector2, info: Dictionary, x_key: String,
		z_key: String, color: Color) -> void:
	var destination: Vector2 = TravelNavigation.target(info, x_key, z_key)
	var guide: Dictionary = TravelNavigation.project(origin, destination, size,
		METERS_RADIUS, MAP_INSET)
	if guide.is_empty():
		return
	var point: Vector2 = guide["point"]
	if bool(guide["inside"]):
		draw_arc(point, 7.5, 0.0, TAU, 24, color, 1.5)
		draw_circle(point, 4.7, color)
	else:
		var heading: Vector2 = (destination - origin).normalized()
		var side := Vector2(-heading.y, heading.x)
		draw_colored_polygon(PackedVector2Array([
			point, point - heading * 12.0 + side * 5.5,
			point - heading * 12.0 - side * 5.5]), color)


func _paint_pin(at: Vector2, center_world: Vector2, shade: Color,
		pixel_radius: float) -> void:
	if in_range(center_world, at):
		draw_circle(map_point(center_world, at, size), pixel_radius, shade)


## Only a snapshot-visible, server-issued cone is rendered as a tactical wedge.
## This is presentation only; the server independently resolves all hits.
func _draw_raid_cone(origin: Vector2, attack: Dictionary) -> void:
	if attack.is_empty():
		return
	for key in ["x", "z", "dx", "dz", "reach", "half_angle", "until"]:
		if not attack.has(key) or not is_finite(float(attack[key])):
			return
	var strike_origin := Vector2(float(attack["x"]), float(attack["z"]))
	var facing := Vector2(float(attack["dx"]), float(attack["dz"]))
	var reach: float = float(attack["reach"])
	var half_angle: float = float(attack["half_angle"])
	if not strike_origin.is_finite() or not facing.is_finite() or \
			absf(facing.length_squared() - 1.0) > 0.01 or \
			reach <= 0.0 or reach > RaidCone.REACH or \
			half_angle <= 0.0 or half_angle > RaidCone.HALF_ANGLE_DEGREES:
		return
	if not in_range(origin, strike_origin):
		return
	var arc_points := PackedVector2Array()
	arc_points.append(map_point(origin, strike_origin, size))
	for index in range(17):
		var radians := deg_to_rad(-half_angle + float(index) * (half_angle * 2.0 / 16.0))
		var tip: Vector2 = strike_origin + facing.rotated(radians) * reach
		arc_points.append(map_point(origin, tip, size))
	draw_colored_polygon(arc_points, Color(1.0, 0.25, 0.12, 0.23))
	draw_polyline(arc_points, Color(1.0, 0.42, 0.16, 0.82), 1.4)


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

	# Locked boss cleave: distinguish the dangerous sector from friendly markers.
	var incoming_cone: Dictionary = {}
	if sim != null and not sim.raid_pending_cone.is_empty():
		incoming_cone = sim.raid_pending_cone.duplicate(true)
		incoming_cone["reach"] = RaidCone.REACH
		incoming_cone["half_angle"] = RaidCone.HALF_ANGLE_DEGREES
	elif client != null:
		incoming_cone = client.raid_cone_telegraph
	if not incoming_cone.is_empty():
		_draw_raid_cone(origin, incoming_cone)

	## The party standard is visible to members as a field aura radius.
	# No non-member coordinates are ever sent by the server.
	var current_standard: Dictionary = {}
	if sim != null and sim.players.has(actor_id):
		current_standard = sim.parties.state_for(actor_id, sim.time).get("standard", {})
	elif client != null:
		current_standard = client.you.get("party", {}).get("standard", {})
	if not current_standard.is_empty():
		var point := Vector2(float(current_standard["x"]), float(current_standard["z"]))
		if in_range(origin, point):
			var map_position: Vector2 = map_point(origin, point, size)
			var scale: float = minf(size.x, size.y) * MAP_INSET / METERS_RADIUS
			draw_arc(map_position, 11.0 * scale, 0.0, TAU, 32,
				Color(0.98, 0.72, 0.25, 0.68), 1.5)
			_paint_pin(point, origin, Color(0.98, 0.72, 0.25), 5.1)

	# This waypoint is private to the map owner, not revealed to other peers.
	# Distant ruins are shown as an edge-pointing arrow until within 72m.
	var active_survey: Dictionary = {}
	if sim != null and sim.players.has(actor_id):
		active_survey = RuinSurvey.public_mark(
			sim.players[actor_id].ruin_survey, sim.time, sim.opened_crates)
	elif client != null:
		active_survey = client.you.get("ruin_survey", {})
	if not active_survey.is_empty():
		var destination := Vector2(float(active_survey["x"]), float(active_survey["z"]))
		if destination.is_finite():
			if in_range(origin, destination):
				_paint_pin(destination, origin, Color(0.84, 0.38, 0.98), 6.0)
			else:
				var arrow_direction: Vector2 = (destination - origin).normalized()
				var tip: Vector2 = center + arrow_direction * (circle_radius - 2.0)
				var tangent := Vector2(-arrow_direction.y, arrow_direction.x)
				var arrow := PackedVector2Array([
					tip, tip - arrow_direction * 12.0 + tangent * 5.0,
					tip - arrow_direction * 12.0 - tangent * 5.0])
				draw_colored_polygon(arrow, Color(0.84, 0.38, 0.98))

	# Teal = private caravan destination; amber = temporary party-only rally.
	# A remote target stays visible as an edge arrow until it is reached.
	_draw_waypoint(origin, current_caravan(), "dst_x", "dst_z",
		Color(0.28, 0.92, 0.92))
	_draw_waypoint(origin, current_rally(), "x", "z",
		Color(1.0, 0.60, 0.22))

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
