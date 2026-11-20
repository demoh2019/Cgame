extends RefCounted
## A small, bounded LRU resource cache for WorldPartition3D terrain patches.
##
## This cache stores only immutable mesh and collision-shape resources.
## It deliberately does not retain scene nodes or physics server instances:
## WorldPartition3D still owns cell activation/unloading and node lifetimes.
## All callers run on the main thread; the cache performs no unsafe concurrent
## RenderingServer / PhysicsServer resource creation.
##
## Use one entry per tile origin (Vector2i grid coordinates). A cached tile
## recreates its MeshInstance3D and StaticBody3D while reusing the expensive
## ArrayMesh + HeightMapShape3D resources from the last visit.

const MAX_CACHED_TILES: int = 12

static var _tiles: Dictionary = {}
static var _lru: Array[Vector2i] = []
static var _hits: int = 0
static var _misses: int = 0
static var _evictions: int = 0


static func lookup(cell: Vector2i) -> Dictionary:
    if not _tiles.has(cell):
        _misses += 1
        return {}
    _hits += 1
    _lru.erase(cell)
    _lru.push_back(cell)
    # Return a shallow copy: callers cannot replace the cached mesh and shape.
    return (_tiles[cell] as Dictionary).duplicate()


static func insert(cell: Vector2i, mesh: ArrayMesh, shape: HeightMapShape3D) -> void:
    if mesh == null or shape == null:
        push_error("TerrainTileCache: refusing empty terrain resources")
        return
    if _tiles.has(cell):
        _lru.erase(cell)
    _tiles[cell] = {"mesh": mesh, "shape": shape}
    _lru.push_back(cell)

    # LRU eviction keeps resource retention bounded as the player moves.
    # Active nodes maintain their own references, so eviction never destroys
    # a still-visible mesh or an active physics collider.
    while _lru.size() > MAX_CACHED_TILES:
        var oldest: Vector2i = _lru.pop_front()
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
    _lru.clear()
    _hits = 0
    _misses = 0
    _evictions = 0
