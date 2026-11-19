extends CharacterBody3D

signal attack_requested(damage: float, range_meters: float)

## Days After + classless progression: survival, scavenging, tiered gathering,
## crafting and tool-gated access to advanced resources live in the game layer.

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 5.0
const GRAVITY := 18.0
const MOUSE_SENSITIVITY := 0.0025
const XP_PER_LEVEL := 60
const SAVE_STATE = preload("res://save_state.gd")
const WEAPON_SKILLS = preload("res://weapon_skill_rules.gd")
const ENERGY_REGEN_PER_SECOND := 9.0

const RECIPES := {
    "field_bandage": {"fiber_t1": 2},
    "scavenger_tool": {"wood_t1": 2, "stone_t1": 1},
    "reinforced_bandage": {"fiber_t2": 2, "fiber_t1": 1},
    "rusty_spear": {"wood_t1": 2, "stone_t1": 2},
    "scrap_vest": {"fiber_t1": 3, "stone_t1": 2},
    "reinforced_spear": {"wood_t2": 2, "stone_t2": 2, "fiber_t1": 1},
}

var health: float = 100.0
var hunger: float = 80.0
var thirst: float = 80.0
var inventory: Dictionary = {}
var gathering_xp: Dictionary = {"wood": 0, "stone": 0, "fiber": 0}
var crafting_xp: int = 0
var equipped_tool: String = ""
var equipped_weapon: String = ""
var equipped_armor: String = ""
var combat_xp: int = 0
var attack_cooldown: float = 0.0
var combat_energy: float = 100.0
var weapon_skill_cooldown: float = 0.0
var last_message: String = "Ищите припасы, сырьё и создавайте снаряжение."

@onready var camera: Camera3D = $Head/Camera3D
@onready var aim_ray: RayCast3D = $Head/Camera3D/AimRay


func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        camera.rotation.x = clampf(
            camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.4, 1.4
        )
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        elif event.keycode == KEY_F5:
            last_message = "Игра сохранена." if SAVE_STATE.save_player(self) else "Не удалось сохранить игру."
        elif event.keycode == KEY_F9:
            last_message = "Сохранение загружено." if SAVE_STATE.load_player(self) else "Нет корректного сохранения."
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= GRAVITY * delta
    elif health > 0.0 and Input.is_action_just_pressed("jump"):
        velocity.y = JUMP_VELOCITY

    var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var direction := (global_transform.basis * Vector3(move_input.x, 0.0, move_input.y)).normalized()
    var move_speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
    velocity.x = direction.x * move_speed if health > 0.0 else 0.0
    velocity.z = direction.z * move_speed if health > 0.0 else 0.0
    move_and_slide()

    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    weapon_skill_cooldown = maxf(0.0, weapon_skill_cooldown - delta)
    if health <= 0.0:
        return
    combat_energy = minf(100.0, combat_energy + ENERGY_REGEN_PER_SECOND * maxf(0.0, delta))
    hunger = maxf(0.0, hunger - 0.24 * delta)
    thirst = maxf(0.0, thirst - 0.38 * delta)
    if hunger <= 0.0 or thirst <= 0.0:
        health = maxf(0.0, health - 3.0 * delta)

    if Input.is_action_just_pressed("attack"):
        perform_attack()
    if Input.is_action_just_pressed("weapon_skill"):
        perform_weapon_skill()
    if Input.is_action_just_pressed("craft_spear"):
        craft_recipe("rusty_spear")
    if Input.is_action_just_pressed("craft_reinforced_spear"):
        craft_recipe("reinforced_spear")
    if Input.is_action_just_pressed("craft_vest"):
        craft_recipe("scrap_vest")
    if Input.is_action_just_pressed("interact"):
        var target := get_aimed_pickup()
        if target != null:
            target.call("interact", self)
    if Input.is_action_just_pressed("consume_food"):
        consume_food()
    if Input.is_action_just_pressed("consume_water"):
        consume_water()
    if Input.is_action_just_pressed("craft_bandage"):
        craft_recipe("field_bandage")
    if Input.is_action_just_pressed("craft_tool"):
        craft_recipe("scavenger_tool")
    if Input.is_action_just_pressed("use_bandage"):
        use_bandage("field_bandage")
    if Input.is_action_just_pressed("craft_advanced_bandage"):
        craft_recipe("reinforced_bandage")
    if Input.is_action_just_pressed("use_advanced_bandage"):
        use_bandage("reinforced_bandage")


func get_aimed_pickup() -> Node:
    if aim_ray == null:
        return null
    aim_ray.force_raycast_update()
    var target := aim_ray.get_collider() as Node
    if target != null and target.has_method("interact"):
        return target
    return null


func get_item_count(item_id: String) -> int:
    return int(inventory.get(item_id, 0))


func add_item(item_id: String, quantity: int) -> void:
    if item_id.is_empty() or quantity <= 0:
        return
    inventory[item_id] = get_item_count(item_id) + quantity


func collect_item(item_type: String, quantity: int) -> void:
    if health <= 0.0 or quantity <= 0:
        return
    if item_type != "food" and item_type != "water":
        return
    add_item(item_type, quantity)
    last_message = "Найдены припасы: %s × %d" % [item_type, quantity]


func consume_food() -> void:
    if get_item_count("food") <= 0 or health <= 0.0:
        return
    inventory["food"] = get_item_count("food") - 1
    hunger = minf(100.0, hunger + 35.0)
    last_message = "Голод утолён."


