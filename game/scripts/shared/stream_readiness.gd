extends RefCounted
## Unified readiness gate for streamed cells. A cell may only be revealed once all stages are
## done: data loaded, GPU resources uploaded, physics shapes created, navmesh warmed up.
## Stages are reported with `mark` or discovered by polling per-stage probe callables in `update`.
## Prerequisites: GPU and physics need data; navmesh needs physics (it bakes from collision), so an
## early mark of a later stage is remembered but does not count until its prerequisites are met.
## Stages that take too long are reported as stuck (once) so the streamer can retry or log.
##
## Concept (not code) from UE World Partition "streaming completed" / level-visibility gating and
## Unity Addressables readiness checks. Original GDScript; no third-party code copied, so no
## license obligations.

enum Stage { DATA_LOADED = 1, GPU_UPLOADED = 2, PHYSICS_READY = 4, NAVMESH_READY = 8 }

const ALL: int = 15
const ORDER: Array[int] = [Stage.DATA_LOADED, Stage.GPU_UPLOADED, Stage.PHYSICS_READY, Stage.NAVMESH_READY]
const STAGE_NAMES: Dictionary = {1: "data_loaded", 2: "gpu_uploaded", 4: "physics_ready", 8: "navmesh_ready"}


class CellState extends RefCounted:
	var marked: int = 0
	var since: float = 0.0
	var last_eff: int = 0
	var stuck_reported: int = 0
	var revealed: bool = false
	var warmup_queued: bool = false


## Seconds a stage may wait (from when it became possible) before it is reported as stuck.
var default_timeout: float = 10.0
var stage_timeouts: Dictionary = {}
## Optional callbacks: on_stuck(report: Dictionary), on_reveal(cell: Vector2i).
var on_stuck: Callable = Callable()
var on_reveal: Callable = Callable()
## Navmesh bake attempts before a cell's warmup is given up.
var max_warmup_attempts: int = 3
var warmup_failed: Array[Vector2i] = []
var stuck_log: Array[Dictionary] = []

var _cells: Dictionary = {}
var _probes: Dictionary = {}
var _warmups: Array[Dictionary] = []
var _auto_bake: Callable = Callable()
var _now: float = 0.0


## Probe: func(cell: Vector2i) -> bool, polled in `update` until it returns true.
func set_probe(stage: int, probe: Callable) -> void:
	_probes[stage] = probe


## Enables automatic navmesh warmup: as soon as a cell's physics become ready, `bake` (func(cell)
## -> bool) is queued on the warmup queue.
func set_auto_warmup(bake: Callable) -> void:
	_auto_bake = bake
	if not bake.is_valid():
		return
	# Runtime modules may enable auto-bake after physics is already ready.
	# Catch up existing cells without duplicating active or finished jobs.
	for cell: Vector2i in _cells.keys():
		var c: CellState = _cells[cell]
		var ready: int = _effective(c.marked)
		if (ready & Stage.PHYSICS_READY) != 0 and 				(ready & Stage.NAVMESH_READY) == 0:
			warmup_navmesh(cell, bake)


func begin(cell: Vector2i, now: float) -> void:
	_now = now
	if _cells.has(cell):
		return
	var c := CellState.new()
	c.since = now
	_cells[cell] = c


func release(cell: Vector2i) -> void:
	_cells.erase(cell)
	for i in range(_warmups.size() - 1, -1, -1):
		if _warmups[i]["cell"] == cell:
			_warmups.remove_at(i)


func is_tracked(cell: Vector2i) -> bool:
	return _cells.has(cell)


func mark(cell: Vector2i, stage: int, now: float = -1.0) -> void:
	if now >= 0.0:
		_now = now
	if not _cells.has(cell):
		begin(cell, _now)
	var c: CellState = _cells[cell]
	c.marked |= stage
	_refresh(cell, c)


## Stages that count as done (prerequisites applied).
func ready_mask(cell: Vector2i) -> int:
	if not _cells.has(cell):
		return 0
	var c: CellState = _cells[cell]
	return _effective(c.marked)


func is_stage_ready(cell: Vector2i, stage: int) -> bool:
	return (ready_mask(cell) & stage) != 0


func is_revealable(cell: Vector2i) -> bool:
	return ready_mask(cell) == ALL


func is_revealed(cell: Vector2i) -> bool:
	if not _cells.has(cell):
		return false
	var c: CellState = _cells[cell]
	return c.revealed


## First stage a cell is currently waiting on (0 when complete).
func waiting_stage(cell: Vector2i) -> int:
	return _waiting(ready_mask(cell))


## Polls probes, tracks timeouts and returns cells that just became revealable (once each).
func update(now: float) -> Array[Vector2i]:
	_now = now
	var out: Array[Vector2i] = []
	for cell: Vector2i in _cells.keys():
		var c: CellState = _cells[cell]
		var eff := _effective(c.marked)
		for stage in ORDER:
			if (eff & stage) != 0 or not _probes.has(stage) or not _prereqs_met(stage, eff):
				continue
			var probe: Callable = _probes[stage]
			if probe.is_valid() and bool(probe.call(cell)):
				c.marked |= stage
				eff = _effective(c.marked)
		_refresh(cell, c)
		if eff == ALL and not c.revealed:
			c.revealed = true
			out.append(cell)
			if on_reveal.is_valid():
				on_reveal.call(cell)
	_report_stuck(now)
	return out


