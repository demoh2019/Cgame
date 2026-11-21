extends Node3D
## Lightweight non-rendered NPC stand-in for testing engine navigation quotas.

var streamer: WorldPartition3D
var agent_id: String = ""
var granted: int = 0
var denied: int = 0
var double_granted: bool = false
var exceeded_budget: bool = false
var grant_frames: Array[int] = []


func configure(world: WorldPartition3D, name: String, priority: int = 1) -> bool:
    streamer = world
    agent_id = name
    return streamer.register_navigation_agent(agent_id, self, priority)


func _physics_process(_delta: float) -> void:
    if not is_instance_valid(streamer) or agent_id.is_empty():
        return
    if streamer.try_acquire_navigation_update(agent_id):
        granted += 1
        grant_frames.append(Engine.get_physics_frames())
        if streamer.try_acquire_navigation_update(agent_id):
            double_granted = true
        if (streamer.get_navigation_updates_used_this_frame()
                > streamer.max_navigation_updates_per_physics_frame):
            exceeded_budget = true
    else:
        denied += 1


func _exit_tree() -> void:
    if is_instance_valid(streamer) and not agent_id.is_empty():
        streamer.unregister_navigation_agent_if_owner(agent_id, self)
