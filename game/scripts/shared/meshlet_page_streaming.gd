extends RefCounted
## Deterministic, device-independent scheduler for GPU-resident meshlet pages.
## This schedules at PAGE granularity; the task/mesh shader still does final
## visibility culling per meshlet, entirely on GPU without visibility readbacks.
##
## Per-page bounds are conservative, so a page is never considered farther
## away than any meshlet inside it. No camera-distance cut is imposed by
## default: budgeted pages favor nearer geometry instead of deleting it by
## arbitrary distance.

const MESHLETS_PER_PAGE: int = 32
const MAX_MESHLET_VERTICES: int = 64
const MAX_MESHLET_TRIANGLES: int = 124
const POSITIONS_BYTES: int = MESHLETS_PER_PAGE * MAX_MESHLET_VERTICES * 16
const VERTEX_IDS_BYTES: int = MESHLETS_PER_PAGE * MAX_MESHLET_VERTICES * 4
const TRIANGLES_BYTES: int = MESHLETS_PER_PAGE * MAX_MESHLET_TRIANGLES * 4
const DESCRIPTORS_BYTES: int = MESHLETS_PER_PAGE * 48
const PAGE_BYTES: int = POSITIONS_BYTES + VERTEX_IDS_BYTES + TRIANGLES_BYTES + DESCRIPTORS_BYTES


## Offline/load-time. Returns a conservative sphere per group of 32 meshlets.
@warning_ignore("integer_division")
static func build_bounds(meshlets: Array) -> Array[Dictionary]:
	var pages: Array[Dictionary] = []
	for start in range(0, meshlets.size(), MESHLETS_PER_PAGE):
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		var stop: int = mini(start + MESHLETS_PER_PAGE, meshlets.size())
		for index in range(start, stop):
			var part: Dictionary = meshlets[index]
			var center: Vector3 = part["bounds_center"]
			var radius: float = maxf(float(part["bounds_radius"]), 0.0)
			var extent := Vector3.ONE * radius
			low = low.min(center - extent)
			high = high.max(center + extent)
		var bounds_center: Vector3 = (low + high) * 0.5
		pages.append({"index": start / MESHLETS_PER_PAGE,
			"center": bounds_center, "radius": (high - low).length() * 0.5,
			"meshlet_count": stop - start})
	return pages


## Desired logical page ids ordered closest first, with stable ties.
## A page budget of zero means all pages (legacy behavior).
static func wanted_pages(bounds: Array[Dictionary], camera_pos: Vector3,
		transform: Transform3D, budget: int = 0) -> PackedInt32Array:
	var ranked: Array[Dictionary] = []
	var scale: float = maxf(transform.basis.x.length(),
		maxf(transform.basis.y.length(), transform.basis.z.length()))
	for page in bounds:
		var center: Vector3 = transform * (page["center"] as Vector3)
		var radius: float = float(page["radius"]) * scale
		var distance: float = maxf(0.0, center.distance_to(camera_pos) - radius)
		ranked.append({"id": int(page["index"]), "distance": distance})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["distance"]), float(b["distance"])):
			return int(a["id"]) < int(b["id"])
		return float(a["distance"]) < float(b["distance"])
	)
	var wanted := PackedInt32Array()
	var count: int = ranked.size() if budget <= 0 else mini(budget, ranked.size())
	for i in count:
		wanted.append(int(ranked[i]["id"]))
	return wanted


## Retain wanted pages already in slots, then use free slots before evicting
## unwanted pages. At most upload_budget new pages enter in one update.
## Never evict a wanted page. Replaying the same input is a no-op.
static func plan(slots: PackedInt32Array, wanted: PackedInt32Array,
		upload_budget: int) -> Dictionary:
	var next_slots: PackedInt32Array = slots.duplicate()
	var uploads: Array[Dictionary] = []
	var evicted := PackedInt32Array()
	if upload_budget <= 0:
		return {"slots": next_slots, "uploads": uploads, "evictions": evicted}
	var seen: Dictionary = {}
	for id in wanted:
		seen[id] = true
	var remaining: int = upload_budget
	for id in wanted:
		if remaining <= 0:
			break
		if next_slots.has(id):
			continue
		var victim: int = -1
		for slot in next_slots.size():
			if next_slots[slot] == -1:
				victim = slot
				break
		if victim < 0:
			for slot in next_slots.size():
				if not seen.has(next_slots[slot]):
					victim = slot
					break
		if victim < 0:
			break
		if next_slots[victim] != -1:
			evicted.append(next_slots[victim])
		next_slots[victim] = id
		uploads.append({"slot": victim, "page": id})
		remaining -= 1
	return {"slots": next_slots, "uploads": uploads, "evictions": evicted}


static func resident_count(slots: PackedInt32Array) -> int:
	var count: int = 0
	for id in slots:
		if id >= 0:
			count += 1
	return count
