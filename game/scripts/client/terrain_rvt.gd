extends Node
## Runtime virtual texture for the terrain (Forward+ only).
##
## The terrain shader (assets/shaders/ground.gdshader) blends up to 13 PBR layers per pixel with noise,
## biome, road and site masks: about 5 ms of an M1's 1080p frame from the orbit camera. Like Unreal's
## Runtime Virtual Texturing, this bakes the finished material once into pages around the camera and the
## shader then reads the page instead of re-deriving it every frame:
##  * pages of 8 m (level 0, near) and 16 m (level 1, out to the detail radius), 256x256 texels;
##  * baked by orthographic cameras looking straight down at the real terrain geometry with the same
##    shader, which detects the bake from CAMERA_VISIBLE_LAYERS (marker layer, no ordinary layers) and
##    outputs albedo, normal+roughness, or wetness masks, drawn with the Unshaded debug mode;
##  * copied into three Texture2DArrays; a 64x32 toroidal page table maps world pages to array layers.
## Close to the camera (parallax, finest detail) and past the cache the shader still shades live, and
## weather, cloud shadows, AO and ripples are always live on top of the page.

const PAGE_TEXELS := 256
const WET_TEXELS := 64
const LEVEL_PAGE: Array[float] = [8.0, 16.0]
const TABLE := 32
const CAPACITY := 176
const TERRAIN_LAYER := 1 << 19 # Visual layer 20: the terrain chunks (ChunkedTerrain3D.render_layers).
const MARK_ALBEDO := 1 << 18
const MARK_DATA := 1 << 17
const MARK_WET := 1 << 16
const BAKES_PER_FRAME := 2
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const RvtCompressor = preload("res://scripts/client/rvt_compressor.gd")
const CHUNK_SETTLE := 0.75 # Seconds a terrain chunk must exist before its pages are baked.

## Where pages replace live shading: from `live_radius` (m) out to the level radii.
var live_radius := 10.0
var level_radius: Array[float] = [26.0, 66.0]

## Winter snow cover (aa_snow_cover), set by the client; the baked pages are redone when it changes.
var snow_cover := 0.0
var camera: Camera3D
var streamer: Node
var chunk_size := 64.0

var _rd: RenderingDevice
var _compressor: RvtCompressor # Mips + BC3/BC5 on the GPU (rvt_compressor.gd).
var _arrays: Array[RID] = [] # albedo, data, wet (RenderingDevice textures)
var _array_textures: Array[Texture2DArrayRD] = []
var _table_image: Image
var _table_texture: ImageTexture
var _table_dirty := false
var _pages := {} # Vector3i(level, x, z) -> layer
var _layer_keys: Array = [] # layer -> Vector3i or null
var _free: Array[int] = []
var _rigs: Array = []
var _chunk_seen := {} # Vector2i chunk cell -> first time seen (s)
var _snow := -1.0
var _enabled := false
var _time := 0.0
var _debug := false # CGAME_RVT_DEBUG=1: tint cached pixels (red level 0, blue level 1), log residency.
var _debug_timer := 0.0
var _wanted: Array = []
var _wanted_eye := Vector3(INF, INF, INF)
var _refresh_timer := 0.0


static func supported() -> bool:
	return RenderingServer.get_rendering_device() != null \
		and ClassDB.class_has_method("ChunkedTerrain3D", "set_render_layers")


