extends Node3D
## Bounded combat encounter director for the streamed forest.
## One deterministic spawn per cell, at most 5 active actors in total.
## Actors are created only for loaded near-LOD cells and deactivated outside
## a 24m significance radius; the native streamer controls cell ownership.

signal player_damaged(amount: int)
signal enemy_defeated(encounter_id: String)

const Stalker = preload("res://scripts/forest_stalker.gd")
const MAX_ACTIVE_STALKERS: int = 5
const SCAN_INTERVAL: float = 0.35
const SPAWN_DISTANCE: float = 35.0
const AI_DISTANCE: float = 24.0
const ATTACK_INTERVAL: float = 0.65
const ATTACK_RANGE: float = 3.4

var streamer: WorldPartition3D
var player: Node3D
var height_fn: Callable
var defeated_ids: Array[String] = []
var active_enemies: Dictionary = {} # Vector2i -> CharacterBody3D
var enabled: bool = false
var _scan_elapsed: float = 0.0
var _attack_cooldown: float = 0.0


func _ready() -> void:
    set_process(false)


func configure(world: WorldPartition3D, controlled_player: Node3D, terrain_height: Callable) -> void:
    streamer = world
    player = controlled_player
    height_fn = terrain_height
    enabled = true
    set_process(true)
    if not streamer.cell_unloaded.is_connected(_on_cell_unloaded):
        streamer.cell_unloaded.connect(_on_cell_unloaded)
    refresh_encounters()


func _process(delta: float) -> void:
    if not enabled:
        return
    _attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
    _scan_elapsed += delta
    if _scan_elapsed >= SCAN_INTERVAL:
        _scan_elapsed = 0.0
        refresh_encounters()


static func encounter_key(cell: Vector2i) -> String:
    return "%d:%d" % [cell.x, cell.y]


func restore_defeated(ids: Array) -> void:
    # Savegame loader already sanitizes; repeat a bounded validation so callers
    # cannot accidentally turn an untrusted list into unbounded memory state.
    defeated_ids.clear()
    for raw in ids:
        if raw is String and not defeated_ids.has(raw) and defeated_ids.size() < 16:
            var pieces: PackedStringArray = raw.split(":")
            if pieces.size() == 2 and pieces[0].is_valid_int() and pieces[1].is_valid_int():
                var x: int = pieces[0].to_int()
                var z: int = pieces[1].to_int()
                if x >= -2 and x < 2 and z >= -2 and z < 2 and (x != 0 or z != 0):
                    defeated_ids.append(encounter_key(Vector2i(x, z)))
    for cell in active_enemies.keys():
        var enemy: Node = active_enemies[cell]
        if is_instance_valid(enemy):
            enemy.queue_free()
    active_enemies.clear()
    if enabled:
        refresh_encounters()


func get_defeated_ids() -> Array[String]:
    return defeated_ids.duplicate()


func get_alive_count() -> int:
    return active_enemies.size()


func is_defeated(cell: Vector2i) -> bool:
    return defeated_ids.has(encounter_key(cell))


func _spawn_position(cell: Vector2i) -> Vector3:
    # Stable coordinates: no RNG state, independent of stream order or reload.
    var px: float = float(cell.x) * streamer.cell_size + 16.0
    var pz: float = float(cell.y) * streamer.cell_size + 16.0
    var y: float = float(height_fn.call(px, pz)) if height_fn.is_valid() else 0.0
    return Vector3(px, y + 1.0, pz)


func _eligible(cell: Vector2i) -> bool:
    if cell == Vector2i.ZERO or is_defeated(cell):
        return false # The home clearing must remain safe.
    if streamer.get_cell_instance(cell) == null:
        return false
    # Independent native simulation state, not the visual LOD tier. Disabling
    # LOD for graphics must not wake AI across the whole loaded world.
    if not streamer.is_cell_simulation_active(cell):
        return false
    var spawn: Vector3 = _spawn_position(cell)
    var planar: Vector2 = Vector2(spawn.x - player.global_position.x,
            spawn.z - player.global_position.z)
    return planar.length_squared() <= SPAWN_DISTANCE * SPAWN_DISTANCE


func refresh_encounters() -> void:
    if not enabled or not is_instance_valid(streamer) or not is_instance_valid(player):
        return

    # Use key snapshots, as streamed removals and signal callbacks may mutate
    # the dictionary while enemies are queued for deletion.
    for cell in active_enemies.keys():
        var enemy: CharacterBody3D = active_enemies[cell]
        if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not _eligible(cell):
            active_enemies.erase(cell)
            if is_instance_valid(enemy):
                enemy.queue_free()
        else:
            var spawn: Vector3 = _spawn_position(cell)
            var dx: float = spawn.x - player.global_position.x
            var dz: float = spawn.z - player.global_position.z
            enemy.call("set_encounter_active", dx * dx + dz * dz <= AI_DISTANCE * AI_DISTANCE)

    # Fixed world grid => deterministic spawn ordering and cheap bounded scan.
    for z in range(-2, 2):
        for x in range(-2, 2):
            if active_enemies.size() >= MAX_ACTIVE_STALKERS:
                return
            var cell := Vector2i(x, z)
            if active_enemies.has(cell) or not _eligible(cell):
                continue
            _spawn(cell)


func _spawn(cell: Vector2i) -> void:
    var enemy := CharacterBody3D.new()
    enemy.name = "Stalker_%d_%d" % [cell.x, cell.y]
    enemy.set_script(Stalker)
    add_child(enemy)
    enemy.call("configure", encounter_key(cell), player, _spawn_position(cell))
    enemy.connect("attack_landed", _on_enemy_attack)
    enemy.connect("defeated", _on_enemy_defeated)
    active_enemies[cell] = enemy
    var origin: Vector3 = _spawn_position(cell)
    var dx: float = origin.x - player.global_position.x
    var dz: float = origin.z - player.global_position.z
    enemy.call("set_encounter_active", dx * dx + dz * dz <= AI_DISTANCE * AI_DISTANCE)


func _on_enemy_attack(amount: int) -> void:
    player_damaged.emit(amount)


func _on_enemy_defeated(id: String) -> void:
    if not defeated_ids.has(id):
        defeated_ids.append(id)
    for cell in active_enemies.keys():
        var npc: Node = active_enemies[cell]
        if is_instance_valid(npc) and npc.get("encounter_id") == id:
            active_enemies.erase(cell)
            break
    enemy_defeated.emit(id)


func _on_cell_unloaded(cell: Vector2i) -> void:
    if active_enemies.has(cell):
        var enemy: Node = active_enemies[cell]
        active_enemies.erase(cell)
        if is_instance_valid(enemy):
            enemy.queue_free()


func attack_from_camera(camera: Camera3D) -> bool:
    if not is_instance_valid(camera) or _attack_cooldown > 0.0:
        return false
    _attack_cooldown = ATTACK_INTERVAL
    # Real physics ray: attack is constrained by the enemy's collider and
    # can't travel through the terrain or trees. Only stalker layer 4 can
    # receive melee hits; the camera/character is not a damage target.
    var origin: Vector3 = camera.global_position
    var endpoint: Vector3 = origin - camera.global_basis.z * ATTACK_RANGE
    var query := PhysicsRayQueryParameters3D.create(origin, endpoint)
    query.collision_mask = 1 | 4 # Terrain/trees occlude hits on enemy layer 4.
    var player_body := player as CollisionObject3D
    if player_body != null:
        query.exclude = [player_body.get_rid()]
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    var collider: Object = hit.get("collider")
    if collider != null and collider.has_method("take_damage"):
        return collider.call("take_damage", 1)
    return false
