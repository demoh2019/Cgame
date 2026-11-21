extends Control
## The whole island on one screen (J), drawn like an old surveyor's chart: muted parchment colours, hillshade lit from the
## north-west, contour lines, an inked coast with shallow water and ripple lines, paper grain and a vignette. Settlements and
## sites are badges with a silhouette glyph; names are placed greedily so they never overlap, with a paper-coloured halo.
## Dashed danger rings, cased roads, a compass rose, a scale bar and a pulsing player arrow. The wheel zooms toward the
## cursor, dragging pans, Space centres on you. A click sets a private waypoint (Shift+click pings the party, right click
## clears it), and the expedition atlas lists this player's goals: clicking one follows it, even as it moves. The picture is charted a few rows per frame the first time it opens.
## Techniques: ArcGIS hillshade (zenith 45°, azimuth 315°), cartographic label hierarchy (Axis Maps, Ordnance Survey),
## greedy candidate-position label placement.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")
const GrassField = preload("res://scripts/client/grass_field.gd")
const GradientBatch = preload("res://scripts/client/gradient_batch.gd")
const ImageBatch = preload("res://scripts/client/image_batch.gd")
const MaskDistanceField = preload("res://scripts/client/mask_distance_field.gd")
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")
const ExpeditionAtlas = preload("res://scripts/shared/expedition_atlas.gd")

signal personal_waypoint_changed(point: Vector2)

const PIXELS := 384
const SPAN := WorldGen.WORLD_RADIUS * 2.0 + 200.0
const ZOOMS := [1.0, 1.6, 2.6, 4.0]
const SAMPLE_ROWS_PER_FRAME := 8
const PAINT_ROWS_PER_FRAME := 48

# Parchment palette.
const PAPER := Color("#eadcc0")
const PAPER_DARK := Color("#d9cba8")
const INK := Color("#2b2418")
const INK_SOFT := Color("#3b3428")
const BIOME_COLORS := [Color("#d8c9a0"), Color("#6e7f4e"), Color("#9ca36b"), Color("#7d8459"), Color("#8e8576")]
const STEPPE := Color("#c2b07a")
const SNOW := Color("#e8e4d8")
const WATER_DEEP := Color("#3f5e6e")
const WATER_SHALLOW := Color("#6e909a")
const RIPPLE := Color("#dce6e0")
const ROAD_FILL := Color("#e3d3ae")
const BIOME_IDS := {"beach": 0, "forest": 1, "plains": 2, "swamp": 3, "mountain": 4}
const CONTOUR_STEP := 20.0
const KIND_COLORS := {
	"village": Color("#e2b54c"), "farm": Color("#b9c46a"), "camp": Color("#d98f4e"), "depot": Color("#a8b0bd"),
	"outpost": Color("#6fa8c8"), "tower": Color("#c9c4b4"), "mine": Color("#a8805e"), "city": Color("#c4584a"),
	"bunker": Color("#9a6ab8"), "lighthouse": Color("#efe3a0"), "dock": Color("#7fa3c4"), "landmark": Color("#7cc4a8"),
}
const RING_COLORS := [Color("#d9b44a"), Color("#d98a3a"), Color("#c0503a")]
const RING_NAMES := ["SAFE LANDS", "BORDERLANDS", "WILDS"]

var client
## Assigned by online_main after the native streamer exists. Optional on
## stock Godot/older Cgame binaries, so map markers remain fully usable.
var world_streamer: WorldStreamer
var _image: Image
var _water_gradient: Gradient
var _texture: ImageTexture
var _heights := PackedFloat32Array()
var _biomes := PackedByteArray()
var _lush := PackedFloat32Array()
var _shore_distances := PackedByteArray()
var _sampled_rows := 0
var _painted_rows := 0
var _sites: Array = []
var _hover := {}
var _frame := Rect2()
var _zoom_index := 0
var _zoom := 1.0
var _center := Vector2.ZERO
var _dragging := false
var _pulse := 0.0
var _place_font: Font
var _title_font: Font
var waypoint: Vector2 = Vector2(INF, INF)
var followed_objective: String = "" # Empty means manually placed private pin.
var _objective_hitboxes: Array[Dictionary] = []
var _press_at := Vector2(INF, INF) # Where the left button went down, to tell a click from a drag.


func setup(p_client) -> void:
	client = p_client
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_water_gradient = GradientBatch.make_gradient(WATER_SHALLOW, WATER_DEEP)
	_image = Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	_image.fill(PAPER_DARK)
	_texture = ImageTexture.create_from_image(_image)
	_heights.resize(PIXELS * PIXELS)
	_biomes.resize(PIXELS * PIXELS)
	_lush.resize(PIXELS * PIXELS)
	_shore_distances = PackedByteArray()
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Palatino", "Book Antiqua", "Times New Roman", "Liberation Serif", "serif"])
	serif.font_weight = 600
	_place_font = serif
	var title := SystemFont.new()
	title.font_names = serif.font_names
	title.font_weight = 700
	_title_font = title


func toggle() -> void:
	visible = not visible
	if visible:
		if _sites.is_empty():
			for rx in range(-14, 14):
				for rz in range(-14, 14):
					_sites.append_array(client.world.poi.sites_in_region(rx, rz))
		_zoom_index = 0
		_zoom = 1.0
		_center = Vector2.ZERO
		grab_focus()


# --- Waypoints and the expedition atlas (private to this client: no RPC, no location leak) ----------------------

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


