extends RefCounted
## Pose Search debugger for the Motion Matching runtime (motion_matching.gd).
##
## Records every search: the query features, the pose the runtime chose and the
## top-N candidate frames with a per-feature-group cost breakdown. The breakdown
## is the squared normalised, weight-scaled distance split by feature group, so
## for every candidate  sum(breakdown) == cost * cost  (continuation bias is
## reported separately as `continue_cost` on the record).
##
## Credit / licensing: original implementation. Concepts from the pose-search
## debuggers of Unreal Engine's Pose Search plugin (public documentation only,
## no source copied) and Clavet, "Motion Matching and The Road to Next-Gen
## Animation", GDC 2016. No third-party code is included.

const MotionMatching = preload("res://scripts/client/motion_matching.gd")

## Feature groups in display order, with the [first, last) dimension ranges.
const GROUPS: Array[String] = ["velocity", "facing", "traj_pos", "traj_facing", "foot_pos", "foot_vel"]

var top_n: int = 5
var max_records: int = 256
var records: Array[Dictionary] = []


## Feature group of dimension `d` (matches the layout documented in motion_matching.gd).
static func group_of(d: int) -> String:
	if d < 2:
		return "velocity"
	if d == 2:
		return "facing"
	if d < 12:
		return "traj_facing" if (d - 3) % 3 == 2 else "traj_pos"
	if d < 18:
		return "foot_pos"
	return "foot_vel"


static func empty_breakdown() -> Dictionary:
	var b := {}
	for g in GROUPS:
		b[g] = 0.0
	return b


## Per-group squared distance between the normalised query and database frame `index`.
static func breakdown_for(db: MotionMatching, q: PackedFloat32Array, index: int) -> Dictionary:
	var b := empty_breakdown()
	var base: int = index * MotionMatching.DIMS
	for d in MotionMatching.DIMS:
		var x: float = q[d] - db.features[base + d]
		var g: String = group_of(d)
		b[g] = float(b[g]) + x * x
	return b


static func _sum(b: Dictionary) -> float:
	var s: float = 0.0
	for g in GROUPS:
		s += float(b[g])
	return s


## Runs a search, records it and returns the record. Brute force over the database
## builds the candidate list (cheap enough for a debug tool); `chosen` comes from
## the real indexed search so the debugger shows what the runtime actually did.
func record_search(db: MotionMatching, query: Dictionary, current_clip: String = "", current_frame: int = -1,
		required_tags: PackedStringArray = PackedStringArray()) -> Dictionary:
	var q: PackedFloat32Array = db._normalize_query(query)
	var ok: PackedByteArray = db._tag_mask(required_tags)
	var scored: Array[Dictionary] = []
	for i in db.clip_of.size():
		if ok[db.clip_of[i]] == 0:
			continue
		var b := breakdown_for(db, q, i)
		scored.append({"index": i, "sq": _sum(b), "breakdown": b})
	scored.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return float(a["sq"]) < float(c["sq"]))
	var cands: Array[Dictionary] = []
	for k in mini(top_n, scored.size()):
		var s: Dictionary = scored[k]
		var idx: int = s["index"]
		var sq: float = s["sq"]
		cands.append({
			"rank": k,
			"index": idx,
			"clip": db.clip_names[db.clip_of[idx]],
			"frame": db.frame_src[idx],
			"cost": sqrt(sq),
			"breakdown": s["breakdown"],
		})
	var chosen: Dictionary = db.search(query, current_clip, current_frame, required_tags)
	var continue_cost: float = -1.0
	var nxt: int = db._next_index(current_clip, current_frame)
	if nxt >= 0 and ok[db.clip_of[nxt]] == 1:
		continue_cost = sqrt(MotionMatching._dsq(q, 0, db.features, nxt * MotionMatching.DIMS)) * db.continue_bias
	var qf: PackedFloat32Array = q
	var rec := {
		"id": records.size() if records.size() < max_records else max_records,
		"query_features": qf,
		"chosen": chosen,
		"continue_cost": continue_cost,
		"candidates": cands,
		"candidate_total": scored.size(),
	}
	records.append(rec)
	if records.size() > max_records:
		records.pop_front()
	return rec


## Group that dominates the chosen pose's cost (the "why did it pick this" answer).
static func dominant_group(candidate: Dictionary) -> String:
	var b: Dictionary = candidate["breakdown"]
	var best: String = GROUPS[0]
	var bv: float = -1.0
	for g in GROUPS:
		var v: float = float(b[g])
		if v > bv:
			bv = v
			best = g
	return best


## Difference in squared cost per group between two candidates (a - b); positive
## means group costs `a` more. Explains why `b` beat `a`.
static func compare(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	var ba: Dictionary = a["breakdown"]
	var bb: Dictionary = b["breakdown"]
	for g in GROUPS:
		out[g] = float(ba[g]) - float(bb[g])
	return out


func clear() -> void:
	records.clear()


## One-line-per-candidate text dump of a record.
static func format_record(rec: Dictionary) -> String:
	var chosen: Dictionary = rec["chosen"]
	var lines: Array[String] = ["chosen %s@%s cost %.3f%s" % [chosen["clip"], str(chosen["frame"]),
			float(chosen["cost"]), " (continuing)" if bool(chosen["continuing"]) else ""]]
	for c in rec["candidates"] as Array:
		var cd: Dictionary = c
		lines.append("  #%d %s@%s cost %.3f dominant %s" % [int(cd["rank"]), cd["clip"], str(cd["frame"]),
				float(cd["cost"]), dominant_group(cd)])
	return "\n".join(lines)
