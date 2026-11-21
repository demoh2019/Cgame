extends RefCounted
## Facade over the native cgame_crowd module with a GDScript fallback.
##
## Uses CgameCrowdAvoidance / CgameMassEntity / CgamePopulationLOD when the engine
## provides them (ClassDB.class_exists), otherwise the GDScript implementations under
## res://scripts/shared/. Stock Godot and older Cgame engines therefore keep working.
##
## Common API surface (identical on both backends):
##   - CrowdAvoidance.compute_velocities(...)        -> compute_velocities(...)
##   - MassEntity: define_fragment, create, destroy, is_alive, get_value, set_value,
##     query, add_processor, remove_processor, processor_order, run, entity_count,
##     archetype_count; plus the facade helpers mass_create_many,
##     mass_add_integrate_processor and mass_add_crowd_avoidance_processor.
##   - PopulationLOD: setup, add_herd, tick, promote, demote, stats, herd_ids, ...
##     and the properties max_herd_size, night, concrete_count, ...;
##     use herd_info() instead of the GDScript-only `herds` dictionary.
## Differences: native MassEntity.query() returns snapshots (write through set_value or
## processors) and ignores the `parallel` flag for script callables.

const _CrowdFallback = preload("res://scripts/shared/crowd_avoidance.gd")
const _MassFallback = preload("res://scripts/shared/mass_entity.gd")
const _PopulationFallback = preload("res://scripts/shared/population_lod.gd")

static var _native_crowd: Object = null


static func has_native_crowd() -> bool:
	return ClassDB.class_exists("CgameCrowdAvoidance")


static func has_native_mass_entity() -> bool:
	return ClassDB.class_exists("CgameMassEntity")


static func has_native_population_lod() -> bool:
	return ClassDB.class_exists("CgamePopulationLOD")


## Returns new velocities that avoid collisions (ORCA). Same signature as crowd_avoidance.gd.
static func compute_velocities(positions: PackedVector2Array, velocities: PackedVector2Array,
		preferred: PackedVector2Array, radius: float, max_speed: float, time_horizon: float,
		neighbor_dist: float, max_neighbors: int, time_step: float = 0.1) -> PackedVector2Array:
	if has_native_crowd():
		if _native_crowd == null:
			_native_crowd = ClassDB.instantiate("CgameCrowdAvoidance")
		# Static native methods are callable through an instance.
		return _native_crowd.call("compute_velocities", positions, velocities, preferred,
				radius, max_speed, time_horizon, neighbor_dist, max_neighbors, time_step)
	return _CrowdFallback.compute_velocities(positions, velocities, preferred, radius,
			max_speed, time_horizon, neighbor_dist, max_neighbors, time_step)


# --- MassEntity ----------------------------------------------------------------

## New world (native CgameMassEntity when available, else the GDScript MassEntity).
static func make_mass_entity() -> Object:
	if has_native_mass_entity():
		return ClassDB.instantiate("CgameMassEntity")
	return _MassFallback.new()


## Creates `count` entities with the same fragment values. Returns their ids.
static func mass_create_many(world: Object, fragments: Dictionary, count: int) -> PackedInt64Array:
	if world.has_method("create_many"):
		return world.create_many(fragments, count)
	var ids := PackedInt64Array()
	for i in count:
		ids.append(world.create(fragments))
	return ids


## position += velocity * delta for every entity with both Vector3 fragments.
static func mass_add_integrate_processor(world: Object, processor_name: String,
		position_fragment: String, velocity_fragment: String,
		depends_on: PackedStringArray = PackedStringArray()) -> void:
	if world.has_method("add_integrate_processor"):
		world.add_integrate_processor(processor_name, position_fragment, velocity_fragment, depends_on)
		return
	world.add_processor(processor_name, PackedStringArray([position_fragment, velocity_fragment]),
			_fallback_integrate.bind(position_fragment, velocity_fragment), depends_on)


## ORCA step over the X/Z plane. The fallback runs per archetype chunk; the native
## processor handles all archetypes as one crowd.
static func mass_add_crowd_avoidance_processor(world: Object, processor_name: String,
		position_fragment: String, velocity_fragment: String, preferred_fragment: String,
		radius: float, max_speed: float, time_horizon: float, neighbor_dist: float,
		max_neighbors: int, depends_on: PackedStringArray = PackedStringArray()) -> void:
	if world.has_method("add_crowd_avoidance_processor"):
		world.add_crowd_avoidance_processor(processor_name, position_fragment, velocity_fragment,
				preferred_fragment, radius, max_speed, time_horizon, neighbor_dist, max_neighbors,
				depends_on, true)
		return
	world.add_processor(processor_name,
			PackedStringArray([position_fragment, velocity_fragment, preferred_fragment]),
			_fallback_crowd.bind(position_fragment, velocity_fragment, preferred_fragment,
					radius, max_speed, time_horizon, neighbor_dist, max_neighbors),
			depends_on)


static func _fallback_integrate(chunk: Dictionary, count: int, delta: float,
		position_fragment: String, velocity_fragment: String) -> void:
	var pos: PackedVector3Array = chunk[position_fragment]
	var vel: PackedVector3Array = chunk[velocity_fragment]
	for i in count:
		pos[i] = pos[i] + vel[i] * delta
	chunk[position_fragment] = pos


static func _fallback_crowd(chunk: Dictionary, count: int, delta: float,
		position_fragment: String, velocity_fragment: String, preferred_fragment: String,
		radius: float, max_speed: float, time_horizon: float, neighbor_dist: float,
		max_neighbors: int) -> void:
	var pos: PackedVector3Array = chunk[position_fragment]
	var vel: PackedVector3Array = chunk[velocity_fragment]
	var pref: PackedVector3Array = chunk[preferred_fragment]
	var p2 := PackedVector2Array()
	var v2 := PackedVector2Array()
	var f2 := PackedVector2Array()
	p2.resize(count)
	v2.resize(count)
	f2.resize(count)
	for i in count:
		p2[i] = Vector2(pos[i].x, pos[i].z)
		v2[i] = Vector2(vel[i].x, vel[i].z)
		f2[i] = Vector2(pref[i].x, pref[i].z)
	var out := _CrowdFallback.compute_velocities(p2, v2, f2, radius, max_speed, time_horizon,
			neighbor_dist, max_neighbors, maxf(delta, 0.0001))
	for i in count:
		vel[i] = Vector3(out[i].x, vel[i].y, out[i].y)
	chunk[velocity_fragment] = vel


# --- Population LOD --------------------------------------------------------------

## New population simulation (native CgamePopulationLOD when available).
static func make_population_lod() -> Object:
	if has_native_population_lod():
		return ClassDB.instantiate("CgamePopulationLOD")
	return _PopulationFallback.new()


## Herd snapshot ({id, region, count, comp, heading, state, pos, ...}) on either backend.
static func herd_info(population: Object, id: int) -> Dictionary:
	if population.has_method("get_herd"):
		return population.get_herd(id)
	var herds: Dictionary = population.herds
	return (herds[id] as Dictionary).duplicate(true) if herds.has(id) else {}
