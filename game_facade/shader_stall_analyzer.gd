extends RefCounted
## Facade for CgameShaderStallAnalyzer (native) with scripts/tools/shader_stall_analyzer.gd as
## GDScript fallback.
##
## Native bonus: start_auto_sampling() makes the engine read the RenderingServer pipeline
## compilation counters and the frame time every main loop iteration, no per-frame script needed.
## Without the native class start_auto_sampling() is a no-op and frames must be fed manually.

const FALLBACK_PATH := "res://scripts/tools/shader_stall_analyzer.gd"

var _impl: Object = null
var _native: bool = false

var spike_factor: float:
	get:
		return _impl.spike_factor if _impl != null else 2.0
	set(value):
		if _impl != null:
			_impl.spike_factor = value

var min_extra_ms: float:
	get:
		return _impl.min_extra_ms if _impl != null else 4.0
	set(value):
		if _impl != null:
			_impl.min_extra_ms = value


func _init() -> void:
	if ClassDB.class_exists("CgameShaderStallAnalyzer"):
		_impl = ClassDB.instantiate("CgameShaderStallAnalyzer")
		_native = true
	elif ResourceLoader.exists(FALLBACK_PATH):
		_impl = (load(FALLBACK_PATH) as GDScript).new()
	else:
		push_error("ShaderStallAnalyzer facade: no backend available")


func is_native() -> bool:
	return _native


## compiles = pipelines compiled during this frame; materials = first drawn this frame.
func feed(index: int, ms: float, compiles: int, first_drawn_materials: Array = []) -> void:
	if _impl == null:
		return
	if _native:
		_impl.feed(index, ms, compiles, PackedStringArray(first_drawn_materials))
	else:
		_impl.feed(index, ms, compiles, first_drawn_materials)


func feed_cumulative(index: int, ms: float, total_compiles: int, first_drawn_materials: Array = []) -> void:
	if _impl == null:
		return
	if _native:
		_impl.feed_cumulative(index, ms, total_compiles, PackedStringArray(first_drawn_materials))
	else:
		_impl.feed_cumulative(index, ms, total_compiles, first_drawn_materials)


## Sum of RenderingServer pipeline compilation counters.
static func live_compile_total() -> int:
	if ClassDB.class_exists("CgameShaderStallAnalyzer"):
		return ClassDB.instantiate("CgameShaderStallAnalyzer").call("live_compile_total")
	if ResourceLoader.exists(FALLBACK_PATH):
		return (load(FALLBACK_PATH) as GDScript).live_compile_total()
	return 0


func baseline_ms() -> float:
	return _impl.baseline_ms() if _impl != null else 0.0


func analyze() -> Dictionary:
	return _impl.analyze() if _impl != null else {}


## Native only: sample counters and frame time automatically every main loop iteration.
func start_auto_sampling() -> bool:
	if _native:
		_impl.start_auto_sampling()
	return _native


func stop_auto_sampling() -> void:
	if _native:
		_impl.stop_auto_sampling()


## Report a material first drawn this frame (consumed by the next automatic sample).
func note_material(material_name: String) -> void:
	if _native:
		_impl.note_material(material_name)
