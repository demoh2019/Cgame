extends Node
## Runtime impostor generation (UE5 Impostor Baker, Unity Amplify Impostors).
## Each mesh is rendered once from FRAMES yaw angles into a horizontal atlas
## inside an isolated SubViewport world, then cached for every far field.
## Headless servers and tests never bake; fields simply stay hidden.

const FRAMES := 8
const RESOLUTION := 128
const SHADER := preload("res://assets/shaders/impostor.gdshader")

static var _cache: Dictionary = {} # mesh instance id -> Texture2D
static var _waiting: Dictionary = {} # mesh instance id -> Array[Callable]
static var _instance: Node = null

var _queue: Array[Mesh] = []
var _busy := false


## Square bake extent and vertical center of a mesh (shared by bake and quad).
static func frame_size(mesh: Mesh) -> Vector2:
	if mesh == null:
		return Vector2(1.0, 0.5)
	var box: AABB = mesh.get_aabb()
	var horizontal: float = Vector2(box.size.x, box.size.z).length()
	var extent: float = maxf(maxf(horizontal, box.size.y), 0.05) * 1.05
	return Vector2(extent, box.position.y + box.size.y * 0.5)


static func can_bake() -> bool:
	return DisplayServer.get_name() != "headless"


static func cached(mesh: Mesh) -> Texture2D:
	return _cache.get(mesh.get_instance_id(), null) if mesh != null else null


static func material_for(mesh: Mesh, atlas: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("frames", float(FRAMES))
	material.set_shader_parameter("quad_size", frame_size(mesh))
	return material


## Calls done(atlas) once the mesh is baked (immediately when cached).
static func request(mesh: Mesh, tree: SceneTree, done: Callable) -> void:
	if mesh == null:
		return
	var key: int = mesh.get_instance_id()
	if _cache.has(key):
		done.call(_cache[key])
		return
	if tree == null or not can_bake():
		return
	if _waiting.has(key):
		(_waiting[key] as Array).append(done)
		return
	_waiting[key] = [done]
	if _instance == null or not is_instance_valid(_instance):
		_instance = new()
		_instance.name = "ImpostorBaker"
		tree.root.add_child.call_deferred(_instance)
	_instance._queue.append(mesh)


static func clear_cache() -> void:
	_cache.clear()
	_waiting.clear()


func _process(_delta: float) -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	_bake(_queue.pop_front())


func _bake(mesh: Mesh) -> void:
	var size: Vector2 = frame_size(mesh)
	var box: AABB = mesh.get_aabb()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(RESOLUTION, RESOLUTION)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	# Flat ambient bake: scene lights shade the impostor at runtime, not twice.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var pivot := Node3D.new()
	viewport.add_child(pivot)
	var model := MeshInstance3D.new()
	model.mesh = mesh
	var center := box.get_center()
	model.position = Vector3(-center.x, 0.0, -center.z)
	pivot.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size.x
	camera.position = Vector3(0.0, size.y, size.x * 2.0)
	camera.near = 0.01
	camera.far = size.x * 4.0
	viewport.add_child(camera)
	add_child(viewport)
	var atlas := Image.create(RESOLUTION * FRAMES, RESOLUTION, false, Image.FORMAT_RGBA8)
	for i in FRAMES:
		pivot.rotation.y = TAU * float(i) / float(FRAMES)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot: Image = viewport.get_texture().get_image()
		if shot != null:
			shot.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(i * RESOLUTION, 0))
	viewport.queue_free()
	atlas.generate_mipmaps()
	var texture := ImageTexture.create_from_image(atlas)
	var key: int = mesh.get_instance_id()
	_cache[key] = texture
	for done in _waiting.get(key, []):
		(done as Callable).call(texture)
	_waiting.erase(key)
	_busy = false
