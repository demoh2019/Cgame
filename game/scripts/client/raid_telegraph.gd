extends Node3D
## Read-only presentation of server-authoritative raid boss ground slam.
## Never sends collision, hit or position requests; the server owns damage.

const MAX_RADIUS := 16.0
const MAX_WARNING_SECONDS := 5.0

var remaining_seconds: float = 0.0
var encounter_id: int = -1
var interrupt_damage: int = 0
var interrupt_required: int = 0
var interrupt_attackers: int = 0
var interrupt_required_attackers: int = 0
var _disk: MeshInstance3D
var _material: StandardMaterial3D
var _caption: Label3D


func _init() -> void:
	_disk = MeshInstance3D.new()
	_disk.name = "DangerDisk"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 0.06
	_disk.mesh = cylinder
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.albedo_color = Color(1.0, 0.13, 0.10, 0.37)
	_disk.material_override = _material
	add_child(_disk)
	_caption = Label3D.new()
	_caption.name = "Countdown"
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_caption.no_depth_test = true
	_caption.pixel_size = 0.012
	_caption.font_size = 34
	_caption.outline_size = 10
	_caption.modulate = Color(1.0, 0.7, 0.45)
	_caption.position.y = 1.0
	add_child(_caption)
	visible = false
	set_process(false)


static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


## Only bounded authoritative warning events may activate the danger circle.
## Terminal event IDs must match; stale events cannot erase a newer warning.
func consume(event: Dictionary, world) -> bool:
	var kind: String = str(event.get("type", ""))
	if kind in ["raid_slam", "raid_interrupted", "raid_defeated", "raid_expired"]:
		if encounter_id > 0 and int(event.get("id", -1)) == encounter_id:
			clear()
			return true
		return false
	if kind != "raid_warning" or world == null:
		return false
	for field in ["x", "z", "radius", "seconds"]:
		if not _valid_number(event.get(field, null)):
			return false
	var x: float = float(event["x"])
	var z: float = float(event["z"])
	var radius: float = float(event["radius"])
	var seconds: float = float(event["seconds"])
	var raid_id: int = int(event.get("id", -1))
	if raid_id <= 0 or radius <= 0.0 or radius > MAX_RADIUS or 			seconds <= 0.0 or seconds > MAX_WARNING_SECONDS:
		return false
	var y: float = world.height_at(x, z)
	if not is_finite(y):
		return false
	var disk_mesh := _disk.mesh as CylinderMesh
	disk_mesh.top_radius = radius
	disk_mesh.bottom_radius = radius
	position = Vector3(x, y + 0.16, z)
	remaining_seconds = seconds
	encounter_id = raid_id
	interrupt_damage = 0
	interrupt_required = 0
	interrupt_attackers = 0
	interrupt_required_attackers = 0
	_refresh_caption()
	visible = true
	set_process(true)
	return true


## Consumes only the sanitized party-only fields from a server snapshot.
## A wrong encounter or malformed tally cannot replace a valid display.
func update_interrupt(progress: Dictionary) -> bool:
	if not visible:
		return false
	if progress.is_empty():
		interrupt_damage = 0
		interrupt_required = 0
		interrupt_attackers = 0
		interrupt_required_attackers = 0
		_refresh_caption()
		return true
	for key in ["id", "damage", "required", "attackers", "required_attackers"]:
		if not progress.get(key, null) is int:
			return false
	var required: int = int(progress["required"])
	var attackers: int = int(progress["attackers"])
	var needed: int = int(progress["required_attackers"])
	var damage: int = int(progress["damage"])
	if int(progress["id"]) != encounter_id or required <= 0 or required > 1000 or \
			needed < 2 or needed > 8 or attackers < 0 or attackers > 8 or \
			damage < 0 or damage > required:
		return false
	interrupt_damage = damage
	interrupt_required = required
	interrupt_attackers = attackers
	interrupt_required_attackers = needed
	_refresh_caption()
	return true


func _refresh_caption() -> void:
	_caption.text = "DANGER  %.1fs" % remaining_seconds
	if interrupt_required > 0:
		_caption.text += "\nBREAK %d/%d  ALLIES %d/%d" % [
			interrupt_damage, interrupt_required,
			interrupt_attackers, interrupt_required_attackers]


func clear() -> void:
	remaining_seconds = 0.0
	encounter_id = -1
	interrupt_damage = 0
	interrupt_required = 0
	interrupt_attackers = 0
	interrupt_required_attackers = 0
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not visible or not is_finite(delta) or delta <= 0.0:
		return
	remaining_seconds = maxf(0.0, remaining_seconds - delta)
	if remaining_seconds <= 0.0:
		clear()
		return
	_refresh_caption()
	_material.albedo_color.a = 0.28 + 0.19 * absf(sin(remaining_seconds * 9.0))
