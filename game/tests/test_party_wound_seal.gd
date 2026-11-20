extends RefCounted
## Cooperative raid preparation through existing authenticated Aid / Share.
## A real zombie melee wound checks the recipient's private persisted buff.

const Defs = preload("res://scripts/shared/defs.gd")
const PartyAid = preload("res://scripts/shared/party_aid.gd")
const WoundSealant = preload("res://scripts/shared/wound_sealant.gd")
const ExpeditionLoadout = preload("res://scripts/shared/expedition_loadout.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	t.current = "manual party prophylaxis in the same catalog as healing"
	var data: Dictionary = Defs.item(WoundSealant.ITEM_ID)
	t.check(PartyAid.supported_item(WoundSealant.ITEM_ID, data),
		"only the genuine bite seal is available to party medics")
	t.check(not PartyAid.supported_item("fake_wound_seal", data),
		"crafted-item identity cannot be spoofed by a client")
	t.check(PartyAid.medical_items().has(WoundSealant.ITEM_ID),
		"existing Aid / Share selection includes bite prophylaxis")
	t.eq(ExpeditionLoadout.TARGETS["scout"]["wound_sealant"], 1,
		"scout expedition preset carries a paid field dose")
	t.eq(ExpeditionLoadout.TARGETS["medic"]["wound_sealant"], 2,
		"medic expedition preset reserves two teammate doses")
	var world := WorldGen.new(451)
	var sim := GameServer.new(world, 451)
	var medic = sim.add_player(851, "Party Medic")
	var ally = sim.add_player(852, "Frontline")
	var outsider = sim.add_player(853, "Outsider")
	medic.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	ally.position = medic.position + Vector3(1.0, 0.0, 0.0)
	outsider.position = medic.position + Vector3(1.5, 0.0, 0.0)
	medic.inventory.add(WoundSealant.ITEM_ID, 3)
	t.eq(sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID).get("reason", ""),
		"not_in_party", "strangers cannot provide prophylaxis")
	t.check(sim.cmd_party_invite(medic.id, ally.id).get("ok", false),
		"medic offers a legitimate party invitation")
	t.check(sim.cmd_party_accept(ally.id).get("ok", false), "recipient accepts the party")
	t.eq(sim.cmd_party_aid(medic.id, outsider.id, WoundSealant.ITEM_ID).get("reason", ""),
		"not_in_party", "outsider cannot receive medicine")
	t.eq(sim.cmd_party_aid(medic.id, medic.id, WoundSealant.ITEM_ID).get("reason", ""),
		"self", "the party-aid route cannot duplicate self-use")
	ally.position += Vector3(12.0, 0.0, 0.0)
	t.eq(sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID).get("reason", ""),
		"too_far", "no remote seal application")
	ally.position = medic.position + Vector3(1.0, 0.0, 0.0)
	medic.combat_tag_until = sim.time + 10.0
	t.eq(sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID).get("reason", ""),
		"in_combat", "medic cannot prepare a dose during combat")
	medic.combat_tag_until = 0.0
	ally.attack_timer = 1.0
	t.eq(sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID).get("reason", ""),
		"in_combat", "recipient cannot be mid-attack")
	ally.attack_timer = 0.0
	t.eq(medic.inventory.count(WoundSealant.ITEM_ID), 3,
		"denied requests have consumed no dose")
	medic.inventory.remove(WoundSealant.ITEM_ID, 3)
	t.eq(sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID).get("reason", ""),
		"not_carried", "server requires actual medic backpack supply")
	medic.inventory.add(WoundSealant.ITEM_ID, 3)

	t.current = "server-owned dose, cooldown and private party notification"
	var first: Dictionary = sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID)
	t.check(first.get("ok", false), "medic can prepare a nearby squad member")
	t.eq(first.get("peer", -1), ally.id, "response identifies the actual patient")
	t.near(float(first.get("wound_seal_seconds", 0.0)),
		WoundSealant.DURATION_SECONDS, 0.001, "no client-selected duration")
	t.eq(medic.inventory.count(WoundSealant.ITEM_ID), 2, "exactly one dose spent")
	t.eq(medic.wound_seal_seconds, 0.0, "medic did not grant self immunity")
	t.near(ally.wound_seal_seconds, WoundSealant.DURATION_SECONDS, 0.001,
		"real recipient receives protective timer")
	t.near(medic.party_aid_timer, PartyAid.COOLDOWN, 0.001,
		"shared party medical cooldown applies")
	t.check(medic.dirty_inventory and medic.dirty_character and ally.dirty_character,
		"both account inventories and recipient buff scheduled for persistence")
	t.eq(sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID).get("reason", ""),
		"cooldown", "immediate retry cannot spend another dose")
	t.eq(medic.inventory.count(WoundSealant.ITEM_ID), 2, "cooldown replay no-ops")
	medic.party_aid_timer = 0.0
	t.eq(sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID).get("reason", ""),
		"already_sealed", "active ally protection cannot stack")
	t.eq(medic.inventory.count(WoundSealant.ITEM_ID), 2,
		"duplicate protection attempt still costs nothing")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_party_aid"), "existing authenticated party RPC is reused")
	var seen: bool = false
	for event in sim.events:
		if event.get("type") != "party_aid" or event.get("item") != WoundSealant.ITEM_ID:
			continue
		seen = true
		t.check(net._event_visible_to(event, medic.id), "giver receives treatment event")
		t.check(net._event_visible_to(event, ally.id), "patient receives treatment event")
		t.check(not net._event_visible_to(event, outsider.id), "outsider cannot inspect medicine")
	t.check(seen, "one authoritative team prophylaxis event is emitted")
	net.free()

	t.current = "real infected hit, persistence and protection expiry"
	var snapshot: Dictionary = sim.snapshot_for(ally.id)
	t.near(float(snapshot["you"].get("wound_seal_seconds", 0.0)),
		WoundSealant.DURATION_SECONDS, 0.001, "patient privately sees status in HUD")
	var saved: Dictionary = sim.character_data(ally)
	ally.wound_seal_seconds = 0.0
	t.check(sim.apply_character(ally, saved), "recipient reload keeps spent buff")
	t.near(ally.wound_seal_seconds, WoundSealant.DURATION_SECONDS, 0.001,
		"cannot relog to restart timing")
	# Remove other survivors from zombie sensing before the hit so this
	# test exercises the actually protected target, not aggro rerouting.
	var old_medic_position: Vector3 = medic.position
	medic.position = Vector3(450.0, world.height_at(450.0, 450.0), 450.0)
	outsider.position = Vector3(460.0, world.height_at(460.0, 460.0), 460.0)
	sim.zombies.clear()
	var infected := Zombie.new(sim.new_id(), "walker",
		ally.position + Vector3(1.1, 0.0, 0.0))
	infected.state = Zombie.State.ATTACK
	infected.target_id = ally.id
	sim.zombies[infected.id] = infected
	sim._tick_zombies(0.1)
	t.near(ally.survival.infection,
		8.0 * WoundSealant.INFECTION_FACTOR, 0.001,
		"actual infected bite hits protected ally, not the medic")
	t.near(ally.survival.bleeding, Defs.ZOMBIE_BLEEDING_PER_HIT["walker"], 0.001,
		"bite bleed is not mitigated")
	ally.survival.reset()
	ally.wound_seal_seconds = 0.0
	medic.position = old_medic_position
	medic.party_aid_timer = 0.0
	t.check(sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID).get("ok", false),
		"a fresh dose can be applied after protection expires")
	t.eq(medic.inventory.count(WoundSealant.ITEM_ID), 1, "one new dose spent")
	medic.party_aid_timer = 0.0
	ally.survival.hurt(1000.0)
	t.eq(sim.cmd_party_aid(medic.id, ally.id, WoundSealant.ITEM_ID).get("reason", ""),
		"dead", "dead patients cannot receive a prophylactic dose")
