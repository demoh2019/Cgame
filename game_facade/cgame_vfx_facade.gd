class_name CgameVfxFacade
extends RefCounted
## Single entry point for the VFX graph (Niagara-style emitter graphs, presets, budget, event
## bindings). Uses the native `cgame_vfx` engine module (VFXGraphAsset, VFXGraphInstance3D,
## VFXBudgetServer, VFXPresets, VFXBindings) when the engine was built with it, and otherwise
## falls back to the reference GDScript implementations in the game project. Both back ends
## accept the same graph dictionaries, so callers never branch on them.
##
## Differences hidden by the facade: native setup() returns bool, the script node returns void;
## particle_count()/profile() are get_particle_count()/get_profile() natively; budget limits are
## max_effects()/active_effects() in script and get_max_effects()/get_active_effects() natively;
## bindings use register() in script and register_binding() natively.
##
## Native-only extras (all degrade gracefully): VFXGraphAsset resources, validate(), use_gpu
## compute updates, GameplayCueQueue feeding through handle_cue_events().

const GRAPH_NODE_SCRIPT := "res://scripts/client/vfx_graph_node.gd"
const PRESETS_SCRIPT := "res://scripts/client/vfx_presets.gd"
const BUDGET_SCRIPT := "res://scripts/client/vfx_budget.gd"
const BINDINGS_SCRIPT := "res://scripts/client/vfx_bindings.gd"

const KNOWN_MODULES: PackedStringArray = [
	"spawn_rate", "spawn_burst", "initial_position_sphere", "initial_position_box",
	"initial_position_cone", "initial_velocity", "lifetime_random", "initial_color",
	"initial_size", "initial_attribute", "gravity", "drag", "curl_noise", "vortex",
	"attractor", "color_over_life", "size_over_life", "collide_plane", "kill_below_plane",
]

static var _budget: Object = null


## True when the whole native module is available.
static func is_native() -> bool:
	return ClassDB.class_exists("VFXGraphInstance3D") \
		and ClassDB.class_exists("VFXGraphAsset") \
		and ClassDB.class_exists("VFXPresets") \
		and Engine.has_singleton("VFXBudgetServer")


# ---- graph validation and assets -------------------------------------------

## Returns human readable problems of a graph dictionary (empty = valid). The fallback only
## checks structure and module names; the native validator also checks parameter types.
static func validate(graph: Dictionary) -> PackedStringArray:
	if ClassDB.class_exists("VFXGraphAsset"):
		return ClassDB.class_call_static("VFXGraphAsset", "validate_graph", graph)
	var errors := PackedStringArray()
	var emitters: Dictionary = graph.get("emitters", {"main": graph})
	if emitters.is_empty():
		errors.append("Graph has no emitters.")
	for key in emitters:
		var def: Variant = emitters[key]
		if not (def is Dictionary):
			errors.append("emitter '%s' must be a Dictionary." % key)
			continue
		for stage in ["spawn", "update"]:
			for i in (def as Dictionary).get(stage, []).size():
				var m: Variant = (def as Dictionary)[stage][i]
				if not (m is Dictionary) or not KNOWN_MODULES.has(str((m as Dictionary).get("type", ""))):
					errors.append("emitter '%s' %s[%d]: unknown module." % [key, stage, i])
	return errors


## Native VFXGraphAsset for a graph dictionary, or null when the module is unavailable.
static func make_asset(graph: Dictionary) -> Resource:
	if ClassDB.class_exists("VFXGraphAsset"):
		return ClassDB.class_call_static("VFXGraphAsset", "create_from_dictionary", graph)
	return null


# ---- presets ----------------------------------------------------------------

## Lightning ground strike graph (sparks that bounce and spawn embers on impact).
static func lightning_sparks(level: int) -> Dictionary:
	if ClassDB.class_exists("VFXPresets"):
		return ClassDB.class_call_static("VFXPresets", "lightning_sparks", level)
	return (load(PRESETS_SCRIPT) as GDScript).call("lightning_sparks", level)


## Spawns a self-freeing effect node at a world position; null when disabled or invalid.
## `asset` is a graph Dictionary (or a native VFXGraphAsset).
static func spawn(parent: Node3D, asset: Variant, at: Vector3, seed_value: int) -> Node3D:
	if ClassDB.class_exists("VFXPresets"):
		return ClassDB.class_call_static("VFXPresets", "spawn", parent, asset, at, seed_value)
	if asset is Dictionary:
		return (load(PRESETS_SCRIPT) as GDScript).call("spawn", parent, asset, at, seed_value)
	return null


