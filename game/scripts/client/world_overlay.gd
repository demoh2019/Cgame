extends Control
## Things drawn over the 3D view at the place they belong: health bars over the infected (colour by kind, gold for elites,
## magenta for raid bosses, with STUN and PIN tags), damage numbers that pop up where a hit lands, and markers at the edge of
## the screen for the nearest places worth walking to (name, kind colour, distance; undiscovered ones marked with "?").
## It reads the client's state and the camera; it never changes the game.

const Defs = preload("res://scripts/shared/defs.gd")

const KIND_COLORS := {
	"village": Color(1.0, 0.85, 0.3), "farm": Color(0.8, 0.9, 0.35), "camp": Color(0.95, 0.65, 0.35), "depot": Color(0.7, 0.75, 0.85),
	"outpost": Color(0.4, 0.8, 1.0), "tower": Color(0.85, 0.85, 0.9), "mine": Color(0.75, 0.55, 0.4), "city": Color(0.95, 0.4, 0.4),
	"bunker": Color(0.75, 0.4, 0.95), "lighthouse": Color(1.0, 1.0, 0.7), "dock": Color(0.5, 0.75, 0.95), "landmark": Color(0.5, 1.0, 0.85),
}
const MARKER_RANGE := 650.0
const MARKER_COUNT := 3
const ZOMBIE_BAR_BUDGET := 32 # Cosmetic HUD only; never cull 3D characters or combat.

# One native significance planner shared across overlay refreshes, if supported.
static var _significance_planner: Object = null
static var _significance_checked: bool = false


## Pure bounded choice used by the actual zombie HUD. The native engine handles
## large crowds; stock Godot uses the same deterministic priority ordering.
static func select_zombie_bar_indices(distances: PackedFloat64Array,
		priorities: PackedByteArray, budget: int = ZOMBIE_BAR_BUDGET,
		allow_native: bool = true) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if distances.size() != priorities.size() or distances.size() > 16384 or budget < 0 or budget > 128:
		return empty
	for i in distances.size():
		if not is_finite(distances[i]) or distances[i] < 0.0 or priorities[i] > 3:
			return empty
	if allow_native:
		if not _significance_checked:
			_significance_checked = true
			if ClassDB.class_exists("SignificanceBudgetPlanner"):
				_significance_planner = ClassDB.instantiate("SignificanceBudgetPlanner")
		if _significance_planner != null and _significance_planner.has_method("select_top"):
			return _significance_planner.call("select_top", distances, priorities, budget)
	var order: Array[int] = []
	for i in distances.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if priorities[a] != priorities[b]:
			return priorities[a] > priorities[b]
		if distances[a] != distances[b]:
			return distances[a] < distances[b]
		return a < b
	)
	var indices := PackedInt32Array()
	for i in mini(order.size(), budget):
		indices.append(order[i])
	return indices


## Strict-priority HUD significance with temporal retention. A previous
## ordinary zombie can only displace another ordinary zombie, not a boss.
## The caller supplies stable server zombie IDs, not ephemeral array indices.
static func select_zombie_bar_indices_stable(distances: PackedFloat64Array,
		priorities: PackedByteArray, ids: PackedInt64Array,
		retained_ids: PackedInt64Array, budget: int = ZOMBIE_BAR_BUDGET,
		max_distance: float = 45.0, hysteresis: float = 1.5,
		allow_native: bool = true) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var count := distances.size()
	if count != priorities.size() or count != ids.size() or count > 16384 \
			or retained_ids.size() > 128 or budget < 0 or budget > 128 \
			or not is_finite(max_distance) or max_distance < 0.0 or max_distance > 1000000.0 \
			or not is_finite(hysteresis) or hysteresis < 0.0 or hysteresis > max_distance:
		return empty
	var known_ids: Dictionary = {}
	for i in count:
		if not is_finite(distances[i]) or distances[i] < 0.0 or priorities[i] > 3 \
				or ids[i] <= 0 or known_ids.has(ids[i]):
			return empty
		known_ids[ids[i]] = true
	var retained: Dictionary = {}
	for stable_id in retained_ids:
		if stable_id <= 0 or retained.has(stable_id):
			return empty
		retained[stable_id] = true
	if allow_native:
		if not _significance_checked:
			_significance_checked = true
			if ClassDB.class_exists("SignificanceBudgetPlanner"):
				_significance_planner = ClassDB.instantiate("SignificanceBudgetPlanner")
		if _significance_planner != null and _significance_planner.has_method("select_top_priority_stable"):
			return _significance_planner.call("select_top_priority_stable",
				distances, priorities, ids, retained_ids, budget, max_distance, hysteresis)
	var order: Array[int] = []
	for i in count:
		if distances[i] <= max_distance:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if priorities[a] != priorities[b]:
			return priorities[a] > priorities[b]
		var ad: float = maxf(0.0, distances[a] - (hysteresis if retained.has(ids[a]) else 0.0))
		var bd: float = maxf(0.0, distances[b] - (hysteresis if retained.has(ids[b]) else 0.0))
		if ad != bd:
			return ad < bd
		if distances[a] != distances[b]:
			return distances[a] < distances[b]
		if ids[a] != ids[b]:
			return ids[a] < ids[b]
		return a < b
	)
	var indices := PackedInt32Array()
	for i in mini(order.size(), budget):
		indices.append(order[i])
	return indices



