extends RefCounted
## Cloth authoring over res://scripts/shared/xpbd_cloth.gd: pin / mass / compliance painting,
## automatic skeleton binding, presets and rest-pose baking. Original code.
## Reads and writes the cloth's underscore-prefixed arrays directly because the library has no
## public setters for per-particle mass or rest lengths.

const XPBDCloth = preload("res://scripts/shared/xpbd_cloth.gd")

## Per-particle painted values (empty until painted). mass in kg, compliance in m/N.
var mass_map := PackedFloat32Array()
var compliance_map := PackedFloat32Array()


static func falloff(dist: float, radius: float) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	return 1.0 - dist / radius


## Pins (or unpins) every particle within `radius` of `center` at its current position.
## Returns the affected particle indices.
func paint_pins(cloth: RefCounted, center: Vector3, radius: float, pinned: bool) -> PackedInt32Array:
	var hit := PackedInt32Array()
	var pts: PackedVector3Array = cloth.call("positions")
	for i in pts.size():
		if pts[i].distance_to(center) > radius:
			continue
		hit.append(i)
		if pinned:
			cloth.call("pin", i, pts[i])
		else:
			cloth.call("unpin", i)
	return hit


func paint_mass(cloth: RefCounted, center: Vector3, radius: float, mass: float, strength: float = 1.0) -> int:
	var pts: PackedVector3Array = cloth.call("positions")
	_ensure_maps(cloth, pts.size())
	var count: int = 0
	var inv_base: PackedFloat32Array = cloth.get("_base_inv_mass")
	var inv_now: PackedFloat32Array = cloth.get("_inv_mass")
	for i in pts.size():
		var w: float = falloff(pts[i].distance_to(center), radius) * strength
		if w <= 0.0:
			continue
		var cur: float = mass_map[i]
		mass_map[i] = lerpf(cur, maxf(mass, 0.000001), minf(w * 2.0, 1.0))
		inv_base[i] = 1.0 / mass_map[i]
		if not bool(cloth.call("is_pinned", i)):
			inv_now[i] = inv_base[i]
		count += 1
	cloth.set("_base_inv_mass", inv_base)
	cloth.set("_inv_mass", inv_now)
	return count


func paint_compliance(cloth: RefCounted, center: Vector3, radius: float, compliance: float, strength: float = 1.0) -> int:
	var pts: PackedVector3Array = cloth.call("positions")
	_ensure_maps(cloth, pts.size())
	var count: int = 0
	for i in pts.size():
		var w: float = falloff(pts[i].distance_to(center), radius) * strength
		if w <= 0.0:
			continue
		compliance_map[i] = lerpf(compliance_map[i], compliance, minf(w * 2.0, 1.0))
		count += 1
	return count


## The solver has per-kind (not per-particle) compliance, so the painted map is reduced to a
## scale on the bend compliance: scale = map mean / current bend compliance (bend dominates drape).
func apply_compliance_map(cloth: RefCounted) -> float:
	if compliance_map.is_empty():
		return float(cloth.get("compliance_bend"))
	var sum: float = 0.0
	for v in compliance_map:
		sum += v
	var mean: float = sum / float(compliance_map.size())
	cloth.set("compliance_bend", mean)
	return mean


func _ensure_maps(cloth: RefCounted, n: int) -> void:
	if mass_map.size() != n:
		var inv: PackedFloat32Array = cloth.get("_base_inv_mass")
		mass_map.resize(n)
		for i in n:
			mass_map[i] = 1.0 / maxf(inv[i], 0.000001) if inv[i] > 0.0 else 1.0
	if compliance_map.size() != n:
		var base: float = float(cloth.get("compliance_bend"))
		compliance_map.resize(n)
		compliance_map.fill(base)


## Maps EVERY particle to its nearest bone name: {particle_index: bone_name}.
## `radius` is not a cut-off here; see pin_near_bones for the radius-limited step.
func auto_attach_to_skeleton(cloth: RefCounted, bone_positions: Dictionary, _radius: float = 0.0) -> Dictionary:
	var map: Dictionary = {}
	if bone_positions.is_empty():
		return map
	var pts: PackedVector3Array = cloth.call("positions")
	for i in pts.size():
		var best: String = ""
		var best_d: float = INF
		for bone in bone_positions:
			var d: float = pts[i].distance_squared_to(bone_positions[bone] as Vector3)
			if d < best_d:
				best_d = d
				best = str(bone)
		map[i] = best
	return map


