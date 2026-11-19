extends RefCounted
## Lineage-style contestable outposts using existing server-owned parties.
## Physical presence, full-loot zoning and claim time are never client-authored.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")


func _at(server, site: Dictionary) -> Vector3:
	var x: float = float(site["x"])
	var z: float = float(site["z"])
	return Vector3(x, server.world.height_at(x, z), z)


func _advance(server, duration: float) -> Array:
	var events: Array = []
	for step in range(int(ceil(duration / 0.25))):
		server.time += 0.25
		events.append_array(server.territory.tick(0.25, server.time, server.players, server.parties))
	return events


func run(t) -> void:
	t.current = "outpost sites are seeded, accessible and inside full-loot territory"
	var first := GameServer.new(WorldGen.new(205), 205)
	var second := GameServer.new(WorldGen.new(205), 205)
	t.check(first.territory.sites.size() >= 1, "at least one contested outpost placed on seed 205")
	t.eq(first.territory.public_state(0.0), second.territory.public_state(0.0),
		"outpost coordinates reproducible from same world seed")
	for site in first.territory.sites:
		var x: float = float(site["x"])
		var z: float = float(site["z"])
		t.check(ZoneRisk.allows_pvp(first.world.zone_at(x, z)), "outpost lies in dangerous PvP territory")
		t.check(not first.world.is_water(x, z), "outpost is on dry ground")
		t.check(first.world.normal_at(x, z).y >= 0.7, "outpost is on navigable terrain")
	if first.territory.sites.is_empty():
		return
	var outpost: Dictionary = first.territory.sites[0]
	var leader = first.add_player(101, "Siege leader")
	var ally = first.add_player(102, "Defender")
	var hostile = first.add_player(103, "Hostile")
	var raider = first.add_player(104, "Raider")
	var spot := _at(first, outpost)
	leader.position = spot
	ally.position = spot + Vector3(1.0, 0.0, 0.0)
	hostile.position = spot + Vector3(60.0, 0.0, 0.0)
	raider.position = spot + Vector3(60.0, 0.0, 0.0)

	t.current = "capture needs two living members of one real server party"
	_advance(first, Territory.CAPTURE_SECONDS + 2.0)
	t.eq(outpost["owner"], 0, "two unaffiliated players cannot capture")
	t.check(first.parties.invite(101, 102, first.time)["ok"], "leader creates a real party")
	t.check(first.parties.accept(102, first.time)["ok"], "ally joins group")
	var owners_party: int = first.parties.group_of(101)
	t.check(owners_party > 0, "server group identity allocated")
	ally.survival.hurt(10000.0)
	_advance(first, Territory.CAPTURE_SECONDS + 2.0)
	t.eq(outpost["owner"], 0, "dead second party member does not count toward capture")
	ally.survival.reset()
	# An enemy can physically contest even without creating a party.
	hostile.position = spot + Vector3(2.0, 0.0, 0.0)
	_advance(first, Territory.CAPTURE_SECONDS + 2.0)
	t.eq(outpost["owner"], 0, "hostile solo survivor prevents an uncontested claim")
	t.check(bool(outpost["contested"]), "point is flagged contested")
	hostile.position = spot + Vector3(60.0, 0.0, 0.0)
	var captured: Array = _advance(first, Territory.CAPTURE_SECONDS + 1.0)
	t.eq(outpost["owner"], owners_party, "uncontested party holds the outpost after capture timer")
	t.check(captured.any(func(e): return e["type"] == "outpost_taken"),
		"server emits one captured event")
	t.eq(captured.filter(func(e): return e["type"] == "outpost_taken").size(), 1,
		"no duplicate capture rewards or events from repeated ticks")
	t.check(first.territory.has_rally_bonus(101, leader.position, first.parties, first.time),
		"living defenders get proximity-based rally benefit")
	t.check(not first.territory.has_rally_bonus(103, hostile.position, first.parties, first.time),
		"unaffiliated players cannot claim party rally benefit")
	t.check(not first.territory.has_rally_bonus(102, spot + Vector3(100.0, 0.0, 0.0), first.parties, first.time),
		"outpost rally cannot be applied remotely")
	var snapshot: Dictionary = first.snapshot_for(101)
	t.eq(snapshot["outposts"].size(), first.territory.sites.size(),
		"server exposes public outpost state in regular snapshots")
	t.check(not snapshot["outposts"][0].has("user_id"),
		"outpost public state does not leak account IDs")

	t.current = "real rival party can retake and owner expiry/disband neutralizes"
	hostile.position = spot
	raider.position = spot + Vector3(1.0, 0.0, 0.0)
	t.check(first.parties.invite(103, 104, first.time)["ok"], "rival can form a party")
	t.check(first.parties.accept(104, first.time)["ok"], "rival has two members")
	var rival_party := first.parties.group_of(103)
	_advance(first, 2.0)
	t.eq(outpost["owner"], owners_party, "contesting does not instantly steal current owner")
	leader.position = spot + Vector3(60.0, 0.0, 0.0)
	ally.position = spot + Vector3(60.0, 0.0, 0.0)
	_advance(first, Territory.CAPTURE_SECONDS + 1.0)
	t.eq(outpost["owner"], rival_party, "second party may retake territory through presence")
	t.check(not first.territory.has_rally_bonus(101, spot, first.parties, first.time),
		"former owner loses stamina rally immediately")
	t.check(first.territory.has_rally_bonus(103, hostile.position, first.parties, first.time),
		"new defenders receive the benefit")
	first.parties.leave(104)
	first.territory.tick(0.25, first.time + 0.25, first.players, first.parties)
	t.eq(outpost["owner"], 0, "disbanding the controlling party frees the outpost")
	t.check(not first.territory.has_rally_bonus(103, hostile.position, first.parties, first.time),
		"no permanent benefits after party disband")

	t.current = "outpost status is bounded and never client owned"
	var public: Array = first.territory.public_state(first.time)
	for entry in public:
		t.check(float(entry["progress"]) >= 0.0 and float(entry["progress"]) <= Territory.CAPTURE_SECONDS,
			"capture progress remains bounded")
		t.check(float(entry["expires_in"]) >= 0.0, "expiry is not negative")
	t.eq(first.territory.tick(NAN, first.time, first.players, first.parties).size(), 0,
		"invalid tick duration cannot advance capture")
