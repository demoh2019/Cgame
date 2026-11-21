extends SceneTree

const Router = preload("res://addons/visual_quality/world_interaction_router.gd")
const Streamer = preload("res://addons/visual_quality/world_streamer.gd")
const Quest = preload("res://addons/visual_quality/exploration_quest.gd")
const StateStore = preload("res://addons/visual_quality/world_state_store.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var player: CharacterBody3D = CharacterBody3D.new()
	player.position = Vector3(2, 0, 0)
	stage.add_child(player)
	var camera: Camera3D = Camera3D.new()
	camera.position.y = 1.65
	player.add_child(camera)
	var streamer = Streamer.new()
	streamer.streaming_enabled = false
	streamer.source = player
	streamer.load_radius_cells = 0
	streamer.unload_radius_cells = 1
	streamer.register_scene_cell(Vector2i.ZERO, "res://world/forest_cell.tscn")
	stage.add_child(streamer)
	streamer.streaming_enabled = true
	var loaded: bool = false
	for i in range(300):
		streamer.refresh_now()
		if streamer.active_cell_count() == 1:
			loaded = true
			break
		await create_timer(0.01).timeout
	assert(loaded, "The streamed cell must instantiate before interactions")
	var cell: Node3D = streamer.get_active_cell(Vector2i.ZERO)
	(cell.call("get_active_npc") as Node).set_physics_process(false)
	var router = Router.new()
	router.streamer = streamer
	router.player = player
	router.camera = camera
	stage.add_child(router)
	camera.look_at(cell.call("get_beacon_world_position"))
	assert(router.find_best_action().get("action_id") == "beacon")
	assert(router.try_interact())
	assert(cell.get("beacon_activated") == true)
	var offers_after_beacon: Array[Dictionary] = cell.call("get_interaction_targets", camera.global_position, 3.5)
	for offer in offers_after_beacon:
		assert(offer["action_id"] != "beacon")
	player.position = Vector3(-2, 0, 0)
	var npc: Node3D = cell.call("get_active_npc")
	camera.look_at(npc.global_position + Vector3.UP)
	assert(router.find_best_action().get("action_id") == "npc")
	assert(router.try_interact())
	assert(cell.get("npc_talk_count") == 1)
	assert((cell.call("save_stream_state") as Dictionary).get("npc_talk_count") == 1)
	var state: Dictionary = cell.call("save_stream_state")
	cell.call("load_stream_state", {})
	assert(cell.get("npc_talk_count") == 0)
	cell.call("load_stream_state", state)
	assert(cell.get("npc_talk_count") == 1)

	# Unloading invalidates a cached focused action without holding a dead node.
	router.refresh_focus()
	player.position = Vector3(84, 0, 0)
	streamer.refresh_now()
	assert(streamer.active_cell_count() == 0)
	assert(router.current_id().is_empty())
	assert(not router.try_interact())

	# The same router works with the global quest provider independently of cells.
	var quest = Quest.new()
	quest.save_enabled = false
	quest.shard_count = 1
	stage.add_child(quest)
	router.quest = quest
	var pos: Vector3 = quest.to_global(quest.positions[0])
	player.position = Vector3(pos.x, 0.0, pos.z + 1.5)
	camera.look_at(pos)
	assert(router.find_best_action().get("action_id") == "shard_0")
	assert(router.try_interact())
	assert(quest.collected_count() == 1)
	assert(not router.try_interact())
	streamer.streaming_enabled = false
	stage.queue_free()
	print("WorldInteractionRouter3D: streamed beacon, NPC and quest routing passed")
	quit(0)
