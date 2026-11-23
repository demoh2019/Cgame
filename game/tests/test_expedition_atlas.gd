extends RefCounted
## Expedition atlas: owner-only snapshot validation, world map selection,
## moving-target radar synchronization and stale-goal cleanup.

const Atlas = preload("res://scripts/shared/expedition_atlas.gd")
const WorldMap = preload("res://scripts/client/world_map.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


class FakeClient:
	extends RefCounted
	var you: Dictionary = {}


func _snapshot() -> Dictionary:
	return {
		"x": 10.0, "z": 12.0,
		"threat_scan": {"x": 90.0, "z": 25.0, "kind": "raid", "remaining": 20.0},
		"prospect_mark": {"x": 320.0, "z": 240.0, "kind": "ore",
			"tier": 3, "remaining": 50.0},
		"ruin_survey": {"x": 610.0, "z": -140.0, "remaining": 71.0},
		"caravan": {"dst_x": 950.0, "dst_z": -680.0},
		"party": {
			"escort_caravan": {"dst_x": 1230.0, "dst_z": -520.0},
			"rally": {"x": 120.0, "z": 370.0, "remaining": 32.0},
			"ping": {"x": -100.0, "z": 80.0, "remaining": 15.0},
		},
	}


func run(t) -> void:
	t.current = "authenticated snapshot produces typed expedition objectives"
	var you: Dictionary = _snapshot()
	var goals: Array[Dictionary] = Atlas.objectives(you)
	t.eq(goals.size(), 7, "all seven existing expedition sources join one atlas")
	var keys: Array = goals.map(func(row: Dictionary): return row["key"])
	t.eq(keys, ["threat", "prospect", "ruin", "caravan", "escort", "rally", "ping"],
		"stable presentation and priority across snapshot refresh")
	t.eq(Atlas.find(goals, "threat").get("label"), "RAID BOSS",
		"authoritative raid class selects safe display label")
	t.eq(Atlas.find(goals, "prospect").get("label"), "T3 ORE VEIN",
		"real resource tier and kind decorate the atlas")
	t.eq(Atlas.find(goals, "caravan").get("x"), 950.0,
		"caravan navigation uses destination, not source settlement")
	t.eq(Atlas.find(goals, "escort").get("z"), -520.0,
		"courier destination comes only from authenticated party snapshot")
	t.eq(Atlas.find(goals, "rally").get("label"), "PARTY RALLY",
		"live rally becomes selectable")
	t.eq(Atlas.find(goals, "missing"), {}, "unknown goal has no navigation target")
	t.eq(Atlas.objectives(null).size(), 0, "malformed top-level state is harmless")
	t.eq(Atlas.objectives({"players": [{"threat_scan": you["threat_scan"]}]}).size(), 0,
		"other players' snapshots can never invent private map goals")

	t.current = "invalid and stale targets never become clickable markers"
	var invalid: Dictionary = _snapshot()
	invalid["threat_scan"] = {"x": INF, "z": 1.0,
		"kind": "raid", "remaining": 25.0}
	invalid["prospect_mark"] = {"x": 10.0, "z": 12.0,
		"kind": "ore", "tier": 8, "remaining": 80.0}
	invalid["ruin_survey"] = {"x": 50.0, "z": 50.0,
		"remaining": 0.0}
	invalid["caravan"] = {"dst_x": 4200.0, "dst_z": 0.0}
	invalid["party"] = {
		"rally": {"x": 60.0, "z": 0.0, "remaining": -1.0},
		"ping": {"x": 60.0, "z": 0.0, "remaining": NAN},
		"escort_caravan": {"dst_x": "500", "dst_z": 900},
	}
	t.eq(Atlas.objectives(invalid).size(), 0,
		"nonfinite, expired, out-of-world, invalid tier and string positions ignored")
	invalid["threat_scan"] = {"x": 10.0, "z": 10.0,
		"kind": "hacker_custom", "remaining": 30.0}
	invalid["prospect_mark"] = {"x": 10.0, "z": 10.0,
		"kind": "ore", "tier": 2, "remaining": "fake"}
	t.eq(Atlas.objectives(invalid).size(), 0,
		"unapproved labels and string timing cannot inject map entries")
	invalid["threat_scan"] = {"x": 10.0, "z": 10.0,
		"kind": "elite", "remaining": 6.0}
	t.eq(Atlas.objectives(invalid).size(), 1,
		"a legitimate elite is supported after invalid data is rejected")
	t.eq(Atlas.objectives(invalid)[0]["label"], "ELITE INFECTED",
		"only fixed safe user-facing text is displayed")

	t.current = "malformed group ping data cannot break personal map objectives"
	var bad_ping: Dictionary = _snapshot()
	bad_ping["party"]["ping"] = ["invalid", "rpc", "value"]
	t.eq(Atlas.objectives(bad_ping).size(), 6,
		"malformed group pings are skipped while other six goals remain")
	bad_ping["party"]["ping"] = {"x": 20.0, "z": -12.0,
		"remaining": 15.0, "kind": "survey", "material": "ore", "tier": "3"}
	t.eq(Atlas.find(Atlas.objectives(bad_ping), "ping").get("label", ""),
		"PARTY PING", "string tier cannot forge a high-tier prospect marker")
	bad_ping["party"]["ping"]["tier"] = 3
	t.eq(Atlas.find(Atlas.objectives(bad_ping), "ping").get("label", ""),
		"T3 ORE PARTY VEIN", "integer tier still shows real party survey detail")

	t.current = "selectable world-map goal synchronizes with radar even while hidden"
	var fake := FakeClient.new()
	fake.you = _snapshot()
	var atlas := WorldMap.new()
	var radar := Radar.new()
	atlas.client = fake
	atlas.visible = false
	atlas.personal_waypoint_changed.connect(radar.set_personal_waypoint)
	t.check(atlas.select_objective("threat"), "clicking tracked boss selects a valid route")
	t.eq(atlas.followed_objective, "threat", "map knows selected goal key")
	t.eq(atlas.waypoint, Vector2(90.0, 25.0),
		"raid target immediately becomes a private navigation pin")
	t.eq(radar.personal_waypoint, atlas.waypoint,
		"map signal also updates radar's real navigation destination")
	t.check(not atlas.select_objective("unknown"),
		"missing goal cannot overwrite a working route")
	t.eq(atlas.followed_objective, "threat",
		"invalid selection preserves existing target")
	fake.you["threat_scan"] = {"x": 105.0, "z": 42.0,
		"kind": "raid", "remaining": 18.0}
	atlas._process(0.1)
	t.eq(atlas.waypoint, Vector2(105.0, 42.0),
		"moving raid target updates full-map route when map is hidden")
	t.eq(radar.personal_waypoint, atlas.waypoint,
		"moving boss also changes the tactical radar guidance")
	fake.you.erase("threat_scan")
	atlas._process(0.1)
	t.check(not atlas.waypoint.is_finite(),
		"missing/expired boss tracking clears route instead of leaving ghost pin")
	t.check(not radar.personal_waypoint.is_finite(),
		"disappearing goal clears radar navigation")
	t.eq(atlas.followed_objective, "", "missing goal stops active following")
	t.check(atlas.select_objective("prospect"),
		"remaining high-tier mineral location can be followed")
	t.eq(radar.personal_waypoint, Vector2(320.0, 240.0),
		"prospecting shares same private map-to-radar signal")
	fake.you["prospect_mark"] = {}
	atlas._process(0.1)
	t.check(not radar.personal_waypoint.is_finite(),
		"depleted mineral target drops stale radar route")

	t.current = "manual map clicks take precedence over automatic following"
	t.check(atlas.select_objective("caravan"), "fixed caravan goal can be selected")
	t.check(atlas.set_waypoint(Vector2(150.0, 200.0)),
		"manual map click creates a new destination")
	t.eq(atlas.followed_objective, "", "manual click stops stale auto-follow")
	fake.you["caravan"] = {}
	atlas._process(0.1)
	t.eq(atlas.waypoint, Vector2(150.0, 200.0),
		"old disappearing caravan cannot erase manually chosen route")
	t.eq(radar.personal_waypoint, Vector2(150.0, 200.0),
		"manual route remains visible in radar")
	t.check(not atlas.select_objective("threat"),
		"expired threat cannot replace a manual waypoint")
	atlas.clear_waypoint()
	t.check(not radar.personal_waypoint.is_finite(),
		"explicit right-click clear propagates to radar")
	atlas.free()
	radar.free()