# ---- graph node -------------------------------------------------------------

## Creates a graph node (not yet in the tree) playing `graph`. `one_shot` frees it when done.
## Returns null if the graph is invalid or rejected. Step it with step() or add it to the tree.
static func make_graph_node(graph: Dictionary, seed_value: int = 1, one_shot: bool = false, use_gpu: bool = false) -> Node3D:
	var node: Node3D
	if ClassDB.class_exists("VFXGraphInstance3D"):
		node = ClassDB.instantiate("VFXGraphInstance3D")
		node.set("one_shot", one_shot)
		node.set("autostart", false)
		node.set("use_gpu", use_gpu)
		if not bool(node.call("setup", graph, seed_value)):
			node.free()
			return null
		return node
	node = (load(GRAPH_NODE_SCRIPT) as GDScript).new()
	node.set("one_shot", one_shot)
	node.call("setup", graph, seed_value)
	return node


static func particle_count(node: Node3D) -> int:
	if node.has_method("get_particle_count"):
		return int(node.call("get_particle_count"))
	return int(node.call("particle_count"))


static func profile(node: Node3D) -> Dictionary:
	if node.has_method("get_profile"):
		return node.call("get_profile")
	return node.call("profile")


## True when the node runs its update on the GPU (always false for the script fallback).
static func is_gpu_active(node: Node3D) -> bool:
	return node.has_method("is_gpu_active") and bool(node.call("is_gpu_active"))


# ---- budget -----------------------------------------------------------------

## Global budget object: the native VFXBudgetServer singleton, or a shared script instance.
static func get_budget() -> Object:
	if Engine.has_singleton("VFXBudgetServer"):
		return Engine.get_singleton("VFXBudgetServer")
	if _budget == null:
		_budget = (load(BUDGET_SCRIPT) as GDScript).new()
	return _budget


static func budget_request_id(category: String, cost: int, priority: float, position: Vector3, camera_pos: Vector3) -> int:
	return int(get_budget().call("request_id", category, cost, priority, position, camera_pos))


static func budget_release(id: int) -> void:
	get_budget().call("release", id)


static func budget_set_tier(tier: int) -> void:
	get_budget().call("set_tier", tier)


static func budget_max_effects(category: String) -> int:
	var b := get_budget()
	return int(b.call("get_max_effects", category)) if b.has_method("get_max_effects") else int(b.call("max_effects", category))


static func budget_active_effects(category: String = "") -> int:
	var b := get_budget()
	return int(b.call("get_active_effects", category)) if b.has_method("get_active_effects") else int(b.call("active_effects", category))


static func budget_active_particles(category: String = "") -> int:
	var b := get_budget()
	return int(b.call("get_active_particles", category)) if b.has_method("get_active_particles") else int(b.call("active_particles", category))


# ---- event bindings ---------------------------------------------------------

static func make_bindings() -> RefCounted:
	if ClassDB.class_exists("VFXBindings"):
		return ClassDB.instantiate("VFXBindings")
	return (load(BINDINGS_SCRIPT) as GDScript).new()


static func register_binding(bindings: RefCounted, event_type: String, spec: Dictionary) -> void:
	if bindings.has_method("register_binding"):
		bindings.call("register_binding", event_type, spec)
	else:
		bindings.call("register", event_type, spec)


## Feeds GameplayCueQueue.take_events() output into the bindings (native module only; the
## script bindings translate the cues here instead). Returns how many effects were started.
static func handle_cue_events(bindings: RefCounted, cue_events: Array, spawn_callable: Callable, position: Vector3 = Vector3.ZERO) -> int:
	if bindings.has_method("handle_cue_events"):
		return int(bindings.call("handle_cue_events", cue_events, spawn_callable, position))
	var started := 0
	for cue in cue_events:
		var kind := str((cue as Dictionary).get("event", "executed"))
		if kind == "updated" or not (cue as Dictionary).has("tag"):
			continue
		var payload: Dictionary = (cue as Dictionary).duplicate()
		payload["position"] = position
		var event_type := str(cue["tag"]) + (":stopped" if kind == "stopped" else "")
		started += int(bindings.call("handle", {"type": event_type, "payload": payload, "position": position}, spawn_callable))
	return started
