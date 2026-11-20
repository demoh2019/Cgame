extends RefCounted
## Crafting and multiplayer field triage: privacy, bounded heal and item spend.

const Defs = preload("res://scripts/shared/defs.gd")
const PartyTriage = preload("res://scripts/shared/party_triage.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "triage kit is a real craftable item"
	t.check(Defs.is_item(PartyTriage.ITEM_ID), "triage pack is registered")
	t.eq(str(Defs.item(PartyTriage.ITEM_ID).get("kind", "")), "party_medical",
		"kit cannot be used as free regular self-healing")
	var recipe: Dictionary = Defs.recipes().get(PartyTriage.ITEM_ID, {})
	t.eq(str(recipe.get("station", "")), "workbench", "proper station required")
	t.eq(recipe.get("inputs", {}).get("bandage", 0), 2,
		"crafting spends two real bandages")
	t.eq(recipe.get("inputs", {}).get("field_antiseptic", 0), 1,
		"crafting spends antiseptic")
	t.check(PartyTriage.can_reach(Vector3.ZERO, Vector3(5.5, 0, 0)),
		"maximum horizontal treatment range is inclusive")
	t.check(not PartyTriage.can_reach(Vector3.ZERO, Vector3(5.51, 0, 0)),
		"healing cannot ignore horizontal distance")
	t.check(not PartyTriage.can_reach(Vector3.ZERO, Vector3(0, 2.6, 0)),
		"healing cannot cross tall floors")
	t.check(not PartyTriage.can_reach(Vector3(INF, 0, 0), Vector3.ZERO),
		"invalid coordinates cannot bypass range")
	t.eq(PartyTriage.urgency(100.0, 100.0, 0.0), 0.0,
		"healthy teammate is not a target")
	t.eq(PartyTriage.urgency(99.0, 100.0, NAN), 0.0,
		"nonfinite wounds cannot be treated")
	t.check(PartyTriage.urgency(60.0, 100.0, 20.0) >
		PartyTriage.urgency(98.0, 100.0, 0.0),
		"severe injuries are treated first")

	t.current = "server chooses three hurt members in party, never a stranger"
	var world := WorldGen.new(810)
	var server := GameServer.new(world, 810)
	var medic = server.add_player(101, "Medic")
	var first = server.add_player(102, "First")
	var second = server.add_player(103, "Second")
	var third = server.add_player(104, "Third")
	var fourth = server.add_player(105, "Fourth")
	var outsider = server.add_player(106, "Outsider")
	medic.position = _at(world, 8.0, 8.0)
	first.position = _at(world, 8.5, 8.0)
	second.position = _at(world, 9.0, 8.0)
	third.position = _at(world, 9.5, 8.0)
	fourth.position = _at(world, 10.0, 8.0)
	outsider.position = _at(world, 10.5, 8.0)
	medic.inventory.add(PartyTriage.ITEM_ID, 2)
	first.survival.hurt(50.0)
	first.survival.add_bleeding(10.0)
	second.survival.hurt(30.0)
	second.survival.add_bleeding(20.0)
	third.survival.hurt(60.0)
	fourth.survival.hurt(2.0)
	medic.survival.hurt(10.0)
	outsider.survival.hurt(30.0)
	t.eq(server.cmd_party_triage(101).get("reason", ""), "not_in_party",
		"unrelated survivors cannot trigger group heals")
	t.eq(medic.inventory.count(PartyTriage.ITEM_ID), 2,
		"no party means no item is spent")
	for id in [102, 103, 104, 105]:
		t.check(server.cmd_party_invite(101, id).get("ok", false), "medic invites survivor")
		t.check(server.cmd_party_accept(id).get("ok", false), "survivor voluntarily joins")
	t.eq(server.cmd_party_triage(106).get("reason", ""), "not_in_party",
		"stranger cannot invoke the group mechanic")
	var outcome: Dictionary = server.cmd_party_triage(101)
	t.check(bool(outcome.get("ok", false)), "carried pack treats a squad")
	t.eq(int(outcome.get("treated", 0)), 3, "no more than three allies treated")
	t.near(float(outcome.get("heal", 0.0)), 54.0, 0.001,
		"three wounded allies each receive at most 18 HP")
	t.near(float(outcome.get("bleeding_stopped", 0.0)), 30.0, 0.001,
		"bleeding treatment is bounded and tracked")
	t.near(first.survival.health, 68.0, 0.001, "first wounded ally healed")
	t.near(second.survival.health, 88.0, 0.001, "second wounded ally healed")
	t.near(third.survival.health, 58.0, 0.001, "third wounded ally healed")
	t.near(fourth.survival.health, 98.0, 0.001, "least urgent fourth ally is untouched")
	t.near(outsider.survival.health, 70.0, 0.001, "outsider never benefits")
	t.near(medic.survival.health, 90.0, 0.001, "medic does not self-heal")
	t.near(first.survival.bleeding, 0.0, 0.001, "small wound staunched")
	t.near(second.survival.bleeding, 0.0, 0.001, "large wound reduced by at most 24")
	t.eq(medic.inventory.count(PartyTriage.ITEM_ID), 1, "exactly one kit consumed")
	t.near(medic.party_aid_timer, PartyTriage.COOLDOWN, 0.001,
		"group treatment shares normal medical cooldown")
	t.check(medic.dirty_inventory and medic.dirty_character,
		"treated consumable is tracked for authoritative inventory state")
	t.eq(server.cmd_party_triage(101).get("reason", ""), "cooldown",
		"replayed request cannot spend another kit")
	t.eq(medic.inventory.count(PartyTriage.ITEM_ID), 1,
		"rejected replay leaves supplies unchanged")
	var triage_events: Array = []
	for event in server.drain_events():
		if event.get("type", "") == "party_triage":
			triage_events.append(event)
	t.eq(triage_events.size(), 3, "one private event per treated recipient")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net.has_method("c_party_triage"), "authenticated network RPC available")
	for event in triage_events:
		var target_id: int = int(event["peer"])
		t.check(net._event_visible_to(event, target_id), "recipient sees their care")
		t.check(net._event_visible_to(event, 101), "medic sees successful care")
		t.check(not net._event_visible_to(event, 106), "outsider cannot see aid data")
		t.check(not net._event_visible_to(event, 105), "untreated member cannot inspect teammate wounds")
	net.free()

	t.current = "no waste on healthy, distant, unreachable or dead patients"
	medic.party_aid_timer = 0.0
	first.survival.heal(100.0)
	second.survival.heal(100.0)
	third.survival.heal(100.0)
	fourth.survival.heal(100.0)
	second.position = _at(world, 90.0, 90.0)
	t.eq(server.cmd_party_triage(101).get("reason", ""), "no_wounded_allies",
		"healthy or distant squad members cannot waste a kit")
	t.eq(medic.inventory.count(PartyTriage.ITEM_ID), 1,
		"no-effect request has no cost and no timer")
	first.survival.hurt(45.0)
	first.position = medic.position + Vector3(0.0, 3.0, 0.0)
	t.eq(server.cmd_party_triage(101).get("reason", ""), "no_wounded_allies",
		"range rejects wounded teammates on a higher floor")
	first.position = _at(world, 8.5, 8.0)
	t.check(server.cmd_party_triage(101).get("ok", false),
		"last pack treats one genuinely wounded ally")
	t.eq(medic.inventory.count(PartyTriage.ITEM_ID), 0, "second valid use spends final kit")
	medic.party_aid_timer = 0.0
	first.survival.hurt(2.0)
	t.eq(server.cmd_party_triage(101).get("reason", ""), "not_carried",
		"zero items means zero healing")
	medic.inventory.add(PartyTriage.ITEM_ID, 1)
	medic.survival.hurt(999.0)
	t.eq(server.cmd_party_triage(101).get("reason", ""), "dead",
		"dead medics cannot provide treatment")
	t.eq(medic.inventory.count(PartyTriage.ITEM_ID), 1,
		"death rejection does not consume supplies")