func setup(p_camera: Camera3D, p_streamer: Node, p_chunk_size: float) -> void:
	camera = p_camera
	streamer = p_streamer
	chunk_size = p_chunk_size
	_enabled = supported() and OS.get_environment("CGAME_RVT") != "0"
	_debug = OS.get_environment("CGAME_RVT_DEBUG") == "1"
	if not _enabled:
		RenderingServer.global_shader_parameter_set(&"aa_rvt_params", Vector4(0.0, live_radius, 0.0, 0.0))
		return
	_rd = RenderingServer.get_rendering_device()
	_compressor = RvtCompressor.new()
	if not _compressor.setup(_rd):
		push_warning("Terrain RVT off: " + _compressor.error)
		_enabled = false
		RenderingServer.global_shader_parameter_set(&"aa_rvt_params", Vector4(0.0, live_radius, 0.0, 0.0))
		return
	_table_image = Image.create(TABLE * 2, TABLE, false, Image.FORMAT_RGBA8)
	_table_texture = ImageTexture.create_from_image(_table_image)
	RenderingServer.global_shader_parameter_set(&"aa_rvt_table", _table_texture)
	_layer_keys.resize(CAPACITY)
	for layer in range(CAPACITY - 1, -1, -1):
		_free.append(layer)
	for i in BAKES_PER_FRAME:
		_rigs.append(_make_rig())
	# The arrays exist before any terrain material binds the globals (an empty array global made each
	# chunk material fail its uniform set once when it was first replaced).
	if not _create_arrays():
		push_warning("Terrain RVT off: page arrays could not be created")
		_enabled = false
		return
	_publish_params(false)


## The terrain layers a chunk needs so the bake cameras can see it.
static func terrain_layers() -> int:
	return 1 | TERRAIN_LAYER


func _publish_params(on: bool) -> void:
	var mode: float = (2.0 if _debug else 1.0) if on else 0.0
	RenderingServer.global_shader_parameter_set(&"aa_rvt_params",
		Vector4(mode, live_radius, level_radius[0], level_radius[1]))


func _make_rig() -> Dictionary:
	var rig := {"key": null, "state": 0, "viewports": [], "cameras": [], "scratch": _compressor.create_scratch()}
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	for pass_index in 3:
		var vp := SubViewport.new()
		var texels: int = WET_TEXELS if pass_index == 2 else PAGE_TEXELS
		vp.size = Vector2i(texels, texels)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = false
		vp.use_debanding = false
		vp.positional_shadow_atlas_size = 0
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		vp.gui_disable_input = true
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0) # Screen right = +X, screen down = +Z.
		cam.near = 1.0
		cam.far = 1200.0
		cam.environment = env
		cam.cull_mask = TERRAIN_LAYER | [MARK_ALBEDO, MARK_DATA, MARK_WET][pass_index]
		vp.add_child(cam)
		add_child(vp)
		cam.current = true
		rig["viewports"].append(vp)
		rig["cameras"].append(cam)
	return rig


func _process(delta: float) -> void:
	if not _enabled or camera == null or not is_instance_valid(camera):
		return
	_time += delta
	_follow_quality()
	_copy_finished_bakes()
	var eye: Vector3 = camera.global_position
	# The page set changes slowly: refresh it a few times a second or after a real move, not every frame.
	_refresh_timer -= delta
	if _refresh_timer <= 0.0 or eye.distance_squared_to(_wanted_eye) > 4.0:
		_refresh_timer = 0.25
		_wanted_eye = eye
		_track_chunks()
		_wanted = _wanted_pages(eye)
		_evict_unwanted(_wanted)
	var wanted: Array = _wanted
	_schedule_bakes(wanted)
	if _table_dirty:
		_table_texture.update(_table_image)
		_table_dirty = false
	if _debug:
		_debug_timer += delta
		if _debug_timer >= 5.0:
			_debug_timer = 0.0
			print("RVT pages level0=%d level1=%d free=%d wanted=%d" % [resident_counts()[0], resident_counts()[1], _free.size(), wanted.size()])


## Level 1 covers the terrain detail radius (quality preset) plus its fade; snow changes the material.
func _follow_quality() -> void:
	var detail: float = float(GraphicsQuality.profile(GraphicsQuality.level()).get("terrain_detail_radius", 42.0))
	var outer: float = clampf(detail + 24.0, level_radius[0] + 8.0, 120.0)
	if not is_equal_approx(outer, level_radius[1]):
		level_radius[1] = outer
		_publish_params(not _pages.is_empty())
	if absf(snow_cover - _snow) > 0.05:
		_snow = snow_cover
		_flush_all()


func _flush_all() -> void:
	for key in _pages.keys():
		_release(key)


