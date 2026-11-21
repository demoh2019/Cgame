extends RefCounted
## Procedural rig toolkit (Control-Rig style): two-bone IK with pole vector, FABRIK chains with
## cone/hinge joint constraints, multi-effector full-body IK with a free pelvis, aim constraint,
## and Skeleton3D read/write helpers. Pure math on position arrays so it runs headless.
##
## Credit / licensing: original implementation written for this project. The algorithms follow
## the published literature, no third-party source code was copied:
##   - FABRIK: Aristidou & Lasenby, "FABRIK: A fast, iterative solver for the inverse kinematics
##     problem", Graphical Models 73(5), 2011 (the multi-chain / sub-base averaging scheme and
##     joint-constraint projection described there).
##   - Two-bone IK: the classic law-of-cosines solution with a pole vector (public domain math,
##     as documented e.g. in Inigo Quilez's "two bone IK" article and many engines).
##   - Aim: shortest-arc quaternion clamped by a cone angle.
## No Apache-2.0 / MIT / BSD source was ported.

const EPS := 0.000001


## Two-bone IK. Returns {"mid": Vector3, "tip": Vector3, "reached": bool}. Bone lengths are
## preserved; an unreachable target gives a straight limb pointing at it. `pole` is a world
## position the middle joint (knee/elbow) is pulled toward.
static func two_bone(root: Vector3, mid: Vector3, tip: Vector3, target: Vector3, pole: Vector3) -> Dictionary:
	var l1 := root.distance_to(mid)
	var l2 := mid.distance_to(tip)
	var to_target := target - root
	var dist := to_target.length()
	var u := Vector3.FORWARD
	if dist > EPS:
		u = to_target / dist
	var min_d := absf(l1 - l2) + EPS
	var max_d := l1 + l2
	var reached := dist <= max_d and dist >= min_d
	var d := clampf(dist, min_d, max_d)
	# Bend plane direction: pole component perpendicular to the root->target axis.
	var perp := (pole - root) - u * (pole - root).dot(u)
	if perp.length_squared() < EPS:
		perp = (mid - root) - u * (mid - root).dot(u)
	if perp.length_squared() < EPS:
		perp = u.cross(Vector3.UP)
		if perp.length_squared() < EPS:
			perp = u.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var new_mid := root + u * a + perp * h
	var new_tip := root + u * d
	return {"mid": new_mid, "tip": new_tip, "reached": reached}


## Limits a bone direction against the previous bone direction. Constraint dictionaries:
## {"type": "cone", "angle": rad}  - direction within `angle` of the previous bone direction;
## {"type": "hinge", "axis": Vector3, "min": rad, "max": rad} - rotation only around the world
##   axis, bend angle relative to the previous direction clamped to [min, max].
static func apply_constraint(prev_dir: Vector3, dir: Vector3, constraint: Dictionary) -> Vector3:
	return FullBodyIK.limit(prev_dir, dir, constraint)



## FABRIK on a single chain (root fixed at positions[0]). `constraints[i]` (optional) limits
## the direction of bone i->i+1 relative to bone i-1->i; for i == 0 an optional "ref" Vector3
## in the dictionary gives the reference direction. Returns the solved positions.
static func fabrik_chain(positions: PackedVector3Array, target: Vector3, iterations: int = 16, tolerance: float = 0.001, constraints: Array = []) -> PackedVector3Array:
	var n := positions.size()
	var out := positions.duplicate()
	if n < 2:
		return out
	var lens := PackedFloat64Array()
	lens.resize(n - 1)
	for i in n - 1:
		lens[i] = positions[i].distance_to(positions[i + 1])
	var root := positions[0]
	for _it in iterations:
		if out[n - 1].distance_to(target) <= tolerance:
			break
		# Backward: tip to target.
		out[n - 1] = target
		for i in range(n - 2, -1, -1):
			var dir := out[i] - out[i + 1]
			if dir.length_squared() < EPS:
				dir = positions[i] - positions[i + 1]
			out[i] = out[i + 1] + dir.normalized() * lens[i]
		# Forward: root back in place, constraints enforced.
		out[0] = root
		for i in n - 1:
			var dir2 := out[i + 1] - out[i]
			if dir2.length_squared() < EPS:
				dir2 = positions[i + 1] - positions[i]
			dir2 = dir2.normalized()
			if i < constraints.size():
				var c: Dictionary = constraints[i]
				if not c.is_empty():
					var prev := Vector3.ZERO
					if i > 0:
						prev = out[i] - out[i - 1]
					else:
						prev = c.get("ref", Vector3.ZERO)
					dir2 = apply_constraint(prev, dir2, c)
			out[i + 1] = out[i] + dir2 * lens[i]
	return out


