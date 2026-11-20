extends Node3D

# Authorable placeholder art: same scene contracts as imported low/high-detail assets.
# Geometry is deterministic, with MultiMesh draw-call batching per cell.
@export var proxy: bool = false

const CELL_SIZE := 128.0
const TREE_COUNT := 160
const PROXY_STRIDE := 8
const QUEST_HUB := Vector2i(0, 0)
const COMBAT_ARENA := Vector2i(4, 2)
const CHAMPION_SHRINE := Vector2i(5, 3)

var cell_coords: Vector2i = Vector2i(9999, 9999)
var hub_reward_claimed := false
var arena_wins := 0
var champion_reward_claimed := false

static var _trunk_mesh: CylinderMesh
static var _crown_detail_mesh: SphereMesh
static var _crown_proxy_mesh: SphereMesh
static var _ground_mesh: PlaneMesh
static var _trunk_material: StandardMaterial3D
static var _leaf_material: StandardMaterial3D
static var _ground_material: StandardMaterial3D

func _ready() -> void:
    _ensure_shared_resources()

    var ground := MeshInstance3D.new()
    ground.name = "Ground"
    ground.mesh = _ground_mesh
    ground.position = Vector3(CELL_SIZE / 2.0, -0.07 if proxy else -0.03, CELL_SIZE / 2.0)
    add_child(ground)

    var count: int = int(TREE_COUNT / PROXY_STRIDE) if proxy else TREE_COUNT
    var trunks := _build_multimesh(_trunk_mesh, count)
    var crowns := _build_multimesh(_crown_proxy_mesh if proxy else _crown_detail_mesh, count)
    var grid := Vector2i(roundi(position.x / CELL_SIZE), roundi(position.z / CELL_SIZE))
    cell_coords = grid
    var rng := RandomNumberGenerator.new()
    rng.seed = int(500003 + (grid.x + 1000) * 73856093 + (grid.y + 1000) * 19349663)
    var output_index := 0
    for i in TREE_COUNT:
        var x := rng.randf_range(4.0, 124.0)
        var z := rng.randf_range(4.0, 124.0)
        var height := rng.randf_range(4.0, 8.0)
        var width := rng.randf_range(0.70, 1.12)
        if proxy and i % PROXY_STRIDE != 0:
            continue
        trunks.set_instance_transform(
            output_index,
            Transform3D(Basis().scaled(Vector3(0.65 * width, height, 0.65 * width)), Vector3(x, height / 2.0, z))
        )
        crowns.set_instance_transform(
            output_index,
            Transform3D(Basis().scaled(Vector3(3.3 * width, 3.6, 3.3 * width)), Vector3(x, height + 1.9, z))
        )
        output_index += 1

    _add_instances("Trunks", trunks)
    _add_instances("Canopies", crowns)

    # Gameplay landmarks belong to detailed scenes only. The demo's native
    # pinning API allows the hub and event arena to remain resident offscreen.
    if not proxy:
        if grid == QUEST_HUB or grid == COMBAT_ARENA:
            _add_gameplay_landmark(grid == QUEST_HUB)
            _refresh_landmark()
        elif grid == CHAMPION_SHRINE:
            _add_champion_shrine()
            _refresh_landmark()

# The native WorldPartition3D streamer invokes these optional scene-root hooks.
# Only gameplay cells retain state; uninteresting procedural foliage returns {}.
func capture_streaming_state() -> Dictionary:
    if proxy:
        return {}
    if cell_coords == QUEST_HUB:
        return {"reward_claimed": hub_reward_claimed}
    if cell_coords == COMBAT_ARENA:
        return {"arena_wins": arena_wins}
    if cell_coords == CHAMPION_SHRINE:
        return {"champion_reward_claimed": champion_reward_claimed}
    return {}

func restore_streaming_state(state: Dictionary) -> void:
    if cell_coords == QUEST_HUB:
        hub_reward_claimed = bool(state.get("reward_claimed", false))
    elif cell_coords == COMBAT_ARENA:
        arena_wins = maxi(0, int(state.get("arena_wins", 0)))
    elif cell_coords == CHAMPION_SHRINE:
        champion_reward_claimed = bool(state.get("champion_reward_claimed", false))
    _refresh_landmark()

func claim_hub_reward() -> bool:
    if proxy or cell_coords != QUEST_HUB or hub_reward_claimed:
        return false
    hub_reward_claimed = true
    _refresh_landmark()
    return true

func win_arena_round() -> int:
    if proxy or cell_coords != COMBAT_ARENA:
        return -1
    arena_wins += 1
    _refresh_landmark()
    return arena_wins

func claim_champion_reward() -> bool:
    if proxy or cell_coords != CHAMPION_SHRINE or champion_reward_claimed:
        return false
    champion_reward_claimed = true
    _refresh_landmark()
    return true