## Newly detected stuck stages are appended to `stuck_log`; returns only the new reports.
func _report_stuck(now: float) -> Array[Dictionary]:
	var fresh: Array[Dictionary] = []
	for cell: Vector2i in _cells.keys():
		var c: CellState = _cells[cell]
		if c.revealed:
			continue
		var w := _waiting(_effective(c.marked))
		if w == 0 or (c.stuck_reported & w) != 0:
			continue
		var limit: float = float(stage_timeouts.get(w, default_timeout))
		var waited := now - c.since
		if waited >= limit:
			c.stuck_reported |= w
			var rep := {"cell": cell, "stage": w, "stage_name": STAGE_NAMES[w], "waited": waited}
			fresh.append(rep)
			stuck_log.append(rep)
			if on_stuck.is_valid():
				on_stuck.call(rep)
	return fresh


## Queue a navmesh bake for a cell. `bake` is func(cell) -> bool (true = navmesh ready). It runs
## from `process_warmup` once the cell's physics are ready.
func warmup_navmesh(cell: Vector2i, bake: Callable) -> void:
	if not _cells.has(cell):
		begin(cell, _now)
	var c: CellState = _cells[cell]
	# Repeated editor/runtime requests cannot schedule duplicate navmesh bakes.
	# A ready cell should never restart a completed bake.
	if c.warmup_queued or (ready_mask(cell) & Stage.NAVMESH_READY) != 0:
		return
	c.warmup_queued = true
	_warmups.append({"cell": cell, "bake": bake, "attempts": 0})


func pending_warmups() -> int:
	return _warmups.size()


## Runs up to `max_count` bakes (and stops early after `max_usec` microseconds when > 0).
## Cells whose physics are not ready yet are skipped without consuming budget. Returns bakes run.
func process_warmup(max_count: int, max_usec: int = 0) -> int:
	var t0 := Time.get_ticks_usec()
	var ran := 0
	var snapshot := _warmups.duplicate()
	for item: Dictionary in snapshot:
		if ran >= max_count or (max_usec > 0 and Time.get_ticks_usec() - t0 >= max_usec):
			break
		# User callbacks can unload cells while this snapshot is being processed.
		if not _warmups.has(item):
			continue
		var cell: Vector2i = item["cell"]
		var state: CellState = _cells.get(cell)
		if state == null or (ready_mask(cell) & Stage.PHYSICS_READY) == 0:
			continue
		ran += 1
		var bake: Callable = item["bake"]
		var ok: bool = bake.is_valid() and bool(bake.call(cell))
		# Never re-create a released cell (or touch a new cell using an old job).
		if not _warmups.has(item) or _cells.get(cell) != state:
			continue
		if ok:
			_warmups.erase(item)
			mark(cell, Stage.NAVMESH_READY)
			continue
		item["attempts"] = int(item["attempts"]) + 1
		if int(item["attempts"]) >= max_warmup_attempts:
			_warmups.erase(item)
			warmup_failed.append(cell)
	return ran


# --- helpers -------------------------------------------------------------------------------

func _refresh(cell: Vector2i, c: CellState) -> void:
	var eff := _effective(c.marked)
	if eff != c.last_eff:
		c.last_eff = eff
		c.since = _now
	if _auto_bake.is_valid() and (eff & Stage.PHYSICS_READY) != 0 and (eff & Stage.NAVMESH_READY) == 0 \
			and not c.warmup_queued:
		warmup_navmesh(cell, _auto_bake)


static func _effective(m: int) -> int:
	var e: int = m & Stage.DATA_LOADED
	if e != 0:
		e |= m & (Stage.GPU_UPLOADED | Stage.PHYSICS_READY)
	if (e & Stage.PHYSICS_READY) != 0:
		e |= m & Stage.NAVMESH_READY
	return e


static func _prereqs_met(stage: int, eff: int) -> bool:
	match stage:
		Stage.GPU_UPLOADED, Stage.PHYSICS_READY:
			return (eff & Stage.DATA_LOADED) != 0
		Stage.NAVMESH_READY:
			return (eff & Stage.PHYSICS_READY) != 0
	return true


static func _waiting(eff: int) -> int:
	for stage in ORDER:
		if (eff & stage) == 0 and _prereqs_met(stage, eff):
			return stage
	return 0


# --- ready-made probes ---------------------------------------------------------------------

## GPU stage: every RID (mesh, texture, material...) is valid on the RenderingServer.
static func probe_rids_valid(rids: Array) -> bool:
	for r in rids:
		if not (r is RID) or not (r as RID).is_valid():
			return false
	return not rids.is_empty()


## Physics stage: the body exists and owns at least `min_shapes` shapes.
static func probe_body_shapes(body: RID, min_shapes: int = 1) -> bool:
	return body.is_valid() and PhysicsServer3D.body_get_shape_count(body) >= min_shapes


## Navmesh stage: the region exists and its navigation iteration was published.
static func probe_nav_region(region: RID) -> bool:
	return region.is_valid() and NavigationServer3D.region_get_iteration_id(region) > 0
