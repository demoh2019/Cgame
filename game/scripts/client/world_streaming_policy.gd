extends RefCounted
## World Partition-style stream priority follows the actual movement mode.
## This only reorders already-resident eligible cells; the engine remains
## responsible for load/unload radius, queue hygiene and shared CPU budget.

const WALK_LOOKAHEAD := 2.0
const RIDING_LOOKAHEAD := 3.0
const IDLE_VELOCITY_SQ := 0.16
# Gameplay movement is much slower. A one-frame network correction or large
# teleport should never project the chunk queue kilometres ahead.
const MAX_PREDICTIVE_SPEED := 48.0


## Check raw frame displacement before the 18 m/s visual hint clamp.
## Otherwise a teleport during a short render frame looks like ordinary
## movement and incorrectly prefetches unrelated terrain for several frames.
static func plausible_velocity(velocity: Vector3) -> bool:
	if not velocity.is_finite():
		return false
	var speed_squared: float = velocity.length_squared()
	return is_finite(speed_squared) and \
		speed_squared <= MAX_PREDICTIVE_SPEED * MAX_PREDICTIVE_SPEED


static func lookahead_seconds(mounted: bool, velocity: Vector3) -> float:
	# Presentation-only; authoritative player movement is never modified.
	if not plausible_velocity(velocity) or velocity.length_squared() < IDLE_VELOCITY_SQ:
		return 0.0
	return RIDING_LOOKAHEAD if mounted else WALK_LOOKAHEAD


## Do not resend identical settings to the native streamer every render frame.
## User preference, world radius and generation budget stay untouched.
static func apply(streamer: WorldStreamer, mounted: bool, velocity: Vector3) -> void:
	if streamer == null:
		return
	var desired: float = lookahead_seconds(mounted, velocity)
	if not is_equal_approx(streamer.lookahead_seconds, desired):
		streamer.lookahead_seconds = desired


## Visibility-weighted streaming source inspired by Unreal World Partition.
## View weighting affects ONLY scheduling, never player-centered residency.
## No camera or mesh work is performed in the native chunk generator.
const VIEW_WEIGHTS := [0.35, 0.48, 0.66, 0.80]
# Degrees of camera change from the last real queue publication.
# The native engine batches rapid turns behind a 50 ms CPU refresh guard.
# Performance reorders less frequently; Ultra responds faster in busy scenes.
const FAST_TURN_ANGLES := [60.0, 45.0, 35.0, 30.0]


static func view_weight(level: int) -> float:
	return float(VIEW_WEIGHTS[clampi(level, 0, VIEW_WEIGHTS.size() - 1)])


static func fast_turn_angle(level: int) -> float:
	return float(FAST_TURN_ANGLES[clampi(level, 0, FAST_TURN_ANGLES.size() - 1)])


static func ground_view(camera: Camera3D) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var forward: Vector3 = -camera.global_transform.basis.z
	if not forward.is_finite():
		return Vector3.ZERO
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.ZERO
	return forward.normalized()


## Convert the perspective camera into a conservative horizontal view cone.
## The extra margin reduces visible pop-in around the screen edges.
## Non-perspective cameras retain legacy heading-only streaming.
static func horizontal_cone_half_angle(fov: float, aspect: float, keep_height: bool) -> float:
	if not is_finite(fov) or not is_finite(aspect) or aspect <= 0.0:
		return 180.0
	var half_angle: float = deg_to_rad(clampf(fov, 1.0, 179.0) * 0.5)
	if keep_height:
		half_angle = atan(tan(half_angle) * aspect)
	return clampf(rad_to_deg(half_angle) + 12.0, 20.0, 89.0)


static func view_cone_half_angle(camera: Camera3D) -> float:
	if camera == null or camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return 180.0
	var viewport: Viewport = camera.get_viewport()
	if viewport == null:
		return 180.0
	var size: Vector2 = viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return 180.0
	return horizontal_cone_half_angle(camera.fov, size.x / size.y,
		camera.keep_aspect == Camera3D.KEEP_HEIGHT)


