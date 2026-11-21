class_name CgameStreaming
extends RefCounted
## Facade over the open-world streaming / rendering-data libraries.
##
## Every factory returns the native engine class from modules/cgame_streaming when the
## engine was built with it, and otherwise falls back to the original GDScript library
## (res://scripts/shared/*.gd, res://scripts/client/virtual_texture.gd). Both back ends
## expose the same method names and semantics, so game code can be written once:
##
##     var queue := CgameStreaming.make_stream_requests()
##     queue.request(Vector2i(3, 4), 1.0, generation)
##
## Differences that cannot be hidden behind a common method name are wrapped by the static
## helpers at the bottom of this file (the native classes expose Godot-style getters instead
## of public variables, and flat constants instead of nested enums).

## Mirrors StreamReadinessGate.Stage / StreamReadiness.Stage.
enum Stage { DATA_LOADED = 1, GPU_UPLOADED = 2, PHYSICS_READY = 4, NAVMESH_READY = 8 }
const STAGE_ALL: int = 15
## Mirrors StreamRequestQueue.State / StreamRequests.State.
enum RequestState { QUEUED = 0, IN_FLIGHT = 1, CANCELLED = 2 }

const SCRIPT_PATHS: Dictionary = {
	"WorldPartitionBake": "res://scripts/shared/world_partition_bake.gd",
	"OriginRebasing": "res://scripts/shared/origin_rebasing.gd",
	"StreamRequestQueue": "res://scripts/shared/stream_requests.gd",
	"StreamReadinessGate": "res://scripts/shared/stream_readiness.gd",
	"StreamReplication": "res://scripts/shared/stream_state_replication.gd",
	"NavMeshStitching": "res://scripts/shared/navmesh_stitching.gd",
	"NavMeshCarving": "res://scripts/shared/navmesh_carving.gd",
	"VirtualTexturePageCache": "res://scripts/client/virtual_texture.gd",
	"ProbeVolume": "res://scripts/shared/probe_volume.gd",
	"SHLighting": "res://scripts/shared/sh_lighting.gd",
	"VirtualShadowPages": "res://scripts/shared/virtual_shadow_pages.gd",
}


## True when the engine provides the native implementation of `native_class`.
static func is_native(native_class: StringName) -> bool:
	return ClassDB.class_exists(native_class)


static func _make(native_class: StringName) -> Variant:
	if ClassDB.class_exists(native_class):
		return ClassDB.instantiate(native_class)
	var script: GDScript = load(SCRIPT_PATHS[String(native_class)])
	return script.new()


## Static-only libraries: the returned object (native instance or GDScript resource) exposes the
## static functions, which GDScript can call through any reference.
static func _make_static_lib(native_class: StringName) -> Variant:
	if ClassDB.class_exists(native_class):
		return ClassDB.instantiate(native_class)
	return load(SCRIPT_PATHS[String(native_class)])


static func make_world_partition_bake() -> RefCounted:
	return _make(&"WorldPartitionBake")


static func make_origin_rebasing() -> RefCounted:
	return _make(&"OriginRebasing")


static func make_stream_requests() -> RefCounted:
	return _make(&"StreamRequestQueue")


static func make_stream_readiness() -> RefCounted:
	return _make(&"StreamReadinessGate")


static func make_stream_replication_server() -> RefCounted:
	return _make(&"StreamReplication")


## Client side of the replication protocol. `report_radius` is the window radius in cells.
static func make_stream_replication_client(report_radius: int = 6) -> RefCounted:
	if ClassDB.class_exists(&"StreamReplicationClient"):
		var native: RefCounted = ClassDB.instantiate(&"StreamReplicationClient")
		native.set("radius", report_radius)
		return native
	var script: GDScript = load(SCRIPT_PATHS["StreamReplication"])
	return script.Client.new(report_radius)


## Static helpers of the replication protocol (bit_index, encode_cells, serialize, ...).
static func stream_replication_lib() -> Variant:
	return _make_static_lib(&"StreamReplication")


static func navmesh_stitching() -> Variant:
	return _make_static_lib(&"NavMeshStitching")


static func make_navmesh_carving() -> RefCounted:
	return _make(&"NavMeshCarving")


static func make_virtual_texture() -> RefCounted:
	return _make(&"VirtualTexturePageCache")


static func make_probe_volume() -> RefCounted:
	return _make(&"ProbeVolume")


static func sh_lighting() -> Variant:
	return _make_static_lib(&"SHLighting")


static func make_virtual_shadow_pages() -> RefCounted:
	return _make(&"VirtualShadowPages")


# --- accessors that differ between the native classes and the GDScript variables ---------------

static func shift_count(rebasing: RefCounted) -> int:
	return rebasing.get_shift_count() if rebasing.has_method("get_shift_count") else rebasing.get("shift_count")


static func stuck_log(gate: RefCounted) -> Array:
	return gate.get_stuck_log() if gate.has_method("get_stuck_log") else gate.get("stuck_log")


static func warmup_failed(gate: RefCounted) -> Array:
	return gate.get_warmup_failed() if gate.has_method("get_warmup_failed") else gate.get("warmup_failed")


static func newest_generation(queue: RefCounted) -> int:
	return queue.get_newest_generation() if queue.has_method("get_newest_generation") else queue.get("newest_generation")


static func vt_top_mip(vt: RefCounted) -> int:
	return vt.get_top_mip() if vt.has_method("get_top_mip") else vt.get("top_mip")


static func vt_pages_mip0(vt: RefCounted) -> int:
	return vt.get_pages_mip0() if vt.has_method("get_pages_mip0") else vt.get("pages_mip0")


static func carving_version(nav: RefCounted) -> int:
	return nav.get_version() if nav.has_method("get_version") else nav.get("version")
