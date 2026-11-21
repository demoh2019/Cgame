extends RefCounted
## Facade over the client rendering libraries.
##
## Every function uses the native engine class from modules/cgame_rendering when the engine was
## built with it (checked with ClassDB), and otherwise falls back to the original GDScript library
## in res://scripts/client. Both back ends keep the same semantics, so game code is written once:
##
##     const Gfx = preload("res://game_facade/cgame_rendering.gd")
##     Gfx.frame_pacing_apply(quality_level)
##     var report = Gfx.gpu_report_new()
##
## The facade has no class_name and the fallback scripts are loaded lazily with load(), so a build
## without the native module never needs them at parse time. Instances returned by the *_new()
## functions share the method names of both back ends (documented per function below).
## Differences that cannot be hidden are wrapped here, for example the native
## CgameAreaLights.register_light() versus AreaLights.register().

## Fallback script of every feature. Keys are the native class names.
const SCRIPT_PATHS: Dictionary = {
	"CgameImpostorBaker": "res://scripts/client/impostor_baker.gd",
	"ImpostorField3D": "res://scripts/client/impostor_field.gd",
	"CgameShaderWarmup": "res://scripts/client/shader_warmup.gd",
	"CgameFoveatedShading": "res://scripts/client/graphics_foveated_shading.gd",
	"CgameFramePacing": "res://scripts/client/graphics_frame_pacing.gd",
	"CgameHDROutput": "res://scripts/client/graphics_hdr_output.gd",
	"CgameAreaLights": "res://scripts/client/graphics_area_lights.gd",
	"CgameVRAMBudget": "res://scripts/client/graphics_vram_budget.gd",
	"CgameGPUResourceReport": "res://scripts/client/gpu_resource_report.gd",
	"CgameRTEffect": "res://scripts/client/rt_compositor_effect.gd",
	"CgameInstanceCulling": "res://scripts/client/gpu_instance_culling.gd",
}
const RT_DRIVER_PATH: String = "res://scripts/client/rt_effects.gd"

static var _scripts: Dictionary = {}


## True when the engine provides the native implementation of `native_class`.
static func is_native(native_class: StringName) -> bool:
	return ClassDB.class_exists(native_class)


## Names of the features currently backed by native code.
static func native_features() -> PackedStringArray:
	var result := PackedStringArray()
	for key: String in SCRIPT_PATHS:
		if is_native(key):
			result.append(key)
	return result


static func _script(native_class: String) -> Variant:
	if not _scripts.has(native_class):
		_scripts[native_class] = load(SCRIPT_PATHS[native_class]) as Script
	return _scripts[native_class]


## ClassDB.class_call_static() is variadic, so it is reached through a Callable to pass an Array.
static func _native(native_class: String, method: StringName, args: Array) -> Variant:
	return Callable(ClassDB, &"class_call_static").callv([native_class, method] + args)


## Calls a static method of the native class, or of its GDScript fallback.
static func _static_call(native_class: String, native_method: StringName, script_method: StringName, args: Array = []) -> Variant:
	if is_native(native_class):
		return _native(native_class, native_method, args)
	return _script(native_class).callv(script_method, args)


static func _new_instance(native_class: String) -> Object:
	if is_native(native_class):
		return ClassDB.instantiate(native_class)
	return _script(native_class).new()


# --- Impostors -------------------------------------------------------------------------------

## Square bake extent (x) and vertical centre (y) of a mesh.
static func impostor_frame_size(mesh: Mesh) -> Vector2:
	if is_native("CgameImpostorBaker"):
		return _native("CgameImpostorBaker", "frame_size", [mesh])
	return _script("CgameImpostorBaker").frame_size(mesh)


## Calls done(atlas) once the mesh is baked (immediately when cached).
static func impostor_request(mesh: Mesh, tree: SceneTree, done: Callable) -> void:
	if is_native("CgameImpostorBaker"):
		_native("CgameImpostorBaker", "request", [mesh, tree, done])
	else:
		_script("CgameImpostorBaker").request(mesh, tree, done)


static func impostor_material(mesh: Mesh, atlas: Texture2D) -> ShaderMaterial:
	if is_native("CgameImpostorBaker"):
		return _native("CgameImpostorBaker", "material_for", [mesh, atlas])
	return _script("CgameImpostorBaker").material_for(mesh, atlas)


static func impostor_clear_cache() -> void:
	if is_native("CgameImpostorBaker"):
		_native("CgameImpostorBaker", "clear_cache", [])
	else:
		_script("CgameImpostorBaker").clear_cache()


## Selects the impostor range tier (0 = no impostors .. 3 = longest range).
static func impostor_configure(level: int) -> void:
	if is_native("ImpostorField3D"):
		_native("ImpostorField3D", "configure", [level])
	else:
		_script("ImpostorField3D").configure(level)


## Adds a far-LOD impostor field for `mesh` at `transforms` under `parent`. Returns the
## MultiMeshInstance3D (ImpostorField3D when native), or null when nothing would be drawn.
static func impostor_field_add(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D],
		mesh_range: float, fade_margin: float = 8.0) -> MultiMeshInstance3D:
	if is_native("ImpostorField3D"):
		return _native("ImpostorField3D", "add", [parent, mesh, transforms, mesh_range, fade_margin])
	return _script("ImpostorField3D").add(parent, mesh, transforms, mesh_range, fade_margin)


# --- Shader warm-up --------------------------------------------------------------------------