## A short left click (not a drag) on the chart: a goal marker follows that goal, anywhere else sets a waypoint, and with
## Shift it pings the party instead (coordinates and party access are validated by the server).
func _click(position: Vector2, shift: bool) -> void:
	if not shift:
		for row in _objective_hitboxes:
			if (row["rect"] as Rect2).has_point(position):
				select_objective(str(row["key"]))
				return
	if not _frame.has_point(position):
		return
	if not shift:
		for objective in current_objectives():
			if _to_screen(float(objective["x"]), float(objective["z"])).distance_squared_to(position) <= 12.0 * 12.0:
				select_objective(str(objective["key"]))
				return
	var destination: Vector2 = _to_world(position)
	if not TravelNavigation.valid_destination(destination, WorldGen.WORLD_RADIUS):
		return
	if shift:
		if client != null:
			client.party_ping(destination)
	else:
		set_waypoint(destination)


# --- Charting the island --------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	# A moving raid target keeps its radar route updated with the atlas CLOSED.
	_sync_followed_objective()
	if not visible:
		return
	_pulse = fmod(_pulse + delta / 1.2, 1.0)
	_zoom = lerpf(_zoom, float(ZOOMS[_zoom_index]), 1.0 - exp(-12.0 * delta))
	_clamp_center()
	var world = client.world
	var step: float = SPAN / float(PIXELS)
	var rows := SAMPLE_ROWS_PER_FRAME
	while rows > 0 and _sampled_rows < PIXELS:
		var row := _sampled_rows
		var row_points := PackedVector2Array()
		var row_heights := PackedFloat64Array()
		row_points.resize(PIXELS)
		row_heights.resize(PIXELS)
		for column in PIXELS:
			var x: float = -SPAN * 0.5 + (float(column) + 0.5) * step
			var z: float = -SPAN * 0.5 + (float(row) + 0.5) * step
			var index := row * PIXELS + column
			var height: float = world.height_at(x, z)
			row_points[column] = Vector2(x, z)
			row_heights[column] = height
			_heights[index] = height
			_lush[index] = GrassField.lushness(x, z)
		var row_biomes: PackedStringArray = world.biomes_at_points(row_points, row_heights)
		for column in PIXELS:
			_biomes[row * PIXELS + column] = int(BIOME_IDS.get(row_biomes[column], 2))
		_sampled_rows += 1
		rows -= 1
	if _sampled_rows == PIXELS and _painted_rows < PIXELS:
		# Compute the entire eight-connected coast distance field once, after
		# the last height sample but before drawing the first chart row.
		if _shore_distances.is_empty():
			_shore_distances = MaskDistanceField.from_heights(
					_heights, Vector2i(PIXELS, PIXELS), Defs.WATER_LEVEL - 0.4, 7)
		var painted := 0
		while painted < PAINT_ROWS_PER_FRAME and _painted_rows < PIXELS:
			_paint_row(_painted_rows)
			_painted_rows += 1
			painted += 1
		_texture.update(_image)
	queue_redraw()


func _h(x: int, y: int) -> float:
	return _heights[clampi(y, 0, PIXELS - 1) * PIXELS + clampi(x, 0, PIXELS - 1)]


func _is_water(x: int, y: int) -> bool:
	return _h(x, y) < Defs.WATER_LEVEL - 0.4


## Nearest coastline in eight-connected raster pixels (Chebyshev metric).
## 255 means no land within the seven-pixel coastline search radius.
func _shore_distance(x: int, y: int) -> int:
	if _shore_distances.size() != PIXELS * PIXELS:
		return 255
	return _shore_distances[clampi(y, 0, PIXELS - 1) * PIXELS + clampi(x, 0, PIXELS - 1)]


func _paint_row(row: int) -> void:
	var cell: float = SPAN / float(PIXELS)
	var zenith := deg_to_rad(45.0)
	var azimuth := deg_to_rad(135.0) # 315° compass (north-west) in maths angles.
	# Compute coast/depth samples once, then evaluate the entire water-color ramp
	# in one native call instead of per-pixel script/native calls.
	var water_offsets := PackedFloat32Array()
	var water_shores := PackedInt32Array()
	water_shores.resize(PIXELS)
	for column in PIXELS:
		var water_height: float = _h(column, row)
		if water_height < Defs.WATER_LEVEL - 0.4:
			var shore: int = _shore_distance(column, row)
			var depth: float = clampf(-water_height / 40.0, 0.0, 1.0)
			water_shores[column] = shore
			water_offsets.append(clampf(maxf(depth, float(shore) / 7.0), 0.0, 1.0))
	var water_colors := PackedColorArray()
	if not water_offsets.is_empty():
		water_colors = GradientBatch.sample_many(_water_gradient, water_offsets)
	var water_index := 0
	var row_colors := PackedColorArray()
	row_colors.resize(PIXELS)
	for column in PIXELS:
		var h: float = _h(column, row)
		var color: Color
		if h < Defs.WATER_LEVEL - 0.4:
			var shore: int = water_shores[column]
			color = water_colors[water_index]
			water_index += 1
			if shore == 3:
				color = color.lerp(RIPPLE, 0.35)
			elif shore == 6:
				color = color.lerp(RIPPLE, 0.2)
		else:
			var biome: int = _biomes[row * PIXELS + column]
			color = BIOME_COLORS[biome]
			if biome == 2:
				color = color.lerp(STEPPE, clampf(0.75 - _lush[row * PIXELS + column] * 1.1, 0.0, 0.8))
			if h > 90.0:
				color = color.lerp(SNOW, clampf((h - 90.0) / 30.0, 0.0, 1.0))
			# Hillshade (Horn-style central differences), exaggerated ×3 so hills read on a small map.
			var dzdx: float = (_h(column + 1, row) - _h(column - 1, row)) / (2.0 * cell)
			var dzdy: float = (_h(column, row + 1) - _h(column, row - 1)) / (2.0 * cell)
			var slope: float = atan(3.0 * sqrt(dzdx * dzdx + dzdy * dzdy))
			var aspect: float = atan2(dzdy, -dzdx)
			var shade: float = maxf(cos(zenith) * cos(slope) + sin(zenith) * sin(slope) * cos(azimuth - aspect), 0.0)
			color = color.lerp(color * lerpf(0.55, 1.15, shade), 0.65)
			# Contour lines every 20 m, a stronger index contour every 100 m.
			var band: int = floori(h / CONTOUR_STEP)
			if band != floori(_h(column + 1, row) / CONTOUR_STEP) or band != floori(_h(column, row + 1) / CONTOUR_STEP):
				color = color.lerp(INK_SOFT, 0.3 if posmod(band, 5) == 0 else 0.15)
			# Inked coastline.
			if _is_water(column + 1, row) or _is_water(column - 1, row) or _is_water(column, row + 1) or _is_water(column, row - 1):
				color = color.lerp(INK_SOFT, 0.8)
		# Paper: a little desaturated, toned toward parchment, with grain.
		var grey: float = color.get_luminance()
		color = Color(grey, grey, grey).lerp(color, 0.82)
		color = color.lerp(color * PAPER, 0.25)
		var grain: float = float(WorldGen.mix(column, row, 5, 9) % 1000) / 1000.0
		color = color * (0.96 + grain * 0.08)
		row_colors[column] = color
	ImageBatch.set_row(_image, row, row_colors)