func _track_chunks() -> void:
	if streamer == null or not streamer.has_method("get_loaded_cells"):
		return
	var loaded := {}
	for loaded_cell in streamer.get_loaded_cells():
		# The streamer runs on the XZ axes: its Vector3i cell (x, 0, z) is chunk (x, z).
		var cell := Vector2i(loaded_cell.x, loaded_cell.z)
		loaded[cell] = true
		if not _chunk_seen.has(cell):
			_chunk_seen[cell] = _time
	for cell in _chunk_seen.keys():
		if not loaded.has(cell):
			_chunk_seen.erase(cell)
			# Its pages may have been baked from geometry that is gone now.
			for key in _pages.keys():
				if _chunk_of(key) == cell:
					_release(key)


func _chunk_of(key: Vector3i) -> Vector2i:
	var size: float = LEVEL_PAGE[key.x]
	var cx: float = (float(key.y) + 0.5) * size
	var cz: float = (float(key.z) + 0.5) * size
	return Vector2i(floori(cx / chunk_size), floori(cz / chunk_size))


func _chunk_ready(key: Vector3i) -> bool:
	var cell := _chunk_of(key)
	return _chunk_seen.has(cell) and _time - float(_chunk_seen[cell]) >= CHUNK_SETTLE


## Pages each level wants, nearest first: [[distance, key], ...].
func _wanted_pages(eye: Vector3) -> Array:
	var rows: Array = []
	for level in 2:
		var size: float = LEVEL_PAGE[level]
		var radius: float = level_radius[level] + size * 0.75
		var x0: int = floori((eye.x - radius) / size)
		var x1: int = floori((eye.x + radius) / size)
		var z0: int = floori((eye.z - radius) / size)
		var z1: int = floori((eye.z + radius) / size)
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				var cx: float = clampf(eye.x, x * size, (x + 1) * size)
				var cz: float = clampf(eye.z, z * size, (z + 1) * size)
				var d: float = Vector2(eye.x - cx, eye.z - cz).length()
				if d <= level_radius[level]:
					rows.append([d + level * 0.01, Vector3i(level, x, z)])
	rows.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	if rows.size() > CAPACITY:
		rows.resize(CAPACITY)
	return rows


func _evict_unwanted(wanted: Array) -> void:
	var keep := {}
	for row in wanted:
		keep[row[1]] = true
	for key in _pages.keys():
		if not keep.has(key):
			_release(key)


func _schedule_bakes(wanted: Array) -> void:
	for rig in _rigs:
		if rig["state"] != 0:
			continue
		for row in wanted:
			var key: Vector3i = row[1]
			if _pages.has(key) or _in_flight(key) or not _chunk_ready(key) or _free.is_empty():
				continue
			_start_bake(rig, key)
			break


func _in_flight(key: Vector3i) -> bool:
	for rig in _rigs:
		if rig["state"] != 0 and rig["key"] == key:
			return true
	return false


