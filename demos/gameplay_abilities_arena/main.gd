extends Node2D
## Playable integration of the Cgame native GameplayAbilitySystem.
## Q: ranged projectile, E: directional dash, R: heal, T: stun toggle, F5/F9: save/load.

const ARENA_SIZE := Vector2(960.0, 540.0)
const PLAYER_SPEED := 245.0
const FIREBALL_SPEED := 580.0
const FIREBALL_DAMAGE := 34.0
const SAVE_PATH := "user://ability_arena.save"

var abilities: GameplayAbilitySystem
var hero_position := Vector2(180.0, 300.0)
var hero_health := 100.0
var enemy_position := Vector2(730.0, 290.0)
var enemy_health := 100.0
var elapsed := 0.0
var invulnerable_time := 0.0
var message := "Fight the moving training golem."
var message_time := 6.0
var kills := 0
var projectiles: Array[Dictionary] = []
var hud: Label
var instructions: Label

func _ready() -> void:
    abilities = GameplayAbilitySystem.new()
    abilities.register_ability("fireball", {
        "cost": 18.0,
        "cooldown": 0.75,
        "required_tags": PackedStringArray(["role.hero"]),
        "blocked_tags": PackedStringArray(["status.stunned"]),
    })
    abilities.register_ability("dash", {
        "cost": 14.0,
        "cooldown": 2.25,
        "blocked_tags": PackedStringArray(["status.stunned"]),
    })
    abilities.register_ability("heal", {
        "cost": 35.0,
        "cooldown": 6.0,
        "blocked_tags": PackedStringArray(["status.stunned"]),
    })
    abilities.add_tag("role.hero")
    abilities.ability_activated.connect(_on_ability_activated)
    abilities.cooldown_finished.connect(_on_cooldown_finished)

    hud = Label.new()
    hud.position = Vector2(20.0, 16.0)
    hud.add_theme_font_size_override("font_size", 20)
    hud.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
    add_child(hud)

    instructions = Label.new()
    instructions.position = Vector2(20.0, 442.0)
    instructions.add_theme_font_size_override("font_size", 17)
    instructions.add_theme_color_override("font_color", Color(0.79, 0.84, 0.94))
    instructions.text = "ARROWS / WASD: move    Q: fireball    E: dash    R: heal\nT: toggle stun (ability blocker)    F5: save    F9: load"
    add_child(instructions)
    _refresh_hud()

func _process(delta: float) -> void:
    elapsed += delta
    abilities.tick(delta)
    abilities.set_resource(minf(abilities.get_resource() + 9.0 * delta, abilities.get_max_resource()))
    invulnerable_time = maxf(0.0, invulnerable_time - delta)
    message_time = maxf(0.0, message_time - delta)

    var direction := _movement_direction()
    hero_position += direction * PLAYER_SPEED * delta
    hero_position = hero_position.clamp(Vector2(30.0, 160.0), ARENA_SIZE - Vector2(30.0, 114.0))

    enemy_position = Vector2(713.0 + 88.0 * sin(elapsed * 0.86), 290.0 + 94.0 * cos(elapsed * 0.63))
    for index in range(projectiles.size() - 1, -1, -1):
        var bullet: Dictionary = projectiles[index]
        var next_position: Vector2 = bullet["position"] + bullet["velocity"] * delta
        bullet["position"] = next_position
        if next_position.distance_to(enemy_position) <= 33.0:
            enemy_health -= FIREBALL_DAMAGE
            projectiles.remove_at(index)
            if enemy_health <= 0.0:
                enemy_health = 100.0
                kills += 1
                _notify("Golem defeated! Kills: %d" % kills)
        elif next_position.x < 0.0 or next_position.x > ARENA_SIZE.x or next_position.y < 0.0 or next_position.y > ARENA_SIZE.y:
            projectiles.remove_at(index)

    if hero_position.distance_to(enemy_position) < 55.0 and invulnerable_time <= 0.0:
        hero_health -= 12.0
        invulnerable_time = 1.25
        if hero_health <= 0.0:
            hero_health = 100.0
            hero_position = Vector2(180.0, 300.0)
            _notify("Respawned at the entrance.")

    _refresh_hud()
    queue_redraw()

func _movement_direction() -> Vector2:
    var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    direction.x += float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
    direction.y += float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
    return direction.normalized()

func _input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return
    match event.keycode:
        KEY_Q:
            _activate("fireball")
        KEY_E:
            _activate("dash")
        KEY_R:
            _activate("heal")
        KEY_T:
            if abilities.has_tag("status.stunned"):
                abilities.remove_tag("status.stunned")
                _notify("Stun cleared: abilities unlocked.")
            else:
                abilities.add_tag("status.stunned")
                _notify("Stunned: all abilities are blocked.")
        KEY_F5:
            _save_game()
        KEY_F9:
            _load_game()

func _activate(id: String) -> void:
    var result: int = abilities.activate(id)
    if result != GameplayAbilitySystem.ACTIVATED:
        var errors := {
            GameplayAbilitySystem.UNKNOWN_ABILITY: "Unknown ability",
            GameplayAbilitySystem.ON_COOLDOWN: "Ability recharging",
            GameplayAbilitySystem.INSUFFICIENT_RESOURCE: "Not enough energy",
            GameplayAbilitySystem.MISSING_REQUIRED_TAG: "Missing required character state",
            GameplayAbilitySystem.BLOCKED_BY_TAG: "Ability blocked by status",
        }
        _notify(errors.get(result, "Cannot use ability"))