# --- View -----------------------------------------------------------------------------------------------------------

func _scale() -> float:
	return _frame.size.x / (SPAN / _zoom)


func _to_screen(x: float, z: float) -> Vector2:
	return _frame.get_center() + (Vector2(x, z) - _center) * _scale()


func _to_world(point: Vector2) -> Vector2:
	return _center + (point - _frame.get_center()) / _scale()


func _clamp_center() -> void:
	var half: float = SPAN / _zoom * 0.5
	_center.x = clampf(_center.x, -SPAN * 0.5 + half, SPAN * 0.5 - half)
	_center.y = clampf(_center.y, -SPAN * 0.5 + half, SPAN * 0.5 - half)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var anchor: Vector2 = _to_world(button.position)
			_zoom_index = clampi(_zoom_index + (1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, ZOOMS.size() - 1)
			_zoom = float(ZOOMS[_zoom_index])
			# Zoom toward the cursor: keep the point under it in place.
			_center = anchor - (button.position - _frame.get_center()) / _scale()
			_clamp_center()
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			# Press and drag pans; a press released where it began is a click.
			if button.pressed:
				_press_at = button.position
				_dragging = true
			else:
				_dragging = false
				if _press_at.is_finite() and _press_at.distance_to(button.position) < 5.0:
					_click(button.position, button.shift_pressed)
				_press_at = Vector2(INF, INF)
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			clear_waypoint()
			accept_event()
	elif event is InputEventMouseMotion and _dragging and _press_at.distance_to((event as InputEventMouseMotion).position) >= 5.0:
		_center -= (event as InputEventMouseMotion).relative / _scale()
		_clamp_center()
		accept_event()
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_SPACE:
		if client.you.has("x"):
			_center = Vector2(float(client.you["x"]), float(client.you["z"]))
			_zoom_index = maxi(_zoom_index, 2)
			_zoom = float(ZOOMS[_zoom_index])
			_clamp_center()
		accept_event()


# --- Drawing --------------------------------------------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.07, 0.06, 0.05, 0.94))
	var side: float = minf(view.x - 300.0, view.y - 110.0)
	_frame = Rect2(Vector2(maxf(250.0, (view.x - side) * 0.5 + 60.0), 70.0), Vector2(side, side))
	var font: Font = ThemeDB.fallback_font
	# The visible part of the chart.
	var world_half: float = SPAN / _zoom * 0.5
	var pixel_rect := Rect2((_center - Vector2.ONE * world_half + Vector2.ONE * SPAN * 0.5) / SPAN * float(PIXELS), Vector2.ONE * world_half * 2.0 / SPAN * float(PIXELS))
	draw_texture_rect_region(_texture, _frame, pixel_rect)
	_draw_rings(font)
	_draw_roads()
	var visited: Dictionary = {}
	for discovered_id in client.you.get("discovered_site_ids", []):
		visited[int(discovered_id)] = true
	_draw_sites_and_labels(visited, font)
	var objectives: Array[Dictionary] = current_objectives()
	_draw_navigation(objectives, font)
	_draw_player()
	# Mask everything that spilled over the edge of the chart, then the frame, vignette and furniture.
	var dark := Color(0.07, 0.06, 0.05, 1.0)
	draw_rect(Rect2(0, 0, view.x, _frame.position.y), dark)
	draw_rect(Rect2(0, _frame.end.y, view.x, view.y - _frame.end.y), dark)
	draw_rect(Rect2(0, _frame.position.y, _frame.position.x, _frame.size.y), dark)
	draw_rect(Rect2(_frame.end.x, _frame.position.y, view.x - _frame.end.x, _frame.size.y), dark)
	_draw_vignette()
	draw_rect(_frame.grow(6.0), Color(0.79, 0.64, 0.36, 0.9), false, 2.0)
	draw_rect(_frame.grow(2.0), Color(0.16, 0.13, 0.09, 0.9), false, 1.0)
	_draw_compass(_frame.position + Vector2(_frame.size.x - 52.0, 52.0))
	_draw_scale_bar(Vector2(_frame.position.x + 18.0, _frame.end.y - 22.0), font)
	_draw_legend(visited, font)
	_draw_atlas(objectives, font, view)
	if _painted_rows < PIXELS:
		var progress: float = (float(_sampled_rows) + float(_painted_rows)) / float(PIXELS * 2)
		_halo_text(font, _frame.get_center() + Vector2(-90, 0), "Charting the island... %d%%" % int(progress * 100.0), 16, INK, PAPER)
	if not _hover.is_empty():
		_draw_tooltip(visited, font)


## The private waypoint with its line from you, the party ping, and this player's expedition goals.
func _draw_navigation(objectives: Array[Dictionary], font: Font) -> void:
	var requested: Dictionary = client.active_supply_beacon()
	if not requested.is_empty():
		var help_at: Vector2 = _to_screen(float(requested["x"]), float(requested["z"]))
		if _frame.has_point(help_at):
			# Amber circle for a temporary party-only aid request. Never a
			# public waypoint, objective, or permanent discovered location.
			draw_circle(help_at, 12.0, Color("#1e1a14"))
			draw_arc(help_at, 8.0, 0.0, TAU, 24, Color("#e49530"), 3.0, true)
			draw_circle(help_at, 3.0, Color("#e49530"))
			_halo_text(font, help_at + Vector2(14, 4),
				"Party needs %s (%ds)" % [
					str(requested["need"]).capitalize(),
					ceili(maxf(0.0, float(requested["expires"]) - client.server_time))],
				12, Color("#7f4a0c"), PAPER)
	if waypoint.is_finite():
		var pin: Vector2 = _to_screen(waypoint.x, waypoint.y)
		if client.you.has("x") and client.you.has("z"):
			var from: Vector2 = _to_screen(float(client.you["x"]), float(client.you["z"]))
			var length: float = from.distance_to(pin)
			var steps: int = int(length / 10.0)
			for i in steps:
				if i % 2 == 0:
					draw_line(from.lerp(pin, float(i) / float(steps)), from.lerp(pin, float(i + 1) / float(steps)), Color("#8a3a2a", 0.85), 2.0, true)
		# A red "X marks the spot" on the chart.
		draw_circle(pin, 10.0, Color(PAPER.r, PAPER.g, PAPER.b, 0.7))
		draw_line(pin + Vector2(-6, -6), pin + Vector2(6, 6), Color("#8a3a2a"), 3.0, true)
		draw_line(pin + Vector2(-6, 6), pin + Vector2(6, -6), Color("#8a3a2a"), 3.0, true)
		_halo_text(_place_font, pin + Vector2(12, 4), "Waypoint", 13, Color("#8a3a2a"), PAPER)
	var squad_ping: Dictionary = client.you.get("party", {}).get("ping", {})
	if not squad_ping.is_empty():
		var target := Vector2(float(squad_ping.get("x", INF)), float(squad_ping.get("z", INF)))
		if TravelNavigation.valid_destination(target, WorldGen.WORLD_RADIUS):
			var marker: Vector2 = _to_screen(target.x, target.y)
			# A shared mineral survey shows amber with the vein's material and tier; an ordinary ping is teal.
			var survey: bool = str(squad_ping.get("kind", "")) == "survey"
			var hue := Color(0.95, 0.65, 0.25) if survey else Color(0.15, 0.7, 0.68)
			draw_circle(marker, 11.0, Color("#1e1a14"))
			draw_colored_polygon(PackedVector2Array([marker + Vector2(0, -9), marker + Vector2(9, 0), marker + Vector2(0, 9), marker + Vector2(-9, 0)]), hue)
			var caption := "Party ping #%d  (%ds)" % [int(squad_ping.get("by", 0)), ceili(float(squad_ping.get("remaining", 0.0)))]
			if survey:
				caption = "Party T%d %s vein  (%ds)" % [int(squad_ping.get("tier", 2)), str(squad_ping.get("material", "ore")).capitalize(), ceili(float(squad_ping.get("remaining", 0.0)))]
			_halo_text(font, marker + Vector2(14, 4), caption, 12, Color("#6a3f0c") if survey else Color("#0f4f4c"), PAPER)
	for objective in objectives:
		var point: Vector2 = _to_screen(float(objective["x"]), float(objective["z"]))
		var color: Color = objective_color(str(objective["key"]))
		draw_circle(point, 9.5, Color("#1e1a14"))
		draw_arc(point, 7.0, 0.0, TAU, 24, color, 2.4, true)
		draw_circle(point, 2.8, color)
		if str(objective["key"]) == followed_objective:
			draw_arc(point, lerpf(11.0, 18.0, _pulse), 0.0, TAU, 24, Color(1, 1, 1, 0.8 * (1.0 - _pulse)), 1.6, true)


## The expedition atlas: this player's goals as clickable rows, and how far the waypoint is.
## World Partition-style source completion is read-only: do not request
## chunks from map draw or display distant pins as loaded.
static func waypoint_streaming_caption(p_streamer: WorldStreamer,
		p_waypoint: Vector2, p_player: Vector2) -> String:
	if p_streamer == null or not p_waypoint.is_finite() or not p_player.is_finite():
		return ""
	if not p_streamer.has_method("is_auxiliary_source_ready") or \
			not p_streamer.has_method("get_auxiliary_source_progress") or \
			not p_streamer.has_method("get_auxiliary_source_failed_count"):
		return ""
	if not p_streamer.has_auxiliary_source():
		return ""
	if p_player.distance_to(p_waypoint) > p_streamer.load_radius + p_streamer.cell_size:
		return ""
	var source: Vector3 = p_streamer.get_auxiliary_source_position()
	if Vector2(source.x, source.z).distance_to(p_waypoint) > 0.05:
		return "" # Stale source from the previous private waypoint.
	if p_streamer.get_auxiliary_source_failed_count() > 0:
		return "Scenery prefetch: retrying"
	if p_streamer.is_auxiliary_source_ready(true):
		return "Scenery prefetch: ready"
	return "Scenery prefetch: %d%%" % floori(
		clampf(p_streamer.get_auxiliary_source_progress(true), 0.0, 1.0) * 100.0)


func _draw_atlas(objectives: Array[Dictionary], font: Font, view: Vector2) -> void:
	_objective_hitboxes.clear()
	var top: float = 76.0 + 46.0 + float(KIND_COLORS.size()) * 24.0 + 92.0 + 16.0
	var rows: int = maxi(objectives.size(), 1)
	var panel := Rect2(Vector2(24, top), Vector2(200, 34.0 + float(rows) * 30.0))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#15130f", 0.9)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color("#6b5a3a")
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 8
	draw_style_box(style, panel)
	draw_string(font, Vector2(panel.position.x + 14, top + 22), "EXPEDITION ATLAS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9a45c"))
	var y: float = top + 32.0
	for objective in objectives:
		var row_rect := Rect2(Vector2(panel.position.x + 6, y), Vector2(panel.size.x - 12, 26.0))
		var chosen: bool = str(objective["key"]) == followed_objective
		var row := StyleBoxFlat.new()
		row.bg_color = Color("#3a2f1e", 0.95) if chosen else Color("#201c15", 0.9)
		row.set_corner_radius_all(4)
		if chosen:
			row.set_border_width_all(1)
			row.border_color = Color("#c9a45c")
		draw_style_box(row, row_rect)
		draw_circle(row_rect.position + Vector2(13.0, 13.0), 5.0, objective_color(str(objective["key"])))
		draw_string(font, row_rect.position + Vector2(25.0, 18.0), str(objective["label"]), HORIZONTAL_ALIGNMENT_LEFT, row_rect.size.x - 30.0, 12,
			Color.WHITE if chosen else Color(0.88, 0.86, 0.8))
		_objective_hitboxes.append({"rect": row_rect, "key": str(objective["key"])})
		y += 30.0
	if objectives.is_empty():
		draw_string(font, Vector2(panel.position.x + 14, y + 16.0), "No active expedition goals", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.68, 0.62))
	var hint := "Click: waypoint   Shift+click: party ping   Right click: clear   Click a goal: follow it"
	if waypoint.is_finite() and client.you.has("x") and client.you.has("z"):
		var from_here := Vector2(float(client.you["x"]), float(client.you["z"]))
		var distance := TravelNavigation.distance_meters(from_here, waypoint)
		var bearing := TravelNavigation.compass(from_here, waypoint)
		hint = "Waypoint: %d m %s   (Shift+click: party ping   Right click: clear)" % [distance, bearing]
		if not followed_objective.is_empty():
			var tracked: Dictionary = ExpeditionAtlas.find(objectives, followed_objective)
			if not tracked.is_empty():
				hint = "Following %s: %d m %s   (Right click: clear)" % [str(tracked["label"]), distance, bearing]
	var width: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_halo_text(font, Vector2(_frame.get_center().x - width * 0.5, view.y - 16.0), hint, 14, Color("#e8c46a"), Color(0.07, 0.06, 0.05), 4)
	if waypoint.is_finite() and client.you.has("x") and client.you.has("z"):
		var caption: String = waypoint_streaming_caption(world_streamer, waypoint,
			Vector2(float(client.you["x"]), float(client.you["z"])))
		if not caption.is_empty():
			var caption_width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_halo_text(font, Vector2(_frame.get_center().x - caption_width * 0.5, view.y - 38.0),
				caption, 12, Color("#9cd8cd"), Color(0.07, 0.06, 0.05), 3)


