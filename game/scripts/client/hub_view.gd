extends Node3D
## The hub town: a paved plaza with the fountain, a ring of houses, lamp posts and the workbench.
## What stands where comes from WorldGen.hub_structures(), the same list the server collides with.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Assets = preload("res://scripts/client/assets.gd")
const Meshes = preload("res://scripts/client/meshes.gd")


func build(world) -> void:
	var height: float = WorldGen.HUB_HEIGHT
	var village := Assets.has_village()
	if village:
		_build_cobble_plaza(height)
	else:
		# Plaza: 5 x 5 paving tiles around the fountain.
		var pavement := Assets.mesh("city/pavement")
		for i in range(-2, 3):
			for j in range(-2, 3):
				_place(pavement, Vector3(i * 7.0, height, j * 7.0), 7.0, 0.0)
	for structure in world.hub_structures():
		var position := Vector3(structure["x"], height, structure["z"])
		match structure["kind"]:
			"fountain":
				_place(Assets.mesh("city/pavement-fountain"), position, structure["scale"], 0.0)
				if village:
					_stone_fountain(get_child(get_child_count() - 1) as MeshInstance3D)
			"building":
				if village:
					var house: Dictionary = Assets.pack_building(int(structure["variant"]))
					_place(house["mesh"], position + Vector3(0, -0.05, 0), house["scale"], structure["yaw"])
				else:
					_place(Assets.building_mesh(structure["variant"]), position, structure["scale"], structure["yaw"])
			"workbench":
				if village:
					_place(Assets.village_mesh("EA03_Prop_Tabble_02a"), position, 2.2, 0.0)
					_place(Assets.village_mesh("EA03_Prop_Container_Barrel_01d"), position + Vector3(-1.4, 0, 0.6), 1.4, 0.7)
					_place(Assets.village_mesh("EA03_Prop_Container_Crate_01a"), position + Vector3(1.3, 0, -0.5), 1.4, 0.3)
					_place(Assets.village_mesh("EA03_Prop_Town_Bench_01a"), position + Vector3(0.2, 0, 1.6), 1.5, PI * 0.5)
				else:
					_place(Meshes.get_mesh("workbench"), position, 1.0, 0.0)
				var label := Label3D.new()
				label.text = "Workbench"
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.no_depth_test = true
				label.pixel_size = 0.008
				label.font_size = 28
				label.outline_size = 8
				label.position = position + Vector3(0, 2.0, 0)
				add_child(label)
	if village:
		_build_hub_props(height)
		return
	# Lamp posts along the plaza edge.
	var lamp := Assets.mesh("city/road-straight-lightposts")
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_place(lamp, Vector3(corner.x * 17.5, height, corner.y * 17.5), 4.0, atan2(corner.x, corner.y))


func _place(mesh: Mesh, position: Vector3, scale_factor: float, yaw: float) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation.y = yaw
	instance.scale = Vector3.ONE * scale_factor
	add_child(instance)


const PLAZA_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Cobblestones in world space whose edge breaks up into the grass: the rim is cut by noise instead of a hard circle.
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float radius = 18.0;
uniform float tile_meters = 3.0;
varying vec2 world_xz;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = world_xz / tile_meters;
	float rim = length(world_xz) / radius;
	float ragged = noise(world_xz * 0.9) * 0.55 + noise(world_xz * 3.1) * 0.25;
	if (rim + ragged * 0.18 > 1.0) {
		discard;
	}
	// Grime toward the edge and in random patches, so the paving looks trodden and old.
	float grime = smoothstep(0.7, 1.0, rim + ragged * 0.2) * 0.45 + noise(world_xz * 0.35) * 0.2;
	vec3 stone = texture(albedo_map, uv).rgb;
	ALBEDO = mix(stone, stone * vec3(0.62, 0.58, 0.45), grime) * 0.72;
	NORMAL_MAP = texture(normal_map, uv).rgb;
	ROUGHNESS = texture(rough_map, uv).r;
}
"""


const FOUNTAIN_SHADER := """
shader_type spatial;
// The Kenney fountain, re-skinned: its pale parts become weathered stone (the plaza texture, projected in world space so
// the scale matches the paving), its blue parts dark, moving water.
uniform sampler2D colormap : source_color, filter_linear_mipmap;
uniform sampler2D stone_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = abs(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz));
}

void fragment() {
	vec3 source = texture(colormap, UV).rgb;
	bool water = source.b > source.r + 0.25 && world_normal.y > 0.85;
	vec3 w = world_normal / (world_normal.x + world_normal.y + world_normal.z);
	vec3 p = world_position / 1.6;
	vec3 stone = texture(stone_map, p.zy).rgb * w.x + texture(stone_map, p.xz).rgb * w.y + texture(stone_map, p.xy).rgb * w.z;
	if (water) {
		float ripple = sin(world_position.x * 3.0 + TIME * 1.7) * sin(world_position.z * 2.6 - TIME * 1.3);
		ALBEDO = vec3(0.07, 0.2, 0.24) + ripple * 0.02;
		ROUGHNESS = 0.08;
		SPECULAR = 0.8;
	} else {
		ALBEDO = stone * 0.85 * mix(0.75, 1.0, source.r);
		NORMAL_MAP = texture(stone_normal, p.xz).rgb;
		ROUGHNESS = 0.9;
	}
}
"""


func _stone_fountain(instance: MeshInstance3D) -> void:
	var stone := load("res://assets/textures/plaza/plaza_diff.jpg") as Texture2D
	var base := instance.mesh.surface_get_material(0) as BaseMaterial3D
	if stone == null or base == null:
		return
	var shader := Shader.new()
	shader.code = FOUNTAIN_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("colormap", base.albedo_texture)
	material.set_shader_parameter("stone_map", stone)
	material.set_shader_parameter("stone_normal", load("res://assets/textures/plaza/plaza_nor_gl.jpg"))
	instance.material_override = material


## The plaza: Poly Haven cobblestones (CC0) on a disc whose rim frays into the grass. Without the texture, a plain stone disc.
func _build_cobble_plaza(height: float) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 18.5
	disc.bottom_radius = 18.5
	disc.height = 0.16
	disc.radial_segments = 64
	disc.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = disc
	var albedo := load("res://assets/textures/plaza/plaza_diff.jpg") as Texture2D
	if albedo != null:
		var shader := Shader.new()
		shader.code = PLAZA_SHADER
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("albedo_map", albedo)
		material.set_shader_parameter("normal_map", load("res://assets/textures/plaza/plaza_nor_gl.jpg"))
		material.set_shader_parameter("rough_map", load("res://assets/textures/plaza/plaza_rough.jpg"))
		instance.material_override = material
	else:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.36, 0.35, 0.33)
		plain.roughness = 0.95
		instance.material_override = plain
	instance.position = Vector3(0, height - 0.05, 0)
	add_child(instance)


## Barrels, crates, benches and baskets around the plaza so the hub looks lived in.
func _build_hub_props(height: float) -> void:
	var props := [
		["EA03_Prop_Container_Barrel_01d", 1.5], ["EA03_Prop_Container_Crate_01a", 1.5], ["EA03_Prop_Town_Bench_01a", 1.6],
		["EA03_Prop_Container_Basket_01a", 1.6], ["EA03_Prop_Stool_01a", 1.5],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in 22:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(17.0, 25.0)
		var spot := Vector2.from_angle(angle) * radius
		var entry: Array = props[rng.randi() % props.size()]
		var mesh := Assets.village_mesh(entry[0])
		if mesh != null:
			_place(mesh, Vector3(spot.x, height, spot.y), float(entry[1]), rng.randf() * TAU)
