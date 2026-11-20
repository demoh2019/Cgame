extends Control
## The whole island on one screen (J): terrain painted from the seed, the danger rings, every settlement, camp, fort and ruin,
## the siege outposts and you. Hover a place to read its name. The picture is made a few rows per frame the first time.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")
const ExpeditionAtlas = preload("res://scripts/shared/expedition_atlas.gd")

signal personal_waypoint_changed(point: Vector2)

const PIXELS := 256
const SPAN := WorldGen.WORLD_RADIUS * 2.0 + 200.0
const KIND_COLORS := {
	"village": Color(1.0, 0.85, 0.3), "farm": Color(0.8, 0.9, 0.35), "camp": Color(0.95, 0.65, 0.35), "depot": Color(0.7, 0.75, 0.85),
	"outpost": Color(0.4, 0.8, 1.0), "tower": Color(0.85, 0.85, 0.9), "mine": Color(0.75, 0.55, 0.4), "city": Color(0.95, 0.4, 0.4),
	"bunker": Color(0.75, 0.4, 0.95), "lighthouse": Color(1.0, 1.0, 0.7), "dock": Color(0.5, 0.75, 0.95),
	"landmark": Color(0.5, 1.0, 0.85),
}
const ZONE_COLORS := [Color(0.35, 0.85, 0.45, 0.5), Color(0.95, 0.82, 0.3, 0.5), Color(0.95, 0.45, 0.3, 0.5)]

var client
var _image: Image
var _texture: ImageTexture
var _next_row := 0
var _sites: Array = []
var _hover := {}
var _panel_rect := Rect2()
var waypoint: Vector2 = Vector2(INF, INF)
var followed_objective: String = "" # Empty means manually placed private pin.
var _objective_hitboxes: Array[Dictionary] = []


func setup(p_client) -> void:
	client = p_client
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_image = Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	_image.fill(Color(0.05, 0.1, 0.2))
	_texture = ImageTexture.create_from_image(_image)


func toggle() -> void:
	visible = not visible
	if visible and _sites.is_empty():
		for rx in range(-14, 14):
			for rz in range(-14, 14):
				_sites.append_array(client.world.poi.sites_in_region(rx, rz))


## Available goals are derived solely from the authenticated local snapshot.
func current_objectives() -> Array[Dictionary]:
	if client == null:
		return []
	return ExpeditionAtlas.objectives(client.you)


## Clicking a goal selects an ordinary private waypoint; there is no RPC.
## Unlike a manual marker, a followed goal can move or expire.
func select_objective(key: String) -> bool:
	var info: Dictionary = ExpeditionAtlas.find(current_objectives(), key)
	if info.is_empty():
		return false
	var point := Vector2(float(info["x"]), float(info["z"]))
	if not set_waypoint(point):
		return false
	followed_objective = key
	return true


func _sync_followed_objective() -> void:
	if followed_objective.is_empty():
		return
	var info: Dictionary = ExpeditionAtlas.find(current_objectives(), followed_objective)
	if info.is_empty():
		clear_waypoint()
		return
	var point := Vector2(float(info["x"]), float(info["z"]))
	if not TravelNavigation.valid_destination(point, WorldGen.WORLD_RADIUS):
		clear_waypoint()
		return
	if waypoint.distance_squared_to(point) > 0.01:
		waypoint = point
		personal_waypoint_changed.emit(waypoint)
		queue_redraw()


static func objective_color(key: String) -> Color:
	match key:
		"recovery":
			return Color(1.0, 0.43, 0.20)
		"threat":
			return Color(1.0, 0.32, 0.45)
		"prospect":
			return Color(0.95, 0.62, 0.21)
		"ruin":
			return Color(0.84, 0.38, 0.98)
		"caravan":
			return Color(0.28, 0.92, 0.92)
		"escort":
			return Color(0.71, 0.51, 1.0)
		"rally":
			return Color(1.0, 0.60, 0.22)
		_:
			return Color(0.20, 0.95, 0.90)


## Player-owned navigation only. No RPC and no server-side location leak.
func set_waypoint(point: Vector2) -> bool:
	if not TravelNavigation.valid_destination(point, WorldGen.WORLD_RADIUS):
		return false
	followed_objective = ""
	waypoint = point
	personal_waypoint_changed.emit(waypoint)
	queue_redraw()
	return true