func _draw_vignette() -> void:
	var steps := 10
	for i in steps:
		var inset: float = float(i) * 3.0
		draw_rect(_frame.grow(-inset), Color(0.1, 0.07, 0.03, 0.05 * (1.0 - float(i) / float(steps))), false, 3.0)


func _halo_text(font: Font, position: Vector2, text: String, size: int, color: Color, halo: Color, halo_size: int = 4) -> void:
	draw_string_outline(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, halo_size, Color(halo.r, halo.g, halo.b, 0.85))
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_rings(font: Font) -> void:
	var center: Vector2 = _to_screen(0.0, 0.0)
	for i in Defs.ZONE_RADII.size():
		var radius: float = float(Defs.ZONE_RADII[i]) * _scale()
		var color: Color = RING_COLORS[i]
		# Dashed: 8 px dashes, 6 px gaps.
		var circumference: float = TAU * radius
		var dashes: int = maxi(12, int(circumference / 14.0))
		for d in dashes:
			var a0: float = float(d) / float(dashes) * TAU
			var a1: float = a0 + TAU / float(dashes) * (8.0 / 14.0)
			draw_arc(center, radius, a0, a1, 4, Color(color.r, color.g, color.b, 0.85), 2.0, true)
		var label_at: Vector2 = center + Vector2(0, -radius - 6.0)
		var width: float = font.get_string_size(RING_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_halo_text(font, label_at - Vector2(width * 0.5, 0), RING_NAMES[i], 11, color.darkened(0.45), PAPER, 3)


func _draw_roads() -> void:
	if client.world.roads == null:
		return
	for road in client.world.roads.all_roads():
		var points: PackedVector2Array = road["points"]
		var line := PackedVector2Array()
		for i in range(0, points.size(), 2):
			line.append(_to_screen(points[i].x, points[i].y))
		line.append(_to_screen(points[points.size() - 1].x, points[points.size() - 1].y))
		var width: float = clampf(1.2 * _zoom, 1.2, 3.0)
		draw_polyline(line, Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 0.55), width + 1.6, true)
		draw_polyline(line, ROAD_FILL, width, true)


