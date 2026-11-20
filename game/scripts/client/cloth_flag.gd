extends RefCounted
## Vertex-shader cloth for outpost banners (Unity Cloth component / Unreal Chaos Cloth, in a cheap analytic form):
## a subdivided plane pinned along the pole edge whose free end ripples in the weather wind. The waving travels
## down the flag, the free edge droops with gravity and lifts with wind strength; no CPU work per frame.
## Wind comes from the same global the vegetation uses (aa_vegetation_wind: xy direction, z strength).

const SEGMENTS := [0, 6, 12, 20] # Width subdivisions per quality tier; 0 keeps the rigid flag on Low.
const SIZE := Vector2(2.4, 1.5)

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
global uniform vec3 aa_vegetation_wind;
uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float flag_width = 2.4;
varying float fold;
void vertex() {
	// UV.x is 0 at the pole and 1 at the free edge; the pinned edge never moves.
	float free_end = UV.x * UV.x;
	float power = clamp(aa_vegetation_wind.z, 0.0, 1.0);
	float strength = 0.12 + power * 0.88;
	float phase = TIME * (2.2 + power * 3.0) - UV.x * 7.0 - UV.y * 1.7;
	float ripple = sin(phase) * 0.22 + sin(phase * 2.3 + 1.7) * 0.07;
	VERTEX.z += ripple * free_end * strength * flag_width * 0.35;
	// Cloth hangs: the free edge sags down, less so when the wind holds it out.
	VERTEX.y -= free_end * (1.0 - power * 0.7) * 0.28;
	VERTEX.x -= free_end * (0.04 + 0.1 * strength);
	fold = cos(phase) * free_end * strength;
	NORMAL = normalize(vec3(-fold * 0.6, 0.0, 1.0));
}
void fragment() {
	ALBEDO = albedo.rgb * (0.88 + fold * 0.14);
	EMISSION = emission_color;
}
"""

static var _shader: Shader


static func segments(level: int) -> int:
	return SEGMENTS[clampi(level, 0, SEGMENTS.size() - 1)]


## A plane facing +Z with UV.x along the free direction, origin at the pole edge (x from 0 to width).
static func build_mesh(width_segments: int) -> ArrayMesh:
	var cols := maxi(width_segments, 1)
	var rows := 3
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for j in rows + 1:
		for i in cols + 1:
			var u := float(i) / cols
			var v := float(j) / rows
			vertices.append(Vector3(u * SIZE.x, (0.5 - v) * SIZE.y, 0.0))
			uvs.append(Vector2(u, v))
			normals.append(Vector3(0, 0, 1))
	var indices := PackedInt32Array()
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			var b := a + 1
			var c := a + cols + 1
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func make_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("flag_width", SIZE.x)
	return material


## Replace a rigid flag mesh with the cloth one; returns the ShaderMaterial (null on Low, flag unchanged).
static func upgrade(flag: MeshInstance3D, level: int) -> ShaderMaterial:
	var count := segments(level)
	if count <= 0 or flag == null:
		return null
	flag.mesh = build_mesh(count)
	flag.position.x -= SIZE.x * 0.5 # The box was centered on its position; the cloth is pinned at the pole.
	var material := make_material()
	flag.material_override = material
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return material


static func tint(material: Material, color: Color) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("albedo", color)
		(material as ShaderMaterial).set_shader_parameter("emission_color", Vector3(color.r, color.g, color.b) * 0.45)
