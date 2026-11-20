extends Control
## The whole island on one screen (J): terrain painted from the seed, the danger rings, every settlement, camp, fort and ruin,
## the siege outposts and you. Hover a place to read its name. The picture is made a few rows per frame the first time.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")

const PIXELS := 256
const SPAN := WorldGen.WORLD_RADIUS * 2.0 + 200.0
const KIND_COLORS := {
	"village": Color(1.0, 0.85, 0.3), "farm": Color(0.8, 0.9, 0.35), "camp": Color(0.95, 0.65, 0.35), "depot": Color(0.7, 0.75, 0.85),
	"outpost": Color(0.4, 0.8, 1.0), "tower": Color(0.85, 0.85, 0.9), "mine": Color(0.75, 0.55, 0.4), "city": Color(0.95, 0.4, 0.4),
	"bunker": Color(0.75, 0.4, 0.95), "lighthouse": Color(1.0, 1.0, 0.7), "dock": Color(0.5, 0.75, 0.95),
}
const ZONE_COLORS := [Color(0.35, 0.85, 0.45, 0.5), Color(0.95, 0.82, 0.3, 0.5), Color(0.95, 0.45, 0.3, 0.5)]

var client
var _image: Image
var _texture: ImageTexture
var _next_row := 0
var _sites: Array = []
var _hover := {}
var _panel_rect := Rect2()


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


func _process(_delta: float) -> void:
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
	# Title, legend and the hovered place.
	draw_string_outline(font, Vector2(30, 36), "THE ISLAND   %d places · %d visited   (J closes)" % [_sites.size(), int(client.you.get("discovered_count", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(30, 36), "THE ISLAND   %d places · %d visited   (J closes)" % [_sites.size(), int(client.you.get("discovered_count", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.98, 0.85, 0.45))
	var legend_y := 90.0
	for kind in KIND_COLORS:
		draw_rect(Rect2(Vector2(30, legend_y - 9.0), Vector2(10, 10)), KIND_COLORS[kind])
		draw_string(font, Vector2(46, legend_y), str(WorldPoi.KINDS[kind]["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.93, 1.0))
		legend_y += 20.0
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