## Run after Camera3D look_at(), so zoom/photo orbit uses the actual
## rendered view instead of stale movement input. Native Cgame setters are
## idempotent; do not touch loaded cells or resource allocations here.
static func apply_view(streamer: WorldStreamer, camera: Camera3D,
		graphics_level: int) -> void:
	if streamer == null:
		return
	var weight: float = view_weight(graphics_level)
	if not is_equal_approx(streamer.view_priority, weight):
		streamer.view_priority = weight
	var degrees: float = fast_turn_angle(graphics_level)
	if not is_equal_approx(streamer.fast_view_refresh_degrees, degrees):
		streamer.fast_view_refresh_degrees = degrees
	var direction: Vector3 = ground_view(camera)
	if not streamer.view_direction.is_equal_approx(direction):
		streamer.view_direction = direction
	# Older custom engine builds keep the original heading-only schedule.
	if "view_cone_half_angle_degrees" in streamer:
		var half_angle: float = view_cone_half_angle(camera)
		if not is_equal_approx(streamer.view_cone_half_angle_degrees, half_angle):
			streamer.view_cone_half_angle_degrees = half_angle


## Nearby personal map markers become a bounded second streaming source.
## Distant quest/map markers remain purely UI: they cannot load a second island
## or bypass the player's authoritative chunk residency and CPU budgets.
static func waypoint_radius(cell_size: float, mounted: bool) -> float:
	if not is_finite(cell_size) or cell_size <= 0.0:
		return 0.0
	return minf(cell_size * (2.0 if mounted else 1.5), 48.0)


static func waypoint_is_near(point: Vector2, player: Vector3,
		load_radius: float, cell_size: float) -> bool:
	if not point.is_finite() or not player.is_finite() or \
			not is_finite(load_radius) or not is_finite(cell_size) or \
			load_radius <= 0.0 or cell_size <= 0.0:
		return false
	return point.distance_to(Vector2(player.x, player.z)) <= load_radius + cell_size


## AStarGrid2D plans a 4-neighbor local path around optional blocked
## streaming cells; the native WorldStreamer prioritizes its route but never
## changes the player-centered resident set. A max 64-cell path and a 3-cell
## detour margin keep this independent of global/untrusted map requests.
static func plan_waypoint_route(streamer: WorldStreamer, waypoint: Vector2,
		player: Vector3, blocked_cells: Array[Vector3i] = []) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if streamer == null or not waypoint_is_near(
			waypoint, player, streamer.load_radius, streamer.cell_size):
		return result
	if streamer.axes != WorldStreamer.AXES_XZ:
		return result
	var from_cell: Vector3i = streamer.world_to_cell(player)
	var to_cell: Vector3i = streamer.world_to_cell(Vector3(waypoint.x, 0.0, waypoint.y))
	var width := absi(to_cell.x - from_cell.x)
	var height := absi(to_cell.z - from_cell.z)
	if width + height + 1 > 64:
		return result
	var start := Vector2i(from_cell.x, from_cell.z)
	var finish := Vector2i(to_cell.x, to_cell.z)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(
		Vector2i(mini(start.x, finish.x) - 3, mini(start.y, finish.y) - 3),
		Vector2i(width + 7, height + 7)
	)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for cell in blocked_cells:
		if cell.y != 0:
			continue
		var id := Vector2i(cell.x, cell.z)
		if id == start or id == finish:
			return result
		if grid.region.has_point(id):
			grid.set_point_solid(id)
	var points: Array[Vector2i] = grid.get_id_path(start, finish)
	if points.is_empty() or points.size() > 64:
		return result
	for point in points:
		result.append(Vector3i(point.x, 0, point.y))
	return result