func clear_waypoint() -> void:
	followed_objective = ""
	waypoint = Vector2(INF, INF)
	personal_waypoint_changed.emit(waypoint)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if not click.pressed:
		return
	# The journal rows remain clickable even outside the terrain rectangle.
	if click.button_index == MOUSE_BUTTON_LEFT and not click.shift_pressed:
		for row in _objective_hitboxes:
			var row_bounds: Rect2 = row["rect"]
			if row_bounds.has_point(click.position):
				if select_objective(str(row["key"])):
					accept_event()
				return
	if not _panel_rect.has_point(click.position):
		return
	# Selecting a goal marker is distinct from placing a manual map pin.
	# Shift+Left retains the existing server-validated party ping behavior.
	if click.button_index == MOUSE_BUTTON_LEFT and not click.shift_pressed:
		for objective in current_objectives():
			var pin := _to_screen(float(objective["x"]), float(objective["z"]))
			if pin.distance_squared_to(click.position) <= 12.0 * 12.0:
				if select_objective(str(objective["key"])):
					accept_event()
				return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			var destination: Vector2 = TravelNavigation.world_from_map(
				click.position, _panel_rect, SPAN, WorldGen.WORLD_RADIUS)
			if not TravelNavigation.valid_destination(destination, WorldGen.WORLD_RADIUS):
				return
			if click.shift_pressed:
				# Coordinates and party access are validated by the server.
				if client != null:
					client.party_ping(destination)
				accept_event()
			elif set_waypoint(destination):
				accept_event()
		MOUSE_BUTTON_RIGHT:
			clear_waypoint()
			accept_event()


func _process(_delta: float) -> void:
	# A moving raid target keeps its radar route updated with the atlas CLOSED.
	_sync_followed_objective()
	if not visible:
		return
	# Paint the terrain a few rows per frame.
	var rows := 12
	while rows > 0 and _next_row < PIXELS:
		_paint_row(_next_row)
		_next_row += 1
		rows -= 1
		if _next_row % 12 == 0 or _next_row == PIXELS:
			_texture.update(_image)
	queue_redraw()


func _paint_row(row: int) -> void:
	var world = client.world
	var step: float = SPAN / float(PIXELS)
	for column in PIXELS:
		var x: float = -SPAN * 0.5 + (float(column) + 0.5) * step
		var z: float = -SPAN * 0.5 + (float(row) + 0.5) * step
		var height: float = world.height_at(x, z)
		var color: Color
		if height < Defs.WATER_LEVEL - 0.4:
			color = Color(0.06, 0.2, 0.38).lerp(Color(0.12, 0.42, 0.6), clampf((height + 20.0) / 20.0, 0.0, 1.0))
		else:
			match world.biome_at(x, z):
				"beach": color = Color(0.8, 0.74, 0.52)
				"forest": color = Color(0.14, 0.38, 0.17)
				"plains": color = Color(0.4, 0.55, 0.22)
				"swamp": color = Color(0.3, 0.38, 0.2)
				"mountain": color = Color(0.5, 0.48, 0.46).lerp(Color(0.95, 0.96, 1.0), clampf((height - 60.0) / 60.0, 0.0, 1.0))
				_: color = Color(0.4, 0.5, 0.25)
			# Light from the north-west: slopes facing it are brighter.
			var shade: float = (world.height_at(x - step, z - step) - world.height_at(x + step, z + step)) * 0.012
			color = color.lightened(clampf(shade, -0.3, 0.3)) if shade > 0.0 else color.darkened(clampf(-shade, 0.0, 0.4))
		_image.set_pixel(column, row, color)


