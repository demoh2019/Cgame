extends RefCounted
## Loot bags land with a physics-style bounce when they first appear (Unity: a dropped Rigidbody with a bouncy
## PhysicMaterial; Unreal: a spawned physics actor). Analytic damped bounce on the bag's visual mesh only: the
## entity's own position is the server's and is never touched, and Low quality skips it.

const DROP_HEIGHT := 1.4
const GRAVITY := 14.0
const RESTITUTION := 0.45
const SQUASH := 0.18
const MIN_BOUNCE := 0.03 # Metres: below this the bag rests.


## Height above the resting spot `age` seconds after being dropped (ball bouncing with restitution).
static func height(age: float, drop_height: float = DROP_HEIGHT) -> float:
	if age <= 0.0:
		return drop_height
	var fall := sqrt(2.0 * drop_height / GRAVITY)
	if age < fall:
		return drop_height - 0.5 * GRAVITY * age * age
	var t := age - fall
	var v := sqrt(2.0 * GRAVITY * drop_height) * RESTITUTION
	while true:
		var peak := v * v / (2.0 * GRAVITY)
		if peak < MIN_BOUNCE:
			return 0.0
		var flight := 2.0 * v / GRAVITY
		if t < flight:
			return v * t - 0.5 * GRAVITY * t * t
		t -= flight
		v *= RESTITUTION
	return 0.0


## Seconds until the bag is at rest.
static func settle_time(drop_height: float = DROP_HEIGHT) -> float:
	var total := sqrt(2.0 * drop_height / GRAVITY)
	var v := sqrt(2.0 * GRAVITY * drop_height) * RESTITUTION
	while v * v / (2.0 * GRAVITY) >= MIN_BOUNCE:
		total += 2.0 * v / GRAVITY
		v *= RESTITUTION
	return total


## Vertical squash factor right as the bag touches down (1 = none), recovering over a short window.
static func squash(age: float) -> float:
	var fall := sqrt(2.0 * DROP_HEIGHT / GRAVITY)
	var since := age - fall
	if since < 0.0 or since > 0.2:
		return 1.0
	return 1.0 - SQUASH * sin(since / 0.2 * PI)


## Drive the first child mesh of a bag node. `level` is the graphics tier; call every frame.
static func apply(bag: Node3D, delta: float, level: int) -> void:
	if level <= 0 or bag == null or bag.get_child_count() == 0:
		return
	var mesh := bag.get_child(0) as Node3D
	if mesh == null:
		return
	if not bag.has_meta("drop_age"):
		bag.set_meta("drop_age", 0.0)
		bag.set_meta("drop_base_y", mesh.position.y)
		bag.set_meta("drop_base_scale", mesh.scale)
	if float(bag.get_meta("drop_age")) < 0.0:
		return # Already at rest.
	var age: float = float(bag.get_meta("drop_age")) + maxf(delta, 0.0)
	if age > settle_time() + 0.3:
		mesh.position.y = float(bag.get_meta("drop_base_y"))
		mesh.scale = bag.get_meta("drop_base_scale")
		bag.set_meta("drop_age", -1.0)
		return
	bag.set_meta("drop_age", age)
	mesh.position.y = float(bag.get_meta("drop_base_y")) + height(age)
	var base_scale: Vector3 = bag.get_meta("drop_base_scale")
	mesh.scale = Vector3(base_scale.x, base_scale.y * squash(age), base_scale.z)
