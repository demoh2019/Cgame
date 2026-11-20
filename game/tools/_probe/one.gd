extends SceneTree
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
func _initialize() -> void:
	var sim := GameServer.new(WorldGen.new(1313), 1313)
	var player = sim.add_player(47, "Traveler", "solo-local")
	var saved: Dictionary = sim.character_data(player)
	var trip: Dictionary = JSON.parse_string(JSON.stringify(saved))
	print("orig valid ", sim.valid_character_data(saved), " trip valid ", sim.valid_character_data(trip))
	for key in saved:
		var fixed := saved.duplicate(true)
		fixed[key] = trip[key]
		if not sim.valid_character_data(fixed):
			print("CULPRIT ", key, " orig=", str(saved[key]).left(200), " trip=", str(trip[key]).left(200))
	quit()