func _to_screen(x: float, z: float) -> Vector2:
	return _panel_rect.position + Vector2((x + SPAN * 0.5) / SPAN, (z + SPAN * 0.5) / SPAN) * _panel_rect.size


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.03, 0.05, 0.88))
	var side: float = minf(view.x - 60.0, view.y - 90.0)
	_panel_rect = Rect2(Vector2((view.x - side) * 0.5, 62.0), Vector2(side, side))
	draw_texture_rect(_texture, _panel_rect, false)
	draw_rect(_panel_rect, Color(0.95, 0.78, 0.35, 0.8), false, 2.0)
	var font: Font = ThemeDB.fallback_font
	# Danger rings.
	for i in Defs.ZONE_RADII.size():
		var radius: float = float(Defs.ZONE_RADII[i]) / SPAN * _panel_rect.size.x
		draw_arc(_to_screen(0.0, 0.0), radius, 0.0, TAU, 96, ZONE_COLORS[i], 1.5)
	# Roads.
	if client.world.roads != null:
		for road in client.world.roads.all_roads():
			var points: PackedVector2Array = road["points"]
			var line := PackedVector2Array()
			for i in range(0, points.size(), 2):
				line.append(_to_screen(points[i].x, points[i].y))
			line.append(_to_screen(points[points.size() - 1].x, points[points.size() - 1].y))
			draw_polyline(line, Color(0.85, 0.72, 0.5, 0.55), 1.2, true)
	var edge: float = WorldGen.WORLD_RADIUS / SPAN * _panel_rect.size.x
	draw_arc(_to_screen(0.0, 0.0), edge, 0.0, TAU, 128, Color(1, 1, 1, 0.25), 1.0)
	# Seeded site positions are public; personal visited marks are not.
	var visited: Dictionary = {}
	for discovered_id in client.you.get("discovered_site_ids", []):
		visited[int(discovered_id)] = true
	# Sites.
	var mouse: Vector2 = get_local_mouse_position()
	_hover = {}
	var best := 14.0
	for site in _sites:
		var spot: Vector2 = _to_screen(float(site["x"]), float(site["z"]))
		var color: Color = KIND_COLORS.get(site["kind"], Color.WHITE)
		var size := 5.0 if bool(site["station"]) else 3.2
		if site["kind"] == "landmark":
			size = 3.6
			draw_colored_polygon(PackedVector2Array([spot + Vector2(0, -size - 1.5), spot + Vector2(size + 1.5, 0), spot + Vector2(0, size + 1.5), spot + Vector2(-size - 1.5, 0)]), Color(0, 0, 0, 0.7))
			draw_colored_polygon(PackedVector2Array([spot + Vector2(0, -size), spot + Vector2(size, 0), spot + Vector2(0, size), spot + Vector2(-size, 0)]), color)
			var landmark_gap: float = spot.distance_to(mouse)
			if landmark_gap < best:
				best = landmark_gap
				_hover = site
			continue
		if site["kind"] == "city":
			size = 4.2
		if bool(site["station"]):
			draw_rect(Rect2(spot - Vector2.ONE * (size + 1.5), Vector2.ONE * (size + 1.5) * 2.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(spot - Vector2.ONE * size, Vector2.ONE * size * 2.0), color)
		if visited.has(int(site["id"])):
			draw_arc(spot, size + 3.0, 0.0, TAU, 16, Color(0.98, 0.92, 0.40), 1.8)
		if bool(site["station"]) and (site["kind"] == "village" or site["kind"] == "outpost"):
			draw_string_outline(font, spot + Vector2(8, 4), str(site["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.9))
			draw_string(font, spot + Vector2(8, 4), str(site["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.95))
		var gap: float = spot.distance_to(mouse)
		if gap < best:
			best = gap
			_hover = site
	# The hub, the siege outposts and the player.
	var hub: Vector2 = _to_screen(0.0, 0.0)
	draw_circle(hub, 7.0, Color(0, 0, 0, 0.8))
	draw_circle(hub, 5.0, Color(1.0, 0.9, 0.4))
	draw_string_outline(font, hub + Vector2(9, 4), "HUB", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
	draw_string(font, hub + Vector2(9, 4), "HUB", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.95, 0.6))
	for post in client.outposts:
		var flag: Vector2 = _to_screen(float(post["x"]), float(post["z"]))
		draw_colored_polygon(PackedVector2Array([flag + Vector2(0, -9), flag + Vector2(8, -5), flag + Vector2(0, -1)]), Color(1.0, 0.45, 0.35))
		draw_line(flag, flag + Vector2(0, -9), Color.WHITE, 1.5)
	if client.you.has("x"):
		var me: Vector2 = _to_screen(float(client.you["x"]), float(client.you["z"]))
		var heading: Vector2 = Vector2(sin(client.yaw), cos(client.yaw))
		var side_vec := Vector2(-heading.y, heading.x)
		draw_colored_polygon(PackedVector2Array([me + heading * 9.0, me - heading * 6.0 + side_vec * 5.5, me - heading * 3.0, me - heading * 6.0 - side_vec * 5.5]), Color(0.3, 0.8, 1.0))
	# Personal travel pin, drawn above sites. Only the local UI knows this point.
	if waypoint.is_finite():
		var pin: Vector2 = _to_screen(waypoint.x, waypoint.y)
		if client.you.has("x") and client.you.has("z"):
			draw_line(_to_screen(float(client.you["x"]), float(client.you["z"])),
				pin, Color(1.0, 0.86, 0.35, 0.55), 1.6, true)
		draw_circle(pin, 8.0, Color(0.0, 0.0, 0.0, 0.85))
		draw_arc(pin, 7.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.3), 2.0)
		draw_circle(pin, 3.0, Color(1.0, 0.85, 0.3))
		draw_string_outline(font, pin + Vector2(11, 4), "WAYPOINT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
		draw_string(font, pin + Vector2(11, 4), "WAYPOINT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.9, 0.5))
	# Teal team ping comes only from this player's authenticated party snapshot.
	var squad_ping: Dictionary = client.you.get("party", {}).get("ping", {})
	if not squad_ping.is_empty():
		var target := Vector2(float(squad_ping.get("x", INF)),
			float(squad_ping.get("z", INF)))
		if TravelNavigation.valid_destination(target, WorldGen.WORLD_RADIUS):
			var marker: Vector2 = _to_screen(target.x, target.y)
			var hue := Color(0.95, 0.65, 0.25) if str(squad_ping.get("kind", "")) == "survey" else Color(0.2, 0.95, 0.9)
			draw_circle(marker, 10.0, Color(0.02, 0.08, 0.1, 0.92))
			draw_colored_polygon(PackedVector2Array([
				marker + Vector2(0, -9), marker + Vector2(9, 0),
				marker + Vector2(0, 9), marker + Vector2(-9, 0)]), hue)
			var caption := "PARTY PING #%d (%ds)" % [
				int(squad_ping.get("by", 0)),
				ceili(float(squad_ping.get("remaining", 0.0)))]
			if str(squad_ping.get("kind", "")) == "survey":
				caption = "PARTY T%d %s VEIN (%ds)" % [
					int(squad_ping.get("tier", 2)),
					str(squad_ping.get("material", "ore")).to_upper(),
					ceili(float(squad_ping.get("remaining", 0.0)))]
			draw_string_outline(font, marker + Vector2(13, -1),
				caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
			draw_string(font, marker + Vector2(13, -1),
				caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hue)
	# The expedition atlas only reads this user's private or party-allowed
	# snapshot. No objective coordinates are sourced from remote actors.
	var objectives: Array[Dictionary] = current_objectives()
	for objective in objectives:
		var point: Vector2 = _to_screen(float(objective["x"]), float(objective["z"]))
		var color: Color = objective_color(str(objective["key"]))
		draw_circle(point, 8.2, Color(0.0, 0.0, 0.0, 0.85))
		draw_arc(point, 6.7, 0.0, TAU, 24, color, 2.2)
		draw_circle(point, 2.7, color)
		if str(objective["key"]) == followed_objective:
			draw_arc(point, 10.5, 0.0, TAU, 24, Color.WHITE, 1.2)
	# Title, legend and the hovered place.
	draw_string_outline(font, Vector2(30, 36), "THE ISLAND   %d places · %d visited   (J closes)" % [_sites.size(), int(client.you.get("discovered_count", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(30, 36), "THE ISLAND   %d places · %d visited   (J closes)" % [_sites.size(), int(client.you.get("discovered_count", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.98, 0.85, 0.45))
	var legend_y := 90.0
	for kind in KIND_COLORS:
		draw_rect(Rect2(Vector2(30, legend_y - 9.0), Vector2(10, 10)), KIND_COLORS[kind])
		draw_string(font, Vector2(46, legend_y), str(WorldPoi.KINDS[kind]["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.93, 1.0))
		legend_y += 20.0
	# Clickable list so nearby/overlapping map pins remain selectable.
	_objective_hitboxes.clear()
	var list_y: float = legend_y + 14.0
	draw_string_outline(font, Vector2(30, list_y), "EXPEDITION ATLAS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color.BLACK)
	draw_string(font, Vector2(30, list_y), "EXPEDITION ATLAS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.94, 0.91, 0.77))
	list_y += 12.0
	for objective in objectives:
		var row_rect := Rect2(Vector2(26.0, list_y), Vector2(274.0, 26.0))
		var chosen: bool = str(objective["key"]) == followed_objective
		draw_rect(row_rect, Color(0.16, 0.20, 0.24, 0.95) if chosen else Color(0.05, 0.08, 0.11, 0.88))
		draw_rect(Rect2(row_rect.position + Vector2(5.0, 7.0), Vector2(11.0, 11.0)),
			objective_color(str(objective["key"])))
		draw_string(font, row_rect.position + Vector2(21.0, 18.0),
			str(objective["label"]), HORIZONTAL_ALIGNMENT_LEFT, 245, 12,
			Color.WHITE if chosen else Color(0.88, 0.91, 0.94))
		_objective_hitboxes.append({"rect": row_rect, "key": str(objective["key"])})
		list_y += 28.0
	if objectives.is_empty():
		draw_string(font, Vector2(30.0, list_y + 17.0),
			"No active expedition goals", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.70, 0.77, 0.80))
	var hint := "Click atlas goal: track   Left: waypoint   Shift+Left: party ping   Right: clear"
	if waypoint.is_finite() and client.you.has("x") and client.you.has("z"):
		var from_here := Vector2(float(client.you["x"]), float(client.you["z"]))
		var distance := TravelNavigation.distance_meters(from_here, waypoint)
		var bearing := TravelNavigation.compass(from_here, waypoint)
		hint = "WAYPOINT: %d m %s   (Shift+Left: party ping; right: clear)" % [
			distance, bearing]
		if not followed_objective.is_empty():
			var tracked: Dictionary = ExpeditionAtlas.find(objectives, followed_objective)
			if not tracked.is_empty():
				hint = "TRACKING %s: %d m %s   (Right: clear)" % [
					str(tracked["label"]), distance, bearing]
	draw_string_outline(font, Vector2(30, view.y - 25), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
	draw_string(font, Vector2(30, view.y - 25), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4))
	if _next_row < PIXELS:
		draw_string(font, Vector2(30, legend_y + 10.0), "drawing the map %d%%" % int(100.0 * float(_next_row) / float(PIXELS)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	if not _hover.is_empty():
		var distance: float = Vector2(float(_hover["x"]) - float(client.you.get("x", 0.0)), float(_hover["z"]) - float(client.you.get("z", 0.0))).length()
		var lines: Array = [str(_hover["display"]), "%s zone   %s%s   %s" % [
			str(Defs.ZONE_NAMES[int(_hover["zone"])]).capitalize(),
			"workbench and trader   " if bool(_hover["station"]) else "",
			"%d m away" % int(distance),
			"VISITED" if visited.has(int(_hover["id"])) else "UNEXPLORED"]]
		var market: Dictionary = RegionalTrade.offer_for_site(_hover)
		var box := Rect2(mouse + Vector2(16, 12), Vector2(295, 64 if not market.is_empty() else 46))
		draw_rect(box, Color(0.04, 0.05, 0.08, 0.95))
		draw_rect(box, Color(0.95, 0.78, 0.35, 0.8), false, 1.5)
		draw_string(font, box.position + Vector2(10, 19), lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		draw_string(font, box.position + Vector2(10, 38), lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.95))
		if not market.is_empty():
			draw_string(font, box.position + Vector2(10, 55),
				"Trade demand: %s +%d%%" % [str(market["category"]).capitalize(),
					int(market["premium_percent"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(1.0, 0.9, 0.5))