## Shortest-arc rotation turning `forward` toward the direction bone_pos -> target, clamped to
## `max_angle` radians. Apply as q * forward.
static func aim(bone_pos: Vector3, forward: Vector3, target: Vector3, max_angle: float = PI) -> Quaternion:
	var to_t := target - bone_pos
	if to_t.length_squared() < EPS or forward.length_squared() < EPS:
		return Quaternion.IDENTITY
	var f := forward.normalized()
	var d := to_t.normalized()
	var q := Quaternion.IDENTITY
	if f.dot(d) < -0.99999:
		var axis := f.cross(Vector3.UP)
		if axis.length_squared() < EPS:
			axis = f.cross(Vector3.RIGHT)
		q = Quaternion(axis.normalized(), PI)
	else:
		q = Quaternion(f, d)
	var ang := q.get_angle()
	if ang > max_angle:
		q = Quaternion(q.get_axis(), maxf(max_angle, 0.0))
	return q


## Reads a Skeleton3D into plain arrays: names, parents, global rest positions/rotations and the
## current global pose positions.
static func pose_from_skeleton(skeleton: Skeleton3D) -> Dictionary:
	var n := skeleton.get_bone_count()
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	var rest := PackedVector3Array()
	var pose := PackedVector3Array()
	var rest_rot: Array = []
	for i in n:
		names.append(skeleton.get_bone_name(i))
		parents.append(skeleton.get_bone_parent(i))
		var gr := skeleton.get_bone_global_rest(i)
		rest.append(gr.origin)
		rest_rot.append(gr.basis.orthonormalized().get_rotation_quaternion())
		pose.append(skeleton.get_bone_global_pose(i).origin)
	return {"names": names, "parents": parents, "rest": rest, "pose": pose, "rest_rot": rest_rot}


## Writes solved global joint positions back to the skeleton as local bone rotations (each
## bone is swung from its rest direction toward its first child; leaf bones keep their rest
## orientation relative to the parent) plus local positions. Twist about the bone axis is
## not recovered. Bones are processed parents first regardless of index order.
static func apply_to_skeleton(skeleton: Skeleton3D, positions: PackedVector3Array) -> void:
	var n := skeleton.get_bone_count()
	if positions.size() != n:
		return
	var parents := PackedInt32Array()
	var first_child := PackedInt32Array()
	first_child.resize(n)
	first_child.fill(-1)
	for i in n:
		var p := skeleton.get_bone_parent(i)
		parents.append(p)
		if p >= 0 and first_child[p] < 0:
			first_child[p] = i
	var order := topo_order(parents)
	var rest_g: Array = []
	for i in n:
		rest_g.append(skeleton.get_bone_global_rest(i))
	var glob: Array = []
	glob.resize(n)
	for i in order:
		var tr: Transform3D = rest_g[i]
		var rest_q := tr.basis.orthonormalized().get_rotation_quaternion()
		var par := parents[i]
		var new_q := rest_q
		var c := first_child[i]
		if c >= 0:
			var tc: Transform3D = rest_g[c]
			var rest_dir := tc.origin - tr.origin
			var new_dir := positions[c] - positions[i]
			if rest_dir.length_squared() > EPS and new_dir.length_squared() > EPS:
				new_q = _arc(rest_dir.normalized(), new_dir.normalized()) * rest_q
			elif par >= 0:
				new_q = _parent_relative(glob, rest_g, par, i)
		elif par >= 0:
			new_q = _parent_relative(glob, rest_g, par, i)
		glob[i] = new_q
		var parent_q := Quaternion.IDENTITY
		var local_rest := tr
		var local_pos := positions[i]
		if par >= 0:
			var tp: Transform3D = rest_g[par]
			local_rest = tp.affine_inverse() * tr
			parent_q = glob[par]
			var gp: Quaternion = glob[par]
			local_pos = gp.inverse() * (positions[i] - positions[par])
		var local_q := parent_q.inverse() * new_q
		var rest_local_q := local_rest.basis.orthonormalized().get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(i, rest_local_q.inverse() * local_q)
		skeleton.set_bone_pose_position(i, local_pos)