## Attaches particles within `radius` of their mapped bone to follow that bone.
## `lookup` is a Callable(bone_name: String) -> Vector3 (live bone position); when invalid the
## static bone_positions are used. Returns the attached particle indices.
func pin_near_bones(cloth: RefCounted, mapping: Dictionary, bone_positions: Dictionary, radius: float, lookup: Callable = Callable()) -> PackedInt32Array:
	var out := PackedInt32Array()
	var pts: PackedVector3Array = cloth.call("positions")
	for key in mapping:
		var i: int = key as int
		var bone: String = mapping[key] as String
		if pts[i].distance_to(bone_positions[bone] as Vector3) > radius:
			continue
		var offset: Vector3 = pts[i] - (bone_positions[bone] as Vector3)
		var fn: Callable
		if lookup.is_valid():
			fn = func() -> Vector3: return (lookup.call(bone) as Vector3) + offset
		else:
			var fixed: Vector3 = pts[i]
			fn = func() -> Vector3: return fixed
		cloth.call("attach", i, fn)
		out.append(i)
	return out


## Named configs: {"width_cells","height_cells","spacing","mass","pins":"top_row|left_column|corners",
## "gravity","wind","drag","compliance_stretch/shear/bend","iterations"}. {} when unknown.
func preset(preset_name: String) -> Dictionary:
	match preset_name:
		"cape":
			return {"width_cells": 10, "height_cells": 16, "spacing": 0.08, "mass": 0.05, "pins": "top_row",
				"gravity": Vector3(0, -9.81, 0), "wind": Vector3.ZERO, "drag": 0.15,
				"compliance_stretch": 0.0, "compliance_shear": 0.0002, "compliance_bend": 0.05, "iterations": 2}
		"flag":
			return {"width_cells": 18, "height_cells": 12, "spacing": 0.07, "mass": 0.03, "pins": "left_column",
				"gravity": Vector3(0, -9.81, 0), "wind": Vector3(3, 0, 1), "drag": 0.3,
				"compliance_stretch": 0.0, "compliance_shear": 0.0001, "compliance_bend": 0.02, "iterations": 1}
		"skirt":
			return {"width_cells": 20, "height_cells": 12, "spacing": 0.05, "mass": 0.06, "pins": "top_row",
				"gravity": Vector3(0, -9.81, 0), "wind": Vector3.ZERO, "drag": 0.1,
				"compliance_stretch": 0.0, "compliance_shear": 0.0005, "compliance_bend": 0.08, "iterations": 2}
	return {}


## Builds a cloth from a preset (grid + parameters + pins). Returns null for unknown presets.
func build_from_preset(preset_name: String, origin: Transform3D = Transform3D.IDENTITY) -> RefCounted:
	var cfg: Dictionary = preset(preset_name)
	if cfg.is_empty():
		return null
	var cloth: RefCounted = XPBDCloth.new()
	cloth.call("setup_grid", cfg["width_cells"] as int, cfg["height_cells"] as int, cfg["spacing"] as float, origin, cfg["mass"] as float)
	cloth.set("gravity", cfg["gravity"] as Vector3)
	cloth.set("wind", cfg["wind"] as Vector3)
	cloth.set("drag", cfg["drag"] as float)
	cloth.set("compliance_stretch", cfg["compliance_stretch"] as float)
	cloth.set("compliance_shear", cfg["compliance_shear"] as float)
	cloth.set("compliance_bend", cfg["compliance_bend"] as float)
	cloth.set("iterations", cfg["iterations"] as int)
	var cols: int = cloth.call("columns")
	var rows: int = cloth.call("rows")
	var pts: PackedVector3Array = cloth.call("positions")
	match cfg["pins"] as String:
		"top_row":
			for i in cols:
				var k: int = cloth.call("index_of", i, 0)
				cloth.call("pin", k, pts[k])
		"left_column":
			for j in rows:
				var k2: int = cloth.call("index_of", 0, j)
				cloth.call("pin", k2, pts[k2])
	return cloth


## Makes the current particle positions the rest pose: zero velocity and re-derive every
## constraint rest length from the current geometry.
func bake_rest_pose(cloth: RefCounted) -> void:
	var pos: PackedVector3Array = cloth.get("_pos")
	cloth.set("_rest_pos", pos.duplicate())
	cloth.set("_prev", pos.duplicate())
	var vel: PackedVector3Array = cloth.get("_vel")
	vel.fill(Vector3.ZERO)
	cloth.set("_vel", vel)
	var ca: PackedInt32Array = cloth.get("_ca")
	var cb: PackedInt32Array = cloth.get("_cb")
	var rest: PackedFloat32Array = cloth.get("_crest")
	for c in ca.size():
		rest[c] = maxf(pos[ca[c]].distance_to(pos[cb[c]]), 0.000001)
	cloth.set("_crest", rest)