func _start_bake(rig: Dictionary, key: Vector3i) -> void:
	var size: float = LEVEL_PAGE[key.x]
	var center := Vector3((float(key.y) + 0.5) * size, 600.0, (float(key.z) + 0.5) * size)
	for pass_index in 3:
		var cam: Camera3D = rig["cameras"][pass_index]
		var texels: float = float(WET_TEXELS if pass_index == 2 else PAGE_TEXELS)
		# One border texel on each side, so bilinear taps at the page edge stay inside it.
		cam.size = size * texels / (texels - 2.0)
		cam.global_position = center
		(rig["viewports"][pass_index] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	rig["key"] = key
	rig["state"] = 1
	rig["frame"] = Engine.get_frames_drawn()


## A bake started in one frame is drawn at the end of it; copy it into the cache afterwards.
func _copy_finished_bakes() -> void:
	for rig in _rigs:
		if rig["state"] != 1 or Engine.get_frames_drawn() <= int(rig["frame"]):
			continue
		var key: Vector3i = rig["key"]
		rig["state"] = 0
		if _free.is_empty() or not _chunk_ready(key):
			continue
		var layer: int = _free.pop_back()
		var baked: Array[RID] = []
		for vp in rig["viewports"]:
			baked.append(RenderingServer.texture_get_rd_texture((vp as SubViewport).get_texture().get_rid()))
		# Albedo + roughness -> BC3, normal -> BC5, both with mips; the low-frequency wet masks stay RGBA8.
		if not _compressor.encode(rig["scratch"], baked[0], baked[1], _arrays[0], _arrays[1], layer):
			_free.append(layer)
			continue
		_rd.texture_copy(baked[2], _arrays[2], Vector3.ZERO, Vector3.ZERO,
			Vector3(WET_TEXELS, WET_TEXELS, 1), 0, 0, 0, layer)
		_pages[key] = layer
		_layer_keys[layer] = key
		_write_table(key, layer)
		if _pages.size() == 1:
			_publish_params(true)


func _create_arrays() -> bool:
	for bc5 in [false, true]:
		var compressed: RID = _compressor.create_array(bc5, CAPACITY)
		if not compressed.is_valid():
			return false
		_arrays.append(compressed)
		var compressed_texture := Texture2DArrayRD.new()
		compressed_texture.texture_rd_rid = compressed
		_array_textures.append(compressed_texture)
	# Wet masks: copied straight from the 8-bit viewport (same format as its colour target).
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.width = WET_TEXELS
	format.height = format.width
	format.array_layers = CAPACITY
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var rid: RID = _rd.texture_create(format, RDTextureView.new())
	if not rid.is_valid():
		return false
	_arrays.append(rid)
	var texture := Texture2DArrayRD.new()
	texture.texture_rd_rid = rid
	_array_textures.append(texture)
	RenderingServer.global_shader_parameter_set(&"aa_rvt_albedo", _array_textures[0])
	RenderingServer.global_shader_parameter_set(&"aa_rvt_data", _array_textures[1])
	RenderingServer.global_shader_parameter_set(&"aa_rvt_wet", _array_textures[2])
	return true


func _release(key: Vector3i) -> void:
	if not _pages.has(key):
		return
	var layer: int = _pages[key]
	_pages.erase(key)
	_layer_keys[layer] = null
	_free.append(layer)
	var slot := _slot(key)
	var current: Color = _table_image.get_pixelv(slot)
	if int(round(current.b * 255.0)) == (key.y & 255) and int(round(current.a * 255.0)) == (key.z & 255):
		_table_image.set_pixelv(slot, Color(0, 0, 0, 0))
		_table_dirty = true


func _slot(key: Vector3i) -> Vector2i:
	return Vector2i((key.y & (TABLE - 1)) + key.x * TABLE, key.z & (TABLE - 1))


func _write_table(key: Vector3i, layer: int) -> void:
	var stored: int = layer + 1
	_table_image.set_pixelv(_slot(key), Color8(stored & 255, stored >> 8, key.y & 255, key.z & 255))
	_table_dirty = true


func _exit_tree() -> void:
	if _rd == null:
		return
	RenderingServer.global_shader_parameter_set(&"aa_rvt_params", Vector4(0.0, live_radius, 0.0, 0.0))
	# Point the globals at a placeholder of the same type first: an emptied Texture2DArrayRD turns into a
	# 2D placeholder and every terrain material would fail to rebuild its uniform set.
	var placeholder := Texture2DArray.new()
	var blank := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	if placeholder.create_from_images([blank]) == OK:
		for global_name in [&"aa_rvt_albedo", &"aa_rvt_data", &"aa_rvt_wet"]:
			RenderingServer.global_shader_parameter_set(global_name, placeholder)
	for texture in _array_textures:
		texture.texture_rd_rid = RID()
	for rid in _arrays:
		if rid.is_valid():
			_rd.free_rid(rid)
	_arrays.clear()
	if _compressor != null:
		for rig in _rigs:
			_compressor.free_scratch(rig["scratch"])
		_compressor.free_all()


## Pages resident per level (for diagnostics and tests).
func resident_counts() -> Array[int]:
	var counts: Array[int] = [0, 0]
	for key in _pages:
		counts[key.x] += 1
	return counts
