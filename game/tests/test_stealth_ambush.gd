extends RefCounted
## Crouching, melee ownership, alertness, PvE rewards and event privacy.
const Combat = preload("res://scripts/shared/combat.gd")
const Ambush = preload("res://scripts/shared/stealth_ambush.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Server = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	var world := WorldGen.new(42)
	var sim := Server.new(world, 192)
	var scout = sim.add_player(91, "Scout")
	scout.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	scout.inventory.add("club_1", 1)
	t.check(scout.inventory.equip("club_1"), "real weapon equipped")
	var infected := Zombie.new(sim.new_id(), "brute",
		Vector3(200.0, world.height_at(200.0, 201.4), 201.4))
	sim.zombies[infected.id] = infected
	t.current = "backstabs require crouched silent melee from behind"
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0, "standing has no bonus")
	scout.crouching = true
	t.near(Ambush.multiplier(scout, infected, "club_1"), Ambush.DAMAGE_MULTIPLIER,
		0.001, "quiet crouched rear opener qualifies")
	t.eq(Ambush.multiplier(scout, infected, ""), 1.0, "fists cannot ambush")
	scout.noise_timer = 1.0
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0,
		"noise breaks the hidden opener")
	scout.noise_timer = 0.0
	scout.survival.bleeding = 10.0
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0,
		"bleeding survivor cannot sneak up unnoticed")
	scout.survival.bleeding = 0.0
	infected.yaw = PI
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0,
		"facing enemy cannot be backstabbed")
	infected.yaw = 0.0
	infected.state = Zombie.State.CHASE
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0,
		"alerted infected is immune")
	infected.state = Zombie.State.IDLE
	infected.target_id = 91
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0,
		"enemy target awareness cannot be bypassed")
	infected.target_id = -1
	infected.threat[91] = 5.0
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0,
		"combat threat prevents repeated ambush")
	infected.threat.clear()
	infected.raid_boss = true
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0, "boss is immune")
	infected.raid_boss = false
	infected.elite = true
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0, "elite is immune")
	infected.elite = false
	infected.supply_cache_id = 10
	t.eq(Ambush.multiplier(scout, infected, "club_1"), 1.0,
		"supply cache guardian is immune")
	infected.supply_cache_id = -1

	t.current = "real server attack bonuses occur once, no artificial progression"
	var before: float = infected.health
	var response: Dictionary = sim.cmd_attack(91, 0.0, 1.0)
	t.check(bool(response.get("hit", false)), "server verifies an actual hit")
	t.check(bool(response.get("ambush", false)), "server acknowledges genuine ambush")
	t.near(infected.health, before - Combat.weapon_damage("club_1") * Ambush.DAMAGE_MULTIPLIER,
		0.001, "melee opener has exactly 45 percent bonus")
	var notify: Dictionary = {}
	for event in sim.events:
		if str(event.get("type", "")) == "stealth_ambush":
			notify = event
	t.eq(int(notify.get("peer", -1)), 91, "only real opening attacks get an event")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to(notify, 91), "own ambush notice is visible")
	t.check(not net._event_visible_to(notify, 92), "private notice is not leaked")
	net.free()
	scout.attack_timer = 0.0
	before = infected.health
	response = sim.cmd_attack(91, 0.0, 1.0)
	t.check(bool(response.get("hit", false)), "subsequent melee attack still hits")
	t.check(not bool(response.get("ambush", false)), "subsequent hit gets no bonus")
	t.near(infected.health, before - Combat.weapon_damage("club_1"),
		0.001, "follow-up has ordinary damage")
	t.eq(int(scout.progression.combat_xp["melee"]), 0, "no invented kill mastery")

	t.current = "ranged fire and stolen weapons are ineligible"
	var second := Zombie.new(sim.new_id(), "brute",
		Vector3(200.0, world.height_at(200.0, 202.0), 202.0))
	sim.zombies[second.id] = second
	scout.inventory.add("pistol", 1)
	t.check(scout.inventory.equip("pistol"), "real pistol equipped")
	t.eq(Ambush.multiplier(scout, second, "pistol"), 1.0,
		"ranged weapons cannot claim melee bonus")
	scout.inventory.equip("club_1")
	scout.inventory.remove("club_1", 1)
	t.eq(Ambush.multiplier(scout, second, "club_1"), 1.0,
		"stale equipment ID cannot claim the bonus")
