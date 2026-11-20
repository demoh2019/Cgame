extends SceneTree
## Bounded HLOD resource-cache regression; independent of scene streaming.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_hlod_cache.gd
##
## The cache stores resource pairs only; live scene roots own their own
## references and can survive resource eviction without invalid resources.

const HLODCache = preload("res://scripts/distant_hlod_cache.gd")


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("HLOD cache smoke FAILED: " + reason)
    HLODCache.clear()
    quit(1)


func _run() -> void:
    HLODCache.clear()
    var capacity: int = int(HLODCache.get_stats()["capacity"])
    if capacity != 96:
        _fail("unexpected HLOD cache capacity")
        return

    var terrain := ArrayMesh.new()
    var canopy_batch := MultiMesh.new()
    HLODCache.insert(Vector2i.ZERO, terrain, canopy_batch)
    for index in range(1, capacity):
        HLODCache.insert(Vector2i(index, 0), ArrayMesh.new(), MultiMesh.new())
    if int(HLODCache.get_stats()["entries"]) != capacity:
        _fail("cache failed to fill to configured capacity")
        return

    # Lookups promote a hit. Eviction removes exactly the oldest resource
    # pair while respecting strong references owned by any active HLOD node.
    var first: Dictionary = HLODCache.lookup(Vector2i.ZERO)
    if first.is_empty() or first["terrain"] != terrain or first["canopies"] != canopy_batch:
        _fail("cache did not preserve both resource identities")
        return

    HLODCache.insert(Vector2i(capacity, 0), ArrayMesh.new(), MultiMesh.new())
    if not HLODCache.lookup(Vector2i(1, 0)).is_empty():
        _fail("the least-recently-used resource pair was not evicted")
        return
    if HLODCache.lookup(Vector2i.ZERO).is_empty():
        _fail("recently used resource pair was incorrectly evicted")
        return

    # A long journey should not increase retained HLOD tile resources without
    # bound. The renderer's active scene references remain independent.
    for index in range(capacity + 1, capacity + 200):
        HLODCache.insert(Vector2i(index, -index), ArrayMesh.new(), MultiMesh.new())
    var stats: Dictionary = HLODCache.get_stats()
    if int(stats["entries"]) != capacity or int(stats["evictions"]) < 199:
        _fail("cache grew without bound or failed to count evictions")
        return
    if int(stats["hits"]) < 2 or int(stats["misses"]) < 1:
        _fail("HLOD cache hit/miss accounting is broken")
        return

    HLODCache.clear()
    stats = HLODCache.get_stats()
    if int(stats["entries"]) != 0 or int(stats["hits"]) != 0 \
            or int(stats["misses"]) != 0 or int(stats["evictions"]) != 0:
        _fail("cache clear did not reset its state and metrics")
        return
    print("HLOD cache smoke PASSED: immutable resource pairs, bounded 96-cell LRU, eviction and accounting")
    quit(0)
