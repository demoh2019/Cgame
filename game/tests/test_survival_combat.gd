extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const Combat = preload("res://scripts/shared/combat.gd")


func run(t) -> void:
	t.current = "hunger and thirst"
	var s := Survival.new()
	for i in 600: # Ten minutes at one second per step.
		s.tick(1.0)
	t.check(s.hunger < 100.0 - 20.0, "hunger falls over time")
	t.check(s.thirst < s.hunger, "thirst falls faster than hunger")
	t.near(s.hunger, 100.0 - Defs.HUNGER_PER_SECOND * 600.0, 0.01, "hunger rate")
	t.check(s.alive, "a well fed player is alive after ten minutes")

	t.current = "starvation"
	s = Survival.new()
	s.hunger = 0.0
	s.thirst = 0.0
	var steps := 0
	while s.alive and steps < 1000:
		s.tick(1.0)
		steps += 1
	t.check(not s.alive, "starving to death happens")
	t.check(steps > 30 and steps < 100, "...but not instantly (%d s)" % steps)
	t.near(s.health, 0.0, 0.0001, "health is clamped at zero")
	t.near(s.tick(1.0), 0.0, 0.0001, "the dead take no more damage")

	t.current = "recovery"
	s = Survival.new()
	s.health = 40.0
	for i in 20:
		s.tick(1.0)
	t.check(s.health > 40.0, "a fed player slowly heals")
	s = Survival.new()
	s.health = 40.0
	s.hunger = 20.0
	for i in 20:
		s.tick(1.0)
	t.check(s.health <= 40.0, "a hungry player does not")

	t.current = "healing and eating"
	s = Survival.new()
	s.hurt(70.0)
	s.heal(28.0)
	t.near(s.health, 58.0, 0.0001, "bandage heals")
	s.heal(1000.0)
	t.near(s.health, Defs.MAX_HEALTH, 0.0001, "healing is capped")
	s.hunger = 10.0
	s.eat(42.0)
	t.near(s.hunger, 52.0, 0.0001, "eating")
	s.eat(500.0)
	t.near(s.hunger, 100.0, 0.0001, "eating is capped")
	var dead := Survival.new()
	dead.hurt(500.0)
	dead.heal(50.0)
	t.near(dead.health, 0.0, 0.0001, "the dead cannot be healed")
	t.near(dead.hurt(10.0), 0.0, 0.0001, "the dead cannot be hurt again")

	t.current = "armour"
	t.near(Combat.apply_armor(100.0, ""), 100.0, 0.0001, "no armour")
	t.near(Combat.apply_armor(100.0, "jacket_1"), 92.0, 0.0001, "tier 1 jacket takes 8 percent")
	t.check(Combat.apply_armor(100.0, "jacket_4") < Combat.apply_armor(100.0, "jacket_2"), "better armour protects more")
	t.check(Combat.apply_armor(100.0, "jacket_4") > 50.0, "armour never makes you immune")

	t.current = "weapons"
	t.check(Combat.weapon_damage("club_1") > Combat.weapon_damage(""), "a club beats fists")
	t.check(Combat.weapon_damage("club_3") > Combat.weapon_damage("club_1"), "higher tier hits harder")
	t.near(Combat.weapon_damage("pistol"), 22.0, 0.0001, "pistol damage")
	t.check(Combat.weapon_cooldown("") > 0.0, "fists have a cooldown")

	t.current = "loot tables"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen: Dictionary = {}
	var always_silver := true
	for i in 300:
		var loot := Combat.crate_loot(i % 4, rng)
		if not loot.has("silver"):
			always_silver = false
		for id in loot:
			seen[id] = true
			t.check(Defs.is_item(id), "crate loot %s is a real item" % id)
			t.check(int(loot[id]) >= 1, "loot amounts are positive")
	t.check(always_silver, "crates always hold some silver")
	t.check(seen.has("canned_food") and seen.has("water_bottle") and seen.has("bandage"), "crates hold supplies")
	t.check(seen.has("ammo_9mm"), "crates hold ammo")
	rng.seed = 7
	var again := Combat.crate_loot(1, rng)
	rng.seed = 7
	t.eq(Combat.crate_loot(1, rng), again, "loot is deterministic for a given seed")
	for i in 50:
		for type in Defs.ZOMBIES:
			for id in Combat.zombie_loot(type, i % 4, rng):
				t.check(Defs.is_item(id), "zombie loot %s is a real item" % id)