static func _parent_relative(glob: Array, rest_g: Array, par: int, i: int) -> Quaternion:
	var tp: Transform3D = rest_g[par]
	var ti: Transform3D = rest_g[i]
	var qp := tp.basis.orthonormalized().get_rotation_quaternion()
	var qi := ti.basis.orthonormalized().get_rotation_quaternion()
	var gp: Quaternion = glob[par]
	return gp * (qp.inverse() * qi)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.dot(to) < -0.99999:
		var axis := from.cross(Vector3.UP)
		if axis.length_squared() < EPS:
			axis = from.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(from, to)


## Indices sorted so every parent precedes its children.
static func topo_order(parents: PackedInt32Array) -> PackedInt32Array:
	var n := parents.size()
	var order := PackedInt32Array()
	var done := PackedByteArray()
	done.resize(n)
	var guard := 0
	while order.size() < n and guard <= n:
		guard += 1
		for i in n:
			if done[i] == 1:
				continue
			var p := parents[i]
			if p < 0 or done[p] == 1:
				done[i] = 1
				order.append(i)
	return order


## Multi-chain full-body IK (FABRIK tree). Skeleton = parent indices (parents precede children,
## root/pelvis is bone 0 with parent -1) + rest positions. Effectors {bone, target, weight} are
## solved simultaneously: the backward pass pulls every chain to its target and averages the
## sub-base candidates where chains share bones (spine, pelvis), so the pelvis shifts toward the
## centroid of the demands; the forward pass restores exact bone lengths and joint constraints.
## Bones not on an effector chain (head, fingers) follow their parent by translation.
class FullBodyIK extends RefCounted:
	var parents := PackedInt32Array()
	var rest := PackedVector3Array()
	var positions := PackedVector3Array()
	var lengths := PackedFloat64Array()
	var effectors: Array = []
	var constraints: Dictionary = {}
	## 0 = pelvis completely free, 1 = pelvis pinned where it started the solve.
	var root_pin := 0.0

	static func limit(prev_dir: Vector3, dir: Vector3, constraint: Dictionary) -> Vector3:
		var kind: String = constraint.get("type", "")
		if prev_dir.length_squared() < EPS or dir.length_squared() < EPS:
			return dir
		var pd := prev_dir.normalized()
		var dn := dir.normalized()
		if kind == "cone":
			var max_a: float = constraint.get("angle", PI)
			if pd.angle_to(dn) <= max_a:
				return dn
			var axis := pd.cross(dn)
			if axis.length_squared() < EPS:
				axis = pd.cross(Vector3.UP)
				if axis.length_squared() < EPS:
					axis = pd.cross(Vector3.RIGHT)
			return pd.rotated(axis.normalized(), max_a).normalized()
		if kind == "hinge":
			var hinge_axis: Vector3 = constraint.get("axis", Vector3.RIGHT)
			hinge_axis = hinge_axis.normalized()
			var lo: float = constraint.get("min", -PI)
			var hi: float = constraint.get("max", PI)
			var pp := pd - hinge_axis * pd.dot(hinge_axis)
			if pp.length_squared() < EPS:
				return dn
			pp = pp.normalized()
			var dp := dn - hinge_axis * dn.dot(hinge_axis)
			if dp.length_squared() < EPS:
				dp = pp
			dp = dp.normalized()
			var ang := clampf(pp.signed_angle_to(dp, hinge_axis), lo, hi)
			return pp.rotated(hinge_axis, ang).normalized()
		return dn

	func setup(p_parents: PackedInt32Array, p_rest: PackedVector3Array) -> void:
		parents = p_parents
		rest = p_rest
		positions = p_rest.duplicate()
		lengths.resize(parents.size())
		for i in parents.size():
			lengths[i] = 0.0 if parents[i] < 0 else rest[i].distance_to(rest[parents[i]])

	func reset() -> void:
		positions = rest.duplicate()

	func clear_effectors() -> void:
		effectors.clear()

	func set_effector(bone: int, target: Vector3, weight: float = 1.0) -> void:
		for e in effectors:
			var ed: Dictionary = e
			if ed["bone"] == bone:
				ed["target"] = target
				ed["weight"] = weight
				return
		effectors.append({"bone": bone, "target": target, "weight": weight})

	## Constraint for the joint at `bone`, limiting every child bone direction against the bone
	## parent->bone (same dictionary format as RigIK.apply_constraint).
	func set_constraint(bone: int, constraint: Dictionary) -> void:
		constraints[bone] = constraint

	func effector_error() -> float:
		var worst := 0.0
		for e in effectors:
			var ed: Dictionary = e
			var w: float = ed["weight"]
			if w < 0.999:
				continue
			var b: int = ed["bone"]
			var tgt: Vector3 = ed["target"]
			worst = maxf(worst, positions[b].distance_to(tgt))
		return worst

	## Runs up to `iterations` FABRIK sweeps; returns the max effector error afterwards.
	func solve(iterations: int = 20, tolerance: float = 0.001) -> float:
		var n := parents.size()
		if effectors.is_empty() or n == 0:
			return 0.0
		var involved := PackedByteArray()
		involved.resize(n)
		var eff_at := {}
		for e in effectors:
			var ed: Dictionary = e
			var b: int = ed["bone"]
			eff_at[b] = ed
			var cur := b
			while cur >= 0 and involved[cur] == 0:
				involved[cur] = 1
				cur = parents[cur]
		var anchor := positions[0]
		var err := effector_error()
		for _it in iterations:
			if err <= tolerance:
				break
			var acc := PackedVector3Array()
			acc.resize(n)
			var wsum := PackedFloat64Array()
			wsum.resize(n)
			var np := positions.duplicate()
			for i in range(n - 1, -1, -1):
				if involved[i] == 0:
					continue
				if eff_at.has(i):
					var ed2: Dictionary = eff_at[i]
					var tgt: Vector3 = ed2["target"]
					var w: float = ed2["weight"]
					np[i] = positions[i].lerp(tgt, w)
				elif wsum[i] > 0.0:
					np[i] = acc[i] / wsum[i]
				var par := parents[i]
				if par >= 0:
					var dir := positions[par] - np[i]
					if dir.length_squared() < EPS:
						dir = rest[par] - rest[i]
					acc[par] += np[i] + dir.normalized() * lengths[i]
					wsum[par] += 1.0
			np[0] = np[0].lerp(anchor, root_pin)
			var fp := positions.duplicate()
			fp[0] = np[0]
			for c in range(1, n):
				var p := parents[c]
				if involved[c] == 1:
					var d := np[c] - fp[p]
					if d.length_squared() < EPS:
						d = positions[c] - positions[p]
					d = d.normalized()
					if constraints.has(p):
						var con: Dictionary = constraints[p]
						var prev := Vector3.ZERO
						var pp := parents[p]
						if pp >= 0:
							prev = fp[p] - fp[pp]
						else:
							prev = con.get("ref", Vector3.ZERO)
						d = limit(prev, d, con)
					fp[c] = fp[p] + d * lengths[c]
				else:
					fp[c] = fp[p] + (positions[c] - positions[p])
			positions = fp
			err = effector_error()
		return err