## World-space variant of priority-stable significance for one or more observers.
## The custom engine finds the nearest viewer and ranks in a single native pass.
## Stock Godot follows identical stable-ID semantics without an engine dependency.
static func select_zombie_bar_world_stable(positions: PackedVector3Array,
		viewers: PackedVector3Array, priorities: PackedByteArray,
		ids: PackedInt64Array, retained_ids: PackedInt64Array,
		budget: int = ZOMBIE_BAR_BUDGET, max_distance: float = 45.0,
		hysteresis: float = 1.5, allow_native: bool = true) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if positions.size() != priorities.size() or positions.size() != ids.size() \
			or positions.size() > 16384 or viewers.is_empty() or viewers.size() > 16:
		return empty
	for viewer in viewers:
		if not viewer.is_finite():
			return empty
	for position in positions:
		if not position.is_finite():
			return empty
	if allow_native:
		if not _significance_checked:
			_significance_checked = true
			if ClassDB.class_exists("SignificanceBudgetPlanner"):
				_significance_planner = ClassDB.instantiate("SignificanceBudgetPlanner")
		if _significance_planner != null and _significance_planner.has_method("select_world_priority_stable"):
			return _significance_planner.call("select_world_priority_stable",
				positions, viewers, priorities, ids, retained_ids, budget,
				max_distance, hysteresis)
	var distances := PackedFloat64Array()
	for position in positions:
		var nearest := INF
		for viewer in viewers:
			nearest = minf(nearest, position.distance_to(viewer))
		if not is_finite(nearest):
			return empty
		distances.append(nearest)
	return select_zombie_bar_indices_stable(distances, priorities, ids, retained_ids,
		budget, max_distance, hysteresis, false)


var client
var camera: Camera3D
var _font: Font
var _floaters: Array = [] # {"pos": Vector3, "text": String, "color": Color, "age": float, "size": int}
var _markers: Array = []
var _marker_timer := 0.0
var _zombie_bar_retained_ids := PackedInt64Array() # Last rendered server IDs, not array indices.


func setup(p_client, p_camera: Camera3D) -> void:
	client = p_client
	camera = p_camera
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	client.event_received.connect(_on_event)


func _on_event(event: Dictionary) -> void:
	if str(event.get("type", "")) != "hit":
		return
	var amount: float = float(event.get("damage", 0.0))
	if amount <= 0.0:
		return
	var where := Vector3.INF
	var color := Color(1.0, 0.95, 0.6)
	var size := 22
	if str(event.get("kind", "")) == "zombie" and event.has("x"):
		where = Vector3(float(event["x"]), client.world.height_at(float(event["x"]), float(event["z"])) + 2.4, float(event["z"]))
		if int(event.get("by", client.peer_id)) == client.peer_id:
			size = 26 if amount >= 25.0 else 22
	elif int(event.get("id", -1)) == client.peer_id:
		where = client.display_position() + Vector3(0, 2.4, 0)
		color = Color(1.0, 0.35, 0.3)
	elif client.players.has(int(event.get("id", -1))):
		var other: Dictionary = client.players[int(event["id"])]
		where = Vector3(float(other["x"]), float(other["y"]) + 2.4, float(other["z"]))
		color = Color(1.0, 0.6, 0.3)
	if where == Vector3.INF:
		return
	where += Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	_floaters.append({"pos": where, "text": str(int(round(amount))), "color": color, "age": 0.0, "size": size})
	if _floaters.size() > 40:
		_floaters.pop_front()


func _process(delta: float) -> void:
	for floater in _floaters:
		floater["age"] = float(floater["age"]) + delta
	_floaters = _floaters.filter(func(f: Dictionary) -> bool: return float(f["age"]) < 1.1)
	_marker_timer -= delta
	if _marker_timer <= 0.0:
		_marker_timer = 0.5
		_update_markers()
	queue_redraw()