func consume_water() -> void:
    if get_item_count("water") <= 0 or health <= 0.0:
        return
    inventory["water"] = get_item_count("water") - 1
    thirst = minf(100.0, thirst + 45.0)
    last_message = "Жажда утолена."


func gathering_level(resource_kind: String) -> int:
    if not gathering_xp.has(resource_kind):
        return 0
    return 1 + floori(float(gathering_xp[resource_kind]) / float(XP_PER_LEVEL))


func try_gather(resource_kind: String, tier: int, quantity: int) -> bool:
    if health <= 0.0 or not gathering_xp.has(resource_kind):
        return false
    if tier < 1 or tier > 2 or quantity <= 0:
        return false
    if gathering_level(resource_kind) < tier:
        last_message = "Нужен навык добычи %s уровня %d." % [resource_kind, tier]
        return false
    if tier >= 2 and equipped_tool != "scavenger_tool":
        last_message = "Для ресурсов T2 требуется экипированный инструмент."
        return false

    add_item("%s_t%d" % [resource_kind, tier], quantity)
    gathering_xp[resource_kind] = int(gathering_xp[resource_kind]) + 25 * tier * quantity
    last_message = "Добыто: %s T%d × %d | навык %d" % [
        resource_kind, tier, quantity, gathering_level(resource_kind)
    ]
    return true


func craft_recipe(recipe_id: String) -> bool:
    if health <= 0.0 or not RECIPES.has(recipe_id):
        return false
    var ingredients: Dictionary = RECIPES[recipe_id]
    for item_id in ingredients:
        if get_item_count(str(item_id)) < int(ingredients[item_id]):
            last_message = "Недостаточно ресурсов для %s." % recipe_id
            return false

    for item_id in ingredients:
        inventory[item_id] = get_item_count(str(item_id)) - int(ingredients[item_id])
    add_item(recipe_id, 1)
    crafting_xp += 20
    match recipe_id:
        "scavenger_tool":
            equipped_tool = recipe_id
        "rusty_spear", "reinforced_spear":
            equipped_weapon = recipe_id
        "scrap_vest":
            equipped_armor = recipe_id
    last_message = "Создано: %s | опыт ремесла: %d" % [recipe_id, crafting_xp]
    return true


func use_bandage(item_id: String) -> bool:
    if health <= 0.0 or health >= 100.0:
        return false
    if item_id != "field_bandage" and item_id != "reinforced_bandage":
        return false
    if get_item_count(item_id) <= 0:
        return false
    inventory[item_id] = get_item_count(item_id) - 1
    health = minf(100.0, health + (60.0 if item_id == "reinforced_bandage" else 30.0))
    last_message = "Раны обработаны: %s." % item_id
    return true


func equip_item(slot: String, item_id: String) -> bool:
    if get_item_count(item_id) <= 0 or health <= 0.0:
        return false
    match slot:
        "tool":
            if item_id != "scavenger_tool":
                return false
            equipped_tool = item_id
        "weapon":
            if item_id != "rusty_spear" and item_id != "reinforced_spear":
                return false
            equipped_weapon = item_id
        "armor":
            if item_id != "scrap_vest":
                return false
            equipped_armor = item_id
        _:
            return false
    last_message = "Экипировано: %s" % item_id
    return true


func get_attack_damage() -> float:
    match equipped_weapon:
        "rusty_spear":
            return 32.0
        "reinforced_spear":
            return 52.0
        _:
            return 12.0


func perform_attack() -> bool:
    if health <= 0.0 or attack_cooldown > 0.0:
        return false
    attack_cooldown = 0.65
    attack_requested.emit(get_attack_damage(), 2.7)
    return true


func perform_weapon_skill() -> bool:
    # Classless abilities are granted by owned/equipped gear, never a class ID.
    # Validate everything before consuming energy or starting cooldowns.
    if health <= 0.0 or attack_cooldown > 0.0 or weapon_skill_cooldown > 0.0:
        return false
    var skill: Dictionary = WEAPON_SKILLS.for_weapon(equipped_weapon)
    if skill.is_empty() or get_item_count(equipped_weapon) < 1:
        return false
    var energy_cost: float = float(skill["energy_cost"])
    if combat_energy < energy_cost:
        last_message = "Недостаточно боевой энергии для приёма."
        return false
    combat_energy -= energy_cost
    attack_cooldown = float(skill["attack_lock"])
    weapon_skill_cooldown = float(skill["cooldown"])
    var damage: float = WEAPON_SKILLS.damage_for(equipped_weapon, get_attack_damage())
    attack_requested.emit(damage, float(skill["range"]))
    last_message = "Особая атака: %s (%d урона)." % [str(skill["name"]), roundi(damage)]
    return true


func get_weapon_skill_status() -> String:
    var skill: Dictionary = WEAPON_SKILLS.for_weapon(equipped_weapon)
    if skill.is_empty() or get_item_count(equipped_weapon) < 1:
        return "Q: требуется экипированное копьё"
    if weapon_skill_cooldown > 0.0:
        return "%s: %.1f сек" % [str(skill["name"]), weapon_skill_cooldown]
    return "%s: готово (энергия %d)" % [str(skill["name"]), int(skill["energy_cost"])]


func take_damage(raw_amount: float) -> void:
    if health <= 0.0 or raw_amount <= 0.0:
        return
    var reduction: float = 0.25 if equipped_armor == "scrap_vest" else 0.0
    health = maxf(0.0, health - raw_amount * (1.0 - reduction))
    if health <= 0.0:
        last_message = "Вы погибли. Нажмите R для перезапуска."


func gain_combat_xp(amount: int) -> void:
    if amount > 0:
        combat_xp += amount