func _on_ability_activated(id: String) -> void:
    match id:
        "fireball":
            var aim := (enemy_position - hero_position).normalized()
            projectiles.append({
                "position": hero_position,
                "velocity": aim * FIREBALL_SPEED,
            })
            _notify("Fireball launched!")
        "dash":
            var heading := _movement_direction()
            if heading == Vector2.ZERO:
                heading = (enemy_position - hero_position).normalized()
            hero_position = (hero_position + heading * 135.0).clamp(
                Vector2(30.0, 160.0), ARENA_SIZE - Vector2(30.0, 114.0))
            invulnerable_time = maxf(invulnerable_time, 0.25)
            _notify("Dash!")
        "heal":
            hero_health = minf(100.0, hero_health + 40.0)
            _notify("Restored 40 health.")

func _on_cooldown_finished(_id: String) -> void:
    pass # Game UI reads live cooldown values every frame.

func _save_game() -> void:
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        _notify("Save failed.")
        return
    file.store_var({
        "abilities": abilities.save_state(),
        "hero_position": hero_position,
        "hero_health": hero_health,
        "kills": kills,
    })
    file.close()
    _notify("Game saved (F9 to restore).")

func _load_game() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        _notify("No save file yet.")
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        _notify("Could not read save.")
        return
    var data: Variant = file.get_var(false)
    file.close()
    if not (data is Dictionary):
        _notify("Invalid save format.")
        return
    var state: Variant = data.get("abilities", null)
    var loaded_pos: Variant = data.get("hero_position", null)
    var loaded_hp: Variant = data.get("hero_health", null)
    var loaded_kills: Variant = data.get("kills", null)
    if not (state is Dictionary) or not (loaded_pos is Vector2) or not (loaded_hp is float) or not (loaded_kills is int):
        _notify("Invalid save data.")
        return
    if not is_finite(loaded_hp) or loaded_hp < 0.0 or loaded_hp > 100.0 or loaded_kills < 0:
        _notify("Invalid save values.")
        return
    if not abilities.load_state(state):
        _notify("Incompatible ability save.")
        return
    hero_position = loaded_pos.clamp(Vector2(30.0, 160.0), ARENA_SIZE - Vector2(30.0, 114.0))
    hero_health = loaded_hp
    kills = loaded_kills
    projectiles.clear()
    _notify("Game restored.")

func _refresh_hud() -> void:
    hud.text = "CGAME  |  GAMEPLAY ABILITIES\n" + \
        "HEALTH: %d / 100    ENERGY: %d / %d    KILLS: %d\n" % [int(hero_health), int(abilities.get_resource()), int(abilities.get_max_resource()), kills] + \
        "Q  Fireball: %.1fs     E  Dash: %.1fs     R  Heal: %.1fs\n" % [
            abilities.get_remaining_cooldown("fireball"),
            abilities.get_remaining_cooldown("dash"),
            abilities.get_remaining_cooldown("heal"),
        ] + \
        "STATUS: %s\n" % ("STUNNED" if abilities.has_tag("status.stunned") else "READY") + \
        ("EVENT: %s" % message if message_time > 0.0 else "")

func _notify(value: String) -> void:
    message = value
    message_time = 2.7

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, ARENA_SIZE), Color(0.045, 0.067, 0.11), true)
    for x in range(0, 961, 48):
        draw_line(Vector2(x, 145), Vector2(x, 436), Color(0.11, 0.16, 0.24, 0.55), 1.0)
    for y in range(145, 437, 48):
        draw_line(Vector2(0, y), Vector2(960, y), Color(0.11, 0.16, 0.24, 0.55), 1.0)
    draw_rect(Rect2(Vector2(1.0, 145.0), Vector2(958.0, 291.0)), Color(0.24, 0.31, 0.43), false, 2.0)

    var hero_color := Color(0.45, 0.73, 1.0)
    if abilities.has_tag("status.stunned"):
        hero_color = Color(0.72, 0.52, 0.92)
    if invulnerable_time > 0.0:
        draw_arc(hero_position, 30.0, 0.0, TAU, 36, Color(0.38, 0.9, 0.9), 3.0)
    draw_circle(hero_position, 23.0, hero_color)
    draw_circle(hero_position + Vector2(6, -5), 5.0, Color(1.0, 1.0, 1.0, 0.85))

    draw_circle(enemy_position, 30.0, Color(0.95, 0.36, 0.35))
    draw_circle(enemy_position + Vector2(-7, -4), 4.0, Color(0.2, 0.13, 0.16))
    draw_circle(enemy_position + Vector2(7, -4), 4.0, Color(0.2, 0.13, 0.16))
    draw_rect(Rect2(enemy_position + Vector2(-30, -48), Vector2(60, 6)), Color(0.18, 0.18, 0.19))
    draw_rect(Rect2(enemy_position + Vector2(-30, -48), Vector2(60.0 * enemy_health / 100.0, 6)), Color(0.55, 0.96, 0.53))

    for bullet in projectiles:
        var position: Vector2 = bullet["position"]
        draw_circle(position, 9.0, Color(1.0, 0.66, 0.2))
        draw_circle(position, 4.0, Color(1.0, 0.96, 0.76))
