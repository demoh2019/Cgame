extends SceneTree
## Bounded LRU terrain-resource cache regression.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_terrain_cache.gd
##
## Cache entries share immutable ArrayMesh/HeightMapShape3D resources, never
## scene nodes. This test is isolated from the user's savegame and real scene.

const Cache = preload("res://scripts/terrain_tile_cache.gd")


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Terrain resource cache smoke FAILED: " + message)
    Cache.clear()
    quit(1)


func _run() -> void:
    Cache.clear()
    var capacity: int = int(Cache.get_stats()["capacity"])
    if capacity != 12:
        _fail("unexpected cache size")
        return

    var original := ArrayMesh.new()
    var first_collision := HeightMapShape3D.new()
    Cache.insert(Vector2i(0, 0), original, first_collision)
    for i in range(1, capacity):
        Cache.insert(Vector2i(i, 0), ArrayMesh.new(), HeightMapShape3D.new())
    var initial: Dictionary = Cache.get_stats()
    if initial["entries"] != capacity or initial["evictions"] != 0:
        _fail("cache failed to populate to capacity")
        return

    # Visiting the oldest entry must promote it to most recently used.
    var again: Dictionary = Cache.lookup(Vector2i(0, 0))
    if again.is_empty() or again["mesh"] != original or again["shape"] != first_collision:
        _fail("cache did not preserve resource identity")
        return

    Cache.insert(Vector2i(capacity, 0), ArrayMesh.new(), HeightMapShape3D.new())
    if not Cache.lookup(Vector2i(1, 0)).is_empty():
        _fail("LRU eviction did not remove the least recently used entry")
        return
    if Cache.lookup(Vector2i(0, 0)).is_empty():
        _fail("LRU erroneously evicted the recently accessed tile")
        return

    # Long traversal must never make the cache grow without bound.
    for i in range(capacity + 1, capacity + 120):
        Cache.insert(Vector2i(i, -i), ArrayMesh.new(), HeightMapShape3D.new())
    var stats: Dictionary = Cache.get_stats()
    if stats["entries"] != capacity or stats["evictions"] <= 0:
        _fail("long traversal exceeded LRU capacity")
        return
    if stats["hits"] < 2 or stats["misses"] < 1:
        _fail("cache statistics did not track accesses")
        return

    Cache.clear()
    var empty: Dictionary = Cache.get_stats()
    if empty["entries"] != 0 or empty["hits"] != 0 or empty["misses"] != 0:
        _fail("cache clear did not reset state and metrics")
        return

    print("Terrain resource cache smoke PASSED: immutable resource reuse, hit/miss accounting, LRU eviction and bounded retention")
    quit(0)
