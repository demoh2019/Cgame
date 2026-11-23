extends Node3D
## Shader / pipeline precompilation (UE5 PSO precaching, Unity
## ShaderVariantCollection.WarmUp): during loading every spatial shader of the
## game is drawn once on a sub-pixel quad in front of the camera, so the
## driver compiles its pipelines before combat instead of mid-fight.

const SHADER_DIRS := ["res://assets/shaders", "res://shaders"]
const FRAMES_VISIBLE := 3

var _frames_left := FRAMES_VISIBLE


static func shader_paths() -> PackedStringArray:
	var result := PackedStringArray()
	for dir in SHADER_DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in ResourceLoader.list_directory(dir):
			var name := String(file).trim_suffix(".remap")
			if name.ends_with(".gdshader"):
				result.append(dir + "/" + name)
	result.sort()
	return result


## The directory index may retain .uid/.remap entries after the source shader is removed.
## Filter by the resource loader, not FileAccess: exported shaders can be remapped.
static func loadable_shader_paths(paths: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for path in paths:
		if ResourceLoader.exists(path, "Shader"):
			result.append(path)
	return result


static func spatial_shaders() -> Array[Shader]:
	var shaders: Array[Shader] = []
	for path in loadable_shader_paths(shader_paths()):
		var shader := load(path) as Shader
		if shader != null and shader.get_mode() == Shader.MODE_SPATIAL:
			shaders.append(shader)
	return shaders


## Attaches a warm-up rig to the camera; it frees itself after a few frames.
static func start(camera: Camera3D) -> Node3D:
	if camera == null or DisplayServer.get_name() == "headless":
		return null
	var rig: Node3D = new()
	rig.name = "ShaderWarmup"
	var shaders := spatial_shaders()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.002, 0.002)
	for i in shaders.size():
		var material := ShaderMaterial.new()
		material.shader = shaders[i]
		var instance := MeshInstance3D.new()
		instance.mesh = quad
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON # Shadow pipeline too.
		instance.position = Vector3(float(i % 8) * 0.003 - 0.012, floorf(float(i) / 8.0) * 0.003, -(camera.near + 0.05))
		rig.add_child(instance)
	camera.add_child(rig)
	return rig


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left <= 0:
		queue_free()