## Attaches the warm-up rig to the camera (null on headless). The rig frees itself.
static func shader_warmup_start(camera: Camera3D) -> Node3D:
	if is_native("CgameShaderWarmup"):
		return _native("CgameShaderWarmup", "start", [camera, PackedStringArray()])
	return _script("CgameShaderWarmup").start(camera)


## {canvas, mesh, surface, draw, specialization, total} pipeline compile counters.
static func pipeline_compile_counters() -> Dictionary:
	if is_native("CgameShaderWarmup"):
		return _native("CgameShaderWarmup", "get_pipeline_compile_counters", [])
	var canvas := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS))
	var mesh := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH))
	var surface := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE))
	var draw := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW))
	var specialization := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION))
	return {
		"canvas": canvas, "mesh": mesh, "surface": surface, "draw": draw,
		"specialization": specialization,
		"total": canvas + mesh + surface + draw + specialization,
	}


# --- Foveated shading / frame pacing / HDR ---------------------------------------------------

static func foveated_settings(level: int, rendering_method: String) -> Dictionary:
	return _static_call("CgameFoveatedShading", &"settings", &"settings", [level, rendering_method])


static func foveated_build_map(size: Vector2i, inner: float, outer: float) -> Image:
	return _static_call("CgameFoveatedShading", &"build_map", &"build_map", [size, inner, outer])


## Applies VRS to the viewport; true when a rate map was assigned.
static func foveated_apply(viewport: Viewport, level: int, rendering_method: String) -> bool:
	return _static_call("CgameFoveatedShading", &"apply", &"apply", [viewport, level, rendering_method])


static func frame_pacing_settings(level: int, refresh_hz: float) -> Dictionary:
	return _static_call("CgameFramePacing", &"settings", &"settings", [level, refresh_hz])


static func frame_pacing_apply(level: int) -> Dictionary:
	return _static_call("CgameFramePacing", &"apply", &"apply", [level])


static func hdr_wanted(level: int, rendering_method: String, supported: bool) -> bool:
	return _static_call("CgameHDROutput", &"wanted", &"wanted", [level, rendering_method, supported])


static func hdr_apply(level: int, rendering_method: String) -> bool:
	return _static_call("CgameHDROutput", &"apply", &"apply", [level, rendering_method])


# --- Area lights -----------------------------------------------------------------------------

static func area_lights_configure(level: int, tree: SceneTree) -> void:
	_static_call("CgameAreaLights", &"configure", &"configure", [level, tree])


static func area_lights_register(light: Light3D, emitter_radius: float) -> void:
	_static_call("CgameAreaLights", &"register_light", &"register", [light, emitter_radius])


static func area_lights_size_for(level: int, emitter_radius: float) -> float:
	return _static_call("CgameAreaLights", &"size_for", &"size_for", [level, emitter_radius])


static func area_lights_filter_quality(level: int) -> int:
	return _static_call("CgameAreaLights", &"filter_quality", &"filter_quality", [level])


# --- VRAM budget / GPU report ----------------------------------------------------------------

## New pressure tracker. Methods: sample(used, level, delta) -> bool (both back ends).
static func vram_budget_new() -> RefCounted:
	return _new_instance("CgameVRAMBudget")


static func vram_budget_bytes(level: int) -> float:
	return _static_call("CgameVRAMBudget", &"budget_bytes", &"budget_bytes", [level])


static func vram_used_bytes() -> float:
	return _static_call("CgameVRAMBudget", &"used_bytes", &"used_bytes")


static func vram_upgrade_allowed(used: float, level: int) -> bool:
	return _static_call("CgameVRAMBudget", &"upgrade_allowed", &"upgrade_allowed", [used, level])


## New report. Methods: collect(root), snapshot(), top(n, kind), timeline_push(), timeline(),
## timeline_peak(key), to_markdown(top_n) (both back ends).
static func gpu_report_new() -> RefCounted:
	return _new_instance("CgameGPUResourceReport")


static func texture_bytes(width: int, height: int, format: int, mipmaps: bool, layers: int = 1) -> int:
	return _static_call("CgameGPUResourceReport", &"texture_bytes", &"texture_bytes", [width, height, format, mipmaps, layers])


static func format_bytes(bytes: int) -> String:
	return _static_call("CgameGPUResourceReport", &"format_bytes", &"format_bytes", [bytes])


# --- Ray-traced shadows / AO -----------------------------------------------------------------

## Quality settings dictionary of the ray-traced shadow/AO driver.
static func rt_settings(level: int, rendering_method: String = "forward_plus") -> Dictionary:
	if is_native("CgameRTEffect"):
		return _native("CgameRTEffect", "settings", [level, rendering_method])
	var driver: Variant = load(RT_DRIVER_PATH)
	return driver.settings(level, rendering_method)


## New CompositorEffect (CgameRTEffect natively). Methods: configure(settings), submit(instances,
## geometry, sun_dir, sun_radius), take_evicted_keys(), is_active() (both back ends). The scene
## driver in rt_effects.gd feeds either effect; it is plain GDScript and has no native twin.
static func rt_effect_new() -> CompositorEffect:
	return _new_instance("CgameRTEffect")


# --- Instance culling ------------------------------------------------------------------------

## New culler. Methods: cull(aabbs, planes, hiz), cull_spheres, cull_packed, cull_cpu, shutdown().
static func instance_culling_new() -> RefCounted:
	return _new_instance("CgameInstanceCulling")