## Badges first (they reserve their space), then names in priority order, each at the first free spot around its badge.
func _draw_sites_and_labels(visited: Dictionary, font: Font) -> void:
	var mouse: Vector2 = get_local_mouse_position()
	_hover = {}
	var best := 16.0
	var taken: Array[Rect2] = []
	var labels: Array = [] # [priority, site, spot, radius]
	var inside := _frame.grow(-4.0)
	for site in _sites:
		var spot: Vector2 = _to_screen(float(site["x"]), float(site["z"]))
		if not inside.has_point(spot):
			continue
		var kind: String = site["kind"]
		var major: bool = bool(site["station"]) or kind == "city"
		# Detail grows with zoom: from afar only settlements, forts and ruined cities are badges, the rest small dots.
		var radius: float = 9.5 if major else (3.2 if _zoom < 1.5 else (6.5 if _zoom < 2.5 else 8.0))
		var seen: bool = visited.has(int(site["id"]))
		if not major and _zoom < 1.5:
			var dot: Color = KIND_COLORS.get(kind, Color.WHITE)
			draw_circle(spot, radius + 1.0, Color("#1e1a14", 0.8))
			draw_circle(spot, radius, dot.lerp(PAPER_DARK, 0.0 if seen else 0.25))
		else:
			_draw_badge(spot, radius, kind, seen, major or _zoom >= 2.5)
		if major or _zoom >= 1.5:
			taken.append(Rect2(spot - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)) # Names may cover the small dots.
		var gap: float = spot.distance_to(mouse)
		if gap < best:
			best = gap
			_hover = site
		if major or _zoom >= 2.6:
			var distance_to_you: float = Vector2(float(site["x"]) - float(client.you.get("x", 0.0)), float(site["z"]) - float(client.you.get("z", 0.0))).length()
			labels.append([(0 if major else 1) * 100000.0 + (0.0 if seen else 50000.0) + distance_to_you, site, spot, radius])
	# The hub and the player keep their space too.
	var hub: Vector2 = _to_screen(0.0, 0.0)
	_draw_hub(hub)
	taken.append(Rect2(hub - Vector2.ONE * 12.0, Vector2.ONE * 24.0))
	labels.append([-1.0, {"name": "Haven", "kind": "hub"}, hub, 12.0])
	if client.you.has("x"):
		var me: Vector2 = _to_screen(float(client.you["x"]), float(client.you["z"]))
		taken.append(Rect2(me - Vector2.ONE * 12.0, Vector2.ONE * 24.0))
	labels.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for entry in labels:
		var site: Dictionary = entry[1]
		var spot: Vector2 = entry[2]
		var radius: float = entry[3]
		var tier: int = 0 if site["kind"] == "hub" else (1 if (site.has("station") and (bool(site["station"]) or site["kind"] == "city")) else 2)
		var size: int = [18, 13 if _zoom < 1.5 else 15, 12][tier]
		var text: String = str(site["name"])
		if tier == 0:
			text = text.to_upper()
		var text_size: Vector2 = _place_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var pad: float = radius + 4.0
		# East first, then the other seven directions.
		var candidates := [
			Vector2(pad, text_size.y * 0.3), Vector2(pad * 0.8, -pad * 0.6), Vector2(pad * 0.8, pad + text_size.y * 0.5),
			Vector2(-pad - text_size.x, text_size.y * 0.3), Vector2(-text_size.x * 0.5, -pad - 2.0),
			Vector2(-text_size.x * 0.5, pad + text_size.y * 0.8), Vector2(-pad * 0.8 - text_size.x, -pad * 0.6),
			Vector2(-pad * 0.8 - text_size.x, pad + text_size.y * 0.5)]
		for offset in candidates:
			var baseline: Vector2 = spot + offset
			var box := Rect2(baseline - Vector2(0, text_size.y * 0.78), text_size).grow(2.0)
			if not inside.encloses(box):
				continue
			var free := true
			for other in taken:
				if other.intersects(box):
					free = false
					break
			if free:
				taken.append(box)
				var ink: Color = INK if tier > 0 else Color("#5a3d12")
				draw_string_outline(_place_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(PAPER.r, PAPER.g, PAPER.b, 0.85))
				draw_string(_place_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
				break
	# Siege outposts.
	for post in client.outposts:
		var flag: Vector2 = _to_screen(float(post["x"]), float(post["z"]))
		draw_line(flag, flag + Vector2(0, -12), INK, 2.0)
		draw_colored_polygon(PackedVector2Array([flag + Vector2(0, -12), flag + Vector2(10, -8), flag + Vector2(0, -4)]), Color("#c0503a"))


func _draw_badge(spot: Vector2, radius: float, kind: String, seen: bool, with_glyph: bool) -> void:
	var color: Color = KIND_COLORS.get(kind, Color.WHITE)
	if not seen:
		color = color.lerp(PAPER_DARK, 0.35)
	draw_circle(spot + Vector2(1.0, 1.5), radius + 1.5, Color(0, 0, 0, 0.4))
	draw_circle(spot, radius + 1.5, Color("#1e1a14"))
	draw_circle(spot, radius, color)
	if seen:
		draw_arc(spot, radius + 3.5, 0.0, TAU, 20, Color("#f4d77a"), 1.6, true)
	if with_glyph:
		_glyph(kind, spot, radius * 0.62, Color("#1e1a14"))


## One silhouette per kind, so places tell apart by shape as well as colour.
func _glyph(kind: String, c: Vector2, s: float, ink: Color) -> void:
	match kind:
		"village":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(0, -s), c + Vector2(s, 0)]), ink)
			draw_rect(Rect2(c + Vector2(-s * 0.7, 0), Vector2(s * 1.4, s * 0.85)), ink)
		"farm":
			for i in 3:
				var y: float = -s * 0.6 + float(i) * s * 0.6
				draw_line(c + Vector2(-s * 0.85, y), c + Vector2(s * 0.85, y), ink, 1.6)
		"camp":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s, s * 0.8), c + Vector2(0, -s), c + Vector2(s, s * 0.8)]), ink)
		"depot":
			draw_rect(Rect2(c - Vector2.ONE * s * 0.8, Vector2.ONE * s * 1.6), ink, false, 1.6)
			draw_line(c - Vector2.ONE * s * 0.8, c + Vector2.ONE * s * 0.8, ink, 1.4)
		"outpost":
			draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.3), Vector2(s * 1.8, s * 1.1)), ink)
			for i in 3:
				draw_rect(Rect2(c + Vector2(-s * 0.9 + float(i) * s * 0.7, -s * 0.8), Vector2(s * 0.4, s * 0.5)), ink)
		"tower":
			draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.5), Vector2(s * 0.6, s * 1.4)), ink)
			draw_rect(Rect2(c + Vector2(-s * 0.6, -s), Vector2(s * 1.2, s * 0.5)), ink)
		"mine":
			draw_line(c + Vector2(-s * 0.8, s * 0.8), c + Vector2(s * 0.5, -s * 0.5), ink, 2.0)
			draw_arc(c + Vector2(s * 0.2, -s * 0.2), s * 0.8, -PI * 0.95, -PI * 0.05, 8, ink, 1.8)
		"city":
			draw_rect(Rect2(c + Vector2(-s * 0.85, -s * 0.2), Vector2(s * 0.5, s * 1.1)), ink)
			draw_rect(Rect2(c + Vector2(s * 0.25, -s * 0.85), Vector2(s * 0.5, s * 1.75)), ink)
			draw_line(c + Vector2(-s, s * 0.9), c + Vector2(s, s * 0.9), ink, 1.6)
		"bunker":
			draw_arc(c + Vector2(0, s * 0.5), s * 0.9, PI, TAU, 10, ink, 2.0)
			draw_line(c + Vector2(-s, s * 0.5), c + Vector2(s, s * 0.5), ink, 2.0)
			draw_line(c + Vector2(-s * 0.35, 0), c + Vector2(s * 0.35, 0), ink, 1.6)
		"lighthouse":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, s), c + Vector2(-s * 0.25, -s * 0.5), c + Vector2(s * 0.25, -s * 0.5), c + Vector2(s * 0.5, s)]), ink)
			draw_circle(c + Vector2(0, -s * 0.8), s * 0.3, ink)
		"dock":
			draw_line(c + Vector2(0, -s), c + Vector2(0, s * 0.8), ink, 1.8)
			draw_line(c + Vector2(-s * 0.5, -s * 0.45), c + Vector2(s * 0.5, -s * 0.45), ink, 1.6)
			draw_arc(c + Vector2(0, s * 0.1), s * 0.75, 0.15, PI - 0.15, 8, ink, 1.8)
		"landmark":
			var points := PackedVector2Array()
			for i in 8:
				var r: float = s if i % 2 == 0 else s * 0.4
				points.append(c + Vector2.from_angle(float(i) * PI / 4.0 - PI * 0.5) * r)
			draw_colored_polygon(points, ink)
		_:
			draw_circle(c, s * 0.4, ink)


