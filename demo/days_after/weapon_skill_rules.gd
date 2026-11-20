extends RefCounted
## Game-only, data-driven active abilities granted by the current weapon.
## These balance rules can later be evaluated authoritatively by the server.

const SKILLS := {
    "rusty_spear": {
        "name": "Heavy Thrust",
        "damage_multiplier": 1.5,
        "range": 3.1,
        "energy_cost": 25.0,
        "cooldown": 6.0,
        "attack_lock": 0.9
    },
    "reinforced_spear": {
        "name": "Piercing Thrust",
        "damage_multiplier": 1.75,
        "range": 3.4,
        "energy_cost": 35.0,
        "cooldown": 8.0,
        "attack_lock": 1.0
    }
}


static func for_weapon(item_id: String) -> Dictionary:
    # Return an independent table entry so accidental edits cannot mutate rules.
    var skill: Variant = SKILLS.get(item_id, {})
    return (skill as Dictionary).duplicate(true)


static func damage_for(item_id: String, base_damage: float) -> float:
    var skill: Dictionary = for_weapon(item_id)
    if skill.is_empty() or base_damage <= 0.0:
        return 0.0
    return base_damage * float(skill["damage_multiplier"])
