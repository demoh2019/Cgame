extends RefCounted
## Group healing scales with earned Medic mastery, never forged clients.
## Existing cooldown, party consent and real supply costs remain authoritative.
const Mastery = preload("res://scripts/shared/party_medic_mastery.gd")
const PartyTriage = preload("res://scripts/shared/party_triage.gd")
const Skills = preload("res://scripts/shared/skills.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "allied healing multiplier is bounded and rejects invalid values"
	t.near(Mastery.heal_amount(28.0, 0.0), 28.0, 0.001,
		"novice party medic has normal bandage healing")
	t.near(Mastery.heal_amount(28.0, 0.25), 35.0, 0.001,
		"earned Medic mastery improves allied health restoration")
	t.near(Mastery.heal_amount(28.0, 3.0), 37.8, 0.001,
		"even high-end perks cannot exceed the 35 percent party cap")
	for invalid in [NAN, INF, -1.0]:
		t.eq(Mastery.heal_amount(28.0, invalid), 0.0,
			"invalid player mastery cannot create free healing")
		t.eq(Mastery.heal_amount(invalid, 0.2), 0.0,
			"invalid base medicine cannot create free healing")
	t.eq(Mastery.training_xp(0, 0, 0, 0, 0), 0.0,
		"no benefit generates zero XP")
	t.eq(Mastery.training_xp(0.001, 0, 0, 0, 0), 0.0,
		"tiny scratches cannot train a medic")
	t.eq(Mastery.training_xp(600, 200, 100, 100, 100), Mastery.MAX_TRAINING_XP,
		"one action can never farm unbounded mastery")
	t.eq(Mastery.training_xp(28, NAN, 0, 0, 0), 0.0,
		"corrupt wound data cannot mint XP")
	t.check(Mastery.training_xp(0, 24, 0, 0, 0) > 0.0,
		"actual wound dressing trains medical mastery even without missing HP")

	t.current = "real party medicine trains Medic and respects cooldown"
	var world := WorldGen.new(5201)
	var server := GameServer.new(world, 5201)
	var medic = server.add_player(201, "Medic")
	var ally = server.add_player(202, "Defender")
	var outsider = server.add_player(203, "Stranger")
	medic.position = _at(world, 8.0, 8.0)
	ally.position = _at(world, 9.0, 8.0)
	outsider.position = _at(world, 10.0, 8.0)
	t.check(server.cmd_party_invite(201, 202).get("ok", false),
		"medic invites legitimate nearby ally")
	t.check(server.cmd_party_accept(202).get("ok", false),
		"recipient consents to the party")
	medic.inventory.add("bandage", 4)
	var initial_bandages: int = medic.inventory.count("bandage")
	ally.survival.hurt(60.0)
	var initial_xp: int = int(medic.skills.xp["medic"])
	t.eq(server.cmd_party_aid(201, 203, "bandage").get("reason", ""), "not_in_party",
		"cannot level up by healing strangers")
	t.eq(int(medic.skills.xp["medic"]), initial_xp,
		"failed foreign treatment gives zero XP")
	var aid: Dictionary = server.cmd_party_aid(201, 202, "bandage")
	t.check(aid.get("ok", false), "real single-target treatment works")
	t.near(float(aid.get("heal", 0.0)), 28.0, 0.001,
		"novice bandage restores base health")
	t.check(int(medic.skills.xp["medic"]) > initial_xp,
		"server awards Medic XP for actual recovered HP")
	t.eq(medic.inventory.count("bandage"), initial_bandages - 1,
		"medicine spends exactly one item even with starter supplies")
	var trained_xp: int = int(medic.skills.xp["medic"])
	t.eq(server.cmd_party_aid(201, 202, "bandage").get("reason", ""), "cooldown",
		"replayed healing cannot bypass five-second timer")
	t.eq(int(medic.skills.xp["medic"]), trained_xp,
		"replayed request cannot farm XP")
	t.eq(medic.inventory.count("bandage"), initial_bandages - 1,
		"replay does not debit extra items")

	t.current = "advanced medics improve normal and automatic party care"
	medic.skills.add_xp("medic", float(Skills.xp_for_level(30)))
	var bonus: float = medic.skills.bonus("heal_power")
	t.check(bonus > 0.0, "real earned mastery grants positive heal_power")
	medic.party_aid_timer = 0.0
	ally.survival.health = 10.0
	var enhanced: Dictionary = server.cmd_party_aid(201, 202, "bandage")
	t.check(enhanced.get("ok", false), "trained healer can treat teammate")
	t.near(float(enhanced.get("heal", 0.0)), Mastery.heal_amount(28.0, bonus),
		0.001, "allied bandage scales from server Medic perks")
	medic.party_aid_timer = 0.0
	ally.survival.health = 10.0
	var automatic: Dictionary = server.cmd_party_aid(201, 202, "auto")
	t.check(automatic.get("ok", false), "automatic selection uses the same mastery")
	t.eq(str(automatic.get("item", "")), "bandage",
		"auto cannot invent expensive or missing medicine")
	t.near(float(automatic.get("heal", 0.0)), Mastery.heal_amount(28.0, bonus),
		0.001, "auto medicine scales with real medic level")
	medic.party_aid_timer = 0.0
	ally.survival.heal(1000.0)
	var xp_before_food: int = int(medic.skills.xp["medic"])
	medic.inventory.add("water_bottle", 1)
	ally.survival.thirst = 20.0
	t.check(server.cmd_party_aid(201, 202, "water_bottle").get("ok", false),
		"existing provisions sharing remains available")
	t.eq(int(medic.skills.xp["medic"]), xp_before_food,
		"providing water is not secretly treated as medical practice")
	medic.party_aid_timer = 0.0
	ally.survival.thirst = 100.0
	var leftover_water: int = medic.inventory.count("water_bottle")
	t.eq(server.cmd_party_aid(201, 202, "water_bottle").get("reason", ""),
		"no_effect", "fully hydrated allies cannot waste another bottle")
	t.eq(medic.inventory.count("water_bottle"), leftover_water,
		"rejected provision share keeps real starter supplies")
	t.eq(int(medic.skills.xp["medic"]), xp_before_food, "failed share gives zero XP")

	t.current = "triage heals actual allies with bounded shared medical mastery"
	var squad_world := WorldGen.new(5202)
	var squad := GameServer.new(squad_world, 5202)
	var healer = squad.add_player(211, "Expert")
	var first = squad.add_player(212, "First")
	var second = squad.add_player(213, "Second")
	healer.position = _at(squad_world, 8.0, 8.0)
	first.position = _at(squad_world, 9.0, 8.0)
	second.position = _at(squad_world, 8.0, 9.0)
	for pid in [212, 213]:
		t.check(squad.cmd_party_invite(211, pid).get("ok", false),
			"triage medic creates the squad")
		t.check(squad.cmd_party_accept(pid).get("ok", false),
			"teammates voluntarily join")
	healer.skills.add_xp("medic", float(Skills.xp_for_level(30)))
	var squad_bonus: float = healer.skills.bonus("heal_power")
	healer.inventory.add(PartyTriage.ITEM_ID, 2)
	first.survival.hurt(50.0)
	second.survival.hurt(50.0)
	var first_xp: int = int(healer.skills.xp["medic"])
	var triage: Dictionary = squad.cmd_party_triage(211)
	t.check(triage.get("ok", false), "trained medic spends a real group pack")
	t.eq(int(triage.get("treated", 0)), 2, "only two existing teammates treated")
	t.near(float(triage.get("heal", 0.0)), Mastery.heal_amount(PartyTriage.HEAL,
		squad_bonus) * 2.0, 0.001, "both patients receive bounded mastery bonus")
	t.eq(healer.inventory.count(PartyTriage.ITEM_ID), 1,
		"one actual kit treats both teammates")
	t.check(int(healer.skills.xp["medic"]) > first_xp,
		"verified group triage trains the healer")
	var after_triage: int = int(healer.skills.xp["medic"])
	t.eq(squad.cmd_party_triage(211).get("reason", ""), "cooldown",
		"replay cannot spend kits or train further")
	t.eq(int(healer.skills.xp["medic"]), after_triage,
		"rejected triage grants no mastery")
	t.eq(healer.inventory.count(PartyTriage.ITEM_ID), 1,
		"cooldown preserves the remaining real kit")