func _draw_hub(spot: Vector2) -> void:
	draw_circle(spot + Vector2(1.0, 1.5), 13.0, Color(0, 0, 0, 0.4))
	draw_circle(spot, 13.0, Color("#1e1a14"))
	draw_circle(spot, 11.0, Color("#f0c55a"))
	var points := PackedVector2Array()
	for i in 10:
		var r: float = 7.5 if i % 2 == 0 else 3.2
		points.append(spot + Vector2.from_angle(float(i) * PI / 5.0 - PI * 0.5) * r)
	draw_colored_polygon(points, Color("#1e1a14"))


func _draw_player() -> void:
	if not client.you.has("x"):
		return
	var me: Vector2 = _to_screen(float(client.you["x"]), float(client.you["z"]))
	if not _frame.has_point(me):
		return
	# A slow pulse so you find yourself at a glance.
	draw_arc(me, lerpf(10.0, 22.0, _pulse), 0.0, TAU, 28, Color(1, 1, 1, 0.55 * (1.0 - _pulse)), 2.0, true)
	var heading: Vector2 = Vector2(sin(client.yaw), cos(client.yaw))
	var side_vec := Vector2(-heading.y, heading.x)
	var arrow := PackedVector2Array([me + heading * 11.0, me - heading * 7.0 + side_vec * 7.0, me - heading * 3.5, me - heading * 7.0 - side_vec * 7.0])
	var outline := PackedVector2Array()
	for point in arrow:
		outline.append(me + (point - me) * 1.3)
	draw_colored_polygon(outline, Color("#1e1a14"))
	draw_colored_polygon(arrow, Color.WHITE)


