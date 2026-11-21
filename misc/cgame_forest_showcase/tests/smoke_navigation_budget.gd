extends SceneTree
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_navigation_budget.gd
## Real physics-frame budget, equal-priority fairness, stale-owner safety,
## dormant streamed cells, urgent source activation and stalker integration.

const Probe = preload("res://tests/navigation_probe.gd")
const Stalker = preload("res://scripts/forest_stalker.gd")
const FOREST: String = "res://cells/forest_cell.tscn"
const FRAMES: int = 420


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Forest navigation budget smoke FAILED: " + message)
    quit(1)


func _wait_cell(stream: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(FRAMES):
        if stream.is_cell_loaded(cell):
            return true
        await process_frame
    return false


func _spawn_probe(stream: WorldPartition3D, name: String, position: Vector3,
        priority: int = 1) -> Node3D:
    var agent := Node3D.new()
    agent.name = name
    agent.set_script(Probe)
    agent.position = position
    root.add_child(agent)
    if not agent.call("configure", stream, name, priority):
        _fail("register_navigation_agent failed for " + name)
    return agent


func _grants(probe: Node3D) -> int:
    return int(probe.get("granted"))


func _run() -> void:
    if not ResourceLoader.exists(FOREST):
        _fail("forest PackedScene not found")
        return

    var observer := Node3D.new()
    root.add_child(observer)
    var stream := WorldPartition3D.new()
    stream.name = "NavigationBudgetTest"
    stream.cell_size = 32.0
    stream.load_radius = 0
    stream.unload_radius = 0
    stream.detail_radius = 0
    stream.physics_radius = 0
    stream.simulation_radius = 0
    stream.max_navigation_updates_per_physics_frame = 2
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(observer)
    stream.set_cell_scene(Vector2i.ZERO, FOREST)
    stream.set_cell_scene(Vector2i(3, 0), FOREST)
    if not await _wait_cell(stream, Vector2i.ZERO):
        _fail("observer cell failed to stream")
        return

    var a: Node3D = _spawn_probe(stream, "agent_a", Vector3(7, 1, 7))
    var b: Node3D = _spawn_probe(stream, "agent_b", Vector3(8, 1, 8))
    var c: Node3D = _spawn_probe(stream, "agent_c", Vector3(9, 1, 9))
    for i in range(18):
        await physics_frame
    await process_frame
    for agent in [a, b, c]:
        if _grants(agent) < 4:
            _fail("equal-priority agents did not receive fair update grants")
            return
        if bool(agent.get("double_granted")) or bool(agent.get("exceeded_budget")):
            _fail("an agent received duplicate grants or exceeded the per-frame budget")
            return
    if stream.get_navigation_agent_count() != 3:
        _fail("registry count is not three agents")
        return

    # A higher-priority active agent wins a scarce steering slot.
    stream.max_navigation_updates_per_physics_frame = 1
    if not stream.set_navigation_agent_priority("agent_c", 3):
        _fail("could not raise critical agent priority")
        return
    var before_a: int = _grants(a)
    var before_b: int = _grants(b)
    var before_c: int = _grants(c)
    for i in range(7):
        await physics_frame
    await process_frame
    if (_grants(c) < before_c + 5
            or _grants(a) > before_a + 2
            or _grants(b) > before_b + 2):
        _fail("priority scheduling does not favor the urgent agent")
        return

    c.set_physics_process(false)
    if not stream.set_navigation_agent_priority("agent_c", 1):
        _fail("could not restore normal priority")
        return
    var frozen: int = _grants(c)
    for i in range(8):
        await physics_frame
    await process_frame
    if _grants(c) != frozen:
        _fail("dormant NPC spent navigation update budget")
        return
    if _grants(a) <= before_a or _grants(b) <= before_b:
        _fail("active peers stopped receiving grants after an NPC went dormant")
        return

    # A preloaded but physics/simulation-dormant cell has NO navigation work.
    stream.simulation_radius = 0
    if not stream.set_streaming_source("background", Vector3(96, 0, 0), 0, 0):
        _fail("could not preload distant target")
        return
    if not await _wait_cell(stream, Vector2i(3, 0)):
        _fail("remote background cell was not streamed")
        return
    var remote: Node3D = _spawn_probe(stream, "remote", Vector3(98, 1, 8), 3)
    for i in range(7):
        await physics_frame
    await process_frame
    if _grants(remote) != 0:
        _fail("background-only remote NPC spent navigation budget")
        return

    # Upgrade both physical and simulation tier by moving the observer to it.
    observer.position.x = 99.0
    for i in range(8):
        await physics_frame
        await process_frame
    if (not stream.is_cell_simulation_active(Vector2i(3, 0))
            or not stream.is_cell_physics_active(Vector2i(3, 0))):
        _fail("remote streamed cell did not enter active simulation/physics")
        return
    if _grants(remote) == 0:
        _fail("newly active remote NPC did not receive a navigation update")
        return

    # Instance ownership matters when the same deterministic encounter ID
    # is reassigned before the previous node's queued deletion completes.
    var replacement := Node3D.new()
    root.add_child(replacement)
    if not stream.register_navigation_agent("remote", replacement, 2):
        _fail("replacement NPC could not reuse the old registry name")
        return
    if stream.unregister_navigation_agent_if_owner("remote", remote):
        _fail("old NPC incorrectly unregistered its new owner")
        return
    if not stream.has_navigation_agent("remote"):
        _fail("new navigation owner was lost")
        return
    if not stream.unregister_navigation_agent_if_owner("remote", replacement):
        _fail("correct owner could not unregister")
        return

    # Actual stalker uses the same native budget for obstacle-ray steering.
    for probe in [a, b, c, remote]:
        probe.queue_free()
    await process_frame
    observer.position.x = 0.0
    if not await _wait_cell(stream, Vector2i.ZERO):
        _fail("returning home did not reload observer cell")
        return
    stream.max_navigation_updates_per_physics_frame = 1
    var target := Node3D.new()
    root.add_child(target)
    target.global_position = Vector3(20, 1, 20)
    var stalker := CharacterBody3D.new()
    stalker.set_script(Stalker)
    root.add_child(stalker)
    stalker.call("configure", "test_stalker", target, Vector3(8, 1, 8), stream)
    stalker.call("set_encounter_active", true)
    for i in range(15):
        await physics_frame
    await process_frame
    if int(stalker.get("steering_updates")) < 2:
        _fail("stalker did not consume native navigation steering grants")
        return
    if int(stalker.get("steering_updates")) > 15:
        _fail("stalker exceeded its navigation update budget")
        return
    stalker.queue_free()
    await process_frame
    if stream.has_navigation_agent("test_stalker"):
        _fail("defeated/removed NPC retained a navigation registration")
        return

    print("Navigation budget smoke PASSED: fair LRU, priority, per-tick budget, dormant filtering, weak-owner cleanup, actual stalker")
    quit(0)
