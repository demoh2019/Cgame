extends RefCounted
## Event-driven storm lighting has no per-strike new lights, meshes or shadow maps.
## Pure profile math plus real Environment/Light node property regression.

const Flash = preload("res://scripts/client/graphics_lightning_flash.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Online = preload("res://scripts/client/online_main.gd")
const Offline = preload("res://scripts/client/client_main.gd")
const Server = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "lightning distance and quality budgets"
	var previous := 0.0
	for tier in 4:
		var strength: float = Flash.strength(tier)
		t.check(strength >= previous and strength <= 1.0,
			"flash energy grows monotonically without overexposing at quality %d" % tier)
		previous = strength
	t.eq(Flash.strength(-100), Flash.strength(0),
		"quality below Performance remains bounded")
	t.eq(Flash.strength(999), Flash.strength(3),
		"quality above Ultra remains bounded")
	t.near(Flash.attenuation(0.0), 1.0, 0.00001,
		"nearby strike has full atmospheric impact")
	t.check(Flash.attenuation(45.0) > Flash.attenuation(90.0),
		"nearby lightning visibly illuminates more than distant strikes")
	t.eq(Flash.attenuation(Flash.MAX_DISTANCE), 0.0,
		"outside the storm visibility radius no lighting override is applied")
	t.eq(Flash.attenuation(-20.0), 0.0,
		"invalid negative strike distance cannot brighten the world")
	t.eq(Flash.attenuation(INF), 0.0,
		"invalid network coordinates cannot overexpose the scene")
	t.eq(Flash.attenuation(NAN), 0.0,
		"NaN network coordinates are discarded")

	t.current = "frame-rate independent cinematic dual flash curve"
	var full := Flash.sample(0.0, 1.0)
	t.check(full > 0.95 and full <= 1.0,
		"primary flash is bright, yet clamped to the tone mapping budget")
	t.check(Flash.sample(0.12, 1.0) > Flash.sample(0.10, 1.0),
		"weaker secondary return stroke follows the primary")
	t.check(Flash.sample(0.3, 1.0) < Flash.sample(0.12, 1.0),
		"impact illumination falls away rather than remaining saturated")
	t.eq(Flash.sample(Flash.DURATION, 1.0), 0.0,
		"storm illumination is exactly off after its lifetime")
	t.eq(Flash.sample(5.0, 1.0), 0.0,
		"long frame stalls cannot leave a permanent lightning effect")
	t.eq(Flash.sample(-0.1, 1.0), 0.0,
		"uninitialized negative time is harmless")
	t.eq(Flash.sample(NAN, 1.0), 0.0,
		"invalid render time never reaches GPU light properties")
	t.eq(Flash.sample(0.0, NAN), 0.0,
		"invalid weighted amplitude cannot reach GPU light properties")
	t.near(Flash.sample(0.0, 0.5), full * 0.5, 0.002,
		"flash scales smoothly with graphics settings and proximity")

	t.current = "actual Godot lighting nodes: reusing existing scene resources"
	var env := Environment.new()
	env.ambient_light_energy = 0.8
	env.ambient_light_color = Color(0.25, 0.35, 0.55)
	env.fog_light_color = Color(0.40, 0.50, 0.65)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.4
	sun.shadow_enabled = false
	Flash.apply(env, sun, 0.0)
	t.near(env.ambient_light_energy, 0.8, 0.00001,
		"clear environment is untouched if no actual strike occurred")
	Flash.apply(env, sun, 0.5)
	t.near(env.ambient_light_energy, 1.16, 0.00001,
		"one flash raises the already-existing ambient light energy")
	t.near(sun.light_energy, 0.71, 0.00001,
		"one flash temporarily reuses existing sun/moon directional light")
	t.check(env.ambient_light_color.b > 0.55,
		"storm flashes add a cool blue atmosphere rather than yellow noise")
	t.check(env.fog_light_color.b > 0.65,
		"existing fog brightens with no extra volume fog texture")
	t.check(not sun.shadow_enabled,
		"lightning never enables additional shadow maps")
	t.eq(sun.get_child_count(), 0,
		"no new lights, render meshes or particles are allocated")
	sun.free()

	t.current = "online and offline use real server strike rather than warning"
	var atmosphere: String = (Atmosphere as Script).source_code
	t.check(atmosphere.contains("func trigger_lightning(distance_m: float)"),
		"atmosphere exposes event-driven visual strike handler")
	t.check(atmosphere.contains("LightningFlash.apply(environment, sun, amount)"),
		"flash rides on existing lighting after regular day/night update")
	t.check(atmosphere.contains("_lightning_elapsed + maxf(0.0, delta)"),
		"flash timer uses frame delta and expires after bounded duration")
	t.check(atmosphere.contains("_lightning_quality = _shadow_filter_level"),
		"visual strike power changes with the saved graphics quality")
	var online: String = (Online as Script).source_code
	t.check(online.contains('str(event.get("type", "")) == "lightning_struck"'),
		"multiplayer flashes only for confirmed server impact")
	t.check(online.contains("atmosphere.trigger_lightning(distance_m)"),
		"multiplayer delivers near-field attenuation to visual atmosphere")
	t.check(online.contains("not Dungeon.is_underground("),
		"online caves are shielded from outdoor sky flashes")
	var offline: String = (Offline as Script).source_code
	t.check(offline.contains('str(game_event.get("type", "")) == "lightning_struck"'),
		"offline simulation uses the same confirmed impact event")
	t.check(offline.contains("_atmosphere.trigger_lightning(distance_m)"),
		"offline lightning uses one equivalent visual pipeline")
	t.check(offline.contains("not Dungeon.is_underground(survivor.position.x)"),
		"offline dungeons are excluded from atmospheric flashes")
	var server_source: String = (Server as Script).source_code
	t.check(server_source.contains('events.append({"type": "lightning_struck"'),
		"authoritative impact event already exists; no new gameplay or RPC")