func _draw_compass(center: Vector2) -> void:
	draw_circle(center, 30.0, Color(PAPER.r, PAPER.g, PAPER.b, 0.55))
	draw_arc(center, 30.0, 0.0, TAU, 36, Color(INK.r, INK.g, INK.b, 0.6), 1.2, true)
	for i in 4:
		var direction := Vector2.from_angle(float(i) * PI * 0.5 - PI * 0.5)
		var side := Vector2(-direction.y, direction.x)
		var length: float = 24.0 if i == 0 else 17.0
		var fill: Color = Color("#8a3a2a") if i == 0 else Color(INK.r, INK.g, INK.b, 0.75)
		draw_colored_polygon(PackedVector2Array([center + direction * length, center + side * 4.0, center - side * 4.0]), fill)
	draw_circle(center, 2.5, INK)
	_halo_text(_title_font, center + Vector2(-6, -34), "N", 15, Color("#8a3a2a"), PAPER, 3)


func _draw_scale_bar(origin: Vector2, font: Font) -> void:
	# A round number of metres about 120 px long.
	var metres_per_px: float = 1.0 / _scale()
	var target: float = 120.0 * metres_per_px
	var nice := 50.0
	for candidate in [50.0, 100.0, 200.0, 250.0, 500.0, 1000.0, 2000.0]:
		if candidate <= target:
			nice = candidate
	var length: float = nice / metres_per_px
	draw_rect(Rect2(origin + Vector2(-6, -18), Vector2(length + 12, 30)), Color(PAPER.r, PAPER.g, PAPER.b, 0.6))
	for i in 4:
		var segment := Rect2(origin + Vector2(length * float(i) / 4.0, 0), Vector2(length / 4.0, 5))
		draw_rect(segment, INK if i % 2 == 0 else PAPER)
	draw_rect(Rect2(origin, Vector2(length, 5)), INK, false, 1.0)
	var caption: String = ("%d km" % int(nice / 1000.0)) if nice >= 1000.0 else ("%d m" % int(nice))
	draw_string(font, origin + Vector2(0, -5), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	draw_string(font, origin + Vector2(length - 16.0, -5), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)


func _draw_legend(visited: Dictionary, font: Font) -> void:
	var panel := Rect2(Vector2(24, 76), Vector2(200, 46 + KIND_COLORS.size() * 24 + 92))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#15130f", 0.9)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color("#6b5a3a")
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 8
	draw_style_box(style, panel)
	draw_string(_title_font, Vector2(24, 44), "THE ISLAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#c9a45c"))
	draw_string(font, Vector2(26, 62), "%d places  ·  %d visited" % [_sites.size(), visited.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.78, 0.72))
	var y: float = panel.position.y + 28.0
	draw_string(font, Vector2(panel.position.x + 14, y - 6), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9a45c"))
	y += 12.0
	for kind in KIND_COLORS:
		_draw_badge(Vector2(panel.position.x + 24, y), 8.0, kind, true, true)
		draw_string(font, Vector2(panel.position.x + 42, y + 5), str(WorldPoi.KINDS[kind]["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.88, 0.82))
		y += 24.0
	y += 8.0
	for line in ["Wheel  zoom", "Drag  pan", "Space  find yourself", "J  close"]:
		var parts: PackedStringArray = line.split("  ")
		draw_string(font, Vector2(panel.position.x + 14, y), parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9a45c"))
		draw_string(font, Vector2(panel.position.x + 70, y), parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.76, 0.7))
		y += 19.0


func _draw_tooltip(visited: Dictionary, font: Font) -> void:
	var mouse: Vector2 = get_local_mouse_position()
	var distance: float = Vector2(float(_hover["x"]) - float(client.you.get("x", 0.0)), float(_hover["z"]) - float(client.you.get("z", 0.0))).length()
	var zone: int = int(_hover["zone"])
	var zone_colors := [Color("#5fbf6a"), Color("#d9b44a"), Color("#d9603a"), Color("#9a5ab8")]
	var market: Dictionary = RegionalTrade.offer_for_site(_hover)
	var height: float = 82.0 + (18.0 if not market.is_empty() else 0.0) + (18.0 if bool(_hover["station"]) else 0.0)
	var box := Rect2(mouse + Vector2(14, 12), Vector2(250, height))
	var view := get_viewport_rect().size
	if box.end.x > view.x - 8.0:
		box.position.x = mouse.x - 14.0 - box.size.x
	if box.end.y > view.y - 8.0:
		box.position.y = mouse.y - 12.0 - box.size.y
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#15130f", 0.95)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color("#c9a45c", 0.8)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 8
	draw_style_box(style, box)
	var x: float = box.position.x + 12.0
	var y: float = box.position.y + 24.0
	draw_string(_title_font, Vector2(x, y), str(_hover["display"]), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24.0, 16, Color.WHITE)
	y += 22.0
	var chip_text: String = str(Defs.ZONE_NAMES[zone]).to_upper() + " ZONE"
	var chip_width: float = font.get_string_size(chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(zone_colors[zone], 0.25)
	chip.border_color = zone_colors[zone]
	chip.set_border_width_all(1)
	chip.set_corner_radius_all(8)
	draw_style_box(chip, Rect2(Vector2(x, y - 12.0), Vector2(chip_width, 17.0)))
	draw_string(font, Vector2(x + 7.0, y + 1.0), chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, zone_colors[zone].lightened(0.3))
	var status: String = "visited" if visited.has(int(_hover["id"])) else "unexplored"
	draw_string(font, Vector2(x + chip_width + 8.0, y + 1.0), "%d m  ·  %s" % [int(distance), status], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.76))
	y += 22.0
	if bool(_hover["station"]):
		draw_string(font, Vector2(x, y), "Workbench and trader", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9a45c"))
		y += 18.0
	if not market.is_empty():
		draw_string(font, Vector2(x, y), "Trade demand: %s +%d%%" % [str(market["category"]).capitalize(), int(market["premium_percent"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.9, 0.5))
