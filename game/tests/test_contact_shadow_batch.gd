extends RefCounted
## Real 3D shadow-batching policy, zero server/gameplay changes.

const ContactShadowBatch = preload("res://scripts/client/contact_shadow_batch.gd")


func run(t) -> void:
	t.current = "shared contact shadow quality is bounded and monotonic"
	t.eq(ContactShadowBatch.profile(-9), ContactShadowBatch.profile(0),
		"negative quality cannot break shadow presets")
	t.eq(ContactShadowBatch.profile(900), ContactShadowBatch.profile(3),
		"out-of-range quality clamps to Ultra")
	var low: Dictionary = ContactShadowBatch.profile(0)
	var ultra: Dictionary = ContactShadowBatch.profile(3)
	t.check(float(low["radius"]) < float(ultra["radius"]),
		"Performance draws only near-camera grounding")
	t.check(int(low["count"]) < int(ultra["count"]),
		"Ultra permits more simultaneous silhouettes")
	t.check(int(ultra["count"]) <= ContactShadowBatch.MAX_INSTANCES,
		"no profile can exceed allocated GPU instances")
	t.check(float(ultra["radius"]) <= ContactShadowBatch.MAX_RADIUS,
		"batch frustum bounds encompass all allowed shadows")
	t.check(float(low["opacity"]) > float(ultra["opacity"]),
		"low-end shadow substitute is clearer when real sunlight shadow maps are off")
	low["radius"] = -999.0
	t.check(float(ContactShadowBatch.profile(0)["radius"]) > 0.0,
		"returned settings cannot corrupt shared defaults")

	t.current = "budget selects closest visible actors and ignores submerged or dead"
	var actors: Array[Dictionary] = [
		{"position": Vector3(12.0, 40.0, 0.0), "radius": 1.0},
		{"position": Vector3(5.0, 20.0, 0.0), "radius": 0.8},
		{"position": Vector3(8.0, 20.0, 0.0), "alive": false},
		{"position": Vector3(3.0, 20.0, 0.0), "visible": false},
		{"position": Vector3(2.0, 20.0, 0.0), "submerged": true},
		{"position": Vector3(100.0, 20.0, 0.0)},
		{"position": Vector3.INF},
	]
	var selected: Array[Dictionary] = ContactShadowBatch.select_actors(
		actors, Vector3(0.0, 22.0, 0.0), 0, 1.0, 0.0)
	t.eq(selected.size(), 2, "only nearby living visible non-submerged actors draw")
	t.eq(selected[0]["position"], Vector3(5.0, 20.0, 0.0),
		"selection draws the nearest character first")
	t.eq(selected[1]["position"], Vector3(12.0, 40.0, 0.0),
		"altitude does not break the horizontal distance budget")
	t.check(float(selected[0]["opacity"]) > float(selected[1]["opacity"]),
		"nearby shadows are stronger and distant ones feather out")
	t.eq(selected[0]["radius"], 0.8, "radius from actor is preserved")
	t.eq(actors[0]["position"], Vector3(12.0, 40.0, 0.0),
		"selection never alters the actual character position")
	var beyond: Array[Dictionary] = [
		{"position": Vector3(52.0, 0.0, 0.0)}
	]
	t.eq(ContactShadowBatch.select_actors(beyond, Vector3.ZERO, 0, 1.0, 0.0).size(),
		0, "Performance culls offscreen distant alpha geometry")
	t.eq(ContactShadowBatch.select_actors(beyond, Vector3.ZERO, 3, 1.0, 0.0).size(),
		1, "Ultra can keep nearby distant grounding at greater range")

	t.current = "fog, daylight and edge fading avoid overdraw and popping"
	var dawn: Array[Dictionary] = ContactShadowBatch.select_actors(
		actors, Vector3(0.0, 22.0, 0.0), 0, 0.0, 0.0)
	var rain: Array[Dictionary] = ContactShadowBatch.select_actors(
		actors, Vector3(0.0, 22.0, 0.0), 0, 1.0, 1.0)
	t.check(float(dawn[0]["opacity"]) < float(selected[0]["opacity"]),
		"moonlit shadow remains faint")
	t.check(float(rain[0]["opacity"]) < float(selected[0]["opacity"]),
		"overcast fades out fake direct-sun contact")
	var edge: Array[Dictionary] = [
		{"position": Vector3(27.999, 0.0, 0.0)}
	]
	var shadow: Array[Dictionary] = ContactShadowBatch.select_actors(
		edge, Vector3.ZERO, 0, 1.0, 0.0)
	t.check(shadow.is_empty() or float(shadow[0]["opacity"]) < 0.01,
		"geometry fades smoothly at the quality limit")
	var crowd: Array[Dictionary] = []
	for i in 300:
		crowd.append({"position": Vector3(float(i % 15), 0.0, float(i / 15)),
			"radius": 1.0})
	for level in 4:
		var shown: Array[Dictionary] = ContactShadowBatch.select_actors(
			crowd, Vector3.ZERO, level, 0.7, 0.2)
		t.eq(shown.size(), int(ContactShadowBatch.profile(level)["count"]),
			"crowd never allocates more shadows than the GPU quality budget")
		t.check(float(shown[0]["distance_squared"]) <= float(shown[-1]["distance_squared"]),
			"closest actors retain priority under crowded GPU limits")

	t.current = "actual GPU resource has one draw and bounded instance allocation"
	var batch := ContactShadowBatch.new()
	batch._ready()
	var mesh: MultiMesh = batch._multimesh
	t.check(mesh != null, "visual batch creates one persistent MultiMesh")
	t.eq(mesh.instance_count, ContactShadowBatch.MAX_INSTANCES,
		"fixed GPU buffer holds the largest quality budget")
	t.eq(mesh.visible_instance_count, 0, "nothing is drawn before actors exist")
	t.check(mesh.use_custom_data, "per-character opacity uses instanced custom data")
	t.check(batch.get_child_count() == 1, "all contact shadows use one render node")
	t.check(batch._instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"soft grounding cannot recursively cast real shadow maps")
	var script_code: String = FileAccess.get_file_as_string(
		"res://assets/shaders/contact_shadow.gdshader")
	t.check(script_code.contains("INSTANCE_CUSTOM.r") and script_code.contains("ALPHA"),
		"one shader reads cached per-instance opacity without an atlas")
	t.check(not script_code.contains("texture(") and not script_code.contains("hint_depth_texture"),
		"analytical shadow avoids extra texture and depth-buffer reads")
	batch.free()

	t.current = "full online/solo world and NPCs actually register for soft grounding"
	var model_code: String = FileAccess.get_file_as_string(
		"res://scripts/client/character_model.gd")
	var online_code: String = FileAccess.get_file_as_string(
		"res://scripts/client/online_main.gd")
	var solo_code: String = FileAccess.get_file_as_string(
		"res://scripts/client/client_main.gd")
	t.check(model_code.contains('add_to_group("aa_grounded_characters")'),
		"all real survivors and infected share one actor render group")
	t.check(online_code.contains("ContactShadowBatch.new()"),
		"the multiplayer world has a shared GPU shadow renderer")
	t.check(solo_code.contains("ContactShadowBatch.new()"),
		"the local survival mode uses the exact same GPU path")
	t.check(solo_code.contains("mesh.add_to_group(ContactShadowBatch.GROUP)"),
		"solo infected are included instead of only the local player")
