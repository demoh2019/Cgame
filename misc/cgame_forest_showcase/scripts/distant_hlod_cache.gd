extends RefCounted
## Bounded resource cache for visual distant-terrain HLOD and canopy batches.
##
## Stores only immutable ArrayMesh / MultiMesh resources; never Node3D,
## MeshInstance3D, physics bodies, or scene ownership. Active HLOD nodes
## retain references to their resources independently of cache eviction.
## This stays on the main thread: no RenderingServer calls in worker threads.
##
## Because HLOD has a larger footprint than near terrain, a 96-cell LRU
## retains recently visited horizon tiles without unbounded VRAM growth.

const MAX_CACHED_TILES: int = 96

static var _tiles: Dictionary = {}
static var _order: Array[Vector2i] = []
static var _hits: int = 0
static var _misses: int = 0
static var _evictions: int = 0


static func lookup(cell: Vector2i) -> Dictionary:
    if not _tiles.has(cell):
        _misses += 1
        return {}
    _hits += 1
    _order.erase(cell)
    _order.push_back(cell)
    return (_tiles[cell] as Dictionary).duplicate()


static func insert(cell: Vector2i, terrain_mesh: ArrayMesh,
        canopy_batch: MultiMesh) -> void:
    if terrain_mesh == null or canopy_batch == null:
        push_error("DistantHLODCache: both HLOD resources are required")
        return

    if _tiles.has(cell):
        _order.erase(cell)
    _tiles[cell] = {
        "terrain": terrain_mesh,
        "canopies": canopy_batch
    }
    _order.push_back(cell)

    while _order.size() > MAX_CACHED_TILES:
        var oldest: Vector2i = _order.pop_front()
        _tiles.erase(oldest)
        _evictions += 1


static func get_stats() -> Dictionary:
    return {
        "capacity": MAX_CACHED_TILES,
        "entries": _tiles.size(),
        "hits": _hits,
        "misses": _misses,
        "evictions": _evictions
    }


static func clear() -> void:
    _tiles.clear()
    _order.clear()
    _hits = 0
    _misses = 0
    _evictions = 0
