class_name CgameFluidsFacade
extends RefCounted
## Single entry point for the fluid solvers. Uses the native C++ classes of the
## `cgame_fluids` engine module (CgameSPHFluid, CgameFLIPFluid, CgameSmokeSim,
## CgameShallowWater, CgameFFTOcean) when the running engine has them, and falls back to the
## GDScript implementations under res://scripts/shared/ otherwise. Both back ends expose the
## same method names, so callers only differ in how the objects are created, which this class
## hides. Pass `force_gdscript = true` to compare back ends or to debug.
##
## Differences callers must respect (the facade helpers below paper over them):
##  - Native objects keep their arrays private: use `smoke_field()` instead of reading
##    `sim.density` / `sim.vx` directly, and `flip_velocities()` / `sph_positions()` etc.
##  - `CgameFFTOcean.fft_1d` returns [re, im] instead of mutating its arguments:
##    use `fft_1d()` below.
##  - Native smoke `sample()` takes a field enum; use `smoke_sample()`.

const SPH_SCRIPT := "res://scripts/shared/sph_fluid.gd"
const FLIP_SCRIPT := "res://scripts/shared/flip_fluid.gd"
const SMOKE_SCRIPT := "res://scripts/shared/smoke_sim.gd"
const SHALLOW_SCRIPT := "res://scripts/shared/shallow_water.gd"
const FFT_SCRIPT := "res://scripts/shared/fft_ocean.gd"

## Cell classification values (identical in both back ends).
const CELL_FLUID := 0
const CELL_AIR := 1
const CELL_SOLID := 2

## Field selectors for smoke_field() / smoke_sample() (match CgameSmokeSim.Field).
enum SmokeField { DENSITY, TEMPERATURE, FUEL, VELOCITY_X, VELOCITY_Y, VELOCITY_Z }


## True when the engine was built with the cgame_fluids module.
static func is_native() -> bool:
	return ClassDB.class_exists("CgameSPHFluid")


static func _use_native(force_gdscript: bool, native_class: String) -> bool:
	return not force_gdscript and ClassDB.class_exists(native_class)


static func make_sph(spacing: float = 0.1, bounds_min: Vector3 = Vector3.ZERO, bounds_max: Vector3 = Vector3(2.0, 2.0, 2.0), force_gdscript: bool = false) -> Object:
	if _use_native(force_gdscript, "CgameSPHFluid"):
		var native: Object = ClassDB.instantiate("CgameSPHFluid")
		native.setup(spacing, bounds_min, bounds_max)
		return native
	return load(SPH_SCRIPT).new(spacing, bounds_min, bounds_max)


static func make_flip(cols: int = 32, rows: int = 32, cell_size: float = 0.1, force_gdscript: bool = false) -> Object:
	if _use_native(force_gdscript, "CgameFLIPFluid"):
		var native: Object = ClassDB.instantiate("CgameFLIPFluid")
		native.setup(cols, rows, cell_size)
		return native
	return load(FLIP_SCRIPT).new(cols, rows, cell_size)


static func make_smoke(grid_size: int = 24, force_gdscript: bool = false) -> Object:
	if _use_native(force_gdscript, "CgameSmokeSim"):
		var native: Object = ClassDB.instantiate("CgameSmokeSim")
		native.setup(grid_size)
		return native
	return load(SMOKE_SCRIPT).new(grid_size)


static func make_shallow_water(width: int, height: int, cell_size: float, terrain: PackedFloat32Array, force_gdscript: bool = false) -> Object:
	var sim: Object
	if _use_native(force_gdscript, "CgameShallowWater"):
		sim = ClassDB.instantiate("CgameShallowWater")
	else:
		sim = load(SHALLOW_SCRIPT).new()
	sim.setup(width, height, cell_size, terrain)
	return sim


static func make_fft_ocean(grid: int, patch: float, wind: Vector2, amplitude: float, ocean_seed: int, force_gdscript: bool = false) -> Object:
	var ocean: Object
	if _use_native(force_gdscript, "CgameFFTOcean"):
		ocean = ClassDB.instantiate("CgameFFTOcean")
	else:
		ocean = load(FFT_SCRIPT).new()
	ocean.setup(grid, patch, wind, amplitude, ocean_seed)
	return ocean


# --- back-end neutral helpers -------------------------------------------------

## Particle positions of an SPH fluid (both back ends provide positions()).
static func sph_positions(sim: Object) -> PackedVector3Array:
	return sim.positions()


## Particle positions of a FLIP fluid.
static func flip_positions(sim: Object) -> PackedVector2Array:
	return sim.particle_positions()


## Particle velocities of a FLIP fluid.
static func flip_velocities(sim: Object) -> PackedVector2Array:
	if sim.has_method("particle_velocities"):
		return sim.particle_velocities()
	return sim.pvel


## Copy of one smoke field for all cells (index = x + size * (y + size * z)).
static func smoke_field(sim: Object, field: SmokeField) -> PackedFloat32Array:
	if sim.has_method("get_field"):
		return sim.get_field(field)
	match field:
		SmokeField.DENSITY:
			return sim.density
		SmokeField.TEMPERATURE:
			return sim.temperature
		SmokeField.FUEL:
			return sim.fuel
		SmokeField.VELOCITY_X:
			return sim.vx
		SmokeField.VELOCITY_Y:
			return sim.vy
		_:
			return sim.vz


## Trilinear sample of a smoke field at a position in cell coordinates.
static func smoke_sample(sim: Object, field: SmokeField, position: Vector3) -> float:
	if sim.has_method("get_field"):
		return sim.sample(field, position)
	return sim.sample(smoke_field(sim, field), position.x, position.y, position.z)


## Writes a velocity into a smoke cell.
static func smoke_set_velocity(sim: Object, cell: Vector3i, velocity: Vector3) -> void:
	if sim.has_method("set_velocity"):
		sim.set_velocity(cell, velocity)
		return
	var i: int = sim.index(cell.x, cell.y, cell.z)
	sim.vx[i] = velocity.x
	sim.vy[i] = velocity.y
	sim.vz[i] = velocity.z


## Radix-2 FFT of a complex signal. Returns [re, im] with the transformed copies (the
## inputs are never modified, unlike FFTOcean.fft_1d in the GDScript back end).
static func fft_1d(re: PackedFloat32Array, im: PackedFloat32Array, inverse: bool, force_gdscript: bool = false) -> Array:
	if _use_native(force_gdscript, "CgameFFTOcean"):
		# Bound static methods can be called through any instance of the class.
		var native: Object = ClassDB.instantiate("CgameFFTOcean")
		return native.call("fft_1d", re, im, inverse)
	return _fft_gd(re, im, inverse)


static func _fft_gd(re: PackedFloat32Array, im: PackedFloat32Array, inverse: bool) -> Array:
	var out_re: PackedFloat32Array = re.duplicate()
	var out_im: PackedFloat32Array = im.duplicate()
	load(FFT_SCRIPT).fft_1d(out_re, out_im, inverse)
	return [out_re, out_im]
