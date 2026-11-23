extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


## Snapshot of the original ordered probability rules. The native sampler
## must preserve actual loot AND consumption of the server's seeded RNG.
static func _legacy_crate_loot(zone: int, rng: RandomNumberGenerator) -> Dictionary:
	var loot: Dictionary = {}
	var tier: int = WorldGen.tier_for_zone(zone)
	var rolls: int = rng.randi_range(2, 4)
	for i in rolls:
		var roll: float = rng.randf()
		if roll < 0.24:
			loot["canned_food"] = int(loot.get("canned_food", 0)) + 1
		elif roll < 0.44:
			loot["water_bottle"] = int(loot.get("water_bottle", 0)) + 1
		elif roll < 0.60:
			loot["bandage"] = int(loot.get("bandage", 0)) + rng.randi_range(1, 2)
		elif roll < 0.76:
			loot["scrap"] = int(loot.get("scrap", 0)) + rng.randi_range(2, 6)
		elif roll < 0.86:
			loot["cloth_%d" % tier] = int(loot.get("cloth_%d" % tier, 0)) + rng.randi_range(1, 3)
		elif roll < 0.95:
			loot["ammo_9mm"] = int(loot.get("ammo_9mm", 0)) + rng.randi_range(6, 18)
		else:
			loot["pistol"] = 1
	if rng.randf() < (0.14 if zone >= 2 else 0.025):
		loot["antibiotics"] = 1
	loot["silver"] = rng.randi_range(2, 10) * tier
	return loot


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

	t.current = "invalid simulation inputs never corrupt persistent vitals"
	var validated := Survival.new()
	validated.health = 60.0
	validated.hunger = 50.0
	validated.thirst = 40.0
	validated.bleeding = 10.0
	var before: Dictionary = validated.to_dict()
	for invalid_delta in [-1.0, NAN, INF]:
		t.eq(validated.tick(invalid_delta), 0.0,
			"invalid clock cannot apply starvation or recovery")
		t.eq(validated.to_dict(), before,
			"invalid clock must leave all saved vitals unchanged")
	for invalid_amount in [NAN, INF, -INF, -10.0]:
		t.eq(validated.hurt(invalid_amount), 0.0,
			"invalid damage does not alter health")
		validated.heal(invalid_amount)
		validated.eat(invalid_amount)
		validated.drink(invalid_amount)
		t.eq(validated.to_dict(), before,
			"invalid healing and consumption cannot poison state")
	t.near(validated.hurt(7.0), 7.0, 0.001,
		"valid damage still applies after rejection")
	validated.heal(4.0)
	t.near(validated.health, 57.0, 0.001,
		"valid healing still works after rejection")
	validated.eat(3.0)
	validated.drink(2.0)
	t.near(validated.hunger, 53.0, 0.001, "valid food restores hunger")
	t.near(validated.thirst, 42.0, 0.001, "valid water restores thirst")

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

	t.current = "native weighted crate categories with seeded fallback parity"
	var boundaries: Array[float] = [0.0, 0.23999, 0.24, 0.43999,
		0.44, 0.59999, 0.60, 0.75999, 0.76, 0.85999, 0.86, 0.94999, 0.95, 0.99999]
	var expected_buckets: Array[int] = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6]
	for i in boundaries.size():
		t.eq(Combat.crate_loot_bucket(boundaries[i]), expected_buckets[i],
			"category boundary %d retains historical probability" % i)
	if ClassDB.class_exists("WeightedChoiceTable"):
		var table: Object = ClassDB.instantiate("WeightedChoiceTable")
		t.check(table != null, "weighted selection is available as a native engine Resource")
		if table != null:
			var weights := PackedFloat64Array([24.0, 20.0, 16.0, 16.0, 10.0, 9.0, 5.0])
			t.check(bool(table.call("configure", weights)), "native table accepts valid crate weights")
			t.eq(int(table.call("get_option_count")), 7, "native table keeps seven loot categories")
			t.near(float(table.call("get_probability", 6)), 0.05, 0.000001,
				"pistol chance stays five percent")
			var samples := PackedFloat64Array([0.0, 0.24, 0.44, 0.95])
			t.eq(table.call("sample_many", samples), PackedInt32Array([0, 1, 2, 6]),
				"native multi-sample preserves order")
			t.check(not bool(table.call("configure", PackedFloat64Array([1.0, -3.0]))),
				"invalid table replacement is rejected")
			t.eq(int(table.call("sample_unit", 0.95)), 6,
				"rejected replacement leaves prior native table intact")
	else:
		t.eq(Combat.crate_loot_bucket(0.95), 6, "stock Godot keeps historical rarity")
	for zone in range(4):
		for sample_seed in range(64):
			var seed: int = sample_seed * 7919 + zone * 16127 + 17
			var expected_rng := RandomNumberGenerator.new()
			var actual_rng := RandomNumberGenerator.new()
			expected_rng.seed = seed
			actual_rng.seed = seed
			var before: Dictionary = _legacy_crate_loot(zone, expected_rng)
			var after: Dictionary = Combat.crate_loot(zone, actual_rng)
			t.eq(after, before, "crate item parity zone %d seed %d" % [zone, seed])
			t.eq(actual_rng.state, expected_rng.state,
				"RNG draw order preserved zone %d seed %d" % [zone, seed])

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