func _refresh_landmark() -> void:
    if cell_coords == QUEST_HUB:
        var label := get_node_or_null("QuestHub/StateLabel") as Label3D
        if label != null:
            label.text = "HUB REWARD CLAIMED" if hub_reward_claimed else "HUB REWARD READY  [C]"
    elif cell_coords == COMBAT_ARENA:
        var label := get_node_or_null("CombatArena/StateLabel") as Label3D
        if label != null:
            label.text = "ARENA WINS: %d  [B]" % arena_wins
    elif cell_coords == CHAMPION_SHRINE:
        var label := get_node_or_null("ChampionShrine/StateLabel") as Label3D
        if label != null:
            label.text = "CHAMPION REWARD CLAIMED" if champion_reward_claimed else "CHAMPION REWARD  [V]"

func _add_champion_shrine() -> void:
    var anchor := Node3D.new()
    anchor.name = "ChampionShrine"
    anchor.position = Vector3(CELL_SIZE * 0.5, 0.0, CELL_SIZE * 0.5)
    add_child(anchor)
    var monument := MeshInstance3D.new()
    monument.name = "Monument"
    var shape := CylinderMesh.new()
    shape.height = 16.0
    shape.top_radius = 0.9
    shape.bottom_radius = 2.5
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.55, 0.20, 0.93)
    material.emission_enabled = true
    material.emission = material.albedo_color
    material.emission_energy_multiplier = 1.8
    shape.material = material
    monument.mesh = shape
    monument.position.y = 8.0
    anchor.add_child(monument)
    var nameplate := Label3D.new()
    nameplate.name = "StateLabel"
    nameplate.font_size = 64
    nameplate.pixel_size = 0.01
    nameplate.position.y = 19.0
    anchor.add_child(nameplate)

func _add_gameplay_landmark(is_hub: bool) -> void:
    var anchor := Node3D.new()
    anchor.name = "QuestHub" if is_hub else "CombatArena"
    anchor.position = Vector3(CELL_SIZE * 0.5, 0.0, CELL_SIZE * 0.5)
    add_child(anchor)

    var column := MeshInstance3D.new()
    column.name = "Landmark"
    var shape := CylinderMesh.new()
    shape.top_radius = 0.7
    shape.bottom_radius = 1.4
    shape.height = 12.0
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.08, 0.75, 0.44) if is_hub else Color(0.85, 0.21, 0.12)
    material.emission_enabled = true
    material.emission = material.albedo_color
    material.emission_energy_multiplier = 1.5
    shape.material = material
    column.mesh = shape
    column.position.y = 6.0
    anchor.add_child(column)

    var nameplate := Label3D.new()
    nameplate.name = "StateLabel"
    nameplate.text = "QUEST HUB  [H]" if is_hub else "COMBAT ARENA  [G]"
    nameplate.font_size = 64
    nameplate.pixel_size = 0.01
    nameplate.position.y = 14.0
    anchor.add_child(nameplate)

func _build_multimesh(mesh: Mesh, count: int) -> MultiMesh:
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = mesh
    mm.instance_count = count
    return mm

func _add_instances(name: String, mm: MultiMesh) -> void:
    var instance := MultiMeshInstance3D.new()
    instance.name = name
    instance.multimesh = mm
    add_child(instance)

func _ensure_shared_resources() -> void:
    if _trunk_mesh != null:
        return
    _trunk_material = StandardMaterial3D.new()
    _trunk_material.albedo_color = Color(0.29, 0.22, 0.16)
    _trunk_material.roughness = 1.0
    _leaf_material = StandardMaterial3D.new()
    _leaf_material.albedo_color = Color(0.08, 0.27, 0.13)
    _leaf_material.roughness = 0.95
    _ground_material = StandardMaterial3D.new()
    _ground_material.albedo_color = Color(0.19, 0.31, 0.20)
    _ground_material.roughness = 1.0

    _trunk_mesh = CylinderMesh.new()
    _trunk_mesh.top_radius = 0.4
    _trunk_mesh.bottom_radius = 0.5
    _trunk_mesh.height = 1.0
    _trunk_mesh.material = _trunk_material

    _crown_detail_mesh = SphereMesh.new()
    _crown_detail_mesh.radial_segments = 12
    _crown_detail_mesh.rings = 6
    _crown_detail_mesh.material = _leaf_material

    _crown_proxy_mesh = SphereMesh.new()
    _crown_proxy_mesh.radial_segments = 6
    _crown_proxy_mesh.rings = 3
    _crown_proxy_mesh.material = _leaf_material

    _ground_mesh = PlaneMesh.new()
    _ground_mesh.size = Vector2(CELL_SIZE, CELL_SIZE)
    _ground_mesh.material = _ground_material