## The nearest places within range that the player is not standing in, closest first.
func _update_markers() -> void:
	_markers = []
	if client == null or not client.you.has("x") or client.world == null:
		return
	var here := Vector2(float(client.you["x"]), float(client.you["z"]))
	var known: Array = client.you.get("discovered_site_ids", [])
	var found: Array = []
	for site in client.world.poi.sites_near(here.x, here.y, MARKER_RANGE):
		var spot := Vector2(float(site["x"]), float(site["z"]))
		var distance: float = here.distance_to(spot)
		if distance < float(site["radius"]) or distance > MARKER_RANGE:
			continue
		found.append({"site": site, "distance": distance, "known": known.has(int(site["id"]))})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	_markers = found.slice(0, MARKER_COUNT)


func _draw() -> void:
	if client == null or camera == null or not client.you.has("x") or _font == null:
		return
	var view: Vector2 = get_viewport_rect().size
	_draw_zombie_bars(view)
	_draw_markers(view)
	_draw_floaters()


func _text(position: Vector2, text: String, size: int, color: Color, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string_outline(_font, position, text, align, width, size, 5, Color(0, 0, 0, 0.85 * color.a))
	draw_string(_font, position, text, align, width, size, color)


func _draw_zombie_bars(view: Vector2) -> void:
	var here: Vector3 = client.display_position()
	var eligible: Array[Dictionary] = []
	var screen_points := PackedVector2Array()
	var positions := PackedVector3Array()
	var priorities := PackedByteArray()
	var ids := PackedInt64Array()
	# The existing proximity and projected-screen checks run before budgeting:
	# offscreen infected never consume scarce HUD slots.
	for zombie_id in client.zombies:
		var zombie: Dictionary = client.zombies[zombie_id]
		var top := Vector3(float(zombie["x"]), float(zombie["y"]) + 2.7, float(zombie["z"]))
		if bool(zombie.get("raid_boss", false)):
			top.y += 2.2
		if not top.is_finite() or top.distance_squared_to(here) > 45.0 * 45.0 or camera.is_position_behind(top):
			continue
		var spot: Vector2 = camera.unproject_position(top)
		if spot.x < -40.0 or spot.y < -40.0 or spot.x > view.x + 40.0 or spot.y > view.y + 40.0:
			continue
		eligible.append(zombie)
		screen_points.append(spot)
		positions.append(top)
		ids.append(int(zombie_id))
		# Boss > elite > actual attacker > ordinary enemy. Critical combat
		# telegraphs still use their own independent animation budget.
		priorities.append(3 if bool(zombie.get("raid_boss", false)) else
			(2 if bool(zombie.get("elite", false)) else
			(1 if int(zombie.get("state", 0)) >= 3 else 0)))
	var chosen: PackedInt32Array = select_zombie_bar_world_stable(positions,
		PackedVector3Array([here]), priorities, ids, _zombie_bar_retained_ids)
	var current_ids := PackedInt64Array()
	for selected in chosen:
		current_ids.append(ids[selected])
	_zombie_bar_retained_ids = current_ids
	for selected in chosen:
		var zombie: Dictionary = eligible[selected]
		var spot: Vector2 = screen_points[selected]
		var maximum: float = maxf(float(zombie.get("max_hp", zombie.get("hp", 1.0))), 1.0)
		var fraction: float = clampf(float(zombie.get("hp", 0.0)) / maximum, 0.0, 1.0)
		var boss: bool = bool(zombie.get("raid_boss", false))
		var elite: bool = bool(zombie.get("elite", false))
		var width: float = 86.0 if boss else (58.0 if elite else 46.0)
		var height: float = 8.0 if boss else 6.0
		var rect := Rect2(spot - Vector2(width * 0.5, 0.0), Vector2(width, height))
		var fill := Color(0.86, 0.22, 0.2)
		if boss:
			fill = Color(0.92, 0.25, 0.68)
		elif elite:
			fill = Color(0.98, 0.66, 0.2)
		var alerted: bool = int(zombie.get("state", 0)) >= 2
		draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.75))
		draw_rect(rect, Color(0.18, 0.04, 0.04, 0.85))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * fraction, rect.size.y)), fill)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * fraction, rect.size.y * 0.4)), Color(1, 1, 1, 0.22))
		if alerted:
			draw_rect(rect.grow(2.5), Color(1.0, 0.3, 0.2, 0.9), false, 1.0)
		var tag := ""
		if float(zombie.get("stagger_seconds", 0.0)) > 0.0:
			tag = "STUN"
		elif float(zombie.get("snared_seconds", 0.0)) > 0.0:
			tag = "PIN"
		if float(zombie.get("sunder_seconds", 0.0)) > 0.0:
			tag = "SUNDER" if tag == "" else tag + "+SND"
		if bool(zombie.get("melee_blocked", false)):
			tag = "BLOCKED" if tag == "" else tag + "+BLK"
		var gait: String = str(zombie.get("wound_phase", ""))
		if gait == "limping":
			tag = "LIMP" if tag == "" else tag + "+LMP"
		elif gait == "frenzied":
			tag = "FRENZY" if tag == "" else tag + "+FRZ"
		if int(zombie.get("resolve_stacks", 0)) >= 2 and float(zombie.get("resolve_seconds", 0.0)) > 0.0:
			tag = "RESIST" if tag == "" else tag + "+RST"
		var title: String = ("RAID BOSS" if boss else ("ELITE " if elite else "")) + ("" if boss else str(zombie.get("type", "")).capitalize())
		if elite or boss or tag != "":
			_text(Vector2(spot.x - 80.0, rect.position.y - 4.0), title + ("  " + tag if tag != "" else ""), 11, fill.lightened(0.3), 160.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_markers(view: Vector2) -> void:
	var here3: Vector3 = client.display_position()
	var center: Vector2 = view * 0.5
	var margin := 46.0
	var bounds := Rect2(Vector2(margin, 110.0), view - Vector2(margin * 2.0, 110.0 + 120.0))
	for marker in _markers:
		var site: Dictionary = marker["site"]
		var target := Vector3(float(site["x"]), here3.y, float(site["z"]))
		var on_screen: Vector2 = camera.unproject_position(target)
		var direction: Vector2 = (on_screen - center)
		if camera.is_position_behind(target):
			direction = -direction
		if direction.length() < 1.0:
			continue
		direction = direction.normalized()
		# Where the line from the centre toward the place leaves the inner frame.
		var scale_x: float = (bounds.size.x * 0.5) / maxf(absf(direction.x), 0.0001)
		var scale_y: float = (bounds.size.y * 0.5) / maxf(absf(direction.y), 0.0001)
		var edge_point: Vector2 = bounds.get_center() + direction * minf(scale_x, scale_y)
		if bounds.has_point(on_screen) and not camera.is_position_behind(target):
			edge_point = on_screen # Already in view: mark the place itself.
		var color: Color = KIND_COLORS.get(site["kind"], Color.WHITE)
		var known: bool = bool(marker["known"])
		# Arrow head pointing at the place.
		var side := Vector2(-direction.y, direction.x)
		var tip: Vector2 = edge_point + direction * 14.0
		draw_colored_polygon(PackedVector2Array([tip, edge_point - side * 8.0, edge_point + side * 8.0]), Color(0, 0, 0, 0.55))
		draw_colored_polygon(PackedVector2Array([tip - direction * 2.0, edge_point - side * 6.0 + direction * 1.5, edge_point + side * 6.0 + direction * 1.5]), color)
		var label: String = str(site["display"]) if known else "? %s" % str(site.get("title", "Place"))
		var distance_text := "%d m" % int(marker["distance"])
		var label_width: float = maxf(_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, _font.get_string_size(distance_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x) + 18.0
		var box_pos: Vector2 = edge_point - direction * 26.0 - Vector2(label_width * 0.5, 17.0)
		box_pos.x = clampf(box_pos.x, 8.0, view.x - label_width - 8.0)
		box_pos.y = clampf(box_pos.y, 100.0, view.y - 150.0)
		var box := Rect2(box_pos, Vector2(label_width, 34.0))
		draw_rect(box, Color(0.04, 0.05, 0.08, 0.78))
		draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), color)
		_text(box.position + Vector2(10.0, 15.0), label, 13, Color(1, 1, 1, 0.95))
		_text(box.position + Vector2(10.0, 29.0), distance_text, 11, color.lightened(0.2))


func _draw_floaters() -> void:
	for floater in _floaters:
		var age: float = float(floater["age"])
		var position: Vector3 = floater["pos"] + Vector3(0.0, age * 1.6, 0.0)
		if camera.is_position_behind(position):
			continue
		var spot: Vector2 = camera.unproject_position(position)
		var alpha: float = clampf(1.0 - (age - 0.6) / 0.5, 0.0, 1.0)
		var pop: float = 1.0 + 0.35 * clampf(1.0 - age * 6.0, 0.0, 1.0)
		var color: Color = floater["color"]
		color.a = alpha
		_text(spot - Vector2(30.0, 0.0), str(floater["text"]), int(float(floater["size"]) * pop), color, 60.0, HORIZONTAL_ALIGNMENT_CENTER)