## Called from the existing private map-waypoint update, with an optional
## game-owned hazard map. Never trusts remote players or creates new chunks.
## Do not rerun AStar each render frame when both endpoint cells are stable.
static func apply_waypoint_route(streamer: WorldStreamer, waypoint: Vector2,
		player: Vector3, blocked_cells: Array[Vector3i] = []) -> void:
	if streamer == null or not streamer.has_method("set_route_cells"):
		return
	var cached: Array = streamer.call("get_route_cells")
	if not waypoint_is_near(waypoint, player, streamer.load_radius, streamer.cell_size) or \
			streamer.axes != WorldStreamer.AXES_XZ:
		if not cached.is_empty():
			streamer.call("clear_route_cells")
		return
	var first: Vector3i = streamer.world_to_cell(player)
	var last: Vector3i = streamer.world_to_cell(Vector3(waypoint.x, 0.0, waypoint.y))
	if blocked_cells.is_empty() and not cached.is_empty() and cached[0] == first and \
			cached[cached.size() - 1] == last:
		return
	var planned: Array[Vector3i] = plan_waypoint_route(streamer, waypoint, player, blocked_cells)
	if planned.is_empty():
		if not cached.is_empty():
			streamer.call("clear_route_cells")
	else:
		streamer.call("set_route_cells", planned)


## Called after focus_position updates, once per frame. Only the fork's
## WorldStreamer implements this opt-in API; ordinary script code stays
## compatible with projects that run on a binary without the extension.
static func apply_waypoint(streamer: WorldStreamer, waypoint: Vector2,
		player: Vector3, mounted: bool) -> void:
	if streamer == null or not streamer.has_method("set_auxiliary_source"):
		return
	apply_waypoint_route(streamer, waypoint, player)
	var is_active: bool = bool(streamer.call("has_auxiliary_source"))
	if not waypoint_is_near(waypoint, player, streamer.load_radius, streamer.cell_size):
		if is_active:
			streamer.call("clear_auxiliary_source")
		return
	var radius: float = waypoint_radius(streamer.cell_size, mounted)
	var destination := Vector3(waypoint.x, 0.0, waypoint.y)
	if not is_active or \
			not (streamer.call("get_auxiliary_source_position") as Vector3).is_equal_approx(destination) or \
			not is_equal_approx(float(streamer.call("get_auxiliary_source_radius")), radius):
		streamer.call("set_auxiliary_source", destination, radius)


## Unreal-inspired named simulation Data Layer. Surface chunk scene roots opt
## into this client-cosmetic layer; disabling it suspends expensive grass,
## decor, windmill and shadow callbacks, not terrain/collision/network play.
## Idempotent setter; old Cgame builds simply retain their normal LOD tier.
static func apply_simulation_layers(streamer: WorldStreamer, underground: bool) -> void:
	if streamer == null or not streamer.has_method("set_simulation_layer_enabled") or \
			not streamer.has_method("is_simulation_layer_enabled"):
		return
	var enabled: bool = not underground
	if bool(streamer.call("is_simulation_layer_enabled", &"SurfaceCosmetics")) != enabled:
		streamer.call("set_simulation_layer_enabled", &"SurfaceCosmetics", enabled)

## Read-only main streaming readiness for a compact client HUD indicator.
## Older fork engines lack this native API; do not invent a percentage.
## Game systems never use this cosmetic estimate as combat authority.
static func format_focus_streaming_status(status: Dictionary) -> String:
	var total: int = int(status.get("total", 0))
	if total <= 0:
		return ""
	if bool(status.get("truncated", false)):
		return "WORLD STREAMING: grid limit reached"
	var failed: int = maxi(0, int(status.get("failed", 0)))
	var pending: int = maxi(0, int(status.get("pending", 0)))
	if failed > 0:
		return "WORLD STREAMING: %d failed, %d pending" % [failed, pending]
	if pending <= 0:
		return ""
	var progress: float = float(status.get("progress", 0.0))
	if not is_finite(progress):
		progress = 0.0
	return "WORLD STREAMING: %d%% | pending %d" % [
		roundi(clampf(progress, 0.0, 1.0) * 100.0), pending]


static func focus_loading_notice(streamer: WorldStreamer) -> String:
	if streamer == null or not streamer.has_method("get_focus_streaming_status"):
		return ""
	var status: Dictionary = streamer.call("get_focus_streaming_status", true)
	return format_focus_streaming_status(status)

